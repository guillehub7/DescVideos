import 'package:dio/dio.dart';

import '../../models/analysis_result.dart';
import '../../models/link_info.dart';
import '../../models/media_variant.dart';
import '../http_client.dart';
import 'base_resolver.dart';

/// Extractor para Facebook (videos, reels y publicaciones con video).
///
/// Estrategia:
/// 1. Se resuelven los enlaces cortos (fb.watch) siguiendo la redireccion.
/// 2. Se pide el HTML publico con User-Agent de navegador.
/// 3. Se verifica si la pagina exige iniciar sesion -> contenido no publico.
/// 4. Se extraen las URLs de video del JSON embebido (claves conocidas de la
///    respuesta de Facebook) y de las etiquetas Open Graph.
class FacebookResolver implements BaseResolver {
  FacebookResolver({Dio? client}) : _client = client ?? HttpClientFactory.createHtmlClient();

  final Dio _client;

  /// Claves donde Facebook publica el mp4 progresivo, en orden de calidad.
  static const _hdKeys = ['playable_url_quality_hd', 'browser_native_hd_url', 'hd_src', 'hd_src_no_ratelimit'];
  static const _sdKeys = ['playable_url', 'browser_native_sd_url', 'sd_src', 'sd_src_no_ratelimit'];
  static const _dashKeys = ['playable_url_dash', 'dash_manifest_url'];

  @override
  Future<AnalysisResult> resolve(LinkInfo link) async {
    final target = await _expand(link);

    // mbasic sirve una version HTML simple donde los mp4 aparecen casi
    // siempre; www se usa como respaldo porque trae mejores metadatos.
    final candidates = <String>[
      _toMbasic(target.normalizedUrl),
      target.normalizedUrl,
    ];

    String? html;
    String? finalUrl;
    Object? lastError;

    for (final url in candidates) {
      try {
        final res = await _client.get<String>(url);
        final body = res.data ?? '';
        finalUrl = res.realUri.toString();
        if (body.isEmpty) continue;
        html = body;

        if (HtmlParseUtils.looksLikeLoginWall(body, finalUrl)) {
          // mbasic a veces exige sesion aunque www no: se sigue probando.
          continue;
        }
        final result = _parse(target, body, finalUrl);
        if (result.variants.isNotEmpty) return result;
      } catch (e) {
        lastError = e;
      }
    }

    if (html == null) {
      throw ResolveException(
        'No se pudo contactar a Facebook. Revisa tu conexion. ${lastError ?? ''}'.trim(),
      );
    }

    if (HtmlParseUtils.looksLikeLoginWall(html, finalUrl)) {
      return AnalysisResult(
        link: target,
        privacy: PrivacyStatus.requiereSesion,
        diagnostic: 'Facebook respondio con un muro de inicio de sesion.',
      );
    }
    if (HtmlParseUtils.looksUnavailable(html)) {
      return AnalysisResult(
        link: target,
        privacy: PrivacyStatus.noDisponible,
        diagnostic: 'Facebook informa que el contenido no esta disponible.',
      );
    }

    return _parse(target, html, finalUrl);
  }

  AnalysisResult _parse(LinkInfo link, String html, String? finalUrl) {
    final variants = <MediaVariant>[];

    for (final key in _hdKeys) {
      for (final url in HtmlParseUtils.jsonStringValues(html, key)) {
        variants.add(MediaVariant(
          url: url,
          label: 'HD',
          format: StreamFormat.progressive,
          height: 720,
        ));
      }
    }
    for (final key in _sdKeys) {
      for (final url in HtmlParseUtils.jsonStringValues(html, key)) {
        variants.add(MediaVariant(
          url: url,
          label: 'SD',
          format: StreamFormat.progressive,
          height: 360,
        ));
      }
    }
    for (final key in _dashKeys) {
      for (final url in HtmlParseUtils.jsonStringValues(html, key)) {
        variants.add(MediaVariant(
          url: url,
          label: 'Adaptativo (DASH)',
          format: StreamFormat.dash,
          height: 1080,
          hasAudio: false,
        ));
      }
    }

    final og = HtmlParseUtils.metaContent(html, 'og:video') ??
        HtmlParseUtils.metaContent(html, 'og:video:url') ??
        HtmlParseUtils.metaContent(html, 'og:video:secure_url');
    if (og != null && og.contains('.mp4')) {
      variants.add(MediaVariant(
        url: og,
        label: 'Estandar',
        format: StreamFormat.progressive,
        height: 480,
      ));
    }

    final normalized = HtmlParseUtils.normalize(variants);
    final privacy = normalized.any((v) => v.isDownloadable)
        ? PrivacyStatus.publico
        : (HtmlParseUtils.looksLikeLoginWall(html, finalUrl)
            ? PrivacyStatus.requiereSesion
            : PrivacyStatus.desconocido);

    final width = int.tryParse(HtmlParseUtils.metaContent(html, 'og:video:width') ?? '');
    final height = int.tryParse(HtmlParseUtils.metaContent(html, 'og:video:height') ?? '');

    return AnalysisResult(
      link: link,
      privacy: privacy,
      variants: _relabel(normalized, width, height),
      title: HtmlParseUtils.metaContent(html, 'og:title') ??
          HtmlParseUtils.metaContent(html, 'twitter:title'),
      author: HtmlParseUtils.jsonTextValue(html, 'owner_name') ??
          HtmlParseUtils.jsonTextValue(html, 'owner') ??
          HtmlParseUtils.metaContent(html, 'og:site_name'),
      thumbnailUrl: HtmlParseUtils.metaContent(html, 'og:image'),
      diagnostic: normalized.isEmpty
          ? 'No se encontraron pistas de video en la respuesta de Facebook. '
              'Puede ser una publicacion sin video, con DRM o un cambio en el sitio.'
          : null,
    );
  }

  /// Cuando Open Graph informa la resolucion real, se usa para etiquetar
  /// la variante HD con el valor correcto (1080p, 720p, ...).
  List<MediaVariant> _relabel(List<MediaVariant> variants, int? width, int? height) {
    if (height == null || height <= 0 || variants.isEmpty) return variants;
    return [
      for (var i = 0; i < variants.length; i++)
        i == 0
            ? variants[i].copyWith(label: '${variants[i].label} (${height}p)', height: height)
            : variants[i],
    ];
  }

  /// Sigue la redireccion de los enlaces cortos fb.watch / fb.me.
  Future<LinkInfo> _expand(LinkInfo link) async {
    if (!link.isShortLink) return link;
    try {
      final res = await _client.get<String>(link.normalizedUrl);
      final expanded = res.realUri.toString();
      if (expanded.isNotEmpty && expanded != link.normalizedUrl) {
        return link.copyWith(normalizedUrl: expanded);
      }
    } catch (_) {
      // Si falla se sigue con la URL corta: el servidor igual redirige.
    }
    return link;
  }

  String _toMbasic(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    if (!uri.host.toLowerCase().contains('facebook.com')) return url;
    return uri.replace(host: 'mbasic.facebook.com').toString();
  }
}
