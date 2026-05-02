import 'dart:typed_data';

class WavAudioService {
  static Uint8List encodePcm16(
    List<double> samples, {
    int sampleRate = 16000,
    int numChannels = 1,
  }) {
    const bytesPerSample = 2;
    final dataLength = samples.length * bytesPerSample;
    final byteData = ByteData(44 + dataLength);

    _writeAscii(byteData, 0, 'RIFF');
    byteData.setUint32(4, 36 + dataLength, Endian.little);
    _writeAscii(byteData, 8, 'WAVE');
    _writeAscii(byteData, 12, 'fmt ');
    byteData.setUint32(16, 16, Endian.little);
    byteData.setUint16(20, 1, Endian.little);
    byteData.setUint16(22, numChannels, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(
      28,
      sampleRate * numChannels * bytesPerSample,
      Endian.little,
    );
    byteData.setUint16(32, numChannels * bytesPerSample, Endian.little);
    byteData.setUint16(34, 16, Endian.little);
    _writeAscii(byteData, 36, 'data');
    byteData.setUint32(40, dataLength, Endian.little);

    var offset = 44;
    for (final sample in samples) {
      final normalized = sample.clamp(-1.0, 1.0);
      final pcm = (normalized * 32767.0).round().clamp(-32768, 32767);
      byteData.setInt16(offset, pcm, Endian.little);
      offset += bytesPerSample;
    }

    return byteData.buffer.asUint8List();
  }

  static void _writeAscii(ByteData byteData, int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      byteData.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  static Uint8List encodePcm16Bytes(
    Uint8List pcmBytes, {
    int sampleRate = 16000,
    int numChannels = 1,
  }) {
    const bytesPerSample = 2;
    final dataLength = pcmBytes.lengthInBytes;
    final byteData = ByteData(44 + dataLength);

    _writeAscii(byteData, 0, 'RIFF');
    byteData.setUint32(4, 36 + dataLength, Endian.little);
    _writeAscii(byteData, 8, 'WAVE');
    _writeAscii(byteData, 12, 'fmt ');
    byteData.setUint32(16, 16, Endian.little);
    byteData.setUint16(20, 1, Endian.little);
    byteData.setUint16(22, numChannels, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(
      28,
      sampleRate * numChannels * bytesPerSample,
      Endian.little,
    );
    byteData.setUint16(32, numChannels * bytesPerSample, Endian.little);
    byteData.setUint16(34, 16, Endian.little);
    _writeAscii(byteData, 36, 'data');
    byteData.setUint32(40, dataLength, Endian.little);

    final output = byteData.buffer.asUint8List();
    output.setRange(44, 44 + dataLength, pcmBytes);
    return output;
  }
}
