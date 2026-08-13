import 'dart:async';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/providers.dart';
import '../../core/audio/hope_audio_source.dart';
import '../../core/utils/money.dart';
import '../../data/remote/ai_api.dart';
import '../../data/repositories/finance_repository.dart';
import '../components/hope_components.dart';
import '../widgets/quick_add_sheet.dart';

/// Chat com a Hope, com consultas e ações sempre sujeitas à confirmação.
/// A resposta chega em streaming (SSE); as consultas que a Hope faz aparecem
/// como um indicador de atividade na própria bolha da resposta.
class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _Msg {
  _Msg(
    this.role,
    this.text, {
    this.streaming = false,
    List<AiAction>? actions,
    List<TransactionRef>? references,
  }) : actions = actions ?? [],
       references = references ?? [];

  final String role; // user|assistant
  String text;
  bool streaming;
  String? activity; // "consultando…" enquanto uma tool roda
  bool error = false;
  final List<AiAction> actions;
  List<TransactionRef> references;
  Uint8List? audio;
  String audioContentType = 'audio/wav';
  bool audioLoading = false;
  bool audioPlaying = false;
}

const _suggestions = [
  'Qual é o meu saldo?',
  'Quanto gastei este mês?',
  'Como está meu orçamento?',
  'O que vence esta semana?',
  'Lance R\$ 50 de mercado hoje',
];

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final _messages = <_Msg>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _speech = SpeechToText();
  final _audioPlayer = AudioPlayer();
  HopeAudioSource? _hopeAudioSource;
  bool _audioSessionConfigured = false;
  String? _conversationId;
  bool _sending = false;
  bool _listening = false;
  bool _voiceSubmissionPending = false;
  _Msg? _playingMessage;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _speech.cancel();
    _audioPlayer.dispose();
    final audioSource = _hopeAudioSource;
    _hopeAudioSource = null;
    unawaited(audioSource?.dispose());
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send(String text, {bool fromVoice = false}) async {
    final message = text.trim();
    if (message.isEmpty || _sending) return;
    _input.clear();
    final reply = _Msg('assistant', '', streaming: true);
    setState(() {
      _messages.add(_Msg('user', message));
      _messages.add(reply);
      _sending = true;
    });
    _scrollToEnd();

    try {
      final stream = ref
          .read(aiApiProvider)
          .chat(conversationId: _conversationId, message: message);
      await for (final event in stream) {
        if (!mounted) return;
        setState(() {
          switch (event.type) {
            case 'meta':
              _conversationId = event.data['conversation_id'] as String?;
            case 'tool':
              reply.activity = 'Consultando seus dados…';
            case 'action':
              reply.activity = null;
              reply.actions.add(AiAction.fromJson(event.data));
            case 'references':
              reply.references =
                  ((event.data['items'] as List<dynamic>?) ?? const [])
                      .map(
                        (r) =>
                            TransactionRef.fromJson(r as Map<String, dynamic>),
                      )
                      .toList();
            case 'delta':
              reply.activity = null;
              reply.text += event.data['text'] as String? ?? '';
            case 'done':
              reply.streaming = false;
              reply.activity = null;
            case 'error':
              reply.text =
                  event.data['message'] as String? ??
                  'A Hope está indisponível agora.';
              reply.streaming = false;
              reply.activity = null;
              reply.error = true;
              ref.invalidate(aiAvailableProvider);
          }
        });
        _scrollToEnd();
      }
    } catch (_) {
      if (!mounted) return;
      ref.invalidate(aiAvailableProvider);
      setState(() {
        reply.text =
            'Não consegui falar com a Hope. Verifique sua conexão '
            'e tente novamente.';
        reply.error = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          reply.streaming = false;
          _sending = false;
        });
        _scrollToEnd();
        if (fromVoice && !reply.error && reply.text.trim().isNotEmpty) {
          await _speak(reply);
        }
      }
    }
  }

  void _retryAvailability() {
    ref.invalidate(aiAvailableProvider);
  }

  Future<void> _speak(_Msg msg) async {
    if (!mounted || msg.role != 'assistant' || msg.text.trim().isEmpty) return;
    if (identical(_playingMessage, msg) && msg.audioPlaying) {
      await _audioPlayer.pause();
      if (mounted) setState(() => msg.audioPlaying = false);
      return;
    }

    HopeAudioSource? preparedSource;
    try {
      if (msg.audio == null) {
        setState(() => msg.audioLoading = true);
        final speech = await ref.read(aiApiProvider).speech(msg.text);
        msg.audio = speech.bytes;
        msg.audioContentType = speech.contentType;
        if (msg.audio!.isEmpty) throw StateError('Áudio vazio');
      }
      await _audioPlayer.stop();
      final previousSource = _hopeAudioSource;
      _hopeAudioSource = null;
      await previousSource?.dispose();
      if (_playingMessage != null && mounted) {
        setState(() => _playingMessage!.audioPlaying = false);
      }
      _playingMessage = msg;
      if (!_audioSessionConfigured) {
        final session = await AudioSession.instance;
        await session.configure(const AudioSessionConfiguration.speech());
        _audioSessionConfigured = true;
      }
      preparedSource = await HopeAudioSource.fromBytes(
        msg.audio!,
        msg.audioContentType,
      );
      _hopeAudioSource = preparedSource;
      await _audioPlayer.setAudioSource(preparedSource.source);
      if (!mounted) return;
      setState(() {
        msg.audioLoading = false;
        msg.audioPlaying = true;
      });
      await _audioPlayer.play();
      await _releaseAudioSource(preparedSource);
      if (mounted && identical(_playingMessage, msg)) {
        setState(() => msg.audioPlaying = false);
      }
    } on PlayerException catch (error, stackTrace) {
      debugPrint('Falha do player da voz da Hope: $error\n$stackTrace');
      if (preparedSource != null) await _releaseAudioSource(preparedSource);
      if (!mounted) return;
      setState(() {
        msg.audioLoading = false;
        msg.audioPlaying = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A voz da Hope está indisponível agora.')),
      );
    } catch (error, stackTrace) {
      debugPrint('Falha ao reproduzir a voz da Hope: $error\n$stackTrace');
      if (preparedSource != null) await _releaseAudioSource(preparedSource);
      if (!mounted) return;
      setState(() {
        msg.audioLoading = false;
        msg.audioPlaying = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A voz da Hope está indisponível agora.')),
      );
    }
  }

  Future<void> _stopAudio() async {
    await _audioPlayer.stop();
    final audioSource = _hopeAudioSource;
    _hopeAudioSource = null;
    await audioSource?.dispose();
    if (!mounted) return;
    setState(() {
      if (_playingMessage != null) _playingMessage!.audioPlaying = false;
      _playingMessage = null;
    });
  }

  Future<void> _releaseAudioSource(HopeAudioSource source) async {
    await source.dispose();
    if (identical(_hopeAudioSource, source)) _hopeAudioSource = null;
  }

  void _openTransaction(String transactionId) {
    context.go('/transactions?openTransactionId=$transactionId');
  }

  Future<void> _decideAction(AiAction action, bool confirm) async {
    if (action.busy || action.status != 'proposed') return;
    setState(() => action.busy = true);
    try {
      final api = ref.read(aiApiProvider);
      final updated = confirm
          ? await api.confirmAction(action.id)
          : await api.rejectAction(action.id);
      if (!mounted) return;
      setState(() {
        action.apply(updated);
        action.busy = false;
      });
      if (confirm) {
        await ref.read(syncServiceProvider).syncNow();
        if (mounted) {
          final title = action.summary['title'] as String? ?? 'Ação';
          final links = _actionTransactionLinks(action);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$title confirmada e sincronizada.'),
              action: links.isEmpty
                  ? null
                  : SnackBarAction(
                      label: 'Ver',
                      onPressed: () => _openTransaction(links.first.id),
                    ),
            ),
          );
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => action.busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível concluir: $error')),
      );
    }
  }

  /// "Revisar": abre o formulário de lançamento pré-preenchido com a proposta
  /// da Hope. Se o usuário gravar por lá, a proposta é encerrada no servidor
  /// para que "Confirmar" não crie um lançamento duplicado.
  Future<void> _reviewAction(AiAction action) async {
    if (action.busy || action.status != 'proposed') return;
    final payload = action.payload;
    if (payload == null) return;
    final saved = await showQuickAddSheet(
      context,
      prefill: QuickAddPrefill(
        type: payload['type'] as String?,
        amount: (payload['amount'] as num?)?.toDouble(),
        description: payload['description'] as String?,
        date: payload['date'] as String?,
        categoryId: payload['category_id'] as String?,
        subcategoryId: payload['subcategory_id'] as String?,
        accountId: payload['account_id'] as String?,
        cardId: payload['card_id'] as String?,
        isPaid: payload['paid'] is bool ? payload['paid'] as bool : null,
        categorySplits: (payload['category_splits'] as List?)
            ?.whereType<Map>()
            .map(
              (split) => TransactionSplit(
                categoryId: split['category_id'] as String? ?? '',
                subcategoryId: split['subcategory_id'] as String?,
                amount: (split['amount'] as num?)?.toDouble() ?? 0,
              ),
            )
            .where((split) => split.categoryId.isNotEmpty && split.amount > 0)
            .toList(),
      ),
    );
    if (saved != true || !mounted) return;
    setState(() => action.busy = true);
    try {
      final updated = await ref.read(aiApiProvider).rejectAction(action.id);
      if (!mounted) return;
      setState(() {
        action.apply(updated);
        action.reviewed = true;
        action.busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      // O lançamento já foi gravado; encerra o card localmente mesmo sem
      // conseguir avisar o servidor (a proposta expira sozinha em minutos).
      setState(() {
        action.status = 'rejected';
        action.reviewed = true;
        action.busy = false;
      });
    }
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await _speech.stop();
      setState(() {
        _listening = false;
        _voiceSubmissionPending = false;
      });
      return;
    }
    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' && mounted) setState(() => _listening = false);
      },
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!available || !mounted) return;
    await _stopAudio();
    setState(() {
      _listening = true;
      _voiceSubmissionPending = true;
    });
    await _speech.listen(
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        localeId: 'pt_BR',
        listenFor: const Duration(seconds: 30),
      ),
      onResult: (SpeechRecognitionResult result) {
        _input.text = result.recognizedWords;
        if (result.finalResult && mounted && _voiceSubmissionPending) {
          final transcript = result.recognizedWords.trim();
          setState(() {
            _listening = false;
            _voiceSubmissionPending = false;
          });
          if (transcript.isNotEmpty) {
            unawaited(_send(transcript, fromVoice: true));
          }
        }
      },
    );
  }

  void _newConversation() {
    unawaited(_stopAudio());
    setState(() {
      _messages.clear();
      _conversationId = null;
    });
  }

  void _leaveChat() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/');
  }

  Future<void> _openHistory() async {
    await _stopAudio();
    if (!mounted) return;
    final api = ref.read(aiApiProvider);
    final selected = await showModalBottomSheet<AiConversation>(
      context: context,
      showDragHandle: true,
      builder: (context) => _HistorySheet(api: api),
    );
    if (selected == null || !mounted) return;
    final messages = await api.conversationMessages(selected.id);
    if (!mounted) return;
    setState(() {
      _conversationId = selected.id;
      _messages
        ..clear()
        ..addAll(
          messages.map(
            (m) => _Msg(
              m.role,
              m.content,
              actions: m.actions,
              references: m.references,
            ),
          ),
        );
    });
    _scrollToEnd();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final availability = ref.watch(aiAvailableProvider);
    final hopeUnavailable =
        availability.valueOrNull == false && !availability.isLoading;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Sair do chat',
          icon: const Icon(Icons.close_rounded),
          onPressed: _leaveChat,
        ),
        title: const Row(
          children: [
            Icon(Icons.auto_awesome_rounded),
            SizedBox(width: 8),
            // Flexível: a barra tem ícone de sair, histórico e "Nova" à
            // direita; sem isso o título estoura em telas de 360px.
            Flexible(child: Text('Hope', overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Conversas anteriores',
            icon: const Icon(Icons.history_rounded),
            onPressed: _sending ? null : _openHistory,
          ),
          AppBarPrimaryAction(
            tooltip: 'Nova conversa',
            label: 'Nova',
            icon: Icons.add_comment_outlined,
            onPressed: _sending ? null : _newConversation,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (hopeUnavailable)
              _AvailabilityNotice(onRetry: _retryAvailability),
            Expanded(
              child: _messages.isEmpty
                  ? _EmptyState(onSuggestion: _send)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (context, i) => _Bubble(
                        msg: _messages[i],
                        onSpeak: () => _speak(_messages[i]),
                        onConfirm: (action) => _decideAction(action, true),
                        onReject: (action) => _decideAction(action, false),
                        onReview: _reviewAction,
                        onOpenTransaction: _openTransaction,
                      ),
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(
                  top: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      enabled: !_sending,
                      decoration: InputDecoration(
                        hintText: _listening
                            ? 'Ouvindo…'
                            : 'Pergunte ou peça uma ação financeira',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: _listening ? 'Parar de ouvir' : 'Falar',
                    icon: Icon(_listening ? Icons.mic : Icons.mic_none_rounded),
                    color: _listening ? scheme.error : null,
                    onPressed: _sending ? null : _toggleMic,
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    tooltip: 'Enviar',
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_upward_rounded),
                    onPressed: _sending ? null : () => _send(_input.text),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvailabilityNotice extends StatelessWidget {
  const _AvailabilityNotice({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      container: true,
      label:
          'A Hope está temporariamente indisponível. Você pode tentar novamente.',
      child: Material(
        color: scheme.errorContainer,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final message = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.cloud_off_outlined, color: scheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'A Hope está temporariamente indisponível. '
                    'Você ainda pode tentar enviar uma mensagem.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            );
            final retry = TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: scheme.onErrorContainer,
              ),
              child: const Text('Tentar novamente'),
            );

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: constraints.maxWidth < 520
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        message,
                        Align(alignment: Alignment.centerRight, child: retry),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: message),
                        const SizedBox(width: 16),
                        retry,
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onSuggestion});

  final void Function(String) onSuggestion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.auto_awesome_rounded, size: 48, color: scheme.primary),
            const SizedBox(height: 16),
            Text(
              'Oi! Eu sou a Hope.',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Consulte suas finanças ou peça uma ação. Qualquer alteração '
              'só acontece depois da sua confirmação.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final s in _suggestions)
                  ActionChip(label: Text(s), onPressed: () => onSuggestion(s)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.msg,
    required this.onSpeak,
    required this.onConfirm,
    required this.onReject,
    required this.onReview,
    required this.onOpenTransaction,
  });

  final _Msg msg;
  final VoidCallback onSpeak;
  final ValueChanged<AiAction> onConfirm;
  final ValueChanged<AiAction> onReject;
  final ValueChanged<AiAction> onReview;
  final ValueChanged<String> onOpenTransaction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = msg.role == 'user';
    final background = isUser
        ? scheme.primaryContainer
        : msg.error
        ? scheme.errorContainer
        : scheme.surfaceContainerHighest;
    final foreground = isUser
        ? scheme.onPrimaryContainer
        : msg.error
        ? scheme.onErrorContainer
        : scheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (msg.text.isNotEmpty)
              _MarkdownLite(text: msg.text, color: foreground),
            if (msg.references.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: msg.text.isNotEmpty ? 8 : 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final ref in msg.references)
                      ActionChip(
                        avatar: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: Text(ref.label, overflow: TextOverflow.ellipsis),
                        onPressed: () => onOpenTransaction(ref.id),
                      ),
                  ],
                ),
              ),
            for (final action in msg.actions)
              Padding(
                padding: EdgeInsets.only(
                  top: msg.text.isNotEmpty || msg.references.isNotEmpty
                      ? 10
                      : 0,
                ),
                child: _ActionCard(
                  action: action,
                  onConfirm: () => onConfirm(action),
                  onReject: () => onReject(action),
                  // Revisar só existe onde há formulário equivalente no app:
                  // o lançamento simples proposto pela Hope.
                  onReview:
                      action.toolName == 'create_transaction' &&
                          action.payload != null
                      ? () => onReview(action)
                      : null,
                  onOpenTransaction: onOpenTransaction,
                ),
              ),
            if (msg.activity != null || (msg.streaming && msg.text.isEmpty))
              Padding(
                padding: EdgeInsets.only(top: msg.text.isNotEmpty ? 8 : 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      msg.activity ?? 'Pensando…',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            if (!isUser &&
                !msg.streaming &&
                !msg.error &&
                msg.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: TextButton.icon(
                  onPressed: msg.audioLoading ? null : onSpeak,
                  icon: msg.audioLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          msg.audioPlaying
                              ? Icons.pause_rounded
                              : Icons.volume_up_outlined,
                          size: 18,
                        ),
                  label: Text(msg.audioPlaying ? 'Pausar' : 'Ouvir resposta'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TxLink {
  const _TxLink(this.label, this.id);

  final String label;
  final String id;
}

/// Lançamentos criados/alterados por uma ação já confirmada, para oferecer
/// "Ver lançamento" no card — o resultado de cada write tool guarda a
/// entidade de negócio criada pelo syncRepo (sempre com `id`).
List<_TxLink> _actionTransactionLinks(AiAction action) {
  if (action.status != 'confirmed') return const [];
  final result = action.result;
  if (result == null) return const [];
  String? idOf(dynamic value) => value is Map ? value['id'] as String? : null;
  switch (action.toolName) {
    case 'create_transaction':
    case 'update_transaction':
      final id = result['id'] as String?;
      return id == null ? const [] : [_TxLink('Ver lançamento', id)];
    case 'pay_transaction':
    case 'add_goal_contribution':
      final id = idOf(result['transaction']);
      return id == null ? const [] : [_TxLink('Ver lançamento', id)];
    case 'create_transfer':
      final debitId = idOf(result['debit']);
      final creditId = idOf(result['credit']);
      return [
        if (debitId != null) _TxLink('Ver saída', debitId),
        if (creditId != null) _TxLink('Ver entrada', creditId),
      ];
    default:
      return const [];
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.action,
    required this.onConfirm,
    required this.onReject,
    required this.onOpenTransaction,
    this.onReview,
  });

  final AiAction action;
  final VoidCallback onConfirm;
  final VoidCallback onReject;
  final VoidCallback? onReview;
  final ValueChanged<String> onOpenTransaction;

  /// Métrica única dos botões do card ("Recusar", "Revisar" e "Confirmar"):
  /// mesma altura e respiro, mudando apenas a ênfase (outlined × filled).
  static const _actionButtonStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(0, 44)),
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
  );

  String _value(Map<String, dynamic> item) {
    final value = item['value'];
    return switch (item['kind']) {
      'money' => formatMoney(value as num?),
      'date' => _formatDate(value?.toString()),
      _ => value?.toString() ?? '—',
    };
  }

  String _formatDate(String? value) {
    if (value == null || value.length < 10) return value ?? '—';
    return '${value.substring(8, 10)}/${value.substring(5, 7)}/${value.substring(0, 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fields = ((action.summary['fields'] as List<dynamic>?) ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final proposed = action.status == 'proposed';
    final (icon, label, color) = switch (action.status) {
      'confirmed' => (Icons.check_circle_rounded, 'Confirmada', scheme.primary),
      'rejected' when action.reviewed => (
        Icons.edit_note_rounded,
        'Gravada após revisão',
        scheme.primary,
      ),
      'rejected' => (Icons.cancel_rounded, 'Recusada', scheme.outline),
      'expired' => (Icons.schedule_rounded, 'Expirada', scheme.error),
      'failed' => (Icons.error_rounded, 'Falhou', scheme.error),
      _ => (
        Icons.fact_check_outlined,
        'Aguardando confirmação',
        scheme.tertiary,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  action.summary['title'] as String? ?? 'Ação proposta',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      item['label']?.toString() ?? '',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _value(item),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          if (proposed)
            Wrap(
              alignment: WrapAlignment.end,
              runAlignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  style: _actionButtonStyle,
                  onPressed: action.busy ? null : onReject,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Recusar'),
                ),
                if (onReview != null)
                  OutlinedButton.icon(
                    style: _actionButtonStyle,
                    onPressed: action.busy ? null : onReview,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Revisar'),
                  ),
                FilledButton.icon(
                  style: _actionButtonStyle,
                  onPressed: action.busy ? null : onConfirm,
                  icon: action.busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Confirmar'),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_actionTransactionLinks(action).isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    children: [
                      for (final link in _actionTransactionLinks(action))
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () => onOpenTransaction(link.id),
                          icon: const Icon(Icons.open_in_new_rounded, size: 16),
                          label: Text(link.label),
                        ),
                    ],
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

/// Renderizador mínimo do "markdown" que a Hope usa: **negrito** e listas
/// iniciadas com "- ". Suficiente e robusto — sem dependências externas.
class _MarkdownLite extends StatelessWidget {
  const _MarkdownLite({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: color, height: 1.4);
    final bold = base?.copyWith(fontWeight: FontWeight.w700);
    final display = text.replaceAllMapped(
      RegExp(r'^\s*[-•]\s+', multiLine: true),
      (_) => '  •  ',
    );

    final spans = <TextSpan>[];
    var index = 0;
    for (final match in RegExp(r'\*\*(.+?)\*\*').allMatches(display)) {
      if (match.start > index) {
        spans.add(TextSpan(text: display.substring(index, match.start)));
      }
      spans.add(TextSpan(text: match.group(1), style: bold));
      index = match.end;
    }
    if (index < display.length) {
      spans.add(TextSpan(text: display.substring(index)));
    }
    return Text.rich(TextSpan(style: base, children: spans));
  }
}

class _HistorySheet extends StatefulWidget {
  const _HistorySheet({required this.api});

  final AiApi api;

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  late Future<List<AiConversation>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.conversations();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final conversations = snapshot.data!;
          if (conversations.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Nenhuma conversa ainda.')),
            );
          }
          return ListView.builder(
            shrinkWrap: true,
            itemCount: conversations.length,
            itemBuilder: (context, i) {
              final c = conversations[i];
              return ListTile(
                leading: const Icon(Icons.chat_bubble_outline_rounded),
                title: Text(
                  c.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: 'Excluir conversa',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () async {
                    await widget.api.deleteConversation(c.id);
                    if (context.mounted) {
                      setState(() => _future = widget.api.conversations());
                    }
                  },
                ),
                onTap: () => Navigator.of(context).pop(c),
              );
            },
          );
        },
      ),
    );
  }
}
