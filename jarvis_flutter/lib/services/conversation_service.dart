import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import '../models/chat_response.dart';
import 'api_service.dart';

class ConversationService extends ChangeNotifier {
  static final ConversationService _instance = ConversationService._internal(
    api: ApiService(),
  );

  factory ConversationService() {
    return _instance;
  }

  ConversationService._internal({required ApiService api}) : _api = api;

  @visibleForTesting
  factory ConversationService.test({ApiService? api}) {
    return ConversationService._internal(api: api ?? ApiService());
  }

  final ApiService _api;

  final List<ChatMessage> _messages = <ChatMessage>[];
  Future<String>? _pendingSession;
  String? _sessionId;

  List<ChatMessage> get messages => List<ChatMessage>.unmodifiable(_messages);
  String? get sessionId => _sessionId;

  Future<bool> ensureSession() async {
    if ((_sessionId ?? '').trim().isNotEmpty) {
      return true;
    }

    final pending = _pendingSession;
    if (pending != null) {
      await pending;
      return (_sessionId ?? '').trim().isNotEmpty;
    }

    _pendingSession = _api.createSession();
    try {
      _sessionId = await _pendingSession;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    } finally {
      _pendingSession = null;
    }
  }

  Future<ChatResponseModel> sendTextMessage(String text) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      return ChatResponseModel(reply: '');
    }

    _messages.add(ChatMessage(cleanText, true));
    notifyListeners();

    try {
      final response = await _sendTextWithRecovery(cleanText);
      if (response == null) {
        return _appendErrorResponse('Nao foi possivel criar a sessao.');
      }
      _appendAssistantReply(response.reply);
      return response;
    } catch (error) {
      return _appendErrorResponse(_formatError(error));
    }
  }

  Future<ChatResponseModel> sendVoiceTurn(
    Uint8List wavBytes, {
    String? platform,
    String? locale,
  }) async {
    try {
      final response = await _sendVoiceWithRecovery(
        wavBytes,
        platform: platform,
        locale: locale,
      );
      if (response == null) {
        return _appendErrorResponse('Nao foi possivel criar a sessao.');
      }

      final transcript = response.transcript.trim();
      if (transcript.isNotEmpty) {
        _messages.add(ChatMessage(transcript, true));
      }
      _appendAssistantReply(response.reply, notify: false);
      notifyListeners();
      return response;
    } catch (error) {
      return _appendErrorResponse(_formatError(error));
    }
  }

  Future<ChatResponseModel?> _sendTextWithRecovery(String cleanText) async {
    final response = await _sendTextOnce(cleanText);
    if (!_isUnknownSessionReply(response?.reply)) {
      return response;
    }

    _invalidateSession();
    return _sendTextOnce(cleanText);
  }

  Future<ChatResponseModel?> _sendTextOnce(String cleanText) async {
    final ready = await ensureSession();
    if (!ready || (_sessionId ?? '').trim().isEmpty) {
      return null;
    }

    return _api.sendMessage(_sessionId!, cleanText);
  }

  Future<ChatResponseModel?> _sendVoiceWithRecovery(
    Uint8List wavBytes, {
    String? platform,
    String? locale,
  }) async {
    final response = await _sendVoiceOnce(
      wavBytes,
      platform: platform,
      locale: locale,
    );
    if (!_isUnknownSessionReply(response?.reply)) {
      return response;
    }

    _invalidateSession();
    return _sendVoiceOnce(wavBytes, platform: platform, locale: locale);
  }

  Future<ChatResponseModel?> _sendVoiceOnce(
    Uint8List wavBytes, {
    String? platform,
    String? locale,
  }) async {
    final ready = await ensureSession();
    if (!ready || (_sessionId ?? '').trim().isEmpty) {
      return null;
    }

    return _api.sendVoiceTurn(
      _sessionId!,
      wavBytes,
      platform: platform,
      locale: locale,
    );
  }

  void resetForAccountSwitch() {
    _messages.clear();
    _sessionId = null;
    _pendingSession = null;
    notifyListeners();
  }

  void appendLocalExchange({
    required String userText,
    required String assistantReply,
  }) {
    final cleanUserText = userText.trim();
    final cleanAssistantReply = assistantReply.trim();

    if (cleanUserText.isNotEmpty) {
      _messages.add(ChatMessage(cleanUserText, true));
    }
    if (cleanAssistantReply.isNotEmpty) {
      _messages.add(ChatMessage(cleanAssistantReply, false));
    }
    notifyListeners();
  }

  void _invalidateSession() {
    _sessionId = null;
    _pendingSession = null;
    notifyListeners();
  }

  void _appendAssistantReply(String reply, {bool notify = true}) {
    final cleanReply = reply.trim();
    if (cleanReply.isEmpty) {
      return;
    }

    _messages.add(ChatMessage(cleanReply, false));
    if (notify) {
      notifyListeners();
    }
  }

  ChatResponseModel _appendErrorResponse(String message) {
    final response = ChatResponseModel(reply: message);
    _appendAssistantReply(message);
    return response;
  }

  String _formatError(Object error) {
    final text = error.toString();
    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length);
    }
    return text;
  }

  bool _isUnknownSessionReply(String? reply) {
    final normalized = (reply ?? '').trim().toLowerCase();
    return normalized.contains('sessao desconhecida');
  }
}
