import 'package:dio/dio.dart';

import '../models/analysis_result.dart';
import '../models/link_info.dart';
import '../models/media_variant.dart';
import 'http_client.dart';
import 'link_detector.dart';
import 'resolvers/base_resolver.dart';
import 'resolvers/facebook_resolver.dart';
import 'resolvers/instagram_resolver.dart';
import 'resolvers/remote_resolver.dart';

/// Orquesta todo el analisis: detecta la plataforma, elige el extractor,
/// verifica que el contenido sea publico y completa el tamano de cada calidad.
class ResolverService {
  ResolverService({
    FacebookResolver? facebook,
    InstagramResolver? instagram,
    Dio? probeClient,
  })  : _facebook = facebook ?? FacebookResolver(),
        _instagram = instagram ?? InstagramResolver(),
        _probe = probeClient ?? HttpClientFactory.createDownloadClient();

  final FacebookResolver _facebook;
  final InstagramResolver _instagram;
  final Dio _probe;

  /// Endpoint propio opcional. Si esta definido se intenta primero.
  String? remoteEndpoint;
  String? remoteApiKey;

  LinkInfo detect(String input) => LinkDetector.detect(input);

  Future<AnalysisResult> analyze(String input) async {
    final link = LinkDetector.detect(input);

    if (!link.isSupported) {
      throw ResolveException(
        'El enlace no es de Facebook ni de Instagram. Comparte o pega un '
        'enlace de esas dos redes.',
      );
    }

    AnalysisResult result;

    final endpoint = remoteEndpoint;
    if (endpoint != null && endpoint.trim().isNotEmpty) {
      try {
        result = await RemoteResolver(endpoint: endpoint.trim(), apiKey: remoteApiKey)
            .resolve(link);
        if (result.variants.isNotEmpty) return await _withSizes(result);
      } catch (_) {
        // Si el servicio propio falla se continua con los extractores locales.
      }
    }

    final resolver = _resolverFor(link.platform);
    result = await resolver.resolve(link);
    return _withSizes(result);
  }

  BaseResolver _resolverFor(Platform platform) => switch (platform) {
        Platform.facebook => _facebook,
        Platform.instagram => _instagram,
        Platform.unknown => throw ResolveException('Plataforma no soportada.'),
      };

  /// Pide el tamano real de cada calidad con una peticion HEAD para que el
  /// usuario elija sabiendo cuanto pesa. Si el servidor no responde HEAD se
  /// deja el tamano en null y la descarga igual funciona.
  Future<AnalysisResult> _withSizes(AnalysisResult result) async {
    if (result.variants.isEmpty) return result;

    final sized = await Future.wait(
      result.variants.map((variant) async {
        if (!variant.isDownloadable || variant.sizeBytes != null) return variant;
        final size = await _contentLength(variant.url);
        return size == null ? variant : variant.copyWith(sizeBytes: size);
      }),
    );

    return result.copyWith(variants: _dedupeBySize(sized));
  }

  Future<int?> _contentLength(String url) async {
    try {
      final res = await _probe.head<dynamic>(
        url,
        options: Options(validateStatus: (s) => s != null && s < 500),
      );
      final raw = res.headers.value(Headers.contentLengthHeader);
      return raw == null ? null : int.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  /// Facebook suele repetir la misma calidad con URLs distintas: si dos
  /// variantes pesan exactamente lo mismo se muestra solo una.
  List<MediaVariant> _dedupeBySize(List<MediaVariant> variants) {
    final seenSizes = <int>{};
    final out = <MediaVariant>[];
    for (final v in variants) {
      final size = v.sizeBytes;
      if (size != null && size > 0 && !seenSizes.add(size)) continue;
      out.add(v);
    }
    return out;
  }
}
