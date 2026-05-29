import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_flutter/services/continuous_conversation_service.dart';

void main() {
  const service = ContinuousConversationService();

  test('normaliza acentos reais e mojibake para frases de paragem', () {
    expect(service.normalizeCommandText('Já podes parar.'), 'ja podes parar');
    expect(service.normalizeCommandText('JÃ¡ podes parar.'), 'ja podes parar');
    expect(
      service.normalizeCommandText('Desliga conversa contínua, por favor!'),
      'desliga conversa continua por favor',
    );
  });

  test('deteta frases naturais de paragem da conversa continua', () {
    expect(service.isStopCommand('Já podes parar.'), isTrue);
    expect(service.isStopCommand('Podes parar a conversa agora.'), isTrue);
    expect(
      service.isStopCommand('Se quiseres, desliga conversa contínua.'),
      isTrue,
    );
    expect(service.isStopCommand('Quero continuar a falar contigo.'), isFalse);
  });

  test('interceta comando de paragem no modo continuo e follow-up', () {
    expect(
      service.shouldInterceptStopCommand(
        continuousConversationEnabled: true,
        isFollowUp: false,
        overlayOnly: false,
      ),
      isTrue,
    );
    expect(
      service.shouldInterceptStopCommand(
        continuousConversationEnabled: false,
        isFollowUp: true,
        overlayOnly: false,
      ),
      isTrue,
    );
    expect(
      service.shouldInterceptStopCommand(
        continuousConversationEnabled: false,
        isFollowUp: false,
        overlayOnly: false,
      ),
      isFalse,
    );
    expect(
      service.shouldInterceptStopCommand(
        continuousConversationEnabled: true,
        isFollowUp: true,
        overlayOnly: true,
      ),
      isFalse,
    );
  });
}
