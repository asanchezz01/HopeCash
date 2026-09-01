import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/design_tokens.dart';
import '../../core/providers.dart';
import '../../core/utils/money.dart';
import '../components/hope_components.dart';
import '../widgets/quick_create_category.dart';

/// Importação unificada: extrato bancário (conta) ou fatura de cartão.
/// Fluxo online: upload → revisão/edição dos itens → confirmação → sync local.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({
    super.key,
    this.initialCardId,
    this.initialReferenceMonth,
    this.initialDueDate,
  });

  final String? initialCardId;
  final String? initialReferenceMonth;
  final String? initialDueDate;

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  /// bank_statement | credit_card_invoice
  String _importKind = 'bank_statement';
  String? _accountId;
  String? _cardId;
  String? _referenceMonth; // YYYY-MM-01
  String? _invoiceDueDate; // YYYY-MM-DD
  String? _fileName;
  bool _uploading = false;
  bool _confirming = false;
  String? _error;

  Map<String, dynamic>? _batch;
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic>? _summary;
  String _filter = 'all';
  List<Map<String, dynamic>> _drafts = [];

  bool get _isInvoice => _importKind == 'credit_card_invoice';

  @override
  void initState() {
    super.initState();
    if (widget.initialCardId != null) {
      _importKind = 'credit_card_invoice';
      _cardId = widget.initialCardId;
      _referenceMonth = widget.initialReferenceMonth;
      _invoiceDueDate = widget.initialDueDate;
    }
    Future.microtask(_loadDrafts);
  }

  Future<void> _loadDrafts() async {
    try {
      final res = await ref.read(apiClientProvider).dio.get('/imports');
      if (!mounted) return;
      setState(
        () => _drafts = (res.data['data'] as List)
            .cast<Map<String, dynamic>>()
            .where((b) => b['status'] == 'reviewing')
            .toList(),
      );
    } on DioException {
      // A lista de rascunhos é uma conveniência; o upload exibirá o erro de conexão.
    }
  }

  Future<void> _resumeDraft(Map<String, dynamic> draft) async {
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final res = await ref
          .read(apiClientProvider)
          .dio
          .get('/imports/${draft['id']}');
      final data = res.data['data'] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _batch = data['batch'] as Map<String, dynamic>;
        _items = (data['items'] as List).cast<Map<String, dynamic>>();
        _summary = data['summary'] as Map<String, dynamic>?;
        _importKind = _batch!['import_kind'] as String;
        _accountId = _batch!['account_id'] as String?;
        _cardId = _batch!['card_id'] as String?;
        _referenceMonth = _batch!['reference_month'] as String?;
        _invoiceDueDate = _batch!['invoice_due_date'] as String?;
        _fileName = _batch!['file_name'] as String?;
      });
    } on DioException catch (e) {
      if (mounted) {
        setState(
          () => _error =
              e.response?.data?['error']?['message'] as String? ??
              'Não foi possível retomar a conciliação.',
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<bool?> _confirmDiscard(String? fileName) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Descartar conciliação?'),
      content: Text(
        '“${fileName ?? 'Fatura sem nome'}” sairá das conciliações em '
        'andamento e as decisões tomadas não serão aplicadas. Nenhum '
        'lançamento existente é alterado; você poderá importar o arquivo '
        'novamente do zero.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Descartar'),
        ),
      ],
    ),
  );

  Future<bool> _cancelBatch(String batchId) async {
    try {
      await ref.read(apiClientProvider).dio.post('/imports/$batchId/cancel');
      return true;
    } on DioException catch (e) {
      if (mounted) {
        setState(
          () => _error =
              e.response?.data?['error']?['message'] as String? ??
              'Não foi possível descartar a conciliação.',
        );
      }
      return false;
    }
  }

  Future<void> _discardDraft(Map<String, dynamic> draft) async {
    final confirmed = await _confirmDiscard(draft['file_name'] as String?);
    if (confirmed != true) return;
    if (!await _cancelBatch(draft['id'] as String)) return;
    if (mounted) {
      setState(() => _drafts.removeWhere((d) => d['id'] == draft['id']));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Conciliação descartada')));
    }
  }

  /// Descarta a conciliação aberta na tela de revisão e volta ao passo inicial.
  Future<void> _discardCurrent() async {
    final confirmed = await _confirmDiscard(_fileName);
    if (confirmed != true) return;
    if (!await _cancelBatch(_batch!['id'] as String)) return;
    if (mounted) {
      setState(() {
        _batch = null;
        _items = [];
        _summary = null;
        _fileName = null;
        _filter = 'all';
        _error = null;
      });
      _loadDrafts();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Conciliação descartada')));
    }
  }

  Future<void> _pickAndUpload() async {
    if (_isInvoice ? _cardId == null : _accountId == null) {
      setState(
        () => _error = _isInvoice
            ? 'Escolha o cartão de destino antes do arquivo.'
            : 'Escolha a conta de destino antes do arquivo.',
      );
      return;
    }
    final typeGroup = XTypeGroup(
      label: _isInvoice ? 'Faturas' : 'Extratos',
      extensions: const ['csv', 'ofx', 'pdf'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;

    final name = file.name.toLowerCase();
    final source = name.endsWith('.ofx')
        ? 'ofx'
        : name.endsWith('.pdf')
        ? 'pdf'
        : 'csv';
    setState(() {
      _uploading = true;
      _error = null;
      _fileName = file.name;
    });

    try {
      // A análise compara contra a versão mais recente do servidor.
      await ref.read(syncServiceProvider).syncNow();
      final bytes = await file.readAsBytes();
      final dio = ref.read(apiClientProvider).dio;
      final res = await dio.post(
        '/imports',
        data: FormData.fromMap({
          'source': source,
          'import_kind': _importKind,
          if (!_isInvoice) 'account_id': _accountId,
          if (_isInvoice) 'card_id': _cardId,
          if (_isInvoice && _invoiceDueDate != null)
            'invoice_due_date': _invoiceDueDate,
          if (_isInvoice && _referenceMonth != null)
            'reference_month': _referenceMonth,
          'file': MultipartFile.fromBytes(bytes, filename: file.name),
        }),
      );
      final data = res.data['data'] as Map<String, dynamic>;
      setState(() {
        _batch = data['batch'] as Map<String, dynamic>;
        _items = (data['items'] as List).cast<Map<String, dynamic>>();
        _summary = data['summary'] as Map<String, dynamic>?;
      });
    } on DioException catch (e) {
      setState(() {
        _error =
            e.response?.data?['error']?['message'] as String? ??
            'Falha no envio. Verifique sua conexão.';
      });
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<bool> _patchItem(
    Map<String, dynamic> item,
    Map<String, dynamic> patch,
  ) async {
    try {
      final dio = ref.read(apiClientProvider).dio;
      final res = await dio.put(
        '/imports/${_batch!['id']}/items/${item['id']}',
        data: patch,
      );
      final updated = res.data['data'] as Map<String, dynamic>;
      setState(() {
        final index = _items.indexWhere((i) => i['id'] == item['id']);
        if (index >= 0) {
          _items[index] = updated['item'] as Map<String, dynamic>;
        }
        _summary = updated['summary'] as Map<String, dynamic>?;
      });
      return true;
    } on DioException {
      return false;
    }
  }

  /// Nome do campo de subcategoria no PATCH: fatura guarda em decision_payload
  /// (chave 'subcategory_id'), extrato tem coluna própria
  /// 'suggested_subcategory_id', espelhando 'suggested_category_id'.
  String get _subcategoryPatchKey =>
      _isInvoice ? 'subcategory_id' : 'suggested_subcategory_id';

  /// Ao trocar a categoria diretamente no card, a subcategoria anterior pode
  /// não pertencer mais a ela, então é limpa na mesma chamada. Categorizar um
  /// item do extrato ainda pendente já é a decisão de criá-lo: sem isso o
  /// usuário categoriza tudo e a conciliação segue bloqueada por falta de
  /// decisão.
  Future<void> _setItemCategory(
    Map<String, dynamic> item,
    String? categoryId,
  ) => _patchItem(item, {
    'suggested_category_id': categoryId,
    _subcategoryPatchKey: null,
    if (categoryId != null && _isPendingStatement(item)) 'decision': 'create',
  });

  static bool _isPendingStatement(Map<String, dynamic> item) =>
      item['item_origin'] == 'statement' && item['decision'] == null;

  /// Quitação: o débito do extrato paga uma dívida ou a fatura de um cartão em
  /// vez de virar despesa avulsa. Escolher também decide criar o lançamento.
  Future<void> _setItemSettlement(
    Map<String, dynamic> item,
    String? value,
  ) async {
    final parts = value?.split(':');
    final ok = await _patchItem(item, {
      'settlement_type': parts?.first,
      'settlement_id': parts?.last,
      if (parts != null && _isPendingStatement(item)) 'decision': 'create',
    });
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível aplicar a quitação')),
      );
    }
  }

  Future<void> _setItemSubcategory(
    Map<String, dynamic> item,
    String? subcategoryId,
  ) => _patchItem(item, {_subcategoryPatchKey: subcategoryId});

  Future<void> _addDifferenceItem() async {
    try {
      final res = await ref
          .read(apiClientProvider)
          .dio
          .post('/imports/${_batch!['id']}/difference-item');
      final data = res.data['data'] as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _batch = data['batch'] as Map<String, dynamic>? ?? _batch;
          _items = (data['items'] as List).cast<Map<String, dynamic>>();
          _summary = data['summary'] as Map<String, dynamic>?;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Item de ajuste criado. Categorize e toque em "Criar" para aplicá-lo.',
            ),
          ),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(
          () => _error =
              e.response?.data?['error']?['message'] as String? ??
              'Não foi possível lançar a diferença.',
        );
      }
    }
  }

  Future<void> _editItem(Map<String, dynamic> item) async {
    var patch = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _EditImportItemSheet(item: item, isInvoice: _isInvoice),
    );
    if (patch != null && patch.isNotEmpty) {
      if (item['item_origin'] == 'hopecash') {
        final amount = (patch['amount'] as num).abs();
        final isCredit =
            item['kind'] == 'card_credit' || item['kind'] == 'credit';
        patch = {
          'decision': 'edit',
          'transaction_patch': {
            'description': patch['description'],
            'competence_date': patch['item_date'],
            'amount_planned': amount,
            // Conta corrente: o saldo da conta soma amount, então mantém
            // sincronizado ao editar um lançamento existente.
            if (!_isInvoice) 'amount': amount,
            'category_id': patch['suggested_category_id'],
            'subcategory_id': patch['subcategory_id'],
            'effect_cents': (amount * 100).round() * (isCredit ? -1 : 1),
          },
        };
      }
      final ok = await _patchItem(item, patch);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível salvar a edição')),
        );
      }
    }
  }

  Future<void> _confirm() async {
    setState(() {
      _confirming = true;
      _error = null;
    });
    try {
      final dio = ref.read(apiClientProvider).dio;
      final res = await dio.post('/imports/${_batch!['id']}/confirm');
      final created = (res.data['data']['created'] as int?) ?? 0;
      final edited = (res.data['data']['edited'] as int?) ?? 0;
      final removed = (res.data['data']['removed'] as int?) ?? 0;
      final futureInstallments =
          (res.data['data']['future_installments'] as int?) ?? 0;
      // Puxa as transações recém-criadas para o banco local.
      await ref.read(syncServiceProvider).syncNow();
      if (mounted) {
        Navigator.of(context).pop();
        final parts = [
          if (created > 0) '$created lançamento(s) criado(s)',
          if (edited > 0) '$edited editado(s)',
          if (removed > 0) '$removed removido(s)',
        ];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isInvoice
                  ? 'Fatura conciliada com diferença de R\$ 0,00.'
                        '${parts.isEmpty ? '' : ' ${parts.join(' · ')}.'}'
                        '${futureInstallments > 0 ? ' $futureInstallments parcela(s) futura(s) lançada(s).' : ''}'
                  : parts.isEmpty
                  ? 'Extrato importado sem alterações'
                  : 'Extrato importado: ${parts.join(' · ')}.',
            ),
          ),
        );
      }
    } on DioException catch (e) {
      setState(() {
        _error =
            e.response?.data?['error']?['message'] as String? ??
            'Falha ao confirmar a importação.';
      });
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _decide(Map<String, dynamic> item, String decision) async {
    if (decision == 'remove') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Remover lançamento?'),
          content: Text(
            '“${item['description']}” será removido por soft delete. Parcelas futuras não serão alteradas.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remover'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await _patchItem(item, {'decision': decision});
  }

  Future<void> _chooseMatch(Map<String, dynamic> item) async {
    final candidates = (item['candidate_transactions'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    if (candidates.isEmpty) {
      await _decide(item, 'create');
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Escolha o lançamento correspondente')),
            for (final tx in candidates)
              ListTile(
                title: Text(tx['description'] as String? ?? ''),
                subtitle: Text(
                  '${formatDate(tx['competence_date'] as String?)} · ${formatMoney((tx['amount_planned'] as num?) ?? tx['amount'] as num? ?? 0)}',
                ),
                onTap: () => Navigator.pop(context, tx['id'] as String),
              ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Não existe no HopeCash — criar'),
              onTap: () => Navigator.pop(context, '__create__'),
            ),
          ],
        ),
      ),
    );
    if (selected == '__create__') await _decide(item, 'create');
    if (selected != null && selected != '__create__') {
      await _patchItem(item, {
        'decision': 'match',
        'matched_transaction_id': selected,
      });
    }
  }

  Future<void> _setOfficialTotal() async {
    final controller = TextEditingController(
      text: _summary?['official_total_cents'] == null
          ? ''
          : (((_summary!['official_total_cents'] as num) / 100)
                .toStringAsFixed(2)
                .replaceAll('.', ',')),
    );
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _isInvoice ? 'Total oficial da fatura' : 'Total do extrato',
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            prefixText: 'R\$ ',
            labelText: 'Valor total',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, parseMoney(controller.text)),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value < 0) return;
    try {
      final res = await ref
          .read(apiClientProvider)
          .dio
          .put(
            '/imports/${_batch!['id']}/official-total',
            data: {'official_total_cents': (value * 100).round()},
          );
      if (mounted) {
        setState(() {
          _batch = res.data['data']['batch'] as Map<String, dynamic>;
          _summary = res.data['data']['summary'] as Map<String, dynamic>;
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(
          () => _error =
              e.response?.data?['error']?['message'] as String? ??
              'Não foi possível salvar o total.',
        );
      }
    }
  }

  Future<void> _bulkDecision(
    List<Map<String, dynamic>> items,
    String decision, {
    String? categoryId,
  }) async {
    if (items.isEmpty) return;
    try {
      final res = await ref
          .read(apiClientProvider)
          .dio
          .post(
            '/imports/${_batch!['id']}/decisions/bulk',
            data: {
              'item_ids': items.map((i) => i['id']).toList(),
              'decision': decision,
              'suggested_category_id': ?categoryId,
            },
          );
      if (mounted) {
        setState(() {
          _items = (res.data['data']['items'] as List)
              .cast<Map<String, dynamic>>();
          _summary = res.data['data']['summary'] as Map<String, dynamic>;
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(
          () => _error =
              e.response?.data?['error']?['message'] as String? ??
              'Não foi possível aplicar a ação em lote.',
        );
      }
    }
  }

  Future<void> _reanalyze() async {
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      await ref.read(syncServiceProvider).syncNow();
      final res = await ref
          .read(apiClientProvider)
          .dio
          .post('/imports/${_batch!['id']}/analyze');
      final data = res.data['data'] as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _batch = data['batch'] as Map<String, dynamic>;
          _items = (data['items'] as List).cast<Map<String, dynamic>>();
          _summary = data['summary'] as Map<String, dynamic>;
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(
          () => _error =
              e.response?.data?['error']?['message'] as String? ??
              'Não foi possível reanalisar.',
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _categorizeAndCreateMissing(
    List<Map<String, dynamic>> items,
  ) async {
    final categories = (ref.read(categoriesProvider).valueOrNull ?? [])
        .where((c) => c.type == 'expense')
        .toList();
    final categoryId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Categoria para as compras selecionadas'),
            ),
            for (final category in categories)
              ListTile(
                title: Text(category.name),
                onTap: () => Navigator.pop(context, category.id),
              ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Nova categoria'),
              onTap: () async {
                final id = await showQuickCreateCategory(
                  context,
                  ref,
                  type: 'expense',
                );
                if (id != null && context.mounted) {
                  Navigator.pop(context, id);
                }
              },
            ),
          ],
        ),
      ),
    );
    if (categoryId != null) {
      await _bulkDecision(items, 'create', categoryId: categoryId);
    }
  }

  Future<void> _pickReferenceMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _referenceMonth != null
          ? DateTime.parse(_referenceMonth!)
          : DateTime(now.year, now.month),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Mês de referência da fatura',
    );
    if (picked != null) {
      setState(() {
        _referenceMonth =
            '${picked.year.toString().padLeft(4, '0')}-'
            '${picked.month.toString().padLeft(2, '0')}-01';
      });
    }
  }

  Future<void> _pickInvoiceDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _invoiceDueDate != null
          ? DateTime.parse(_invoiceDueDate!)
          : DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Vencimento da fatura',
    );
    if (picked != null) {
      setState(
        () => _invoiceDueDate = picked.toIso8601String().substring(0, 10),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final reviewing = _batch != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(reviewing ? 'Revisar importação' : 'Importar lançamentos'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (!reviewing) ..._buildSetupStep(context),
          if (reviewing) ..._buildReviewStep(context),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.hopeColors.expense),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildSetupStep(BuildContext context) {
    final accounts = ref.watch(accountsProvider).valueOrNull ?? [];
    final cards = (ref.watch(creditCardsProvider).valueOrNull ?? [])
        .where((c) => c.isActive)
        .toList();

    return [
      if (_drafts.isNotEmpty) ...[
        AppSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Conciliações em andamento',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final draft
                  in _drafts
                      .where(
                        (d) => _isInvoice
                            ? _cardId == null || d['card_id'] == _cardId
                            : _accountId == null ||
                                  d['account_id'] == _accountId,
                      )
                      .take(3))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.restore_outlined),
                  title: Text(draft['file_name'] as String? ?? 'Sem nome'),
                  subtitle: Text(
                    _isInvoice
                        ? 'Ciclo ${formatDate(draft['invoice_due_date'] as String?)}'
                        : 'Extrato ${formatDate(draft['period_start'] as String?)} a ${formatDate(draft['period_end'] as String?)}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Retomar'),
                      IconButton(
                        tooltip: 'Descartar',
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _discardDraft(draft),
                      ),
                    ],
                  ),
                  onTap: () => _resumeDraft(draft),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
      AppSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '1. O que você quer importar?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'bank_statement',
                  label: Text('Extrato bancário'),
                  icon: Icon(Icons.account_balance_outlined),
                ),
                ButtonSegment(
                  value: 'credit_card_invoice',
                  label: Text('Fatura de cartão'),
                  icon: Icon(Icons.credit_card_outlined),
                ),
              ],
              selected: {_importKind},
              onSelectionChanged: (s) => setState(() {
                _importKind = s.first;
                _error = null;
              }),
            ),
            const SizedBox(height: 12),
            Text(
              _isInvoice
                  ? 'A fatura será comparada nos dois sentidos com os lançamentos '
                        'do cartão. A conclusão exige diferença exata de R\$ 0,00. '
                        'Formatos: CSV, OFX e PDF com texto.'
                  : 'O extrato será comparado nos dois sentidos com os '
                        'lançamentos existentes na conta. Você decide item a '
                        'item: associar, criar, ignorar, manter, editar ou '
                        'remover. Formatos: CSV, OFX e PDF com texto.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      AppSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '2. Destino e arquivo',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (!_isInvoice)
              DropdownButtonFormField<String>(
                initialValue: _accountId,
                decoration: const InputDecoration(
                  labelText: 'Conta de destino',
                  prefixIcon: Icon(Icons.account_balance_outlined),
                ),
                items: [
                  for (final a in accounts)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => setState(() => _accountId = v),
              )
            else ...[
              DropdownButtonFormField<String>(
                initialValue: _cardId,
                decoration: const InputDecoration(
                  labelText: 'Cartão de destino',
                  prefixIcon: Icon(Icons.credit_card_outlined),
                ),
                items: [
                  for (final c in cards)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _cardId = v),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickReferenceMonth,
                      icon: const Icon(Icons.calendar_month_outlined, size: 18),
                      label: Text(
                        _referenceMonth == null
                            ? 'Mês de referência'
                            : 'Ref.: ${_referenceMonth!.substring(5, 7)}/${_referenceMonth!.substring(0, 4)}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickInvoiceDueDate,
                      icon: const Icon(Icons.event_outlined, size: 18),
                      label: Text(
                        _invoiceDueDate == null
                            ? 'Vencimento'
                            : 'Venc.: ${formatDate(_invoiceDueDate)}',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'O ciclo usa o vencimento da fatura, mantendo a mesma regra da '
                'tela do cartão. Se o arquivo não trouxer o total oficial, você '
                'deverá confirmá-lo antes de concluir.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _uploading ? null : _pickAndUpload,
              icon: _uploading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_outlined),
              label: Text(
                _uploading
                    ? 'Enviando ${_fileName ?? ''}...'
                    : 'Selecionar arquivo',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Nada é alterado sem a sua revisão. Antes da análise, os dados '
              'pendentes são sincronizados. Categorias são sugeridas pelo histórico. '
              'PDFs escaneados (imagem) não são suportados.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildReviewStep(BuildContext context) =>
      _buildReconciliationStep(context);

  List<Widget> _buildReconciliationStep(BuildContext context) {
    final summary = _summary ?? const <String, dynamic>{};
    final accounts = ref.watch(accountsProvider).valueOrNull ?? [];
    final accountName =
        accounts
            .where((a) => a.id == _accountId)
            .map((a) => a.name)
            .firstOrNull ??
        'Conta';
    String group(Map<String, dynamic> item) {
      if (item['item_origin'] == 'hopecash') return 'hopecash_only';
      final type = item['match_type'] as String? ?? 'statement_only';
      return type == 'exact_match' || type == 'probable_match'
          ? 'matched'
          : type;
    }

    final counts = <String, int>{};
    for (final item in _items) {
      counts[group(item)] = (counts[group(item)] ?? 0) + 1;
    }
    final pending = _items.where((i) => i['decision'] == null).toList();
    final visible = switch (_filter) {
      'all' => _items,
      'pending' => pending,
      _ => _items.where((i) => group(i) == _filter).toList(),
    };
    final missing = _items
        .where((i) => group(i) == 'statement_only' && i['decision'] == null)
        .toList();
    final extras = _items
        .where((i) => group(i) == 'hopecash_only' && i['decision'] == null)
        .toList();
    final canComplete = summary['can_complete'] == true;
    final difference = summary['difference_cents'] as num?;

    return [
      AppSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                FinanceIconBadge(
                  icon: Icons.fact_check_outlined,
                  color: context.hopeColors.success,
                ),
                const SizedBox(width: HopeSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _fileName ?? (_isInvoice ? 'Fatura' : 'Extrato'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        _isInvoice
                            ? 'Ciclo ${formatDate(_batch?['invoice_due_date'] as String?)} · ${_items.length} itens'
                            : 'Conta $accountName · ${_items.length} itens',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _setOfficialTotal,
                  child: const Text('Editar total'),
                ),
              ],
            ),
            const Divider(height: 24),
            _FinancialLine(
              'Total oficial',
              summary['official_total_cents'] as num?,
            ),
            _FinancialLine(
              'Itens reconhecidos',
              summary['recognized_total_cents'] as num?,
            ),
            _FinancialLine(
              'HopeCash atual',
              summary['current_total_cents'] as num?,
            ),
            _FinancialLine('A adicionar', summary['additions_cents'] as num?),
            _FinancialLine('A remover', summary['removals_cents'] as num?),
            _FinancialLine(
              'Total projetado',
              summary['projected_total_cents'] as num?,
              emphasized: true,
            ),
            const Divider(),
            _FinancialLine(
              'Diferença restante',
              difference,
              emphasized: true,
              color: difference == 0
                  ? context.hopeColors.success
                  : context.hopeColors.expense,
            ),
            // Fatura exige total oficial para concluir; extrato deixa opcional
            // (só cobra se o usuário informar o total e houver diferença).
            if (_isInvoice && summary['official_total_cents'] == null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'O arquivo não informou o total oficial. Confirme-o para continuar.',
                ),
              ),
            if (difference != null && difference != 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  onPressed: _addDifferenceItem,
                  icon: const Icon(Icons.add_circle_outline),
                  label: Text(
                    'Lançar diferença de ${formatMoney(difference.abs() / 100)} em novo item',
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final entry in [
              ('all', 'Todos'),
              ('pending', 'Pendentes'),
              ('matched', 'Conciliados'),
              ('statement_only', _isInvoice ? 'Só na fatura' : 'Só no extrato'),
              ('hopecash_only', 'Só no HopeCash'),
              ('ambiguous', 'Duvidosos'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  selected: _filter == entry.$1,
                  label: Text(
                    '${entry.$2} (${switch (entry.$1) {
                      'all' => _items.length,
                      'pending' => pending.length,
                      _ => counts[entry.$1] ?? 0,
                    }})',
                  ),
                  onSelected: (_) => setState(() => _filter = entry.$1),
                ),
              ),
          ],
        ),
      ),
      if (missing.isNotEmpty || extras.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (missing.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => _categorizeAndCreateMissing(missing),
                icon: const Icon(Icons.category_outlined),
                label: Text('Categorizar e criar ${missing.length}'),
              ),
            if (extras.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => _bulkDecision(extras, 'keep'),
                icon: const Icon(Icons.check_outlined),
                label: Text('Manter ${extras.length}'),
              ),
          ],
        ),
      ],
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: _uploading ? null : _reanalyze,
          icon: const Icon(Icons.refresh_outlined),
          label: const Text('Sincronizar e reanalisar'),
        ),
      ),
      const SizedBox(height: 8),
      if (visible.isEmpty)
        const AppSurface(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nenhum item neste grupo.'),
            ),
          ),
        ),
      for (final item in visible)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _ReconciliationItemTile(
            item: item,
            onEdit: () => _editItem(item),
            onDecision: (decision) => _decide(item, decision),
            onChooseMatch: () => _chooseMatch(item),
            onCategoryChanged: (categoryId) =>
                _setItemCategory(item, categoryId),
            onSubcategoryChanged: (subcategoryId) =>
                _setItemSubcategory(item, subcategoryId),
            onSettlementChanged: _isInvoice
                ? null
                : (value) => _setItemSettlement(item, value),
          ),
        ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: (_confirming || !canComplete) ? null : _confirm,
        icon: _confirming
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.verified_outlined),
        label: const Text('Concluir conciliação'),
      ),
      if (!canComplete)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            pending.isNotEmpty
                ? '${pending.length} item(ns) ainda sem decisão impedem a '
                      'conclusão. Use o filtro "Pendentes" para localizá-los.'
                // Sem pendências e sem total oficial, o extrato já conclui;
                // este ramo (total ausente) só ocorre na fatura.
                : difference == null
                ? 'Informe o total oficial e revise todas as decisões.'
                : 'Resolva as pendências até a diferença chegar exatamente a R\$ 0,00.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      TextButton(
        onPressed: _confirming ? null : () => Navigator.of(context).pop(),
        child: const Text('Sair e retomar depois'),
      ),
      TextButton(
        onPressed: _confirming ? null : _discardCurrent,
        style: TextButton.styleFrom(
          foregroundColor: context.hopeColors.expense,
        ),
        child: const Text('Descartar conciliação'),
      ),
    ];
  }
}

class _FinancialLine extends StatelessWidget {
  const _FinancialLine(
    this.label,
    this.cents, {
    this.emphasized = false,
    this.color,
  });
  final String label;
  final num? cents;
  final bool emphasized;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: emphasized
                ? const TextStyle(fontWeight: FontWeight.w700)
                : null,
          ),
        ),
        Text(
          cents == null
              ? 'Não informado'
              : formatMoney(cents!.toDouble() / 100),
          style: TextStyle(
            fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    ),
  );
}

class _ReconciliationItemTile extends ConsumerWidget {
  const _ReconciliationItemTile({
    required this.item,
    required this.onEdit,
    required this.onDecision,
    required this.onChooseMatch,
    required this.onCategoryChanged,
    required this.onSubcategoryChanged,
    this.onSettlementChanged,
  });
  final Map<String, dynamic> item;
  final VoidCallback onEdit;
  final ValueChanged<String> onDecision;
  final VoidCallback onChooseMatch;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String?> onSubcategoryChanged;

  /// Só extrato bancário quita dívida/fatura; null esconde o seletor.
  final ValueChanged<String?>? onSettlementChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final origin = item['item_origin'] as String? ?? 'statement';
    final kind = item['kind'] as String?;
    final match = item['match_type'] as String? ?? '';
    final decision = item['decision'] as String?;
    final matched = item['matched_transaction'] as Map<String, dynamic>?;
    final special =
        item['decision_payload'] as Map<String, dynamic>? ?? const {};
    final categoryId = item['suggested_category_id'] as String?;
    // Fatura guarda a subcategoria em decision_payload; extrato, na coluna
    // suggested_subcategory_id — que é também onde o dicionário deixa a
    // subcategoria aprendida.
    final subcategoryId =
        (special['subcategory_id'] ?? item['suggested_subcategory_id'])
            as String?;
    final label = switch (match) {
      'exact_match' => 'Correspondência exata',
      'probable_match' => 'Correspondência provável',
      'ambiguous' => 'Correspondência duvidosa',
      'hopecash_only' => 'Somente no HopeCash',
      _ => 'Somente na fatura',
    };
    final amount = ((item['amount_cents'] as num?)?.abs() ?? 0) / 100;
    final decided = decision != null;
    final statusColor = decided
        ? context.hopeColors.success
        : context.hopeColors.warning;
    final decisionLabel = switch (decision) {
      'match' => 'Associado',
      'create' => 'Criar novo',
      'ignore' => 'Ignorado',
      'keep' => 'Mantido',
      'edit' => 'Editado',
      'remove' => 'Remover',
      _ => 'Pendente',
    };
    // Pendentes ganham borda âmbar mais forte para chamar a revisão;
    // decididos ficam com borda verde discreta.
    return AppSurface(
      padding: const EdgeInsets.all(HopeSpacing.md),
      borderColor: statusColor.withValues(alpha: decided ? 0.35 : 0.65),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              FinanceIconBadge(
                icon: decided
                    ? Icons.check_rounded
                    : match == 'ambiguous'
                    ? Icons.help_outline
                    : match.endsWith('_match')
                    ? Icons.link
                    : Icons.compare_arrows,
                color: statusColor,
                size: 34,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['description'] as String? ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      '${formatDate(item['item_date'] as String?)} · $label',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatMoney(amount),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  _DecisionBadge(
                    label: decisionLabel,
                    icon: decided
                        ? Icons.check_circle_rounded
                        : Icons.pending_outlined,
                    color: statusColor,
                  ),
                ],
              ),
            ],
          ),
          if (matched != null) ...[
            const SizedBox(height: 6),
            Text(
              'HopeCash: ${matched['description']} · confiança ${item['match_confidence'] ?? 0}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (item['match_reason'] != null)
              Text(
                item['match_reason'] as String,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
          if (special['status'] == 'paid' ||
              special['installment_group_id'] != null ||
              special['recurrence_id'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                [
                  if (special['status'] == 'paid') 'Já pago',
                  if (special['installment_group_id'] != null)
                    'Parcela ${special['installment_number'] ?? ''}',
                  if (special['recurrence_id'] != null) 'Recorrente',
                ].join(' · '),
                style: TextStyle(
                  color: context.hopeColors.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (origin == 'statement' &&
              ((item['installment_total'] as num?) ?? 0) > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Parcela ${item['installment_number'] ?? '?'} de '
                '${item['installment_total']} — ao criar, as demais serão '
                'lançadas nas próximas faturas.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.hopeColors.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (origin == 'statement' &&
              onSettlementChanged != null &&
              (item['amount_cents'] as num? ?? 0) < 0) ...[
            const SizedBox(height: 8),
            _SettlementField(
              itemId: item['id'] as String,
              value: special['settlement_type'] == null
                  ? null
                  : '${special['settlement_type']}:${special['settlement_id']}',
              onChanged: onSettlementChanged!,
            ),
          ],
          if (origin == 'statement' && special['settlement_type'] != 'card') ...[
            const SizedBox(height: 8),
            _CategorySubcategoryRow(
              itemId: item['id'] as String,
              kind: kind,
              categoryId: categoryId,
              subcategoryId: subcategoryId,
              onCategoryChanged: onCategoryChanged,
              onSubcategoryChanged: onSubcategoryChanged,
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (match == 'ambiguous')
                FilledButton.tonal(
                  onPressed: onChooseMatch,
                  child: const Text('Escolher associação'),
                ),
              if (origin == 'statement' &&
                  (match == 'statement_only' || match == 'ambiguous')) ...[
                OutlinedButton(
                  onPressed: () => onDecision('create'),
                  child: const Text('Criar'),
                ),
                TextButton(
                  onPressed: () => onDecision('ignore'),
                  child: const Text('Ignorar'),
                ),
              ],
              if (origin == 'hopecash') ...[
                OutlinedButton(
                  onPressed: () => onDecision('keep'),
                  child: const Text('Manter'),
                ),
                OutlinedButton(onPressed: onEdit, child: const Text('Editar')),
                TextButton(
                  onPressed: () => onDecision('remove'),
                  child: const Text('Remover'),
                ),
              ],
              if (match == 'exact_match' || match == 'probable_match')
                TextButton(
                  onPressed: onChooseMatch,
                  child: const Text('Trocar associação'),
                ),
              if (origin == 'statement')
                TextButton(onPressed: onEdit, child: const Text('Editar item')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Selo compacto de status da decisão: verde quando o item já foi acatado
/// (qualquer decisão registrada), âmbar enquanto aguarda revisão.
class _DecisionBadge extends StatelessWidget {
  const _DecisionBadge({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    ),
  );
}

/// Escolha da dívida ou fatura que o débito do extrato quita. Ao concluir a
/// conciliação, a dívida tem o saldo devedor baixado e a fatura tem as compras
/// do ciclo marcadas como pagas — em vez de nascer uma despesa avulsa.
class _SettlementField extends ConsumerWidget {
  const _SettlementField({
    required this.itemId,
    required this.value,
    required this.onChanged,
  });

  final String itemId;

  /// `debt:<id>` ou `card:<id>`; null quando o item é uma despesa comum.
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debts = (ref.watch(debtsProvider).valueOrNull ?? [])
        .where((d) => d.status == 'active')
        .toList();
    final cards = (ref.watch(creditCardsProvider).valueOrNull ?? [])
        .where((c) => c.isActive)
        .toList();
    if (debts.isEmpty && cards.isEmpty) return const SizedBox.shrink();
    final options = [
      for (final d in debts) ('debt:${d.id}', 'Dívida · ${d.name}'),
      for (final c in cards) ('card:${c.id}', 'Fatura · ${c.name}'),
    ];
    return DropdownButtonFormField<String>(
      key: ValueKey('settlement-$itemId-$value-${options.length}'),
      initialValue: options.any((o) => o.$1 == value) ? value : null,
      isExpanded: true,
      isDense: true,
      decoration: const InputDecoration(
        labelText: 'Quitação',
        isDense: true,
        helperText: 'Dá baixa na dívida ou na fatura em vez de criar despesa',
        prefixIcon: Icon(Icons.price_check_outlined, size: 18),
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('Despesa comum')),
        for (final option in options)
          DropdownMenuItem(
            value: option.$1,
            child: Text(option.$2, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

/// Seleção rápida de categoria e subcategoria direto no card, sem abrir a
/// edição completa. Usado tanto na revisão de extrato bancário quanto na
/// conciliação de fatura de cartão, para itens de origem 'statement' (os
/// que podem virar um novo lançamento).
class _CategorySubcategoryRow extends ConsumerWidget {
  const _CategorySubcategoryRow({
    required this.itemId,
    required this.kind,
    required this.categoryId,
    required this.subcategoryId,
    required this.onCategoryChanged,
    required this.onSubcategoryChanged,
  });

  final String itemId;
  final String? kind;
  final String? categoryId;
  final String? subcategoryId;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String?> onSubcategoryChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = (kind == 'card_credit' || kind == 'credit')
        ? 'income'
        : 'expense';
    final categories = (ref.watch(categoriesProvider).valueOrNull ?? [])
        .where((c) => c.type == type)
        .toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey(
              'card-category-$itemId-$categoryId-${categories.length}',
            ),
            initialValue: categories.any((c) => c.id == categoryId)
                ? categoryId
                : null,
            isExpanded: true,
            isDense: true,
            decoration: const InputDecoration(
              labelText: 'Categoria',
              isDense: true,
              prefixIcon: Icon(Icons.category_outlined, size: 18),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('Sem categoria')),
              for (final c in categories)
                DropdownMenuItem(
                  value: c.id,
                  child: Text(c.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: onCategoryChanged,
          ),
        ),
        IconButton(
          tooltip: 'Nova categoria',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add_circle_outline, size: 20),
          onPressed: () async {
            final id = await showQuickCreateCategory(context, ref, type: type);
            if (id != null) onCategoryChanged(id);
          },
        ),
        const SizedBox(width: 4),
        Expanded(
          child: SubcategorySelector(
            categoryId: categoryId,
            value: subcategoryId,
            dense: true,
            onChanged: onSubcategoryChanged,
          ),
        ),
      ],
    );
  }
}

String _kindLabel(String? kind, num amount) => switch (kind) {
  'card_purchase' => 'Compra no cartão',
  'card_credit' => 'Crédito/estorno',
  'credit' => 'Receita',
  'debit' => 'Despesa',
  _ => amount >= 0 ? 'Receita' : 'Despesa',
};

/// Edição de um item antes da confirmação: descrição, data, valor,
/// categoria e subcategoria. Retorna o patch a enviar ao backend (ou null
/// se cancelado).
class _EditImportItemSheet extends ConsumerStatefulWidget {
  const _EditImportItemSheet({required this.item, this.isInvoice = false});

  final Map<String, dynamic> item;

  /// Fatura de cartão guarda a subcategoria em decision_payload e permite o
  /// patch especial de item de origem 'hopecash'; extrato usa a coluna
  /// suggested_subcategory_id diretamente. Ambos exibem o seletor.
  final bool isInvoice;

  @override
  ConsumerState<_EditImportItemSheet> createState() =>
      _EditImportItemSheetState();
}

class _EditImportItemSheetState extends ConsumerState<_EditImportItemSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _description;
  late final TextEditingController _amount;
  late String _date;
  String? _categoryId;
  String? _subcategoryId;

  /// Subcategoria vive em decision_payload para fatura e para itens de origem
  /// 'hopecash'; itens 'statement' de extrato usam a coluna
  /// suggested_subcategory_id.
  late final bool _usesPayloadSubcategory;

  bool get _isIncome {
    final kind = widget.item['kind'] as String?;
    return kind == 'credit' || kind == 'card_credit';
  }

  @override
  void initState() {
    super.initState();
    final amount = ((widget.item['amount'] as num?)?.toDouble() ?? 0).abs();
    _description = TextEditingController(
      text: widget.item['description'] as String? ?? '',
    );
    _amount = TextEditingController(
      text: amount.toStringAsFixed(2).replaceAll('.', ','),
    );
    _date = (widget.item['item_date'] as String?) ?? todayIso();
    final payload =
        widget.item['decision_payload'] as Map<String, dynamic>? ?? const {};
    // Itens de origem 'hopecash' guardam a categoria da transação original em
    // decision_payload, não na coluna suggested_category_id.
    _categoryId =
        (widget.item['suggested_category_id'] as String?) ??
        payload['category_id'] as String?;
    _usesPayloadSubcategory =
        widget.isInvoice || widget.item['item_origin'] == 'hopecash';
    _subcategoryId = _usesPayloadSubcategory
        ? payload['subcategory_id'] as String?
        : widget.item['suggested_subcategory_id'] as String?;
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_date) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _date = picked.toIso8601String().substring(0, 10));
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop({
      'description': _description.text.trim(),
      'item_date': _date,
      'amount': parseMoney(_amount.text),
      'suggested_category_id': _categoryId,
      (_usesPayloadSubcategory ? 'subcategory_id' : 'suggested_subcategory_id'):
          _subcategoryId,
    });
  }

  @override
  Widget build(BuildContext context) {
    final type = _isIncome ? 'income' : 'expense';
    final categories = (ref.watch(categoriesProvider).valueOrNull ?? [])
        .where((c) => c.type == type)
        .toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Editar item', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              _kindLabel(
                widget.item['kind'] as String?,
                (widget.item['amount'] as num?) ?? 0,
              ),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(
                labelText: 'Descrição',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Informe a descrição'
                  : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Valor',
                      prefixText: 'R\$ ',
                    ),
                    validator: (v) {
                      final parsed = parseMoney(v ?? '');
                      if (parsed == null || parsed <= 0) {
                        return 'Valor inválido';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(formatDate(_date)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(
                      'edit-category-$type-$_categoryId-${categories.length}',
                    ),
                    initialValue: categories.any((c) => c.id == _categoryId)
                        ? _categoryId
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Categoria',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Sem categoria'),
                      ),
                      for (final c in categories)
                        DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() {
                      _categoryId = v;
                      _subcategoryId = null;
                    }),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Nova categoria',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () async {
                    final id = await showQuickCreateCategory(
                      context,
                      ref,
                      type: type,
                    );
                    if (id != null) {
                      setState(() {
                        _categoryId = id;
                        _subcategoryId = null;
                      });
                    }
                  },
                ),
              ],
            ),
            if (_categoryId != null) ...[
              const SizedBox(height: 12),
              SubcategorySelector(
                categoryId: _categoryId,
                value: _subcategoryId,
                onChanged: (v) => setState(() => _subcategoryId = v),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(onPressed: _save, child: const Text('Salvar')),
          ],
        ),
      ),
    );
  }
}
