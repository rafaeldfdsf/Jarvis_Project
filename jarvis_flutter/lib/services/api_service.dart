import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/app_endpoints.dart';
import '../models/chat_response.dart';
import '../models/memory_entry.dart';

class ApiService {
  static const Duration _requestTimeout = Duration(seconds: 15);

  final String baseUrl = AppEndpoints.apiBaseUrl;

  Future<String> createSession() async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/sessions'),
            headers: AppEndpoints.apiHeaders(),
          )
          .timeout(_requestTimeout);
      if (res.statusCode != 200) {
        throw Exception(
          _extractErrorMessage(res.body) ?? 'Erro do servidor (${res.statusCode})',
        );
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final sessionId = data['session_id']?.toString() ?? '';
      if (sessionId.isEmpty) {
        throw Exception('Resposta invalida ao criar sessao.');
      }
      return sessionId;
    } on TimeoutException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on SocketException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on http.ClientException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    }
  }

  Future<ChatResponseModel> sendMessage(
    String sessionId,
    String message,
  ) async {
    final body = {'session_id': sessionId, 'message': message};

    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/chat'),
            headers: AppEndpoints.apiHeaders(includeJsonContentType: true),
            body: jsonEncode(body),
          )
          .timeout(_requestTimeout);

      print('BACKEND RESPONSE: ${res.body}');

      if (res.statusCode != 200) {
        final detail = _extractErrorMessage(res.body);
        return ChatResponseModel(
          reply: detail ?? 'Erro do servidor (${res.statusCode})',
        );
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return ChatResponseModel.fromJson(data);
    } on TimeoutException {
      return ChatResponseModel(reply: AppEndpoints.apiUnavailableMessage());
    } on SocketException {
      return ChatResponseModel(reply: AppEndpoints.apiUnavailableMessage());
    } on http.ClientException {
      return ChatResponseModel(reply: AppEndpoints.apiUnavailableMessage());
    }
  }

  Future<ChatResponseModel> sendVoiceTurn(
    String sessionId,
    Uint8List wavBytes, {
    String? platform,
    String? locale,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/voice/turn'),
    );

    request.fields['session_id'] = sessionId;
    request.headers.addAll(AppEndpoints.apiHeaders());

    if (platform != null && platform.trim().isNotEmpty) {
      request.fields['platform'] = platform;
    }

    if (locale != null && locale.trim().isNotEmpty) {
      request.fields['locale'] = locale;
    }

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        wavBytes,
        filename: 'voice_turn.wav',
      ),
    );

    try {
      final response = await request.send().timeout(_requestTimeout);
      final body = await response.stream.bytesToString();

      print('VOICE TURN RESPONSE: $body');

      if (response.statusCode != 200) {
        final detail = _extractErrorMessage(body);
        return ChatResponseModel(
          reply: detail ?? 'Erro do servidor (${response.statusCode})',
        );
      }

      final data = jsonDecode(body) as Map<String, dynamic>;
      return ChatResponseModel.fromJson(data);
    } on TimeoutException {
      return ChatResponseModel(reply: AppEndpoints.apiUnavailableMessage());
    } on SocketException {
      return ChatResponseModel(reply: AppEndpoints.apiUnavailableMessage());
    } on http.ClientException {
      return ChatResponseModel(reply: AppEndpoints.apiUnavailableMessage());
    }
  }

  Future<List<MemoryEntry>> fetchMemoryEntries() async {
    try {
      final res = await http
          .get(
            Uri.parse('$baseUrl/memory'),
            headers: AppEndpoints.apiHeaders(),
          )
          .timeout(_requestTimeout);

      if (res.statusCode != 200) {
        throw Exception('Erro ao carregar memoria (${res.statusCode}).');
      }

      final data = jsonDecode(res.body) as List<dynamic>;
      return data
          .map((item) => MemoryEntry.fromJson(item as Map<String, dynamic>))
          .toList();
    } on TimeoutException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on SocketException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on http.ClientException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    }
  }

  Future<MemoryEntry> updateMemoryEntry(String key, String value) async {
    final encodedKey = Uri.encodeComponent(key);
    try {
      final res = await http
          .put(
            Uri.parse('$baseUrl/memory/$encodedKey'),
            headers: AppEndpoints.apiHeaders(includeJsonContentType: true),
            body: jsonEncode({'value': value}),
          )
          .timeout(_requestTimeout);

      if (res.statusCode != 200) {
        throw Exception('Erro ao atualizar memoria (${res.statusCode}).');
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return MemoryEntry.fromJson(data);
    } on TimeoutException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on SocketException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on http.ClientException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    }
  }

  Future<void> deleteMemoryEntry(String key) async {
    final encodedKey = Uri.encodeComponent(key);
    try {
      final res = await http
          .delete(
            Uri.parse('$baseUrl/memory/$encodedKey'),
            headers: AppEndpoints.apiHeaders(),
          )
          .timeout(_requestTimeout);

      if (res.statusCode != 200) {
        throw Exception('Erro ao remover memoria (${res.statusCode}).');
      }
    } on TimeoutException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on SocketException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on http.ClientException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    }
  }

  Future<void> clearMemory() async {
    try {
      final res = await http
          .delete(
            Uri.parse('$baseUrl/memory'),
            headers: AppEndpoints.apiHeaders(),
          )
          .timeout(_requestTimeout);

      if (res.statusCode != 200) {
        throw Exception('Erro ao limpar memoria (${res.statusCode}).');
      }
    } on TimeoutException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on SocketException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on http.ClientException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    }
  }

  String? _extractErrorMessage(String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map<String, dynamic>) {
        final detail = data['detail'];
        if (detail is String && detail.trim().isNotEmpty) {
          return detail;
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }
}
