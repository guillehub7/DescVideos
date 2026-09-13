/// Formato del stream encontrado. Solo `progressive` (mp4 directo) se puede
/// descargar sin un muxer tipo ffmpeg.
enum StreamFormat { progressive, hls, dash }

/// Una opcion de calidad concreta para un mismo video.
class MediaVariant {
  const MediaVariant({
    required this.url,
    required this.label,
    required this.format,
    this.height,
    this.width,
    this.bitrate,
    this.sizeBytes,
    this.hasAudio = true,
    this.container = 'mp4',
  });

  final String url;

  /// Etiqueta visible: "HD (720p)", "SD", "1080p", etc.
  final String label;
  final StreamFormat format;
  final int? height;
  final int? width;
  final int? bitrate;

  /// Tamano real reportado por el servidor (Content-Length). Se completa
  /// durante el analisis con una peticion HEAD.
  final int? sizeBytes;
  final bool hasAudio;
  final String container;

  bool get isDownloadable => format == StreamFormat.progressive && hasAudio;

  /// Peso aproximado para ordenar de mayor a menor calidad.
  int get rank => (height ?? 0) * 1000000 + (bitrate ?? 0);

  String get sizeLabel {
    final bytes = sizeBytes;
    if (bytes == null || bytes <= 0) return 'Tamano desconocido';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 100 || unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  MediaVariant copyWith({int? sizeBytes, String? label, int? height}) {
    return MediaVariant(
      url: url,
      label: label ?? this.label,
      format: format,
      height: height ?? this.height,
      width: width,
      bitrate: bitrate,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      hasAudio: hasAudio,
      container: container,
    );
  }
}
