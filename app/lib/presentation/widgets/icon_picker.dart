import 'package:flutter/material.dart';

/// Grade de ícones selecionáveis, tingidos com [color].
///
/// Usada nos formulários de contas e categorias como seletor visual de ícone
/// (substitui dropdowns). Não cria rolagem interna; o formulário pai controla
/// o scroll para evitar telas com gestos competindo.
class IconPickerGrid extends StatelessWidget {
  const IconPickerGrid({
    super.key,
    required this.icons,
    required this.selected,
    required this.color,
    required this.onSelected,
  });

  /// Chave (salva no banco) → ícone exibido.
  final Map<String, IconData> icons;
  final String? selected;
  final Color color;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final entry in icons.entries)
            _IconChoice(
              icon: entry.value,
              selected: selected == entry.key,
              color: color,
              onTap: () => onSelected(entry.key),
            ),
        ],
      ),
    );
  }
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: selected ? 0.22 : 0.08),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? color
                : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Icon(
          icon,
          size: 22,
          color: selected
              ? color
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
