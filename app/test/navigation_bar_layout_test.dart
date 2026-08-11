import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hopecash/core/theme/app_theme.dart';

void main() {
  testWidgets('rótulo Histórico não quebra na largura do iPhone 11', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(414, 896));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          bottomNavigationBar: NavigationBar(
            selectedIndex: 1,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                label: 'Início',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                label: 'Histórico',
              ),
              NavigationDestination(
                icon: Icon(Icons.account_balance_outlined),
                label: 'Contas',
              ),
              NavigationDestination(
                icon: Icon(Icons.more_horiz),
                label: 'Mais',
              ),
            ],
          ),
        ),
      ),
    );

    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('Histórico'),
    );
    final textBoxes = paragraph.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: 9),
    );
    expect(
      textBoxes.map((box) => box.top).toSet(),
      hasLength(1),
      reason:
          'bar=${tester.getSize(find.byType(NavigationBar))}, '
          'label=${paragraph.size}, boxes=$textBoxes',
    );
    expect(tester.takeException(), isNull);
  });
}
