import 'dart:async';

import 'package:flutter/foundation.dart';

class AppShellService extends ChangeNotifier {
  static final AppShellService _instance = AppShellService._internal();

  factory AppShellService() {
    return _instance;
  }

  AppShellService._internal();

  Timer? _dismissTimer;
  int _wakePromptToken = 0;
  int _voiceCaptureToken = 0;
  int _voiceOverlayDismissToken = 0;
  bool _wakePromptVisible = false;
  bool _voiceOverlayMode = false;
  String _wakePromptMessage = 'Podes falar agora.';

  int get wakePromptToken => _wakePromptToken;
  int get voiceCaptureToken => _voiceCaptureToken;
  int get voiceOverlayDismissToken => _voiceOverlayDismissToken;
  bool get wakePromptVisible => _wakePromptVisible;
  bool get voiceOverlayMode => _voiceOverlayMode;
  String get wakePromptMessage => _wakePromptMessage;

  void requestWakeActivation({String? message}) {
    _wakePromptToken += 1;
    _voiceCaptureToken += 1;
    _wakePromptVisible = true;
    _wakePromptMessage = message?.trim().isNotEmpty == true
        ? message!.trim()
        : 'Podes falar agora.';

    _dismissTimer?.cancel();
    _dismissTimer = Timer(const Duration(seconds: 5), dismissWakePrompt);
    notifyListeners();
  }

  void requestWakePrompt({String? message}) {
    _wakePromptToken += 1;
    _wakePromptVisible = true;
    _wakePromptMessage = message?.trim().isNotEmpty == true
        ? message!.trim()
        : 'Podes falar agora.';

    _dismissTimer?.cancel();
    _dismissTimer = Timer(const Duration(seconds: 5), dismissWakePrompt);
    notifyListeners();
  }

  void requestVoiceCapture() {
    _voiceCaptureToken += 1;
    notifyListeners();
  }

  void enterVoiceOverlayMode() {
    if (_voiceOverlayMode) {
      return;
    }

    _voiceOverlayMode = true;
    notifyListeners();
  }

  void exitVoiceOverlayMode() {
    if (!_voiceOverlayMode) {
      return;
    }

    _voiceOverlayMode = false;
    notifyListeners();
  }

  void requestVoiceOverlayDismiss() {
    if (!_voiceOverlayMode) {
      return;
    }

    _voiceOverlayDismissToken += 1;
    notifyListeners();
  }

  void dismissWakePrompt() {
    if (!_wakePromptVisible) {
      return;
    }

    _wakePromptVisible = false;
    notifyListeners();
  }
}
