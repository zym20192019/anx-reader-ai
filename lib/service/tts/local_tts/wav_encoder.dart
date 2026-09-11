import 'dart:typed_data';

/// Encodes raw PCM float32 samples into standard 16-bit PCM WAV bytes (RIFF format).
class WavEncoder {
  /// Encodes [samples] (-1.0 to 1.0) into a valid WAV file byte array.
  static Uint8List encodeToWav({
    required Float32List samples,
    required int sampleRate,
    int numChannels = 1,
  }) {
    final int numSamples = samples.length;
    final int bytesPerSample = 2; // 16-bit PCM
    final int dataSize = numSamples * bytesPerSample;
    final int fileSize = 44 + dataSize;

    final Uint8List buffer = Uint8List(fileSize);
    final ByteData byteData = ByteData.sublistView(buffer);

    // 0..3 "RIFF"
    buffer.setRange(0, 4, 'RIFF'.codeUnits);
    // 4..7 File size - 8
    byteData.setUint32(4, fileSize - 8, Endian.little);
    // 8..11 "WAVE"
    buffer.setRange(8, 12, 'WAVE'.codeUnits);
    // 12..15 "fmt "
    buffer.setRange(12, 16, 'fmt '.codeUnits);
    // 16..19 Subchunk1Size (16 for PCM)
    byteData.setUint32(16, 16, Endian.little);
    // 20..21 AudioFormat (1 for PCM)
    byteData.setUint16(20, 1, Endian.little);
    // 22..23 NumChannels (1 = Mono, 2 = Stereo)
    byteData.setUint16(22, numChannels, Endian.little);
    // 24..27 SampleRate
    byteData.setUint32(24, sampleRate, Endian.little);
    // 28..31 ByteRate = SampleRate * NumChannels * BitsPerSample/8
    byteData.setUint32(28, sampleRate * numChannels * bytesPerSample, Endian.little);
    // 32..33 BlockAlign = NumChannels * BitsPerSample/8
    byteData.setUint16(32, numChannels * bytesPerSample, Endian.little);
    // 34..35 BitsPerSample = 16
    byteData.setUint16(34, 16, Endian.little);
    // 36..39 "data"
    buffer.setRange(36, 40, 'data'.codeUnits);
    // 40..43 Subchunk2Size
    byteData.setUint32(40, dataSize, Endian.little);

    // 44..end PCM samples
    int offset = 44;
    for (int i = 0; i < numSamples; i++) {
      final double sample = samples[i];
      final int intSample = (sample * 32767.0).round().clamp(-32768, 32767);
      byteData.setInt16(offset, intSample, Endian.little);
      offset += 2;
    }

    return buffer;
  }

  /// Checks if [bytes] start with standard RIFF ... WAVE magic header.
  static bool isWav(Uint8List bytes) {
    if (bytes.length < 12) return false;
    return bytes[0] == 0x52 && // R
        bytes[1] == 0x49 && // I
        bytes[2] == 0x46 && // F
        bytes[3] == 0x46 && // F
        bytes[8] == 0x57 && // W
        bytes[9] == 0x41 && // A
        bytes[10] == 0x56 && // V
        bytes[11] == 0x45; // E
  }

  /// Detects MIME type from audio data. Returns 'audio/wav' if WAV, else defaults to 'audio/mp3'.
  static String detectAudioMimeType(Uint8List bytes) {
    return isWav(bytes) ? 'audio/wav' : 'audio/mp3';
  }
}
