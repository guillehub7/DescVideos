import 'link_info.dart';
import 'media_variant.dart';

/// Estado de privacidad detectado antes de permitir la descarga.
enum PrivacyStatus {
  /// El contenido responde sin sesion: es publico.
  publico,

  /// La pagina redirige a login o pide iniciar sesion: es privado o restringido.
  requiereSesion,

  /// La publicacion existe pero es de una cuenta privada.
  privado,

  /// Eliminado, no existe o no disponible en la region.
  noDisponible,

  /// No se pudo determinar (error de red, bloqueo temporal, etc.).
  desconocido,
}

extension PrivacyStatusX on PrivacyStatus {
  String get label => switch (this) {
        PrivacyStatus.publico => 'Publico',
        PrivacyStatus.requiereSesion => 'Requiere iniciar sesion',
        PrivacyStatus.privado => 'Cuenta privada',
        PrivacyStatus.noDisponible => 'No disponible',
        PrivacyStatus.desconocido => 'No verificado',
      };

  String get explanation => switch (this) {
        PrivacyStatus.publico =>
          'El contenido se puede ver sin iniciar sesion, la descarga esta habilitada.',
        PrivacyStatus.requiereSesion =>
          'La publicacion pide iniciar sesion. Para evitar inconvenientes legales y de privacidad, la descarga queda bloqueada.',
        PrivacyStatus.privado =>
          'La cuenta es privada. Solo se permiten descargas de contenido publico.',
        PrivacyStatus.noDisponible =>
          'La publicacion fue eliminada, es privada o no esta disponible en tu region.',
        PrivacyStatus.desconocido =>
          'No se pudo verificar si el contenido es publico. Revisa tu conexion e intenta de nuevo.',
      };

  bool get allowsDownload => this == PrivacyStatus.publico;
}

/// Resultado completo del analisis de un enlace.
class AnalysisResult {
  const AnalysisResult({
    required this.link,
    required this.privacy,
    this.variants = const [],
    this.title,
    this.author,
    this.thumbnailUrl,
    this.durationSeconds,
    this.diagnostic,
  });

  final LinkInfo link;
  final PrivacyStatus privacy;

  /// Calidades disponibles ordenadas de mayor a menor.
  final List<MediaVariant> variants;
  final String? title;
  final String? author;
  final String? thumbnailUrl;
  final int? durationSeconds;

  /// Detalle tecnico para mostrar cuando algo falla.
  final String? diagnostic;

  List<MediaVariant> get downloadable =>
      variants.where((v) => v.isDownloadable).toList();

  bool get canDownload => privacy.allowsDownload && downloadable.isNotEmpty;

  String get suggestedFileName {
    final base = (title == null || title!.trim().isEmpty)
        ? '${link.platform.label}_${DateTime.now().millisecondsSinceEpoch}'
        : title!.trim();
    final clean = base
        .replaceAll(RegExp(r'[^\w\s\-\.]', unicode: true), '')
        .replaceAll(RegExp(r'\s+'), '_');
    final trimmed = clean.length > 60 ? clean.substring(0, 60) : clean;
    return trimmed.isEmpty
        ? 'video_${DateTime.now().millisecondsSinceEpoch}'
        : trimmed;
  }

  AnalysisResult copyWith({
    PrivacyStatus? privacy,
    List<MediaVariant>? variants,
    String? diagnostic,
  }) {
    return AnalysisResult(
      link: link,
      privacy: privacy ?? this.privacy,
      variants: variants ?? this.variants,
      title: title,
      author: author,
      thumbnailUrl: thumbnailUrl,
      durationSeconds: durationSeconds,
      diagnostic: diagnostic ?? this.diagnostic,
    );
  }
}
