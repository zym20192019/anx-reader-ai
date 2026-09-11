/// Installation and download status for a local voice model.
enum ModelInstallStatus {
  notDownloaded,
  downloading,
  installed,
  error,
}

/// Metadata and specification for a local offline voice model package.
class LocalVoiceModel {
  const LocalVoiceModel({
    required this.id,
    required this.displayName,
    required this.locale,
    required this.gender,
    required this.sampleRate,
    required this.downloadSizeBytes,
    required this.downloadUrl,
    required this.sha256,
    required this.license,
    required this.datasetSource,
    required this.onnxFileName,
    required this.tokensFileName,
    required this.lexiconFileName,
    required this.ruleFsts,
    required this.requiredFiles,
  });

  /// Unique identifier of this model package (e.g. 'zh-piper-chaowen-medium').
  final String id;

  /// User-friendly label displayed in settings (no technical jargon like ONNX/VITS).
  final String displayName;

  /// BCP 47 language/region tag (e.g. 'zh-CN').
  final String locale;

  /// Voice gender ('male' or 'female').
  final String gender;

  /// Output audio sample rate in Hz (e.g. 22050).
  final int sampleRate;

  /// Compressed archive file size in bytes.
  final int downloadSizeBytes;

  /// Verified official release URL of the model archive.
  final String downloadUrl;

  /// Fixed SHA-256 checksum of the downloaded archive.
  final String sha256;

  /// Verified open license of the dataset/model (e.g. 'CC0').
  final String license;

  /// Source repository or dataset location.
  final String datasetSource;

  /// File name of the ONNX acoustic model inside the extracted package.
  final String onnxFileName;

  /// File name of the tokens definition inside the extracted package.
  final String tokensFileName;

  /// File name of the pronunciation lexicon inside the extracted package.
  final String lexiconFileName;

  /// Rule FST filenames used for text normalization.
  final List<String> ruleFsts;

  /// All files that must exist and be non-empty for the model to be valid.
  final List<String> requiredFiles;

  /// Formatted download size (e.g. '57.6 MB').
  String get formattedSize {
    final mb = downloadSizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  /// Default verified Chinese offline natural voice model (Piper chaowen, CC0).
  static const LocalVoiceModel defaultChineseModel = LocalVoiceModel(
    id: 'zh-piper-chaowen-medium',
    displayName: '标准中文（超文）',
    locale: 'zh-CN',
    gender: 'male',
    sampleRate: 22050,
    downloadSizeBytes: 60443846,
    downloadUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-zh_CN-chaowen-medium.tar.bz2',
    sha256: '1b69bdcf10bb6331c7f8a7591940febeb175c6bb86caa3802d96531f8e4ad211',
    license: 'CC0',
    datasetSource: 'https://github.com/OHF-Voice/voice-datasets',
    onnxFileName: 'zh_CN-chaowen-medium.onnx',
    tokensFileName: 'tokens.txt',
    lexiconFileName: 'lexicon.txt',
    ruleFsts: ['phone.fst', 'date.fst', 'number.fst'],
    requiredFiles: [
      'zh_CN-chaowen-medium.onnx',
      'tokens.txt',
      'lexicon.txt',
      'phone.fst',
      'date.fst',
      'number.fst',
    ],
  );
}
