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

  bool _authenticated = false;
  bool _initialized = false;
  bool _initializing = false;
  bool _captureInProgress = false;
  bool _wakeWordEnabled = Platform.isWindows;
  bool _wakeWordReady = false;
  String _lastWakeWordPhrase = AppSettingsService.defaultAssistantName;
  int _lastWakeWordSensitivity = 40;

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
    _lastWakeWordSensitivity = _settings.wakeWordSensitivity;
    _settings.addListener(_handleSettingsChanged);
    _initialized = true;
    _initializing = false;
    notifyListeners();
    if (_authenticated) {
      await ensureWakeWordListening();
    }
  }

  Future<void> setAuthenticated(bool authenticated) async {
    _authenticated = authenticated;

    if (!authenticated) {
      _captureInProgress = false;
      _wakeWordReady = false;
      notifyListeners();
      await _wakeWordService.cancel();
      return;
    }

    await _settings.load(force: true);
    _lastWakeWordPhrase = _settings.wakeWordPhrase;
    _lastWakeWordSensitivity = _settings.wakeWordSensitivity;
    notifyListeners();

    if (_initialized) {
      await ensureWakeWordListening(forceRestart: true);
    }
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
    if (
      !_authenticated ||
      !_wakeWordEnabled ||
      _captureInProgress ||
      !Platform.isWindows
    ) {
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
      sensitivity: _settings.wakeWordSensitivity,
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
    final updatedWakeWordSensitivity = _settings.wakeWordSensitivity;
    if (
      _lastWakeWordPhrase == updatedWakeWordPhrase &&
      _lastWakeWordSensitivity == updatedWakeWordSensitivity
    ) {
      return;
    }

    _lastWakeWordPhrase = updatedWakeWordPhrase;
    _lastWakeWordSensitivity = updatedWakeWordSensitivity;
    if (_wakeWordEnabled && !_captureInProgress) {
      unawaited(ensureWakeWordListening(forceRestart: true));
    }
  }
}
