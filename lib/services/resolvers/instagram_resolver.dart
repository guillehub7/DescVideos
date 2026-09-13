import 'dart:convert';

import 'package:dio/dio.dart';

import '../../models/analysis_result.dart';
import '../../models/link_info.dart';
import '../../models/media_variant.dart';
import '../http_client.dart';
import 'base_resolver.dart';

/// Extractor para Instagram (reels, posts con video e IGTV).
///
/// Instagram no expone `og:video` ni un campo `video_url` plano. Lo que sirve
/// en la pagina publica es un JSON embebido con un array `video_versions`, mas
/// las URLs del manifiesto DASH. Todas apuntan al mismo CDN y se distinguen
/// por el parametro `efg` de la URL, que es un JSON en base64 cuyo campo
/// `vencode_tag` describe el stream:
///
///   xpv_progressive.INSTAGRAM.CLIPS.C3.720.dash_baseline  -> mp4 con audio
///   ig-xpvds.clips...dash_r2evevp9-r1gen2vp9_q80          -> solo video
///   ig-xpvds.clips...dash_ln_heaac_vbr3_audio             -> solo audio
///
/// Solo la progresiva se puede descargar tal cual; las DASH necesitarian
/// unirse con la pista de audio (ffmpeg), asi que se listan pero no se
/// habilitan.
class InstagramResolver implements BaseResolver {
  InstagramResolver({Dio? client})
      : _client = client ?? HttpClientFactory.createHtmlClient();

  final Dio _client;

  /// Cualquier mp4 del CDN, todavia escapado como aparece en el HTML.
  static final _mp4Pattern = RegExp(r'https?:\\?/\\?/[^"\s]+?\.mp4[^"\s]*');

  /// El array `video_versions` completo, para saber que URLs son las que
  /// Instagram considera reproducibles directamente.
  static final _videoVersionsPattern =
      RegExp(r'"video_versions"\s*:\s*\[(.*?)\]', dotAll: true);

  @override
  Future<AnalysisResult> resolve(LinkInfo link) async {
    if (link.kind == ContentKind.story) {
      return AnalysisResult(
        link: link,
        privacy: PrivacyStatus.requiereSesion,
        diagnostic: 'Las historias de Instagram nunca son publicas: siempre '
            'requieren una sesion iniciada.',
      );
    }

    final shortcode = link.shortcode;

    // La pagina con User-Agent de navegador es la que trae el JSON completo.
    // El endpoint /embed/ solo devuelve el armazon de JavaScript.
    final attempts = <_Attempt>[
      _Attempt(link.normalizedUrl, HttpClientFactory.desktopUserAgent),
      if (shortcode != null)
        _Attempt(
          'https://www.instagram.com/reel/$shortcode/',
          HttpClientFactory.desktopUserAgent,
        ),
      if (shortcode != null)
        _Attempt(
          'https://www.instagram.com/p/$shortcode/embed/captioned/',
          HttpClientFactory.desktopUserAgent,
        ),
    ];

    String? lastHtml;
    String? lastUrl;
    Object? lastError;

    for (final attempt in attempts) {
      try {
        final res = await _client.get<String>(
          attempt.url,
          options: Options(headers: {'User-Agent': attempt.userAgent}),
        );
        final html = res.data ?? '';
        if (html.isEmpty) continue;
        lastHtml = html;
        lastUrl = res.realUri.toString();

        final result = _parse(link, html, lastUrl);
        if (result.downloadable.isNotEmpty) return result;
      } catch (e) {
        lastError = e;
      }
    }

    if (lastHtml == null) {
      throw ResolveException(
        'No se pudo contactar a Instagram. Revisa tu conexion. ${lastError ?? ''}'
            .trim(),
      );
    }

    if (HtmlParseUtils.looksUnavailable(lastHtml)) {
      return AnalysisResult(
        link: link,
        privacy: PrivacyStatus.noDisponible,
        diagnostic: 'Instagram informa que la publicacion no esta disponible.',
      );
    }
    if (_isPrivate(lastHtml) || HtmlParseUtils.looksLikeLoginWall(lastHtml, lastUrl)) {
      return AnalysisResult(
        link: link,
        privacy: PrivacyStatus.privado,
        diagnostic: 'La publicacion pertenece a una cuenta privada o exige '
            'iniciar sesion para verla.',
      );
    }

    return _parse(link, lastHtml, lastUrl);
  }

  AnalysisResult _parse(LinkInfo link, String html, String? finalUrl) {
    final variants = _extractVariants(html);
    final progressive = variants.where((v) => v.isDownloadable).toList();

    // Que el CDN entregue la URL sin sesion es la prueba de que es publico.
    // `is_private` lo confirma desde el propio JSON cuando esta presente.
    final PrivacyStatus privacy;
    if (_isPrivate(html)) {
      privacy = PrivacyStatus.privado;
    } else if (progressive.isNotEmpty) {
      privacy = PrivacyStatus.publico;
    } else if (HtmlParseUtils.looksLikeLoginWall(html, finalUrl)) {
      privacy = PrivacyStatus.requiereSesion;
    } else {
      privacy = PrivacyStatus.desconocido;
    }

    final dashOnly = variants.length - progressive.length;

    return AnalysisResult(
      link: link,
      privacy: privacy,
      variants: variants,
      title: _title(html),
      author: HtmlParseUtils.jsonTextValue(html, 'username') ?? _authorFromOgUrl(html),
      thumbnailUrl: HtmlParseUtils.metaContent(html, 'og:image'),
      diagnostic: progressive.isEmpty
          ? 'No se encontro un video descargable en esta publicacion. Puede '
              'ser solo imagenes, una cuenta privada o un cambio en Instagram.'
          : (dashOnly > 0
              ? 'Instagram publica 1 version con audio y $dashOnly pistas DASH '
                  'sueltas (video o audio por separado), que no se pueden '
                  'descargar sin unirlas.'
              : null),
    );
  }

  /// Recorre todos los mp4 de la pagina y los clasifica por su `vencode_tag`.
  List<MediaVariant> _extractVariants(String html) {
    // URLs que Instagram lista como reproducibles directamente.
    final playable = <String>{};
    for (final match in _videoVersionsPattern.allMatches(html)) {
      final block = match.group(1) ?? '';
      for (final url in _mp4Pattern.allMatches(block)) {
        playable.add(_key(HtmlParseUtils.unescape(url.group(0)!)));
      }
    }

    final variants = <MediaVariant>[];

    for (final match in _mp4Pattern.allMatches(html)) {
      final url = HtmlParseUtils.unescape(match.group(0)!);
      final tag = _vencodeTag(url) ?? '';

      // La pista de audio suelta no le sirve al usuario.
      if (tag.contains('audio') && !tag.contains('progressive')) continue;

      final isProgressive = tag.contains('progressive') ||
          (tag.isEmpty && playable.contains(_key(url)));

      if (isProgressive) {
        final height = _heightFromTag(tag);
        variants.add(MediaVariant(
          url: url,
          label: height != null ? '${height}p (video + audio)' : 'Original',
          format: StreamFormat.progressive,
          height: height,
        ));
      } else if (tag.contains('dash')) {
        final quality = RegExp(r'_q(\d+)').firstMatch(tag)?.group(1);
        variants.add(MediaVariant(
          url: url,
          label: 'DASH${quality != null ? ' q$quality' : ''} (sin audio)',
          format: StreamFormat.dash,
          // Sin audio: MediaVariant.isDownloadable lo deja fuera.
          hasAudio: false,
          bitrate: quality == null ? null : int.tryParse(quality),
        ));
      }
    }

    return HtmlParseUtils.normalize(variants);
  }

  /// Identidad de una URL del CDN ignorando los parametros de sesion.
  String _key(String url) => url.split('?').first;

  /// Decodifica el parametro `efg` (JSON en base64) y devuelve `vencode_tag`.
  String? _vencodeTag(String url) {
    final raw = RegExp(r'[?&]efg=([^&"]+)').firstMatch(url)?.group(1);
    if (raw == null) return null;
    try {
      final decoded = base64.decode(base64.normalize(Uri.decodeComponent(raw)));
      final json = jsonDecode(utf8.decode(decoded));
      if (json is Map<String, dynamic>) return json['vencode_tag'] as String?;
    } catch (_) {
      // Un efg ilegible solo significa que no podemos clasificar esa URL.
    }
    return null;
  }

  /// `xpv_progressive.INSTAGRAM.CLIPS.C3.720.dash_baseline_1_v1` -> 720
  int? _heightFromTag(String tag) {
    for (final part in tag.split('.')) {
      final value = int.tryParse(part);
      if (value != null && value >= 144 && value <= 4320) return value;
    }
    return null;
  }

  String? _title(String html) {
    final og = HtmlParseUtils.metaContent(html, 'og:title');
    if (og == null || og.isEmpty) return null;
    // og:title llega como `Autor en Instagram: "texto del pie"`.
    final quoted = RegExp(r'"(.+)"', dotAll: true).firstMatch(og);
    final text = (quoted?.group(1) ?? og).trim();
    final firstLine = text.split('\n').first.trim();
    return firstLine.isEmpty ? text : firstLine;
  }

  /// `og:url` es `instagram.com/<usuario>/reel/<codigo>/`: sirve de respaldo
  /// cuando el JSON no trae `username`.
  String? _authorFromOgUrl(String html) {
    final og = HtmlParseUtils.metaContent(html, 'og:url');
    if (og == null) return null;
    final segments = Uri.tryParse(og)?.pathSegments.where((s) => s.isNotEmpty);
    if (segments == null || segments.isEmpty) return null;
    final first = segments.first;
    return const {'p', 'reel', 'reels', 'tv'}.contains(first) ? null : first;
  }

  bool _isPrivate(String html) {
    if (html.contains('"is_private":true')) return true;
    final lower = html.toLowerCase();
    return lower.contains('this account is private') ||
        lower.contains('esta cuenta es privada');
  }
}

class _Attempt {
  const _Attempt(this.url, this.userAgent);
  final String url;
  final String userAgent;
}
