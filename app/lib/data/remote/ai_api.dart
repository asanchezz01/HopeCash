import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/utils/voice_parse.dart';
import 'api_client.dart';

/// Evento do stream SSE do chat da Hope.
/// Tipos: meta | tool | action | delta | references | done | error.
class AiChatEvent {
  const AiChatEvent(this.type, this.data);

  final String type;
  final Map<String, dynamic> data;
}

class AiSpeechAudio {
  const AiSpeechAudio(this.bytes, this.contentType);

  final Uint8List bytes;
  final String contentType;
}

/// Conversa persistida no servidor (o chat só existe online).
class AiConversation {
  const AiConversation({
    required this.id,
    required this.title,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String updatedAt;

  factory AiConversation.fromJson(Map<String, dynamic> json) => AiConversation(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    updatedAt: json['updated_at'] as String? ?? '',
  );
}

/// Referência a um lançamento citado numa resposta da Hope, usada para
/// oferecer um link "Ver lançamento" (leitura) ou no card de ação confirmada.
class TransactionRef {
  const TransactionRef({required this.id, required this.label});

  final String id;
  final String label;

  factory TransactionRef.fromJson(Map<String, dynamic> json) => TransactionRef(
    id: json['id'] as String,
    label: json['label'] as String? ?? '',
  );
}

/// Mensagem de uma conversa carregada do histórico.
class AiChatMessage {
  const AiChatMessage({
    required this.role,
    required this.content,
    this.actions = const [],
    this.references = const [],
  });

  final String role; // user|assistant
  final String content;
  final List<AiAction> actions;
  final List<TransactionRef> references;
}

/// Ação de escrita proposta pela Hope e aguardando decisão humana.
class AiAction {
  AiAction({
    required this.id,
    required this.toolName,
    required this.summary,
    required this.status,
    required this.expiresAt,
    this.payload,
    this.result,
    this.error,
  });

  final String id;
  final String toolName;
  final Map<String, dynamic> summary;

  /// Dados resolvidos da proposta (ids reais de conta/cartão/categoria),
  /// usados para pré-preencher o formulário no fluxo "Revisar".
  final Map<String, dynamic>? payload;
  String status;
  String expiresAt;
  Map<String, dynamic>? result;
  String? error;
  bool busy = false;

  /// O usuário gravou o lançamento pela tela de revisão (estado local da
  /// sessão): o card mostra "Gravada após revisão" em vez de "Recusada".
  bool reviewed = false;

  factory AiAction.fromJson(Map<String, dynamic> json) => AiAction(
    id: json['id'] as String,
    toolName: json['tool_name'] as String? ?? '',
    summary: Map<String, dynamic>.from(
      json['summary'] as Map? ?? const <String, dynamic>{},
    ),
    status: json['status'] as String? ?? 'proposed',
    expiresAt: json['expires_at'] as String? ?? '',
    payload: json['payload'] == null
        ? null
        : Map<String, dynamic>.from(json['payload'] as Map),
    result: json['result'] == null
        ? null
        : Map<String, dynamic>.from(json['result'] as Map),
    error: json['error'] as String?,
  );

  void apply(AiAction other) {
    status = other.status;
    expiresAt = other.expiresAt;
    result = other.result;
    error = other.error;
  }
}

/// Recursos de IA via backend (LLM local/Ollama): interpretação de voz,
/// chat da Hope (SSE) e disponibilidade do serviço.
class AiApi {
  AiApi(this._client);

  final ApiClient _client;

  /// A IA está no ar? Controla a visibilidade dos recursos da Hope na UI.
  Future<bool> health() async {
    try {
      final res = await _client.dio.get(
        '/ai/health',
        options: Options(receiveTimeout: const Duration(seconds: 8)),
      );
      return res.data['data']['ok'] == true;
    } catch (_) {
      return false; // offline ou backend/Ollama fora → recursos se ocultam
    }
  }

  /// Envia a transcrição e devolve o lançamento estruturado, ou null se o
  /// serviço estiver indisponível (o chamador cai no parser local).
  Future<VoiceParseResult?> parseTransaction(String transcript) async {
    try {
      final res = await _client.dio.post(
        '/ai/parse-transaction',
        data: {'transcript': transcript},
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 35),
        ),
      );
      final d = res.data['data'] as Map<String, dynamic>;
      return VoiceParseResult(
        type: d['type'] as String? ?? 'expense',
        amount: (d['amount'] as num?)?.toDouble(),
        description: d['description'] as String? ?? transcript,
        date: d['date'] as String? ?? '',
        categoryId: d['category_id'] as String?,
        accountId: d['account_id'] as String?,
        cardId: d['card_id'] as String?,
        installments: (d['installments'] as num?)?.toInt() ?? 1,
        paid: d['paid'] as bool? ?? true,
        source: 'ai',
      );
    } catch (_) {
      return null; // offline ou Ollama fora do ar → fallback local
    }
  }

  /// Conversa com a Hope. Emite os eventos SSE conforme chegam.
  Stream<AiChatEvent> chat({
    String? conversationId,
    required String message,
  }) async* {
    final res = await _client.dio.post<ResponseBody>(
      '/ai/chat',
      data: {'conversation_id': conversationId, 'message': message},
      options: Options(
        responseType: ResponseType.stream,
        sendTimeout: const Duration(seconds: 10),
        // Entre eventos pode haver a latência de uma rodada completa do
        // modelo (tools + geração) — folga generosa.
        receiveTimeout: const Duration(minutes: 2),
        headers: {'Accept': 'text/event-stream'},
      ),
    );

    var event = '';
    var data = '';
    final lines = res.data!.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (line.startsWith('event: ')) {
        event = line.substring(7);
      } else if (line.startsWith('data: ')) {
        data = line.substring(6);
      } else if (line.isEmpty && event.isNotEmpty) {
        yield AiChatEvent(event, jsonDecode(data) as Map<String, dynamic>);
        event = '';
        data = '';
      }
    }
  }

  /// Gera a fala da Hope no servidor privado e devolve o MP3 em memória.
  Future<AiSpeechAudio> speech(String text) async {
    final res = await _client.dio.post<List<int>>(
      '/ai/speech',
      data: {'text': text},
      options: Options(
        responseType: ResponseType.bytes,
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 50),
        headers: {'Accept': 'audio/*'},
      ),
    );
    final contentType = res.headers
        .value(Headers.contentTypeHeader)
        ?.split(';')
        .first
        .trim();
    return AiSpeechAudio(
      Uint8List.fromList(res.data ?? const []),
      contentType?.startsWith('audio/') == true ? contentType! : 'audio/wav',
    );
  }

  Future<List<AiConversation>> conversations() async {
    final res = await _client.dio.get('/ai/conversations');
    return (res.data['data'] as List<dynamic>)
        .map((c) => AiConversation.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  Future<List<AiChatMessage>> conversationMessages(String id) async {
    final res = await _client.dio.get('/ai/conversations/$id');
    return (res.data['data']['messages'] as List<dynamic>)
        .map(
          (m) => AiChatMessage(
            role: m['role'] as String,
            content: m['content'] as String? ?? '',
            actions: ((m['actions'] as List<dynamic>?) ?? const [])
                .map(
                  (action) => AiAction.fromJson(action as Map<String, dynamic>),
                )
                .toList(),
            references: ((m['references'] as List<dynamic>?) ?? const [])
                .map(
                  (ref) => TransactionRef.fromJson(ref as Map<String, dynamic>),
                )
                .toList(),
          ),
        )
        .toList();
  }

  Future<void> deleteConversation(String id) =>
      _client.dio.delete('/ai/conversations/$id');

  Future<AiAction> confirmAction(String id) async {
    final res = await _client.dio.post('/ai/actions/$id/confirm');
    return AiAction.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  Future<AiAction> rejectAction(String id) async {
    final res = await _client.dio.post('/ai/actions/$id/reject');
    return AiAction.fromJson(res.data['data'] as Map<String, dynamic>);
  }
}
