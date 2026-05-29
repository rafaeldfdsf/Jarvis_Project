import 'dart:async';
import 'dart:io';

import '../config/app_endpoints.dart';
import 'agent_service.dart';
import 'app_settings_service.dart';
import 'log_service.dart';

class WakeWordService {
  final AgentService _agentService = AgentService();
  final LogService _logService = LogService();

  bool _running = false;
  bool _triggered = false;
  String _keyword = AppSettingsService.defaultAssistantName;
  String? _lastStartupError;
  Future<void> Function(String? seededTranscript)? _onWakeWordDetected;

  bool get isListening => _running;

  Future<bool> startListening({
    required Future<void> Function(String? seededTranscript) onWakeWordDetected,
    String keyword = AppSettingsService.defaultAssistantName,
    int sensitivity = 40,
    String inputDeviceId = '',
    String inputDeviceLabel = '',
  }) async {
    if (_running) {
      return true;
    }

    if (!Platform.isWindows) {
      _logService.addLog(
        'INFO',
        'Wake word automatica reservada ao agent Windows neste momento.',
      );
      return false;
    }

    final cleanKeyword = keyword.trim().isEmpty
        ? AppSettingsService.defaultAssistantName
        : keyword.trim();
    final startResult = await _agentService.startWakeWord(
      keyword: cleanKeyword,
      sensitivity: sensitivity,
      inputDeviceId: inputDeviceId,
      inputDeviceLabel: inputDeviceLabel,
    );
    if (!startResult.ok) {
      final failureMessage = await _resolveStartErrorMessage(startResult);
      if (_lastStartupError != failureMessage) {
        _logService.addLog('ERROR', failureMessage);
        _lastStartupError = failureMessage;
      }
      return false;
    }

    _lastStartupError = null;
    _running = true;
    _triggered = false;
    _keyword = cleanKeyword;
    _onWakeWordDetected = onWakeWordDetected;

    _logService.addLog(
      'DEBUG',
      'Wake word Windows ativa com sensibilidade $sensitivity.',
    );
    unawaited(_pollLoop());
    return true;
  }

  Future<void> stopListening() async {
    _running = false;
    await _agentService.stopWakeWord();
  }

  Future<void> cancel() async {
    _running = false;
    _triggered = false;
    await _agentService.stopWakeWord();
  }

  void dispose() {
    unawaited(cancel());
  }

  Future<String> _resolveStartErrorMessage(
    AgentWakeWordStartResult startResult,
  ) async {
    final startError = startResult.error?.trim();
    final health = await _agentService.getHealth();
    final runtimeError = health?.wakeWordError?.trim();
    final engine = health?.wakeWordEngine?.trim();

    if (startError != null && startError.isNotEmpty) {
      if (runtimeError != null &&
          runtimeError.isNotEmpty &&
          runtimeError != startError) {
        return 'Wake word indisponivel: $startError Detalhe: $runtimeError';
      }
      return 'Wake word indisponivel: $startError';
    }

    if (runtimeError != null && runtimeError.isNotEmpty) {
      return 'Wake word indisponivel: $runtimeError';
    }

    if (health == null) {
      return 'Wake word indisponivel. ${AppEndpoints.agentUnavailableMessage()}';
    }

    if (engine != null && engine.isNotEmpty) {
      return 'Wake word indisponivel no agent Windows ($engine).';
    }

    return 'Wake word indisponivel. Confirma que o agent Windows esta ativo.';
  }

  Future<void> _pollLoop() async {
    while (_running && !_triggered) {
      final event = await _agentService.nextWakeWordEvent(
        timeout: const Duration(seconds: 1),
      );

      if (!_running || _triggered || event == null) {
        continue;
      }

      if (event.type == 'wake_word_heard') {
        final transcript = event.transcript?.trim();
        if (transcript != null && transcript.isNotEmpty) {
          final scoreSuffix = event.score != null
              ? ' (${event.score!.toStringAsFixed(0)})'
              : '';
          _logService.addLog('DEBUG', 'Wake word ouviu: $transcript$scoreSuffix');
        }
        continue;
      }

      if (event.type == 'wake_word_detected') {
        _triggered = true;
        _running = false;
        final heardKeyword = event.keyword?.trim().isNotEmpty == true
            ? event.keyword!.trim()
            : _keyword;
        _logService.addLog(
          'INFO',
          'Wake word "$heardKeyword" detetada no agent Windows.',
        );

        final callback = _onWakeWordDetected;
        if (callback != null) {
          await callback(null);
        }
        return;
      }

      if (event.type == 'wake_word_error') {
        _logService.addLog(
          'ERROR',
          event.message ?? 'Erro desconhecido na wake word.',
        );
        continue;
      }

      if (event.type == 'wake_word_warning') {
        _logService.addLog(
          'WARN',
          event.message ?? 'Aviso da wake word.',
        );
      }
    }
  }
}
