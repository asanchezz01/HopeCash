import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hopecash/core/theme/app_theme.dart';

void main() {
  test('iOS usa escala tipográfica mais compacta sem ultrapassar o piso', () {
    final ios = AppTheme.light(platform: TargetPlatform.iOS).textTheme;
    final android = AppTheme.light(platform: TargetPlatform.android).textTheme;

    expect(ios.bodyLarge?.fontSize, closeTo(15.2, 0.001));
    expect(android.bodyLarge?.fontSize, 16);
    expect(ios.displaySmall?.fontSize, closeTo(30.4, 0.001));
    expect(ios.labelSmall?.fontSize, 11);
  });

  test('escala compacta também é aplicada no tema escuro do iOS', () {
    final iosDark = AppTheme.dark(platform: TargetPlatform.iOS);

    expect(iosDark.platform, TargetPlatform.iOS);
    expect(iosDark.textTheme.titleLarge?.fontSize, 19);
    expect(iosDark.textTheme.bodyMedium?.fontSize, closeTo(13.3, 0.001));
  });
}
