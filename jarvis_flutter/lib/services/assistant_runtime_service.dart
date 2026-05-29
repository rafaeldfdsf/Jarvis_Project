import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_settings_service.dart';
import 'app_shell_service.dart';
import 'wake_word_service.dart';

class AssistantRuntimeService extends ChangeNotifier {
  static final AssistantRuntimeService _instance =
      AssistantRuntimeService._internal(
        settingsListenable: AppSettingsService(),
        loadSettings: ({bool force = false}) =>
            AppSettingsService().load(force: force),
        readWakeWordPhrase: () => AppSettingsService().wakeWordPhrase,
        readWakeWordSensitivity: () => AppSettingsService().wakeWordSensitivity,
        readMicrophoneDeviceId: () => AppSettingsService().microphoneDeviceId,
        readMicrophoneDeviceLabel: () => AppSettingsService().microphoneDeviceLabel,
        startWakeWordListening:
            ({
              required onWakeWordDetected,
              required keyword,
              required sensitivity,
              required inputDeviceId,
              required inputDeviceLabel,
            }) {
              return WakeWordService().startListening(
                onWakeWordDetected: onWakeWordDetected,
                keyword: keyword,
                sensitivity: sensitivity,
                inputDeviceId: inputDeviceId,
                inputDeviceLabel: inputDeviceLabel,
              );
            },
        cancelWakeWordListening: () => WakeWordService().cancel(),
        stopWakeWordListening: () => WakeWordService().stopListening(),
        requestWakeActivation: ({String? message}) =>
            AppShellService().requestWakeActivation(message: message),
        isWindows: () => Platform.isWindows,
      );

  factory AssistantRuntimeService() {
    return _instance;
  }

  AssistantRuntimeService._internal({
    required Listenable settingsListenable,
    required Future<void> Function({bool force}) loadSettings,
    required String Function() readWakeWordPhrase,
    required int Function() readWakeWordSensitivity,
    required String Function() readMicrophoneDeviceId,
    required String Function() readMicrophoneDeviceLabel,
    required Future<bool> Function({
      required Future<void> Function(String? seededTranscript)
      onWakeWordDetected,
      required String keyword,
      required int sensitivity,
      required String inputDeviceId,
      required String inputDeviceLabel,
    })
    startWakeWordListening,
    required Future<void> Function() cancelWakeWordListening,
    required Future<void> Function() stopWakeWordListening,
    required void Function({String? message}) requestWakeActivation,
    required bool Function() isWindows,
  }) : _settingsListenable = settingsListenable,
       _loadSettings = loadSettings,
       _readWakeWordPhrase = readWakeWordPhrase,
       _readWakeWordSensitivity = readWakeWordSensitivity,
       _readMicrophoneDeviceId = readMicrophoneDeviceId,
       _readMicrophoneDeviceLabel = readMicrophoneDeviceLabel,
       _startWakeWordListening = startWakeWordListening,
       _cancelWakeWordListening = cancelWakeWordListening,
       _stopWakeWordListening = stopWakeWordListening,
       _requestWakeActivation = requestWakeActivation,
       _isWindows = isWindows;

  @visibleForTesting
  factory AssistantRuntimeService.test({
    required Listenable settingsListenable,
    required Future<void> Function({bool force}) loadSettings,
    required String Function() readWakeWordPhrase,
    required int Function() readWakeWordSensitivity,
    required String Function() readMicrophoneDeviceId,
    required String Function() readMicrophoneDeviceLabel,
    required Future<bool> Function({
      required Future<void> Function(String? seededTranscript)
      onWakeWordDetected,
      required String keyword,
      required int sensitivity,
      required String inputDeviceId,
      required String inputDeviceLabel,
    })
    startWakeWordListening,
    required Future<void> Function() cancelWakeWordListening,
    required Future<void> Function() stopWakeWordListening,
    required void Function({String? message}) requestWakeActivation,
    required bool Function() isWindows,
  }) {
    return AssistantRuntimeService._internal(
      settingsListenable: settingsListenable,
      loadSettings: loadSettings,
      readWakeWordPhrase: readWakeWordPhrase,
      readWakeWordSensitivity: readWakeWordSensitivity,
      readMicrophoneDeviceId: readMicrophoneDeviceId,
      readMicrophoneDeviceLabel: readMicrophoneDeviceLabel,
      startWakeWordListening: startWakeWordListening,
      cancelWakeWordListening: cancelWakeWordListening,
      stopWakeWordListening: stopWakeWordListening,
      requestWakeActivation: requestWakeActivation,
      isWindows: isWindows,
    );
  }

  final Listenable _settingsListenable;
  final Future<void> Function({bool force}) _loadSettings;
  final String Function() _readWakeWordPhrase;
  final int Function() _readWakeWordSensitivity;
  final String Function() _readMicrophoneDeviceId;
  final String Function() _readMicrophoneDeviceLabel;
  final Future<bool> Function({
    required Future<void> Function(String? seededTranscript) onWakeWordDetected,
    required String keyword,
    required int sensitivity,
    required String inputDeviceId,
    required String inputDeviceLabel,
  })
  _startWakeWordListening;
  final Future<void> Function() _cancelWakeWordListening;
  final Future<void> Function() _stopWakeWordListening;
  final void Function({String? message}) _requestWakeActivation;
  final bool Function() _isWindows;

  bool _authenticated = false;
  bool _initialized = false;
  bool _initializing = false;
  bool _captureInProgress = false;
  bool _wakeWordEnabled = true;
  bool _wakeWordReady = false;
  String _lastWakeWordPhrase = AppSettingsService.defaultAssistantName;
  int _lastWakeWordSensitivity = 40;
  String _lastMicrophoneDeviceId = '';
  String _lastMicrophoneDeviceLabel = '';

  bool get wakeWordEnabled => _wakeWordEnabled;
  bool get wakeWordReady => _wakeWordReady;
  String get wakeWordPhrase => _readWakeWordPhrase();

  Future<void> initialize() async {
    if (_initialized || _initializing) {
      return;
    }

    _initializing = true;
    _wakeWordEnabled = _isWindows();
    await _loadSettings();
    _lastWakeWordPhrase = _readWakeWordPhrase();
    _lastWakeWordSensitivity = _readWakeWordSensitivity();
    _lastMicrophoneDeviceId = _readMicrophoneDeviceId();
    _lastMicrophoneDeviceLabel = _readMicrophoneDeviceLabel();
    _settingsListenable.addListener(_handleSettingsChanged);
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
      await _cancelWakeWordListening();
      return;
    }

    await _loadSettings(force: true);
    _lastWakeWordPhrase = _readWakeWordPhrase();
    _lastWakeWordSensitivity = _readWakeWordSensitivity();
    _lastMicrophoneDeviceId = _readMicrophoneDeviceId();
    _lastMicrophoneDeviceLabel = _readMicrophoneDeviceLabel();
    notifyListeners();

    if (_initialized) {
      await ensureWakeWordListening(forceRestart: true);
    }
  }

  Future<void> setWakeWordEnabled(bool enabled) async {
    _wakeWordEnabled = enabled && _isWindows();
    if (!_wakeWordEnabled) {
      _wakeWordReady = false;
      notifyListeners();
      await _cancelWakeWordListening();
      return;
    }

    notifyListeners();
    await ensureWakeWordListening(forceRestart: true);
  }

  Future<void> beginVoiceCaptureSession() {
    _captureInProgress = true;
    _wakeWordReady = false;
    notifyListeners();
    unawaited(_stopWakeWordListening());
    return Future<void>.value();
  }

  Future<void> endVoiceCaptureSession() async {
    _captureInProgress = false;
    await ensureWakeWordListening();
  }

  Future<void> ensureWakeWordListening({bool forceRestart = false}) async {
    if (!_authenticated ||
        !_wakeWordEnabled ||
        _captureInProgress ||
        !_isWindows()) {
      return;
    }

    if (forceRestart) {
      await _cancelWakeWordListening();
      _wakeWordReady = false;
      notifyListeners();
    }

    final started = await _startWakeWordListening(
      onWakeWordDetected: _handleWakeWordDetected,
      keyword: _readWakeWordPhrase(),
      sensitivity: _readWakeWordSensitivity(),
      inputDeviceId: _readMicrophoneDeviceId(),
      inputDeviceLabel: _readMicrophoneDeviceLabel(),
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
    _requestWakeActivation(
      message: 'Wake word "${_readWakeWordPhrase()}" detetada. Podes falar.',
    );
  }

  void _handleSettingsChanged() {
    final updatedWakeWordPhrase = _readWakeWordPhrase();
    final updatedWakeWordSensitivity = _readWakeWordSensitivity();
    final updatedMicrophoneDeviceId = _readMicrophoneDeviceId();
    final updatedMicrophoneDeviceLabel = _readMicrophoneDeviceLabel();
    if (_lastWakeWordPhrase == updatedWakeWordPhrase &&
        _lastWakeWordSensitivity == updatedWakeWordSensitivity &&
        _lastMicrophoneDeviceId == updatedMicrophoneDeviceId &&
        _lastMicrophoneDeviceLabel == updatedMicrophoneDeviceLabel) {
      return;
    }

    _lastWakeWordPhrase = updatedWakeWordPhrase;
    _lastWakeWordSensitivity = updatedWakeWordSensitivity;
    _lastMicrophoneDeviceId = updatedMicrophoneDeviceId;
    _lastMicrophoneDeviceLabel = updatedMicrophoneDeviceLabel;
    if (_wakeWordEnabled && !_captureInProgress) {
      unawaited(ensureWakeWordListening(forceRestart: true));
    }
  }

  @override
  void dispose() {
    _settingsListenable.removeListener(_handleSettingsChanged);
    super.dispose();
  }
}
