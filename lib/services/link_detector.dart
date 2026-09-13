import '../models/link_info.dart';

/// Detecta de que red social viene un enlace y que tipo de contenido es.
/// No hace red: solo analiza el texto, por eso es instantaneo al pegar o al
/// recibir un "Compartir con..." desde otra app.
class LinkDetector {
  static final RegExp _urlPattern = RegExp(
    r'https?://[^\s<>"' "'" r']+',
    caseSensitive: false,
  );

  static const _facebookHosts = {
    'facebook.com',
    'www.facebook.com',
    'm.facebook.com',
    'mbasic.facebook.com',
    'web.facebook.com',
    'business.facebook.com',
    'fb.watch',
    'fb.gg',
    'fb.me',
  };

  static const _instagramHosts = {
    'instagram.com',
    'www.instagram.com',
    'm.instagram.com',
    'instagr.am',
    'ig.me',
  };

  /// Extrae la primera URL de un texto arbitrario (portapapeles, texto
  /// compartido por la app de Instagram, etc.).
  static String? extractUrl(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final match = _urlPattern.firstMatch(text.trim());
    return match?.group(0);
  }

  /// Analiza un texto o URL y devuelve la plataforma detectada.
  static LinkInfo detect(String rawInput) {
    final raw = extractUrl(rawInput) ?? rawInput.trim();
    final uri = Uri.tryParse(raw);

    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return LinkInfo(
        originalUrl: raw,
        normalizedUrl: raw,
        platform: Platform.unknown,
        kind: ContentKind.unknown,
      );
    }

    final host = uri.host.toLowerCase();

    if (_instagramHosts.contains(host)) return _detectInstagram(raw, uri);
    if (_facebookHosts.contains(host)) return _detectFacebook(raw, uri);

    return LinkInfo(
      originalUrl: raw,
      normalizedUrl: raw,
      platform: Platform.unknown,
      kind: ContentKind.unknown,
    );
  }

  static LinkInfo _detectInstagram(String raw, Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    var kind = ContentKind.unknown;
    String? shortcode;

    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i].toLowerCase();
      final next = i + 1 < segments.length ? segments[i + 1] : null;
      if (seg == 'p' && next != null) {
        kind = ContentKind.post;
        shortcode = next;
        break;
      }
      if ((seg == 'reel' || seg == 'reels') && next != null) {
        kind = ContentKind.reel;
        shortcode = next;
        break;
      }
      if (seg == 'tv' && next != null) {
        kind = ContentKind.video;
        shortcode = next;
        break;
      }
      if (seg == 'stories') {
        kind = ContentKind.story;
        break;
      }
    }

    // Las historias siempre exigen sesion: se marcan para avisar temprano.
    final normalized = shortcode != null
        ? 'https://www.instagram.com/${kind == ContentKind.reel ? 'reel' : kind == ContentKind.video ? 'tv' : 'p'}/$shortcode/'
        : _stripTracking(uri);

    return LinkInfo(
      originalUrl: raw,
      normalizedUrl: normalized,
      platform: Platform.instagram,
      kind: kind,
      shortcode: shortcode,
      isShortLink: uri.host.toLowerCase() == 'instagr.am',
    );
  }

  static LinkInfo _detectFacebook(String raw, Uri uri) {
    final host = uri.host.toLowerCase();
    final isShort = host == 'fb.watch' || host == 'fb.me' || host == 'fb.gg';
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

    var kind = ContentKind.unknown;
    String? videoId = uri.queryParameters['v'];

    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i].toLowerCase();
      final next = i + 1 < segments.length ? segments[i + 1] : null;
      if (seg == 'videos' && next != null) {
        kind = ContentKind.video;
        videoId ??= RegExp(r'^\d+$').hasMatch(next) ? next : null;
      } else if (seg == 'reel' && next != null) {
        kind = ContentKind.reel;
        videoId ??= next;
      } else if (seg == 'watch') {
        kind = ContentKind.video;
      } else if (seg == 'story.php' || seg == 'stories') {
        kind = ContentKind.story;
      } else if (seg == 'posts' || seg == 'permalink.php' || seg == 'share') {
        kind = ContentKind.post;
      }
    }

    if (kind == ContentKind.unknown && isShort) kind = ContentKind.video;

    return LinkInfo(
      originalUrl: raw,
      normalizedUrl: isShort ? raw : _stripTracking(uri),
      platform: Platform.facebook,
      kind: kind,
      videoId: videoId,
      isShortLink: isShort,
    );
  }

  /// Quita parametros de rastreo que ensucian la URL y a veces rompen el
  /// scraping (fbclid, igshid, utm_*).
  static String _stripTracking(Uri uri) {
    const noise = {'fbclid', 'igshid', 'igsh', 'mibextid', 'rdid', '_rdr', 'comment_id'};
    final params = Map<String, String>.from(uri.queryParameters)
      ..removeWhere((k, _) => noise.contains(k) || k.startsWith('utm_'));
    return uri.replace(queryParameters: params.isEmpty ? null : params).toString();
  }
}
