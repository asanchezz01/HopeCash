import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/design_tokens.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/database.dart';
import '../components/hope_components.dart';
import '../widgets/icon_picker.dart';

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  final _search = TextEditingController();
  String _type = 'expense';
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = (ref.watch(categoriesProvider).valueOrNull ?? [])
        .where((c) => c.type == _type)
        .toList();
    final subcategories = ref.watch(subcategoriesProvider).valueOrNull ?? [];
    final normalizedQuery = _normalizeSearch(_query);
    final categoryResults = <_CategorySearchResult>[];
    for (final category in categories) {
      final categorySubcategories = subcategories
          .where((s) => s.categoryId == category.id)
          .toList();
      if (normalizedQuery.isEmpty) {
        categoryResults.add(
          _CategorySearchResult(category, categorySubcategories),
        );
        continue;
      }
      final categoryMatches = _matchesSearch(category.name, normalizedQuery);
      final matchingSubcategories = categorySubcategories
          .where((s) => _matchesSearch(s.name, normalizedQuery))
          .toList();
      if (categoryMatches || matchingSubcategories.isNotEmpty) {
        categoryResults.add(
          _CategorySearchResult(
            category,
            categoryMatches ? categorySubcategories : matchingSubcategories,
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Categorias',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          AppBarPrimaryAction(
            onPressed: () => _showCategorySheet(context, initialType: _type),
            icon: Icons.add_rounded,
            label: 'Categoria',
            tooltip: 'Nova categoria',
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          context.pagePadding,
          HopeSpacing.xs,
          context.pagePadding,
          120,
        ),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'expense',
                label: Text('Despesas'),
                icon: Icon(Icons.arrow_downward_rounded),
              ),
              ButtonSegment(
                value: 'income',
                label: Text('Receitas'),
                icon: Icon(Icons.arrow_upward_rounded),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (value) => setState(() => _type = value.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _search,
            decoration: InputDecoration(
              labelText: 'Buscar categoria ou subcategoria',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpar busca',
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
            textInputAction: TextInputAction.search,
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 16),
          if (categories.isEmpty)
            AppSurface(
              child: PremiumEmptyState(
                compact: true,
                icon: Icons.category_outlined,
                title: 'Nenhuma categoria por aqui',
                subtitle:
                    'Categorias organizam os lançamentos e alimentam o '
                    'orçamento e os gráficos do painel.',
                action: FilledButton.icon(
                  onPressed: () =>
                      _showCategorySheet(context, initialType: _type),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Criar categoria'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, kHopeMinTapTarget),
                    padding: const EdgeInsets.symmetric(
                      horizontal: HopeSpacing.lg,
                    ),
                  ),
                ),
              ),
            ),
          if (categories.isNotEmpty && categoryResults.isEmpty)
            AppSurface(
              child: PremiumEmptyState(
                compact: true,
                icon: Icons.search_off_outlined,
                title: 'Nada encontrado para "$_query"',
                subtitle:
                    'Tente outro nome de categoria ou subcategoria.',
                action: TextButton(
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                  child: const Text('Limpar busca'),
                ),
              ),
            ),
          for (final result in categoryResults)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _CategoryCard(
                category: result.category,
                subcategories: result.subcategories,
                onEdit: () =>
                    _showCategorySheet(context, category: result.category),
                onDelete: result.category.isSystem
                    ? null
                    : () => _confirmDeleteCategory(context, result.category),
                onAddSubcategory: () =>
                    _showSubcategorySheet(context, category: result.category),
                onEditSubcategory: (subcategory) => _showSubcategorySheet(
                  context,
                  category: result.category,
                  subcategory: subcategory,
                ),
                onDeleteSubcategory: (subcategory) =>
                    _confirmDeleteSubcategory(context, subcategory),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showCategorySheet(
    BuildContext context, {
    LocalCategory? category,
    String initialType = 'expense',
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CategorySheet(
        category: category,
        initialType: category?.type ?? initialType,
      ),
    );
  }

  Future<void> _showSubcategorySheet(
    BuildContext context, {
    required LocalCategory category,
    LocalSubcategory? subcategory,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          _SubcategorySheet(category: category, subcategory: subcategory),
    );
  }

  Future<void> _confirmDeleteCategory(
    BuildContext context,
    LocalCategory category,
  ) async {
    final repository = ref.read(financeRepositoryProvider);
    final inUse = await repository.categoryHasReferences(category.id);
    if (!context.mounted) return;
    if (inUse) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Categoria em uso'),
          content: const Text(
            'Esta categoria possui lançamentos ou orçamentos vinculados e não '
            'pode ser excluída. Remova ou recategorize esses vínculos antes.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Entendi'),
            ),
          ],
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir categoria?'),
        content: const Text(
          'As subcategorias desta categoria também serão removidas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await repository.deleteCategory(category);
      ref.read(syncServiceProvider).syncNow();
    }
  }

  Future<void> _confirmDeleteSubcategory(
    BuildContext context,
    LocalSubcategory subcategory,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir subcategoria?'),
        content: Text('Remover "${subcategory.name}" da sua organização?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(financeRepositoryProvider).deleteSubcategory(subcategory);
      ref.read(syncServiceProvider).syncNow();
    }
  }
}

class _CategorySearchResult {
  const _CategorySearchResult(this.category, this.subcategories);

  final LocalCategory category;
  final List<LocalSubcategory> subcategories;
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.subcategories,
    required this.onEdit,
    required this.onDelete,
    required this.onAddSubcategory,
    required this.onEditSubcategory,
    required this.onDeleteSubcategory,
  });

  final LocalCategory category;
  final List<LocalSubcategory> subcategories;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;
  final VoidCallback onAddSubcategory;
  final ValueChanged<LocalSubcategory> onEditSubcategory;
  final ValueChanged<LocalSubcategory> onDeleteSubcategory;

  @override
  Widget build(BuildContext context) {
    final color =
        _parseColor(category.color) ??
        (category.type == 'income' ? context.hopeColors.income : context.hopeColors.expense);
    return Card(
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.14),
          child: Icon(_iconFor(category.icon), color: color),
        ),
        title: Text(category.name),
        subtitle: Text(
          subcategories.isEmpty
              ? 'Sem subcategorias'
              : '${subcategories.length} subcategorias',
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: 'Editar categoria',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Excluir categoria',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onAddSubcategory,
              icon: const Icon(Icons.add),
              label: const Text('Subcategoria'),
            ),
          ),
          for (final subcategory in subcategories)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_iconFor(subcategory.icon), color: color),
              title: Text(subcategory.name),
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: 'Editar subcategoria',
                    onPressed: () => onEditSubcategory(subcategory),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Excluir subcategoria',
                    onPressed: () => onDeleteSubcategory(subcategory),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CategorySheet extends ConsumerStatefulWidget {
  const _CategorySheet({this.category, required this.initialType});

  final LocalCategory? category;
  final String initialType;

  @override
  ConsumerState<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends ConsumerState<_CategorySheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  String _type = 'expense';
  String _color = '#2F80ED';
  String? _icon;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final category = widget.category;
    _name.text = category?.name ?? '';
    _type = category?.type ?? widget.initialType;
    _color =
        category?.color ??
        (_type == 'income' ? '#27AE60' : AppTheme.expense.toHex());
    _icon = category?.icon;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final category = widget.category;
    await ref
        .read(financeRepositoryProvider)
        .upsertCategory(
          id: category?.id,
          name: _name.text.trim(),
          type: _type,
          icon: _icon,
          color: _color,
          isSystem: category?.isSystem ?? false,
          currentVersion: category?.version,
        );
    ref.read(syncServiceProvider).syncNow();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PremiumFormSheet(
      title: widget.category == null ? 'Nova categoria' : 'Editar categoria',
      subtitle:
          'Defina como essa categoria aparece nos lançamentos e gráficos.',
      icon: Icons.category_outlined,
      formKey: _formKey,
      fields: [
        PremiumFormSection(
          title: 'Dados principais',
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nome',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Informe o nome'
                  : null,
            ),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'expense',
                  label: Text('Despesa'),
                  icon: Icon(Icons.arrow_downward_rounded),
                ),
                ButtonSegment(
                  value: 'income',
                  label: Text('Receita'),
                  icon: Icon(Icons.arrow_upward_rounded),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (value) => setState(() {
                _type = value.first;
                _color = _type == 'income' ? '#27AE60' : '#EB5757';
              }),
            ),
          ],
        ),
        PremiumFormSection(
          title: 'Aparência',
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final color in const [
                  '#2F80ED',
                  '#27AE60',
                  '#EB5757',
                  '#F2994A',
                  '#9B51E0',
                  '#00A3A3',
                ])
                  ChoiceChip(
                    label: const SizedBox(width: 18, height: 18),
                    selected: _color == color,
                    avatar: CircleAvatar(backgroundColor: _parseColor(color)),
                    onSelected: (_) => setState(() => _color = color),
                  ),
              ],
            ),
            IconPickerGrid(
              icons: categoryIcons,
              selected: _icon,
              color:
                  _parseColor(_color) ??
                  (_type == 'income' ? context.hopeColors.income : context.hopeColors.expense),
              onSelected: (key) => setState(() => _icon = key),
            ),
          ],
        ),
      ],
      secondaryAction: OutlinedButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      primaryAction: FilledButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check_circle_outline),
        label: const Text('Salvar'),
      ),
    );
  }
}

class _SubcategorySheet extends ConsumerStatefulWidget {
  const _SubcategorySheet({required this.category, this.subcategory});

  final LocalCategory category;
  final LocalSubcategory? subcategory;

  @override
  ConsumerState<_SubcategorySheet> createState() => _SubcategorySheetState();
}

class _SubcategorySheetState extends ConsumerState<_SubcategorySheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  String? _icon;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name.text = widget.subcategory?.name ?? '';
    _icon = widget.subcategory?.icon;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final subcategory = widget.subcategory;
    await ref
        .read(financeRepositoryProvider)
        .upsertSubcategory(
          id: subcategory?.id,
          categoryId: widget.category.id,
          name: _name.text.trim(),
          icon: _icon,
          currentVersion: subcategory?.version,
        );
    ref.read(syncServiceProvider).syncNow();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PremiumFormSheet(
      title: widget.subcategory == null
          ? 'Nova subcategoria'
          : 'Editar subcategoria',
      subtitle: widget.category.name,
      icon: Icons.label_outline,
      formKey: _formKey,
      fields: [
        PremiumFormSection(
          title: 'Dados principais',
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nome',
                prefixIcon: Icon(Icons.label_outline),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Informe o nome'
                  : null,
            ),
            IconPickerGrid(
              icons: categoryIcons,
              selected: _icon,
              color:
                  _parseColor(widget.category.color) ??
                  (widget.category.type == 'income'
                      ? context.hopeColors.income
                      : context.hopeColors.expense),
              onSelected: (key) => setState(() => _icon = key),
            ),
          ],
        ),
      ],
      secondaryAction: OutlinedButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      primaryAction: FilledButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check_circle_outline),
        label: const Text('Salvar'),
      ),
    );
  }
}

/// Catálogo de ícones para categorias e subcategorias (chave salva no banco →
/// ícone). Mantido amplo para cobrir os principais tipos de gasto/receita.
const categoryIcons = <String, IconData>{
  'home': Icons.home_outlined,
  'rent': Icons.apartment_outlined,
  'maintenance': Icons.handyman_outlined,
  'food': Icons.restaurant_outlined,
  'groceries': Icons.shopping_cart_outlined,
  'coffee': Icons.local_cafe_outlined,
  'bar': Icons.local_bar_outlined,
  'car': Icons.directions_car_outlined,
  'transport': Icons.directions_bus_outlined,
  'fuel': Icons.local_gas_station_outlined,
  'flight': Icons.flight_outlined,
  'travel': Icons.luggage_outlined,
  'health': Icons.health_and_safety_outlined,
  'medicine': Icons.medical_services_outlined,
  'fitness': Icons.fitness_center_outlined,
  'beauty': Icons.spa_outlined,
  'work': Icons.work_outline,
  'salary': Icons.payments_outlined,
  'business': Icons.storefront_outlined,
  'education': Icons.school_outlined,
  'books': Icons.menu_book_outlined,
  'shopping': Icons.shopping_bag_outlined,
  'clothing': Icons.checkroom_outlined,
  'gift': Icons.card_giftcard_outlined,
  'entertainment': Icons.movie_outlined,
  'games': Icons.sports_esports_outlined,
  'music': Icons.music_note_outlined,
  'sports': Icons.sports_soccer_outlined,
  'pets': Icons.pets_outlined,
  'kids': Icons.child_care_outlined,
  'phone': Icons.smartphone_outlined,
  'internet': Icons.wifi_outlined,
  'subscription': Icons.subscriptions_outlined,
  'bills': Icons.receipt_long_outlined,
  'water': Icons.water_drop_outlined,
  'electricity': Icons.bolt_outlined,
  'gas': Icons.local_fire_department_outlined,
  'insurance': Icons.shield_outlined,
  'taxes': Icons.account_balance_outlined,
  'savings': Icons.savings_outlined,
  'investment': Icons.trending_up_outlined,
  'card': Icons.credit_card_outlined,
  'donation': Icons.volunteer_activism_outlined,
  'more': Icons.category_outlined,
};

IconData _iconFor(String? value) =>
    categoryIcons[value] ?? Icons.category_outlined;

bool _matchesSearch(String value, String normalizedQuery) =>
    _normalizeSearch(value).contains(normalizedQuery);

String _normalizeSearch(String value) {
  const replacements = {
    'á': 'a',
    'à': 'a',
    'ã': 'a',
    'â': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'õ': 'o',
    'ô': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
  };
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    buffer.write(replacements[char] ?? char);
  }
  return buffer.toString().trim();
}

Color? _parseColor(String? value) {
  if (value == null || value.isEmpty) return null;
  final hex = value.replaceFirst('#', '');
  final parsed = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
  return parsed == null ? null : Color(parsed);
}

extension on Color {
  String toHex() =>
      '#${toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
}
