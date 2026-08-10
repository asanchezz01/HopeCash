import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/design_system/design_tokens.dart';
import '../../core/providers.dart';
import '../../core/utils/voice_parse.dart';
import 'quick_add_sheet.dart';

/// Lançamento por voz: ouve a frase, interpreta (LLM local via backend, com
/// fallback offline) e devolve o prefill para o lançamento rápido — o
/// chamador abre o formulário para o usuário confirmar.
Future<QuickAddPrefill?> showVoiceAddSheet(BuildContext context) {
  return showModalBottomSheet<QuickAddPrefill>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _VoiceAddSheet(),
  );
}

class _VoiceAddSheet extends ConsumerStatefulWidget {
  const _VoiceAddSheet();

  @override
  ConsumerState<_VoiceAddSheet> createState() => _VoiceAddSheetState();
}

enum _Phase { starting, listening, processing, error }

class _VoiceAddSheetState extends ConsumerState<_VoiceAddSheet> {
  final _speech = SpeechToText();
  _Phase _phase = _Phase.starting;
  String _transcript = '';
  String _error = '';

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final available = await _speech.initialize(
      onStatus: (status) {
        // O reconhecedor para sozinho após uma pausa na fala.
        if (status == 'done' && _phase == _Phase.listening) _finish();
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _phase = _Phase.error;
          _error = e.errorMsg == 'error_no_match'
              ? 'Não entendi. Tente falar de novo.'
              : 'Falha no reconhecimento de voz (${e.errorMsg}).';
        });
      },
    );
    if (!mounted) return;
    if (!available) {
      setState(() {
        _phase = _Phase.error;
        _error =
            'Reconhecimento de voz indisponível neste aparelho. '
            'Verifique a permissão do microfone.';
      });
      return;
    }
    setState(() => _phase = _Phase.listening);
    await _speech.listen(
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.dictation,
        localeId: 'pt_BR',
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 30),
      ),
      onResult: (SpeechRecognitionResult result) {
        if (!mounted) return;
        setState(() => _transcript = result.recognizedWords);
        if (result.finalResult && _phase == _Phase.listening) _finish();
      },
    );
  }

  Future<void> _finish() async {
    if (_transcript.trim().length < 3) {
      setState(() {
        _phase = _Phase.error;
        _error = 'Não entendi. Tente falar de novo.';
      });
      return;
    }
    setState(() => _phase = _Phase.processing);
    await _speech.stop();

    // 1º: interpretação pelo backend (Ollama). 2º: heurística local offline.
    var parsed = await ref.read(aiApiProvider).parseTransaction(_transcript);
    parsed ??= _parseLocally();

    final prefill = _toPrefill(parsed);
    if (!mounted) return;
    Navigator.of(context).pop(prefill);
  }

  VoiceParseResult _parseLocally() {
    final categories = ref.read(categoriesProvider).valueOrNull ?? [];
    final accounts = ref.read(accountsProvider).valueOrNull ?? [];
    final cards = ref.read(creditCardsProvider).valueOrNull ?? [];
    return parseVoiceLocally(
      _transcript,
      categories: [
        for (final c in categories)
          VoiceOption(id: c.id, name: c.name, type: c.type),
      ],
      accounts: [for (final a in accounts) VoiceOption(id: a.id, name: a.name)],
      cards: [for (final c in cards) VoiceOption(id: c.id, name: c.name)],
    );
  }

  /// Converte o resultado em prefill, garantindo que os ids existem
  /// localmente e são coerentes com o tipo (evita dropdowns inválidos).
  QuickAddPrefill _toPrefill(VoiceParseResult r) {
    final categories = ref.read(categoriesProvider).valueOrNull ?? [];
    final accounts = ref.read(accountsProvider).valueOrNull ?? [];
    final cards = ref.read(creditCardsProvider).valueOrNull ?? [];

    final categoryOk = categories.any(
      (c) => c.id == r.categoryId && c.type == r.type,
    );
    final accountOk = accounts.any((a) => a.id == r.accountId);
    final cardOk =
        r.type == 'expense' && cards.any((c) => c.id == r.cardId && c.isActive);

    return QuickAddPrefill(
      type: r.type,
      amount: r.amount,
      description: r.description,
      date: RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(r.date) ? r.date : null,
      categoryId: categoryOk ? r.categoryId : null,
      accountId: accountOk && !cardOk ? r.accountId : null,
      cardId: cardOk ? r.cardId : null,
      installments: r.installments,
      isPaid: r.paid,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listening = _phase == _Phase.listening;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Lançamento por voz', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Ex.: "gastei 45 reais no mercado ontem no cartão em 3 vezes"',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: EdgeInsets.all(listening ? 28 : 20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    (listening ? Theme.of(context).colorScheme.primary : theme.colorScheme.primary)
                        .withValues(alpha: listening ? 0.18 : 0.10),
              ),
              child: _phase == _Phase.processing
                  ? const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  : Icon(
                      _phase == _Phase.error ? Icons.mic_off : Icons.mic,
                      size: 40,
                      color: _phase == _Phase.error
                          ? context.hopeColors.expense
                          : Theme.of(context).colorScheme.primary,
                    ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            switch (_phase) {
              _Phase.starting => 'Preparando o microfone...',
              _Phase.listening =>
                _transcript.isEmpty ? 'Pode falar...' : _transcript,
              _Phase.processing => '"$_transcript"\n\nInterpretando...',
              _Phase.error => _error,
            },
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _phase == _Phase.error
                    ? FilledButton.icon(
                        onPressed: () {
                          setState(() {
                            _phase = _Phase.starting;
                            _transcript = '';
                          });
                          _start();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tentar de novo'),
                      )
                    : FilledButton.icon(
                        onPressed: listening && _transcript.isNotEmpty
                            ? _finish
                            : null,
                        icon: const Icon(Icons.check),
                        label: const Text('Concluir'),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
