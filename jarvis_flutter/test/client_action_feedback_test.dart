import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_flutter/models/chat_response.dart';
import 'package:jarvis_flutter/services/client_action_feedback.dart';

void main() {
  test('gera mensagem honesta para falha a abrir app', () {
    final action = ClientAction(
      type: 'pc_action',
      action: 'open_app',
      arguments: const <String, dynamic>{'app_name': 'spotify'},
    );

    final message = buildClientActionFailureMessage(
      action,
      detail: 'Timeout ao esperar resposta do agente pc-escritorio.',
    );

    expect(message, contains('Nao consegui abrir spotify.'));
    expect(message, contains('Timeout ao esperar resposta do agente'));
  });

  test('gera mensagem especifica para falha a tocar musica no YouTube', () {
    final action = ClientAction(
      type: 'pc_action',
      action: 'youtube_play',
      arguments: const <String, dynamic>{'query': 'musica calma'},
    );

    final message = buildClientActionFailureMessage(action);

    expect(message, 'Nao consegui por a musica a tocar no YouTube.');
  });
}
