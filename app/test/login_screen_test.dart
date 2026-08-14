import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hopecash/presentation/screens/login_screen.dart';

void main() {
  testWidgets('LoginScreen usa painel de marca apenas em tela larga', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );

    expect(find.text('Sua vida financeira, mais clara'), findsOneWidget);
    expect(find.byType(Card), findsNothing);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();

    expect(find.text('Sua vida financeira, mais clara'), findsNothing);
    expect(find.text('Acesse sua carteira'), findsOneWidget);
  });

  testWidgets('LoginScreen valida campos obrigatórios', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );

    expect(find.text('HopeCash'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);

    // Submeter vazio deve mostrar validações, sem chamar a API.
    await tester.tap(find.text('Entrar'));
    await tester.pump();
    expect(find.text('E-mail inválido'), findsOneWidget);
    expect(find.text('Mínimo de 8 caracteres'), findsOneWidget);

    // Alternar para cadastro exibe o campo de nome.
    await tester.tap(find.text('Criar uma conta gratuita'));
    await tester.pump();
    expect(find.text('Nome'), findsOneWidget);
    expect(find.text('Criar conta'), findsOneWidget);
  });

  testWidgets('LoginScreen exibe fluxo de recuperação de senha', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );

    expect(find.text('Esqueci minha senha'), findsOneWidget);

    await tester.tap(find.text('Esqueci minha senha'));
    await tester.pumpAndSettle();

    expect(find.text('Recuperar senha'), findsOneWidget);

    await tester.tap(find.text('Enviar'));
    await tester.pump();
    expect(find.text('E-mail inválido'), findsOneWidget);

    await tester.tap(find.text('Já tenho token'));
    await tester.pumpAndSettle();

    expect(find.text('Redefinir senha'), findsOneWidget);
    expect(find.text('Token recebido'), findsOneWidget);
  });
}
