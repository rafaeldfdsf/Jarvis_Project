import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_endpoints.dart';

class AgentWakeWordEvent {
  final String type;
  final String? keyword;
  final String? transcript;
  final String? rawTranscript;
  final String? message;
  final double? score;

  const AgentWakeWordEvent({
    required this.type,
    this.keyword,
    this.transcript,
    this.rawTranscript,
    this.message,
    this.score,
  });

  factory AgentWakeWordEvent.fromJson(Map<String, dynamic> json) {
    final rawScore = json['score'];
    return AgentWakeWordEvent(
      type: (json['type'] ?? '').toString(),
      keyword: json['keyword']?.toString(),
      transcript: json['transcript']?.toString(),
      rawTranscript: json['raw_transcript']?.toString(),
      message: json['message']?.toString(),
      score: rawScore is num ? rawScore.toDouble() : null,
    );
  }
}

class AgentActionResult {
  final bool ok;
  final String action;
  final String? url;
  final String? app;
  final String? error;

  const AgentActionResult({
    required this.ok,
    required this.action,
    this.url,
    this.app,
    this.error,
  });

  factory AgentActionResult.fromJson(String action, Map<String, dynamic>? json) {
    return AgentActionResult(
      ok: json?['ok'] == true,
      action: action,
      url: json?['url']?.toString(),
      app: json?['app']?.toString(),
      error: json?['error']?.toString(),
    );
  }
}

class AgentWakeWordStartResult {
  final bool ok;
  final bool running;
  final String? engine;
  final String? keyword;
  final String? error;

  const AgentWakeWordStartResult({
    required this.ok,
    required this.running,
    this.engine,
    this.keyword,
    this.error,
  });

  factory AgentWakeWordStartResult.fromJson(Map<String, dynamic>? json) {
    return AgentWakeWordStartResult(
      ok: json?['ok'] == true,
      running: json?['running'] == true,
      engine: json?['engine']?.toString(),
      keyword: json?['keyword']?.toString(),
      error: json?['error']?.toString(),
    );
  }
}

class AgentHealthStatus {
  final bool ok;
  final bool wakeWordRunning;
  final String? wakeWordEngine;
  final String? wakeWordError;
  final String? wakeWordPhrase;

  const AgentHealthStatus({
    required this.ok,
    required this.wakeWordRunning,
    this.wakeWordEngine,
    this.wakeWordError,
    this.wakeWordPhrase,
  });

  factory AgentHealthStatus.fromJson(Map<String, dynamic>? json) {
    return AgentHealthStatus(
      ok: json?['ok'] == true,
      wakeWordRunning: json?['wake_word_running'] == true,
      wakeWordEngine: json?['wake_word_engine']?.toString(),
      wakeWordError: json?['wake_word_error']?.toString(),
      wakeWordPhrase: json?['wake_word_phrase']?.toString(),
    );
  }
}

class AgentService {
  static const Duration _requestTimeout = Duration(seconds: 5);

  static final AgentService _instance = AgentService._internal();

  factory AgentService() {
    return _instance;
  }

  AgentService._internal();

  final String baseUrl = AppEndpoints.agentBaseUrl;

  Future<AgentActionResult> sendPcAction(
    String action, {
    Map<String, dynamic>? extra,
  }) async {
    try {
      final body = {'action': action, ...?extra};
      final res = await http
          .post(
            Uri.parse('$baseUrl/action'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_requestTimeout);

      print('AGENT RESPONSE: ${res.body}');
      if (res.statusCode != 200) {
        return AgentActionResult(
          ok: false,
          action: action,
          error: 'Erro do agent (${res.statusCode}).',
        );
      }

      final data = _decodeJson(res.body);
      return AgentActionResult.fromJson(action, data);
    } catch (error) {
      print('ERRO AO FALAR COM AGENT: $error');
      print(AppEndpoints.agentUnavailableMessage());
      return AgentActionResult(
        ok: false,
        action: action,
        error: AppEndpoints.agentUnavailableMessage(),
      );
    }
  }

  Future<AgentWakeWordStartResult> startWakeWord({String? keyword}) async {
    try {
      final payload = <String, dynamic>{};
      final cleanKeyword = keyword?.trim() ?? '';
      if (cleanKeyword.isNotEmpty) {
        payload['keyword'] = cleanKeyword;
      }

      final res = await http
          .post(
            Uri.parse('$baseUrl/wake-word/start'),
            headers: payload.isEmpty ? null : {'Content-Type': 'application/json'},
            body: payload.isEmpty ? null : jsonEncode(payload),
          )
          .timeout(_requestTimeout);
      print('AGENT WAKE START: ${res.body}');
      final data = _decodeJson(res.body);
      if (res.statusCode != 200) {
        return AgentWakeWordStartResult(
          ok: false,
          running: false,
          error: data?['error']?.toString() ?? 'Erro do agent (${res.statusCode}).',
        );
      }

      return AgentWakeWordStartResult.fromJson(data);
    } catch (error) {
      print('ERRO AO INICIAR WAKE WORD: $error');
      print(AppEndpoints.agentUnavailableMessage());
      return AgentWakeWordStartResult(
        ok: false,
        running: false,
        error: AppEndpoints.agentUnavailableMessage(),
      );
    }
  }

  Future<AgentHealthStatus?> getHealth() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(_requestTimeout);
      if (res.statusCode != 200) {
        return null;
      }

      final data = _decodeJson(res.body);
      return AgentHealthStatus.fromJson(data);
    } catch (error) {
      print('ERRO AO CONSULTAR HEALTH DO AGENT: $error');
      return null;
    }
  }

  Future<void> stopWakeWord() async {
    try {
      await http
          .post(Uri.parse('$baseUrl/wake-word/stop'))
          .timeout(_requestTimeout);
    } catch (error) {
      print('ERRO AO PARAR WAKE WORD: $error');
    }
  }

  Future<AgentWakeWordEvent?> nextWakeWordEvent({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/wake-word/events/next?timeout_ms=${timeout.inMilliseconds}',
      );
      final res = await http.get(uri).timeout(_requestTimeout);

      if (res.statusCode != 200) {
        return null;
      }

      final data = _decodeJson(res.body);
      final eventData = data?['event'];
      if (eventData is! Map<String, dynamic>) {
        return null;
      }

      return AgentWakeWordEvent.fromJson(eventData);
    } catch (error) {
      print('ERRO AO LER EVENTO DE WAKE WORD: $error');
      return null;
    }
  }

  Map<String, dynamic>? _decodeJson(String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map<String, dynamic>) {
        return data;
      }
    } catch (_) {
      return null;
    }

    return null;
  }
}

Future<AgentActionResult> sendPcAction(
  String action, {
  Map<String, dynamic>? extra,
}) async {
  return AgentService().sendPcAction(action, extra: extra);
}
