import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/database.dart';
import 'quick_create_category.dart';

const _emptyCategoryValue = '__empty_category__';

class SearchableCategoryField extends StatelessWidget {
  const SearchableCategoryField({
    super.key,
    required this.categories,
    required this.value,
    required this.onChanged,
    this.labelText = 'Categoria',
    this.placeholder = 'Selecione uma categoria',
    this.emptyLabel = 'Sem categoria',
    this.allowEmpty = true,
    this.enabled = true,
    this.validator,
    this.quickCreateType,
  });

  final List<LocalCategory> categories;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String labelText;
  final String placeholder;
  final String emptyLabel;
  final bool allowEmpty;
  final bool enabled;
  final String? Function(String?)? validator;

  /// Quando informado ('expense' ou 'income'), a busca exibe um atalho para
  /// criar uma nova categoria desse tipo na hora.
  final String? quickCreateType;

  @override
  Widget build(BuildContext context) {
    final selectedCategory = _categoryById(categories, value);
    return FormField<String>(
      key: ValueKey('category-search-${value ?? 'none'}-${categories.length}'),
      initialValue: value,
      validator: (_) => validator?.call(value),
      builder: (field) {
        final textTheme = Theme.of(context).textTheme;
        final scheme = Theme.of(context).colorScheme;
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled
              ? () async {
                  FocusScope.of(context).unfocus();
                  final picked = await showModalBottomSheet<String>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    showDragHandle: true,
                    builder: (_) => _CategorySearchSheet(
                      title: labelText,
                      categories: categories,
                      selectedId: value,
                      allowEmpty: allowEmpty,
                      emptyLabel: emptyLabel,
                      quickCreateType: quickCreateType,
                    ),
                  );
                  if (picked == null) return;
                  final nextValue = picked == _emptyCategoryValue
                      ? null
                      : picked;
                  field.didChange(nextValue);
                  onChanged(nextValue);
                }
              : null,
          child: InputDecorator(
            isEmpty: selectedCategory == null,
            decoration: InputDecoration(
              labelText: labelText,
              prefixIcon: const Icon(Icons.category_outlined),
              suffixIcon: const Icon(Icons.search_rounded),
              enabled: enabled,
              errorText: field.errorText,
            ),
            child: Text(
              selectedCategory?.name ?? placeholder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: selectedCategory == null
                  ? textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    )
                  : textTheme.bodyLarge,
            ),
          ),
        );
      },
    );
  }
}

class _CategorySearchSheet extends ConsumerStatefulWidget {
  const _CategorySearchSheet({
    required this.title,
    required this.categories,
    required this.selectedId,
    required this.allowEmpty,
    required this.emptyLabel,
    this.quickCreateType,
  });

  final String title;
  final List<LocalCategory> categories;
  final String? selectedId;
  final bool allowEmpty;
  final String emptyLabel;
  final String? quickCreateType;

  @override
  ConsumerState<_CategorySearchSheet> createState() =>
      _CategorySearchSheetState();
}

class _CategorySearchSheetState extends ConsumerState<_CategorySearchSheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _createNew() async {
    final id = await showQuickCreateCategory(
      context,
      ref,
      type: widget.quickCreateType!,
      initialName: _query.trim(),
    );
    if (id != null && mounted) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _normalizeCategorySearch(_query);
    final filtered = normalizedQuery.isEmpty
        ? widget.categories
        : widget.categories
              .where(
                (category) => _normalizeCategorySearch(
                  category.name,
                ).contains(normalizedQuery),
              )
              .toList();
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, bottom + 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.82,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                controller: _search,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Buscar por nome da categoria',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpar busca',
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
                textInputAction: TextInputAction.search,
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 12),
              Flexible(
                child:
                    widget.categories.isEmpty && widget.quickCreateType == null
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Nenhuma categoria cadastrada.'),
                        ),
                      )
                    : filtered.isEmpty && widget.quickCreateType == null
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Nenhuma categoria encontrada.'),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          if (widget.allowEmpty && normalizedQuery.isEmpty)
                            _CategoryOptionTile(
                              icon: Icons.block_outlined,
                              title: widget.emptyLabel,
                              selected: widget.selectedId == null,
                              onTap: () =>
                                  Navigator.pop(context, _emptyCategoryValue),
                            ),
                          for (final category in filtered)
                            _CategoryOptionTile(
                              icon: Icons.category_outlined,
                              title: category.name,
                              selected: category.id == widget.selectedId,
                              onTap: () => Navigator.pop(context, category.id),
                            ),
                          if (widget.quickCreateType != null)
                            _CategoryOptionTile(
                              icon: Icons.add_rounded,
                              title: _query.trim().isEmpty
                                  ? 'Criar nova categoria'
                                  : 'Criar categoria "${_query.trim()}"',
                              selected: false,
                              onTap: _createNew,
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryOptionTile extends StatelessWidget {
  const _CategoryOptionTile({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: Theme.of(
          context,
        ).colorScheme.primary.withValues(alpha: 0.12),
        child: Icon(icon, color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: selected ? const Icon(Icons.check_rounded) : null,
      selected: selected,
      onTap: onTap,
    );
  }
}

LocalCategory? _categoryById(List<LocalCategory> categories, String? id) {
  if (id == null) return null;
  for (final category in categories) {
    if (category.id == id) return category;
  }
  return null;
}

String _normalizeCategorySearch(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[áàâãä]'), 'a')
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[íìîï]'), 'i')
      .replaceAll(RegExp(r'[óòôõö]'), 'o')
      .replaceAll(RegExp(r'[úùûü]'), 'u')
      .replaceAll('ç', 'c')
      .trim();
}
