import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/app_endpoints.dart';
import '../models/app_setting_entry.dart';
import '../models/chat_response.dart';
import '../models/home_assistant_device.dart';
import '../models/memory_entry.dart';
import '../models/registered_device.dart';
import '../models/routine.dart';

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

  Future<String> transcribeAudio(Uint8List wavBytes) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/transcribe'),
    );
    request.headers.addAll(AppEndpoints.apiHeaders());
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        wavBytes,
        filename: 'microphone_test.wav',
      ),
    );

    try {
      final response = await request.send().timeout(_requestTimeout);
      final body = await response.stream.bytesToString();

      if (response.statusCode != 200) {
        throw Exception(
          _extractErrorMessage(body) ??
              'Erro ao transcrever audio (${response.statusCode}).',
        );
      }

      try {
        final decoded = jsonDecode(body);
        if (decoded is String) {
          return decoded.trim();
        }
      } catch (_) {
        return body.trim();
      }

      return body.trim();
    } on TimeoutException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on SocketException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on http.ClientException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    }
  }

  Future<List<AppSettingEntry>> fetchAppSettings() async {
    try {
      final res = await http
          .get(
            Uri.parse('$baseUrl/settings'),
            headers: AppEndpoints.apiHeaders(),
          )
          .timeout(_requestTimeout);

      if (res.statusCode != 200) {
        throw Exception(
          _extractErrorMessage(res.body) ??
              'Erro ao carregar configuracoes (${res.statusCode}).',
        );
      }

      final data = jsonDecode(res.body) as List<dynamic>;
      return data
          .whereType<Map<String, dynamic>>()
          .map(AppSettingEntry.fromJson)
          .toList();
    } on TimeoutException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on SocketException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on http.ClientException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    }
  }

  Future<List<AppSettingEntry>> updateAppSettings({
    required String assistantName,
    required String userName,
    required String wakeWordPhrase,
    required bool homeAssistantEnabled,
    required String homeAssistantUrl,
    required String homeAssistantToken,
  }) async {
    final body = jsonEncode({
      'assistant_name': assistantName,
      'user_name': userName,
      'wake_word_phrase': wakeWordPhrase,
      'home_assistant_enabled': homeAssistantEnabled,
      'home_assistant_url': homeAssistantUrl,
      'home_assistant_token': homeAssistantToken,
    });

    try {
      final res = await http
          .put(
            Uri.parse('$baseUrl/settings'),
            headers: AppEndpoints.apiHeaders(includeJsonContentType: true),
            body: body,
          )
          .timeout(_requestTimeout);

      if (res.statusCode != 200) {
        throw Exception(
          _extractErrorMessage(res.body) ??
              'Erro ao guardar configuracoes (${res.statusCode}).',
        );
      }

      final data = jsonDecode(res.body) as List<dynamic>;
      return data
          .whereType<Map<String, dynamic>>()
          .map(AppSettingEntry.fromJson)
          .toList();
    } on TimeoutException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on SocketException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on http.ClientException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    }
  }

  Future<int> clearAppSettings() async {
    try {
      final res = await http
          .delete(
            Uri.parse('$baseUrl/settings'),
            headers: AppEndpoints.apiHeaders(),
          )
          .timeout(_requestTimeout);

      if (res.statusCode != 200) {
        throw Exception(
          _extractErrorMessage(res.body) ??
              'Erro ao limpar configuracoes (${res.statusCode}).',
        );
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return (data['count'] as num?)?.toInt() ?? 0;
    } on TimeoutException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on SocketException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on http.ClientException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    }
  }

  Future<List<RegisteredDevice>> fetchRegisteredDevices() async {
    try {
      final res = await http
          .get(
            Uri.parse('$baseUrl/devices'),
            headers: AppEndpoints.apiHeaders(),
          )
          .timeout(_requestTimeout);

      if (res.statusCode != 200) {
        throw Exception(
          _extractErrorMessage(res.body) ??
              'Erro ao carregar dispositivos (${res.statusCode}).',
        );
      }

      final data = jsonDecode(res.body) as List<dynamic>;
      return data
          .whereType<Map<String, dynamic>>()
          .map(RegisteredDevice.fromJson)
          .toList();
    } on TimeoutException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on SocketException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on http.ClientException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    }
  }

  Future<RegisteredDevice> updateRegisteredDevice(
    String deviceId, {
    String? name,
    String? location,
    String? platform,
    bool? isActive,
    bool? preferredForWakeWord,
    bool? preferredForTts,
    bool? preferredForDesktopControl,
  }) async {
    final payload = <String, dynamic>{};
    if (name != null) {
      payload['name'] = name;
    }
    if (location != null) {
      payload['location'] = location;
    }
    if (platform != null) {
      payload['platform'] = platform;
    }
    if (isActive != null) {
      payload['is_active'] = isActive;
    }
    if (preferredForWakeWord != null) {
      payload['preferred_for_wake_word'] = preferredForWakeWord;
    }
    if (preferredForTts != null) {
      payload['preferred_for_tts'] = preferredForTts;
    }
    if (preferredForDesktopControl != null) {
      payload['preferred_for_desktop_control'] = preferredForDesktopControl;
    }

    try {
      final res = await http
          .put(
            Uri.parse('$baseUrl/devices/${Uri.encodeComponent(deviceId)}'),
            headers: AppEndpoints.apiHeaders(includeJsonContentType: true),
            body: jsonEncode(payload),
          )
          .timeout(_requestTimeout);

      if (res.statusCode != 200) {
        throw Exception(
          _extractErrorMessage(res.body) ??
              'Erro ao atualizar dispositivo (${res.statusCode}).',
        );
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return RegisteredDevice.fromJson(data);
    } on TimeoutException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on SocketException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on http.ClientException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    }
  }

  Future<HomeAssistantStatus> testHomeAssistantConnection() async {
    try {
      final res = await http
          .get(
            Uri.parse('$baseUrl/home-assistant/status'),
            headers: AppEndpoints.apiHeaders(),
          )
          .timeout(_requestTimeout);

      if (res.statusCode != 200) {
        throw Exception(
          _extractErrorMessage(res.body) ??
              'Erro ao testar Home Assistant (${res.statusCode}).',
        );
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return HomeAssistantStatus.fromJson(data);
    } on TimeoutException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on SocketException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on http.ClientException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    }
  }

  Future<List<HomeAssistantDevice>> fetchHomeAssistantDevices() async {
    try {
      final res = await http
          .get(
            Uri.parse('$baseUrl/home-assistant/devices'),
            headers: AppEndpoints.apiHeaders(),
          )
          .timeout(_requestTimeout);

      if (res.statusCode != 200) {
        throw Exception(
          _extractErrorMessage(res.body) ??
              'Erro ao carregar dispositivos Home Assistant (${res.statusCode}).',
        );
      }

      final data = jsonDecode(res.body) as List<dynamic>;
      return data
          .whereType<Map<String, dynamic>>()
          .map(HomeAssistantDevice.fromJson)
          .toList();
    } on TimeoutException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on SocketException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on http.ClientException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    }
  }

  Future<List<HomeAssistantDevice>> syncHomeAssistantDevices() async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/home-assistant/devices/sync'),
            headers: AppEndpoints.apiHeaders(),
          )
          .timeout(_requestTimeout);

      if (res.statusCode != 200) {
        throw Exception(
          _extractErrorMessage(res.body) ??
              'Erro ao sincronizar dispositivos Home Assistant (${res.statusCode}).',
        );
      }

      final data = jsonDecode(res.body) as List<dynamic>;
      return data
          .whereType<Map<String, dynamic>>()
          .map(HomeAssistantDevice.fromJson)
          .toList();
    } on TimeoutException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on SocketException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on http.ClientException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    }
  }

  Future<HomeAssistantDevice> updateHomeAssistantDeviceAlias(
    String entityId,
    String alias,
  ) async {
    try {
      final res = await http
          .put(
            Uri.parse(
              '$baseUrl/home-assistant/devices/${Uri.encodeComponent(entityId)}/alias',
            ),
            headers: AppEndpoints.apiHeaders(includeJsonContentType: true),
            body: jsonEncode({'alias': alias}),
          )
          .timeout(_requestTimeout);

      if (res.statusCode != 200) {
        throw Exception(
          _extractErrorMessage(res.body) ??
              'Erro ao atualizar alias do dispositivo (${res.statusCode}).',
        );
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return HomeAssistantDevice.fromJson(data);
    } on TimeoutException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on SocketException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on http.ClientException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    }
  }

  Future<void> deleteHomeAssistantDevice(String entityId) async {
    try {
      final res = await http
          .delete(
            Uri.parse(
              '$baseUrl/home-assistant/devices/${Uri.encodeComponent(entityId)}',
            ),
            headers: AppEndpoints.apiHeaders(),
          )
          .timeout(_requestTimeout);

      if (res.statusCode != 200) {
        throw Exception(
          _extractErrorMessage(res.body) ??
              'Erro ao remover dispositivo (${res.statusCode}).',
        );
      }
    } on TimeoutException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on SocketException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on http.ClientException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    }
  }

  Future<int> clearHomeAssistantDevices() async {
    try {
      final res = await http
          .delete(
            Uri.parse('$baseUrl/home-assistant/devices'),
            headers: AppEndpoints.apiHeaders(),
          )
          .timeout(_requestTimeout);

      if (res.statusCode != 200) {
        throw Exception(
          _extractErrorMessage(res.body) ??
              'Erro ao limpar dispositivos (${res.statusCode}).',
        );
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return (data['count'] as num?)?.toInt() ?? 0;
    } on TimeoutException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on SocketException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on http.ClientException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    }
  }

  Future<List<Routine>> fetchRoutines() async {
    try {
      final res = await http
          .get(
            Uri.parse('$baseUrl/routines'),
            headers: AppEndpoints.apiHeaders(),
          )
          .timeout(_requestTimeout);

      if (res.statusCode != 200) {
        throw Exception('Erro ao carregar rotinas (${res.statusCode}).');
      }

      final data = jsonDecode(res.body) as List<dynamic>;
      return data
          .whereType<Map<String, dynamic>>()
          .map(Routine.fromJson)
          .toList();
    } on TimeoutException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on SocketException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on http.ClientException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    }
  }

  Future<Routine> createRoutine({
    required String name,
    required String description,
    required String triggerText,
    required List<RoutineAction> actions,
    required bool enabled,
  }) async {
    return _saveRoutine(
      '$baseUrl/routines',
      method: 'POST',
      name: name,
      description: description,
      triggerText: triggerText,
      actions: actions,
      enabled: enabled,
    );
  }

  Future<Routine> updateRoutine(
    String routineId, {
    required String name,
    required String description,
    required String triggerText,
    required List<RoutineAction> actions,
    required bool enabled,
  }) async {
    return _saveRoutine(
      '$baseUrl/routines/${Uri.encodeComponent(routineId)}',
      method: 'PUT',
      name: name,
      description: description,
      triggerText: triggerText,
      actions: actions,
      enabled: enabled,
    );
  }

  Future<Routine> _saveRoutine(
    String url, {
    required String method,
    required String name,
    required String description,
    required String triggerText,
    required List<RoutineAction> actions,
    required bool enabled,
  }) async {
    final uri = Uri.parse(url);
    final body = jsonEncode({
      'name': name,
      'description': description,
      'trigger_text': triggerText,
      'actions': actions.map((item) => item.toJson()).toList(),
      'enabled': enabled,
    });

    try {
      final request = http.Request(method, uri)
        ..headers.addAll(AppEndpoints.apiHeaders(includeJsonContentType: true))
        ..body = body;
      final streamed = await request.send().timeout(_requestTimeout);
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode != 200) {
        throw Exception(
          _extractErrorMessage(response.body) ??
              'Erro ao guardar rotina (${response.statusCode}).',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return Routine.fromJson(data);
    } on TimeoutException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on SocketException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on http.ClientException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    }
  }

  Future<void> deleteRoutine(String routineId) async {
    try {
      final res = await http
          .delete(
            Uri.parse('$baseUrl/routines/${Uri.encodeComponent(routineId)}'),
            headers: AppEndpoints.apiHeaders(),
          )
          .timeout(_requestTimeout);

      if (res.statusCode != 200) {
        throw Exception('Erro ao remover rotina (${res.statusCode}).');
      }
    } on TimeoutException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on SocketException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    } on http.ClientException {
      throw Exception(AppEndpoints.apiUnavailableMessage());
    }
  }

  Future<Map<String, dynamic>> runRoutine(String routineId) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/routines/${Uri.encodeComponent(routineId)}/run'),
            headers: AppEndpoints.apiHeaders(),
          )
          .timeout(_requestTimeout);

      if (res.statusCode != 200) {
        throw Exception(
          _extractErrorMessage(res.body) ??
              'Erro ao executar rotina (${res.statusCode}).',
        );
      }

      return jsonDecode(res.body) as Map<String, dynamic>;
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
