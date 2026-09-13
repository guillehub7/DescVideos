import 'media_variant.dart';

enum DownloadStatus { pendiente, descargando, guardando, completado, error, cancelado }

extension DownloadStatusX on DownloadStatus {
  String get label => switch (this) {
        DownloadStatus.pendiente => 'En cola',
        DownloadStatus.descargando => 'Descargando',
        DownloadStatus.guardando => 'Guardando en la galeria',
        DownloadStatus.completado => 'Completado',
        DownloadStatus.error => 'Error',
        DownloadStatus.cancelado => 'Cancelado',
      };

  bool get isActive =>
      this == DownloadStatus.descargando ||
      this == DownloadStatus.guardando ||
      this == DownloadStatus.pendiente;
}

class DownloadTask {
  DownloadTask({
    required this.id,
    required this.fileName,
    required this.variant,
    required this.sourceUrl,
    required this.platformLabel,
    this.status = DownloadStatus.pendiente,
    this.received = 0,
    this.total = 0,
    this.savedPath,
    this.error,
    this.thumbnailUrl,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String fileName;
  final MediaVariant variant;

  /// Enlace original de la publicacion (para referencia en el historial).
  final String sourceUrl;
  final String platformLabel;
  final String? thumbnailUrl;
  final DateTime createdAt;

  DownloadStatus status;
  int received;
  int total;

  /// Ruta final visible para el usuario (Movies/<carpeta>/archivo.mp4).
  String? savedPath;
  String? error;

  double get progress {
    if (total <= 0) return 0;
    final p = received / total;
    return p.clamp(0, 1).toDouble();
  }

  String get progressLabel {
    if (total <= 0) return '${(received / 1048576).toStringAsFixed(1)} MB';
    return '${(received / 1048576).toStringAsFixed(1)} / '
        '${(total / 1048576).toStringAsFixed(1)} MB';
  }
}
