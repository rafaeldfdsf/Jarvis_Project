import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_flutter/services/assistant_runtime_service.dart';

class _FakeSettings extends ChangeNotifier {
  _FakeSettings({
    this.wakeWordPhrase = 'Jarvis',
    this.wakeWordSensitivity = 40,
  });

  String wakeWordPhrase;
  int wakeWordSensitivity;
  int loadCalls = 0;
  bool lastForce = false;

  Future<void> load({bool force = false}) async {
    loadCalls += 1;
    lastForce = force;
  }

  void update({String? wakeWordPhrase, int? wakeWordSensitivity}) {
    if (wakeWordPhrase != null) {
      this.wakeWordPhrase = wakeWordPhrase;
    }
    if (wakeWordSensitivity != null) {
      this.wakeWordSensitivity = wakeWordSensitivity;
    }
    notifyListeners();
  }
}

void main() {
  test('runtime inicia a wake word e usa a configuracao atual', () async {
    final settings = _FakeSettings();
    var startCalls = 0;
    var cancelCalls = 0;
    String? capturedKeyword;
    int? capturedSensitivity;

    final runtime = AssistantRuntimeService.test(
      settingsListenable: settings,
      loadSettings: settings.load,
      readWakeWordPhrase: () => settings.wakeWordPhrase,
      readWakeWordSensitivity: () => settings.wakeWordSensitivity,
      startWakeWordListening:
          ({
            required onWakeWordDetected,
            required keyword,
            required sensitivity,
          }) async {
            startCalls += 1;
            capturedKeyword = keyword;
            capturedSensitivity = sensitivity;
            return true;
          },
      cancelWakeWordListening: () async {
        cancelCalls += 1;
      },
      stopWakeWordListening: () async {},
      requestWakeActivation: ({String? message}) {},
      isWindows: () => true,
    );

    await runtime.initialize();
    await runtime.setAuthenticated(true);

    expect(settings.loadCalls, 2);
    expect(settings.lastForce, isTrue);
    expect(startCalls, 1);
    expect(cancelCalls, 1);
    expect(runtime.wakeWordReady, isTrue);
    expect(runtime.wakeWordEnabled, isTrue);
    expect(runtime.wakeWordPhrase, 'Jarvis');
    expect(capturedKeyword, 'Jarvis');
    expect(capturedSensitivity, 40);
    runtime.dispose();
  });

  test('runtime pausa a wake word durante captura e reativa no fim', () async {
    final settings = _FakeSettings();
    var startCalls = 0;
    var stopCalls = 0;

    final runtime = AssistantRuntimeService.test(
      settingsListenable: settings,
      loadSettings: settings.load,
      readWakeWordPhrase: () => settings.wakeWordPhrase,
      readWakeWordSensitivity: () => settings.wakeWordSensitivity,
      startWakeWordListening:
          ({
            required onWakeWordDetected,
            required keyword,
            required sensitivity,
          }) async {
            startCalls += 1;
            return true;
          },
      cancelWakeWordListening: () async {},
      stopWakeWordListening: () async {
        stopCalls += 1;
      },
      requestWakeActivation: ({String? message}) {},
      isWindows: () => true,
    );

    await runtime.initialize();
    await runtime.setAuthenticated(true);
    await runtime.beginVoiceCaptureSession();

    expect(runtime.wakeWordReady, isFalse);
    expect(stopCalls, 1);

    await runtime.endVoiceCaptureSession();

    expect(startCalls, 2);
    expect(runtime.wakeWordReady, isTrue);
    runtime.dispose();
  });

  test('runtime reinicia a wake word quando a configuracao muda', () async {
    final settings = _FakeSettings();
    final startedKeywords = <String>[];
    final startedSensitivities = <int>[];
    var cancelCalls = 0;

    final runtime = AssistantRuntimeService.test(
      settingsListenable: settings,
      loadSettings: settings.load,
      readWakeWordPhrase: () => settings.wakeWordPhrase,
      readWakeWordSensitivity: () => settings.wakeWordSensitivity,
      startWakeWordListening:
          ({
            required onWakeWordDetected,
            required keyword,
            required sensitivity,
          }) async {
            startedKeywords.add(keyword);
            startedSensitivities.add(sensitivity);
            return true;
          },
      cancelWakeWordListening: () async {
        cancelCalls += 1;
      },
      stopWakeWordListening: () async {},
      requestWakeActivation: ({String? message}) {},
      isWindows: () => true,
    );

    await runtime.initialize();
    await runtime.setAuthenticated(true);
    settings.update(wakeWordPhrase: 'Friday', wakeWordSensitivity: 72);
    await Future<void>.delayed(Duration.zero);

    expect(cancelCalls, 2);
    expect(startedKeywords, <String>['Jarvis', 'Friday']);
    expect(startedSensitivities, <int>[40, 72]);
    runtime.dispose();
  });

  test(
    'runtime reage a uma deteccao real e pode desligar a wake word',
    () async {
      final settings = _FakeSettings();
      Future<void> Function(String? seededTranscript)? detectedCallback;
      var cancelCalls = 0;
      var requestedMessage = '';

      final runtime = AssistantRuntimeService.test(
        settingsListenable: settings,
        loadSettings: settings.load,
        readWakeWordPhrase: () => settings.wakeWordPhrase,
        readWakeWordSensitivity: () => settings.wakeWordSensitivity,
        startWakeWordListening:
            ({
              required onWakeWordDetected,
              required keyword,
              required sensitivity,
            }) async {
              detectedCallback = onWakeWordDetected;
              return true;
            },
        cancelWakeWordListening: () async {
          cancelCalls += 1;
        },
        stopWakeWordListening: () async {},
        requestWakeActivation: ({String? message}) {
          requestedMessage = message ?? '';
        },
        isWindows: () => true,
      );

      await runtime.initialize();
      await runtime.setAuthenticated(true);
      await detectedCallback?.call(null);

      expect(runtime.wakeWordReady, isFalse);
      expect(requestedMessage, contains('Wake word "Jarvis" detetada.'));

      await runtime.setWakeWordEnabled(false);

      expect(runtime.wakeWordEnabled, isFalse);
      expect(cancelCalls, 2);
      runtime.dispose();
    },
  );
}
