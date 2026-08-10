import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// Diálogos de criação rápida (ad-hoc) de categoria e subcategoria, usados
/// como atalho nos seletores espalhados pelo app. Criam localmente, disparam
/// a sincronização em segundo plano e retornam o id criado (ou null se
/// cancelado), para o chamador selecionar o novo valor imediatamente.

Future<String?> showQuickCreateCategory(
  BuildContext context,
  WidgetRef ref, {
  required String type,
  String initialName = '',
}) async {
  final name = await _promptName(
    context,
    title: type == 'income' ? 'Nova categoria de receita' : 'Nova categoria',
    label: 'Nome da categoria',
    initialName: initialName,
  );
  if (name == null) return null;
  final id = await ref
      .read(financeRepositoryProvider)
      .upsertCategory(name: name, type: type);
  ref.read(syncServiceProvider).syncNow();
  return id;
}

Future<String?> showQuickCreateSubcategory(
  BuildContext context,
  WidgetRef ref, {
  required String categoryId,
  String initialName = '',
}) async {
  final name = await _promptName(
    context,
    title: 'Nova subcategoria',
    label: 'Nome da subcategoria',
    initialName: initialName,
  );
  if (name == null) return null;
  final id = await ref
      .read(financeRepositoryProvider)
      .upsertSubcategory(categoryId: categoryId, name: name);
  ref.read(syncServiceProvider).syncNow();
  return id;
}

/// Dropdown de subcategoria com atalho "+" para criar uma nova na hora.
/// Fica visível sempre que houver categoria selecionada — inclusive quando a
/// categoria ainda não tem subcategorias, caso em que o atalho é a única ação.
class SubcategorySelector extends ConsumerWidget {
  const SubcategorySelector({
    super.key,
    required this.categoryId,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.emptyOptionLabel = 'Sem subcategoria',
    this.labelText = 'Subcategoria',
    this.prefixIcon = Icons.label_outline,
    this.dense = false,
  });

  final String? categoryId;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  final String emptyOptionLabel;
  final String labelText;
  final IconData prefixIcon;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoryId = this.categoryId;
    if (categoryId == null) return const SizedBox.shrink();
    final subcategories = (ref.watch(subcategoriesProvider).valueOrNull ?? [])
        .where((s) => s.categoryId == categoryId)
        .toList();

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String?>(
            // A quantidade entra na chave para reaplicar o initialValue assim
            // que uma subcategoria recém-criada chegar pela stream local.
            key: ValueKey(
              'subcat-$categoryId-$value-${subcategories.length}',
            ),
            initialValue: subcategories.any((s) => s.id == value)
                ? value
                : null,
            isExpanded: true,
            isDense: dense,
            decoration: InputDecoration(
              labelText: labelText,
              isDense: dense,
              prefixIcon: Icon(prefixIcon, size: dense ? 18 : null),
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(emptyOptionLabel),
              ),
              for (final s in subcategories)
                DropdownMenuItem<String?>(
                  value: s.id,
                  child: Text(s.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: enabled && subcategories.isNotEmpty ? onChanged : null,
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Nova subcategoria',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add_circle_outline),
          onPressed: !enabled
              ? null
              : () async {
                  final id = await showQuickCreateSubcategory(
                    context,
                    ref,
                    categoryId: categoryId,
                  );
                  if (id != null) onChanged(id);
                },
        ),
      ],
    );
  }
}

Future<String?> _promptName(
  BuildContext context, {
  required String title,
  required String label,
  required String initialName,
}) async {
  final controller = TextEditingController(text: initialName);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Criar'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (name == null || name.isEmpty) return null;
  return name;
}
