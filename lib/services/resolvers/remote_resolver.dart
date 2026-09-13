import 'package:dio/dio.dart';

import '../../models/analysis_result.dart';
import '../../models/link_info.dart';
import '../../models/media_variant.dart';
import 'base_resolver.dart';

/// Extractor opcional que delega el analisis en un servicio propio.
///
/// Los extractores por HTML se rompen cada vez que Facebook o Instagram
/// cambian su front-end. Si configuras un endpoint propio (por ejemplo un
/// pequeno servidor con yt-dlp), la app lo usa primero y cae a los extractores
/// locales solo si el servicio falla.
///
/// Contrato esperado (JSON):
/// ```json
/// {
///   "public": true,
///   "title": "...",
///   "author": "...",
///   "thumbnail": "https://...",
///   "formats": [
///     {"url": "https://...mp4", "label": "1080p", "height": 1080,
///      "filesize": 12345678, "ext": "mp4", "has_audio": true}
///   ]
/// }
/// ```
class RemoteResolver implements BaseResolver {
  RemoteResolver({required this.endpoint, Dio? client, this.apiKey})
      : _client = client ?? Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 45),
        ));

  final String endpoint;
  final String? apiKey;
  final Dio _client;

  @override
  Future<AnalysisResult> resolve(LinkInfo link) async {
    final res = await _client.get<Map<String, dynamic>>(
      endpoint,
      queryParameters: {'url': link.normalizedUrl},
      options: Options(
        headers: {
          if (apiKey != null && apiKey!.isNotEmpty) 'Authorization': 'Bearer $apiKey',
        },
        responseType: ResponseType.json,
      ),
    );

    final data = res.data;
    if (data == null) {
      throw ResolveException('El servicio remoto no devolvio datos.');
    }

    final isPublic = data['public'] as bool? ?? false;
    final formats = (data['formats'] as List?) ?? const [];

    final variants = <MediaVariant>[
      for (final raw in formats.whereType<Map>())
        MediaVariant(
          url: raw['url']?.toString() ?? '',
          label: raw['label']?.toString() ??
              (raw['height'] != null ? '${raw['height']}p' : 'Calidad'),
          format: StreamFormat.progressive,
          height: (raw['height'] as num?)?.toInt(),
          width: (raw['width'] as num?)?.toInt(),
          bitrate: (raw['tbr'] as num?)?.toInt(),
          sizeBytes: (raw['filesize'] as num?)?.toInt(),
          hasAudio: raw['has_audio'] as bool? ?? true,
          container: raw['ext']?.toString() ?? 'mp4',
        ),
    ];

    return AnalysisResult(
      link: link,
      privacy: isPublic ? PrivacyStatus.publico : PrivacyStatus.requiereSesion,
      variants: HtmlParseUtils.normalize(variants),
      title: data['title']?.toString(),
      author: data['author']?.toString(),
      thumbnailUrl: data['thumbnail']?.toString(),
      durationSeconds: (data['duration'] as num?)?.toInt(),
    );
  }
}
