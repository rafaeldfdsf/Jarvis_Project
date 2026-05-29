import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_flutter/screens/voice_assistant_screen.dart';

void main() {
  testWidgets(
    'VoiceAssistantScreen mostra controlos locais sem arrancar o runtime',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VoiceAssistantScreen(embedded: true, autoInitialize: false),
          ),
        ),
      );

      expect(find.text('Pronto para conversar'), findsOneWidget);
      expect(find.text('Conversa continua desligada'), findsOneWidget);
      expect(find.text('Mostrar transcricao'), findsOneWidget);

      await tester.tap(find.text('Mostrar transcricao'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Ultimo texto reconhecido'), findsOneWidget);
      expect(
        find.text(
          'Ativa a conversa continua para falar sem repetir a wake word.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Conversa continua desligada'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Conversa continua ligada'), findsOneWidget);
      expect(
        find.text("Diz 'parar conversa' para sair da escuta continua."),
        findsOneWidget,
      );

      await tester.tap(find.text('Conversa continua ligada'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Conversa continua desligada'), findsOneWidget);
      expect(
        find.text(
          'Ativa a conversa continua para falar sem repetir a wake word.',
        ),
        findsOneWidget,
      );
    },
  );
}
