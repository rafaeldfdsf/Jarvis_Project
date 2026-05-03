import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_flutter/models/auth_models.dart';
import 'package:jarvis_flutter/models/chat_response.dart';
import 'package:jarvis_flutter/models/routine.dart';

void main() {
  test('ChatResponseModel faz parsing de client action e tool result', () {
    final response = ChatResponseModel.fromJson({
      'reply': 'A abrir o Spotify.',
      'transcript': 'abre o spotify',
      'client_action': {
        'type': 'pc_action',
        'action': 'open_app',
        'arguments': {'app_name': 'spotify'},
      },
      'tool_result': {
        'tool_name': 'open_app',
        'ok': true,
        'data': 'Acao enviada para o cliente.',
      },
      'tool_call': {
        'type': 'tool_call',
        'tool_name': 'open_app',
        'arguments': {'app_name': 'spotify'},
      },
    });

    expect(response.reply, 'A abrir o Spotify.');
    expect(response.transcript, 'abre o spotify');
    expect(response.clientAction?.action, 'open_app');
    expect(response.clientAction?.arguments['app_name'], 'spotify');
    expect(response.toolResult?.ok, isTrue);
    expect(response.toolCall?.toolName, 'open_app');
  });

  test('RoutineAction serializa apenas campos preenchidos', () {
    const action = RoutineAction(
      type: 'home_assistant_service',
      domain: 'light',
      service: 'turn_off',
      entityId: 'light.sala',
      serviceData: {'transition': 2},
      message: '   ',
    );

    expect(action.toJson(), {
      'type': 'home_assistant_service',
      'domain': 'light',
      'service': 'turn_off',
      'entity_id': 'light.sala',
      'service_data': {'transition': 2},
    });
  });

  test('AuthUserModel preserva round-trip do payload', () {
    const user = AuthUserModel(
      id: 'user-1',
      email: 'rafael@example.com',
      displayName: 'Rafael',
      createdAt: '2026-05-03T10:00:00+00:00',
      emailVerified: true,
      emailVerifiedAt: '2026-05-03T10:05:00+00:00',
    );

    final restored = AuthUserModel.fromJson(user.toJson());

    expect(restored.id, user.id);
    expect(restored.email, user.email);
    expect(restored.displayName, user.displayName);
    expect(restored.emailVerified, isTrue);
    expect(restored.emailVerifiedAt, user.emailVerifiedAt);
  });
}
