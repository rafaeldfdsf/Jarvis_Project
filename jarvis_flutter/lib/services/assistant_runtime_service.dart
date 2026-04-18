import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_settings_service.dart';
import 'app_shell_service.dart';
import 'wake_word_service.dart';

class AssistantRuntimeService extends ChangeNotifier {
  static final AssistantRuntimeService _instance =
      AssistantRuntimeService._internal();

  factory AssistantRuntimeService() {
    return _instance;
  }

  AssistantRuntimeService._internal();

  final AppSettingsService _settings = AppSettingsService();
  final WakeWordService _wakeWordService = WakeWordService();

  bool _initialized = false;
  bool _initializing = false;
  bool _captureInProgress = false;
  bool _wakeWordEnabled = Platform.isWindows;
  bool _wakeWordReady = false;
  String _lastWakeWordPhrase = AppSettingsService.defaultAssistantName;

  bool get wakeWordEnabled => _wakeWordEnabled;
  bool get wakeWordReady => _wakeWordReady;
  String get wakeWordPhrase => _settings.wakeWordPhrase;

  Future<void> initialize() async {
    if (_initialized || _initializing) {
      return;
    }

    _initializing = true;
    await _settings.load();
    _lastWakeWordPhrase = _settings.wakeWordPhrase;
    _settings.addListener(_handleSettingsChanged);
    _initialized = true;
    _initializing = false;
    notifyListeners();
    await ensureWakeWordListening();
  }

  Future<void> setWakeWordEnabled(bool enabled) async {
    _wakeWordEnabled = enabled && Platform.isWindows;
    if (!_wakeWordEnabled) {
      _wakeWordReady = false;
      notifyListeners();
      await _wakeWordService.cancel();
      return;
    }

    notifyListeners();
    await ensureWakeWordListening(forceRestart: true);
  }

  Future<void> beginVoiceCaptureSession() {
    _captureInProgress = true;
    _wakeWordReady = false;
    notifyListeners();
    unawaited(_wakeWordService.stopListening());
    return Future<void>.value();
  }

  Future<void> endVoiceCaptureSession() async {
    _captureInProgress = false;
    await ensureWakeWordListening();
  }

  Future<void> ensureWakeWordListening({bool forceRestart = false}) async {
    if (!_wakeWordEnabled || _captureInProgress || !Platform.isWindows) {
      return;
    }

    if (forceRestart) {
      await _wakeWordService.cancel();
      _wakeWordReady = false;
      notifyListeners();
    }

    final started = await _wakeWordService.startListening(
      onWakeWordDetected: _handleWakeWordDetected,
      keyword: _settings.wakeWordPhrase,
    );

    if (_wakeWordReady != started) {
      _wakeWordReady = started;
      notifyListeners();
    }
  }

  Future<void> _handleWakeWordDetected(String? _seededTranscript) async {
    if (_captureInProgress) {
      return;
    }

    _wakeWordReady = false;
    notifyListeners();
    AppShellService().requestWakeActivation(
      message: 'Wake word "${_settings.wakeWordPhrase}" detetada. Podes falar.',
    );
  }

  void _handleSettingsChanged() {
    final updatedWakeWordPhrase = _settings.wakeWordPhrase;
    if (_lastWakeWordPhrase == updatedWakeWordPhrase) {
      return;
    }

    _lastWakeWordPhrase = updatedWakeWordPhrase;
    if (_wakeWordEnabled && !_captureInProgress) {
      unawaited(ensureWakeWordListening(forceRestart: true));
    }
  }
}
