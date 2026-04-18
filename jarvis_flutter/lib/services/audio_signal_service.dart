import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class AudioSignalLevel {
  const AudioSignalLevel({
    required this.rms,
    required this.peak,
    required this.activeRatio,
  });

  final double rms;
  final double peak;
  final double activeRatio;
}

class AudioSignalService {
  static Future<AudioSignalLevel> analyzeWavFile(String path) async {
    final bytes = await File(path).readAsBytes();
    if (bytes.length < 46) {
      return const AudioSignalLevel(rms: 0, peak: 0, activeRatio: 0);
    }

    final dataStart = _findDataChunkOffset(bytes);
    if (dataStart == null || dataStart >= bytes.length - 1) {
      return const AudioSignalLevel(rms: 0, peak: 0, activeRatio: 0);
    }

    final data = ByteData.sublistView(bytes);
    var sumSquares = 0.0;
    var peak = 0.0;
    var activeSamples = 0;
    var sampleCount = 0;

    for (var offset = dataStart; offset + 1 < bytes.length; offset += 2) {
      final sample = data.getInt16(offset, Endian.little);
      final level = sample.abs() / 32768.0;

      if (level > peak) {
        peak = level;
      }

      if (level >= 0.015) {
        activeSamples += 1;
      }

      sumSquares += level * level;
      sampleCount += 1;
    }

    if (sampleCount == 0) {
      return const AudioSignalLevel(rms: 0, peak: 0, activeRatio: 0);
    }

    return AudioSignalLevel(
      rms: sqrt(sumSquares / sampleCount),
      peak: peak,
      activeRatio: activeSamples / sampleCount,
    );
  }

  static Future<bool> likelyHasSpeech(
    String path, {
    double minRms = 0.012,
    double minPeak = 0.09,
    double minActiveRatio = 0.02,
    int requiredSignals = 2,
  }) async {
    final level = await analyzeWavFile(path);
    var score = 0;

    if (level.rms >= minRms) {
      score += 1;
    }

    if (level.peak >= minPeak) {
      score += 1;
    }

    if (level.activeRatio >= minActiveRatio) {
      score += 1;
    }

    return score >= requiredSignals;
  }

  static int? _findDataChunkOffset(Uint8List bytes) {
    for (var i = 12; i <= bytes.length - 8; i++) {
      if (bytes[i] == 100 &&
          bytes[i + 1] == 97 &&
          bytes[i + 2] == 116 &&
          bytes[i + 3] == 97) {
        return i + 8;
      }
    }

    return 44 <= bytes.length ? 44 : null;
  }
}
