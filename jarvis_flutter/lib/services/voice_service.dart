import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:vad/vad.dart';

import 'wav_audio_service.dart';

class VoiceCaptureResult {
  final Uint8List wavBytes;

  const VoiceCaptureResult({required this.wavBytes});

  bool get hasAudio => wavBytes.isNotEmpty;
}

class VoiceService {
  final VadHandler _vadHandler = VadHandler.create(isDebug: false);

  Completer<VoiceCaptureResult?>? _captureCompleter;
  StreamSubscription<dynamic>? _speechStartSubscription;
  StreamSubscription<dynamic>? _realSpeechStartSubscription;
  StreamSubscription<List<double>>? _speechEndSubscription;
  StreamSubscription<dynamic>? _vadMisfireSubscription;
  StreamSubscription<String>? _errorSubscription;
  Timer? _initialWaitTimer;
  Timer? _finishFallbackTimer;

  bool _speechStarted = false;
  bool _disposed = false;

  Future<VoiceCaptureResult?> captureSpeechTurn({
    Duration maxInitialWait = const Duration(seconds: 6),
    void Function()? onSpeechStart,
  }) async {
    if (_disposed || _captureCompleter != null) {
      return null;
    }

    final recorder = AudioRecorder();
    final hasPermission = await recorder.hasPermission();
    recorder.dispose();

    if (!hasPermission) {
      return null;
    }

    _speechStarted = false;
    final completer = Completer<VoiceCaptureResult?>();
    _captureCompleter = completer;

    _bindVadListeners(onSpeechStart);
    _initialWaitTimer = Timer(maxInitialWait, () {
      if (!_speechStarted) {
        unawaited(cancelCapture());
      }
    });

    try {
      await _vadHandler.startListening(
        positiveSpeechThreshold: 0.60,
        negativeSpeechThreshold: 0.35,
        preSpeechPadFrames: 2,
        redemptionFrames: 16,
        minSpeechFrames: 2,
        submitUserSpeechOnPause: true,
        recordConfig: const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );

      return await completer.future;
    } catch (error) {
      print('Falha ao iniciar VAD: $error');
      if (!completer.isCompleted) {
        completer.complete(null);
      }
      return null;
    } finally {
      _initialWaitTimer?.cancel();
      _initialWaitTimer = null;
      _finishFallbackTimer?.cancel();
      _finishFallbackTimer = null;
      await _stopVadSafely();
      await _unbindVadListeners();
      _captureCompleter = null;
      _speechStarted = false;
    }
  }

  Future<void> finishCapture() async {
    final completer = _captureCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }

    if (!_speechStarted) {
      completer.complete(null);
      await _stopVadSafely();
      return;
    }

    try {
      await _vadHandler.pauseListening();
      _finishFallbackTimer?.cancel();
      _finishFallbackTimer = Timer(const Duration(milliseconds: 1200), () {
        final pending = _captureCompleter;
        if (pending != null && !pending.isCompleted) {
          pending.complete(null);
          unawaited(_stopVadSafely());
        }
      });
    } catch (error) {
      print('Falha ao terminar captura de voz: $error');
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }
  }

  Future<void> cancelCapture() async {
    _finishFallbackTimer?.cancel();
    _finishFallbackTimer = null;
    final completer = _captureCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(null);
    }

    await _stopVadSafely();
  }

  void dispose() {
    _disposed = true;
    unawaited(cancelCapture());
    _vadHandler.dispose();
  }

  void _bindVadListeners(void Function()? onSpeechStart) {
    _speechStartSubscription = _vadHandler.onSpeechStart.listen((_) {
      if (_speechStarted) {
        return;
      }

      _speechStarted = true;
      _initialWaitTimer?.cancel();
      onSpeechStart?.call();
    });

    _realSpeechStartSubscription = _vadHandler.onRealSpeechStart.listen((_) {
      _speechStarted = true;
      _initialWaitTimer?.cancel();
    });

    _speechEndSubscription = _vadHandler.onSpeechEnd.listen((samples) {
      final completer = _captureCompleter;
      if (completer == null || completer.isCompleted || samples.isEmpty) {
        return;
      }

      _speechStarted = true;
      _initialWaitTimer?.cancel();
      _finishFallbackTimer?.cancel();
      _finishFallbackTimer = null;
      completer.complete(
        VoiceCaptureResult(
          wavBytes: WavAudioService.encodePcm16(samples),
        ),
      );
    });

    _vadMisfireSubscription = _vadHandler.onVADMisfire.listen((_) {
      // Mantemos a escuta ativa; um misfire nao deve fechar o turno.
    });

    _errorSubscription = _vadHandler.onError.listen((message) {
      print('Erro de VAD: $message');
      _finishFallbackTimer?.cancel();
      _finishFallbackTimer = null;
      final completer = _captureCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete(null);
      }
    });
  }

  Future<void> _unbindVadListeners() async {
    await _speechStartSubscription?.cancel();
    await _realSpeechStartSubscription?.cancel();
    await _speechEndSubscription?.cancel();
    await _vadMisfireSubscription?.cancel();
    await _errorSubscription?.cancel();

    _speechStartSubscription = null;
    _realSpeechStartSubscription = null;
    _speechEndSubscription = null;
    _vadMisfireSubscription = null;
    _errorSubscription = null;
  }

  Future<void> _stopVadSafely() async {
    try {
      await _vadHandler.stopListening();
    } catch (_) {
      // Ignorado: pode acontecer quando o handler ja nao esta em escuta.
    }
  }
}
