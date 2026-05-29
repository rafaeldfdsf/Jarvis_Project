import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_flutter/models/chat_response.dart';
import 'package:jarvis_flutter/services/api_service.dart';
import 'package:jarvis_flutter/services/conversation_service.dart';

class _FakeConversationApiService extends ApiService {
  int createSessionCalls = 0;
  int sendMessageCalls = 0;
  int sendVoiceTurnCalls = 0;
  final List<String> seenSessionIds = <String>[];
  bool failFirstTextRequestWithUnknownSession = false;
  bool failFirstVoiceRequestWithUnknownSession = false;

  int _textUnknownSessionFailures = 0;
  int _voiceUnknownSessionFailures = 0;

  @override
  Future<String> createSession() async {
    createSessionCalls += 1;
    return createSessionCalls == 1
        ? 'sess-voice-chat'
        : 'sess-voice-chat-$createSessionCalls';
  }

  @override
  Future<ChatResponseModel> sendMessage(
    String sessionId,
    String message,
  ) async {
    sendMessageCalls += 1;
    seenSessionIds.add(sessionId);
    if (failFirstTextRequestWithUnknownSession &&
        _textUnknownSessionFailures == 0) {
      _textUnknownSessionFailures += 1;
      return ChatResponseModel(reply: 'Sessao desconhecida: $sessionId');
    }
    return ChatResponseModel(reply: 'Resposta ao texto: $message');
  }

  @override
  Future<ChatResponseModel> sendVoiceTurn(
    String sessionId,
    Uint8List wavBytes, {
    String? platform,
    String? locale,
  }) async {
    sendVoiceTurnCalls += 1;
    seenSessionIds.add(sessionId);
    if (failFirstVoiceRequestWithUnknownSession &&
        _voiceUnknownSessionFailures == 0) {
      _voiceUnknownSessionFailures += 1;
      return ChatResponseModel(reply: 'Sessao desconhecida: $sessionId');
    }
    return ChatResponseModel(
      reply: 'Resposta ao audio',
      transcript: 'transcricao de voz',
    );
  }
}

void main() {
  test(
    'ConversationService partilha a mesma sessao entre voz e chat',
    () async {
      final api = _FakeConversationApiService();
      final service = ConversationService.test(api: api);

      final voiceResponse = await service.sendVoiceTurn(
        Uint8List.fromList(<int>[1, 2, 3]),
        platform: 'windows',
        locale: 'pt-PT',
      );
      final textResponse = await service.sendTextMessage('continua');

      expect(voiceResponse.transcript, 'transcricao de voz');
      expect(textResponse.reply, 'Resposta ao texto: continua');
      expect(api.createSessionCalls, 1);
      expect(api.sendVoiceTurnCalls, 1);
      expect(api.sendMessageCalls, 1);
      expect(api.seenSessionIds, everyElement('sess-voice-chat'));
      expect(service.sessionId, 'sess-voice-chat');
      expect(service.messages.map((item) => item.text).toList(), <String>[
        'transcricao de voz',
        'Resposta ao audio',
        'continua',
        'Resposta ao texto: continua',
      ]);
      expect(service.messages.map((item) => item.isUser).toList(), <bool>[
        true,
        false,
        true,
        false,
      ]);
    },
  );

  test(
    'ConversationService mantém a mesma sessao ao longo de varios follow-ups',
    () async {
      final api = _FakeConversationApiService();
      final service = ConversationService.test(api: api);

      final firstVoice = await service.sendVoiceTurn(
        Uint8List.fromList(<int>[1, 2, 3]),
        platform: 'windows',
        locale: 'pt-PT',
      );
      final secondVoice = await service.sendVoiceTurn(
        Uint8List.fromList(<int>[4, 5, 6]),
        platform: 'windows',
        locale: 'pt-PT',
      );
      final textResponse = await service.sendTextMessage('e continua');

      expect(firstVoice.reply, 'Resposta ao audio');
      expect(secondVoice.reply, 'Resposta ao audio');
      expect(textResponse.reply, 'Resposta ao texto: e continua');
      expect(api.createSessionCalls, 1);
      expect(api.sendVoiceTurnCalls, 2);
      expect(api.sendMessageCalls, 1);
      expect(
        api.seenSessionIds,
        everyElement('sess-voice-chat'),
      );
      expect(
        service.messages.map((item) => item.text).toList(),
        <String>[
          'transcricao de voz',
          'Resposta ao audio',
          'transcricao de voz',
          'Resposta ao audio',
          'e continua',
          'Resposta ao texto: e continua',
        ],
      );
    },
  );

  test(
    'appendLocalExchange adiciona utilizador e assistente na ordem certa',
    () {
      final service = ConversationService.test(
        api: _FakeConversationApiService(),
      );

      service.appendLocalExchange(
        userText: 'parar conversa',
        assistantReply: 'Conversa continua desligada.',
      );

      expect(service.messages.length, 2);
      expect(service.messages.first.text, 'parar conversa');
      expect(service.messages.first.isUser, isTrue);
      expect(service.messages.last.text, 'Conversa continua desligada.');
      expect(service.messages.last.isUser, isFalse);
    },
  );

  test(
    'appendLocalExchange permite acrescentar apenas a resposta local do assistente',
    () {
      final service = ConversationService.test(
        api: _FakeConversationApiService(),
      );

      service.appendLocalExchange(
        userText: '',
        assistantReply: 'Nao consegui executar essa acao no dispositivo.',
      );

      expect(service.messages.length, 1);
      expect(service.messages.single.text, 'Nao consegui executar essa acao no dispositivo.');
      expect(service.messages.single.isUser, isFalse);
    },
  );

  test(
    'ConversationService recria a sessao quando o chat perde contexto',
    () async {
      final api = _FakeConversationApiService()
        ..failFirstTextRequestWithUnknownSession = true;
      final service = ConversationService.test(api: api);

      final response = await service.sendTextMessage('ola outra vez');

      expect(response.reply, 'Resposta ao texto: ola outra vez');
      expect(api.createSessionCalls, 2);
      expect(api.sendMessageCalls, 2);
      expect(api.seenSessionIds, <String>[
        'sess-voice-chat',
        'sess-voice-chat-2',
      ]);
      expect(service.sessionId, 'sess-voice-chat-2');
      expect(service.messages.map((item) => item.text).toList(), <String>[
        'ola outra vez',
        'Resposta ao texto: ola outra vez',
      ]);
    },
  );

  test(
    'ConversationService recria a sessao quando a voz perde contexto',
    () async {
      final api = _FakeConversationApiService()
        ..failFirstVoiceRequestWithUnknownSession = true;
      final service = ConversationService.test(api: api);

      final response = await service.sendVoiceTurn(
        Uint8List.fromList(<int>[7, 8, 9]),
        platform: 'windows',
        locale: 'pt-PT',
      );

      expect(response.reply, 'Resposta ao audio');
      expect(response.transcript, 'transcricao de voz');
      expect(api.createSessionCalls, 2);
      expect(api.sendVoiceTurnCalls, 2);
      expect(api.seenSessionIds, <String>[
        'sess-voice-chat',
        'sess-voice-chat-2',
      ]);
      expect(service.sessionId, 'sess-voice-chat-2');
      expect(service.messages.map((item) => item.text).toList(), <String>[
        'transcricao de voz',
        'Resposta ao audio',
      ]);
    },
  );
}
