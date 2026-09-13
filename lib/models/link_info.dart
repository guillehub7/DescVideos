/// Plataformas soportadas por la app.
enum Platform { facebook, instagram, unknown }

extension PlatformX on Platform {
  String get label => switch (this) {
        Platform.facebook => 'Facebook',
        Platform.instagram => 'Instagram',
        Platform.unknown => 'Desconocida',
      };

  String get emoji => switch (this) {
        Platform.facebook => 'f',
        Platform.instagram => 'ig',
        Platform.unknown => '?',
      };
}

/// Tipo de contenido detectado dentro de la plataforma.
enum ContentKind { video, reel, story, post, unknown }

extension ContentKindX on ContentKind {
  String get label => switch (this) {
        ContentKind.video => 'Video',
        ContentKind.reel => 'Reel',
        ContentKind.story => 'Historia',
        ContentKind.post => 'Publicacion',
        ContentKind.unknown => 'Contenido',
      };
}

/// Resultado del detector de enlaces: que plataforma es y que identificador
/// tiene el contenido dentro de ella.
class LinkInfo {
  const LinkInfo({
    required this.originalUrl,
    required this.normalizedUrl,
    required this.platform,
    required this.kind,
    this.shortcode,
    this.videoId,
    this.isShortLink = false,
  });

  final String originalUrl;

  /// URL limpia (sin parametros de tracking) lista para analizar.
  final String normalizedUrl;
  final Platform platform;
  final ContentKind kind;

  /// Codigo de la publicacion de Instagram (p/reel/tv).
  final String? shortcode;

  /// Id numerico del video de Facebook, cuando se puede extraer del enlace.
  final String? videoId;

  /// fb.watch / instagr.am requieren seguir la redireccion antes de analizar.
  final bool isShortLink;

  bool get isSupported => platform != Platform.unknown;

  LinkInfo copyWith({String? normalizedUrl, String? videoId, String? shortcode}) {
    return LinkInfo(
      originalUrl: originalUrl,
      normalizedUrl: normalizedUrl ?? this.normalizedUrl,
      platform: platform,
      kind: kind,
      shortcode: shortcode ?? this.shortcode,
      videoId: videoId ?? this.videoId,
      isShortLink: isShortLink,
    );
  }
}
