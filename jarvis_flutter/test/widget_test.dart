import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jarvis_flutter/screens/login_screen.dart';

void main() {
  testWidgets('LoginScreen mostra as accoes principais do modo login', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Criar uma conta nova'), findsOneWidget);
    expect(find.text('Esqueci-me da palavra-passe'), findsOneWidget);
    expect(find.text('Entrar'), findsWidgets);
  });

  testWidgets('LoginScreen alterna entre os modos de autenticacao', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Criar uma conta nova'), findsOneWidget);

    await tester.tap(find.text('Criar uma conta nova'));
    await tester.pumpAndSettle();

    expect(find.text('Criar Conta'), findsOneWidget);
    expect(find.text('Ja tenho conta'), findsOneWidget);

    await tester.tap(find.text('Ja tenho conta'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ja tenho um codigo de verificacao'));
    await tester.pumpAndSettle();

    expect(find.text('Confirmar Email'), findsOneWidget);
    expect(find.text('Reenviar codigo'), findsOneWidget);

    await tester.tap(find.text('Voltar ao login'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Esqueci-me da palavra-passe'));
    await tester.pumpAndSettle();

    expect(find.text('Recuperar Palavra-passe'), findsOneWidget);
    expect(find.text('Enviar codigo'), findsOneWidget);
  });
}
