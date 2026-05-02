import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:vad/vad.dart';

import 'wav_audio_service.dart';

class VoiceCaptureResult {
  final Uint8List wavBytes;

  const VoiceCaptureResult({required this.wavBytes});

  bool get hasAudio => wavBytes.isNotEmpty;
}

class MicrophoneDevice {
  const MicrophoneDevice({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;

  String get displayLabel => label.trim().isEmpty ? id : label.trim();
}

class MicrophoneTestResult {
  const MicrophoneTestResult({
    required this.ok,
    required this.message,
    required this.peakLevel,
    required this.averageLevel,
    required this.sampleCount,
    required this.wavBytes,
  });

  final bool ok;
  final String message;
  final double peakLevel;
  final double averageLevel;
  final int sampleCount;
  final Uint8List wavBytes;

  String get sensitivityLabel {
    if (sampleCount == 0) {
      return 'Sem sinal';
    }
    if (peakLevel >= 0.95) {
      return 'Demasiado alto';
    }
    if (peakLevel >= 0.75 || averageLevel >= 0.20) {
      return 'Alto';
    }
    if (peakLevel >= 0.12 || averageLevel >= 0.03) {
      return 'Bom';
    }
    if (peakLevel >= 0.05 || averageLevel >= 0.015) {
      return 'Baixo';
    }
    return 'Muito baixo';
  }

  String get sensitivityHint {
    switch (sensitivityLabel) {
      case 'Demasiado alto':
        return 'O microfone pode estar a saturar. Afasta-te um pouco ou reduz o ganho.';
      case 'Alto':
        return 'O nível está forte. Deve perceber bem a tua voz.';
      case 'Bom':
        return 'O nível está equilibrado para reconhecimento de fala.';
      case 'Baixo':
        return 'A voz chega, mas convém falar mais perto do microfone.';
      case 'Muito baixo':
        return 'O nível está fraco e o assistente pode falhar a transcrição.';
      default:
        return 'Nao foi captado sinal suficiente para avaliar.';
    }
  }
}

class VoiceService {
  final VadHandler _vadHandler = VadHandler.create(isDebug: false);

  static const double _positiveSpeechThreshold = 0.58;
  static const double _negativeSpeechThreshold = 0.32;
  static const int _redemptionFrames = 10;
  static const int _minSpeechFrames = 2;
  static const Duration _manualFinishFallback = Duration(milliseconds: 450);

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
    String? inputDeviceId,
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
      final inputDevice = await _resolveInputDevice(inputDeviceId);
      await _vadHandler.startListening(
        positiveSpeechThreshold: _positiveSpeechThreshold,
        negativeSpeechThreshold: _negativeSpeechThreshold,
        preSpeechPadFrames: 2,
        redemptionFrames: _redemptionFrames,
        minSpeechFrames: _minSpeechFrames,
        submitUserSpeechOnPause: true,
        recordConfig: RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          device: inputDevice,
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
      _finishFallbackTimer = Timer(_manualFinishFallback, () {
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

  Future<List<MicrophoneDevice>> listAvailableMicrophones() async {
    final recorder = AudioRecorder();
    try {
      final hasPermission = await recorder.hasPermission();
      if (!hasPermission) {
        return const <MicrophoneDevice>[];
      }

      final devices = await recorder.listInputDevices();
      return devices
          .map(
            (device) => MicrophoneDevice(
              id: device.id,
              label: device.label,
            ),
          )
          .toList();
    } catch (error) {
      print('Falha ao listar microfones: $error');
      return const <MicrophoneDevice>[];
    } finally {
      await recorder.dispose();
    }
  }

  Future<MicrophoneTestResult> testMicrophone({
    String? inputDeviceId,
    Duration duration = const Duration(seconds: 3),
  }) async {
    if (_captureCompleter != null) {
      return MicrophoneTestResult(
        ok: false,
        message: 'Ja existe uma captura de voz em curso.',
        peakLevel: 0,
        averageLevel: 0,
        sampleCount: 0,
        wavBytes: Uint8List(0),
      );
    }

    final recorder = AudioRecorder();
    StreamSubscription<Uint8List>? subscription;
    var peakLevel = 0.0;
    var sumAbs = 0.0;
    var sampleCount = 0;

    try {
      final hasPermission = await recorder.hasPermission();
      if (!hasPermission) {
        return MicrophoneTestResult(
          ok: false,
          message: 'Sem permissao para gravar audio.',
          peakLevel: 0,
          averageLevel: 0,
          sampleCount: 0,
          wavBytes: Uint8List(0),
        );
      }

      final inputDevice = await _resolveInputDevice(inputDeviceId, recorder: recorder);
      final bytesBuilder = BytesBuilder(copy: false);
      final stream = await recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          device: inputDevice,
        ),
      );

      subscription = stream.listen((chunk) {
        bytesBuilder.add(chunk);
        final analysis = _analyzePcm16Chunk(chunk);
        peakLevel = math.max(peakLevel, analysis.$1);
        sumAbs += analysis.$2;
        sampleCount += analysis.$3;
      });

      await Future<void>.delayed(duration);
      await subscription.cancel();
      await recorder.stop();

      final averageLevel = sampleCount > 0 ? sumAbs / sampleCount : 0.0;
      final detectedAudio = peakLevel >= 0.03 || averageLevel >= 0.01;
      final selectedLabel = inputDevice?.label.trim().isNotEmpty == true
          ? inputDevice!.label.trim()
          : 'microfone predefinido';
      final wavBytes = WavAudioService.encodePcm16Bytes(bytesBuilder.takeBytes());

      return MicrophoneTestResult(
        ok: detectedAudio,
        message: detectedAudio
            ? 'Microfone "$selectedLabel" captou audio com sucesso.'
            : 'Nao detetei audio util no "$selectedLabel". Verifica o volume de entrada ou fala mais perto do microfone.',
        peakLevel: peakLevel,
        averageLevel: averageLevel,
        sampleCount: sampleCount,
        wavBytes: wavBytes,
      );
    } catch (error) {
      print('Falha ao testar microfone: $error');
      return MicrophoneTestResult(
        ok: false,
        message: 'Falha ao testar microfone: $error',
        peakLevel: peakLevel,
        averageLevel: sampleCount > 0 ? sumAbs / sampleCount : 0.0,
        sampleCount: sampleCount,
        wavBytes: Uint8List(0),
      );
    } finally {
      await subscription?.cancel();
      try {
        await recorder.stop();
      } catch (_) {}
      await recorder.dispose();
    }
  }

  void dispose() {
    _disposed = true;
    unawaited(cancelCapture());
    _vadHandler.dispose();
  }

  Future<InputDevice?> _resolveInputDevice(
    String? inputDeviceId, {
    AudioRecorder? recorder,
  }) async {
    final cleanDeviceId = inputDeviceId?.trim() ?? '';
    if (cleanDeviceId.isEmpty) {
      return null;
    }

    final localRecorder = recorder ?? AudioRecorder();
    final shouldDispose = recorder == null;
    try {
      final devices = await localRecorder.listInputDevices();
      for (final device in devices) {
        if (device.id == cleanDeviceId) {
          return device;
        }
      }
    } catch (error) {
      print('Falha ao resolver dispositivo de audio: $error');
    } finally {
      if (shouldDispose) {
        await localRecorder.dispose();
      }
    }
    return null;
  }

  (double, double, int) _analyzePcm16Chunk(Uint8List chunk) {
    if (chunk.lengthInBytes < 2) {
      return (0.0, 0.0, 0);
    }

    final byteData = ByteData.sublistView(chunk);
    var peak = 0.0;
    var sumAbs = 0.0;
    var samples = 0;

    for (var offset = 0; offset + 1 < byteData.lengthInBytes; offset += 2) {
      final sample = byteData.getInt16(offset, Endian.little) / 32768.0;
      final absolute = sample.abs();
      peak = math.max(peak, absolute);
      sumAbs += absolute;
      samples += 1;
    }

    return (peak, sumAbs, samples);
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
