import 'dart:io';

import 'package:dio/dio.dart';

import '../models/analysis_result.dart';
import '../models/download_task.dart';
// Necesario para la extension PlatformX (link.platform.label).
import '../models/link_info.dart';
import '../models/media_variant.dart';
import 'http_client.dart';
import 'storage_service.dart';

/// Descarga el mp4 elegido y lo publica en la carpeta de videos.
class DownloadService {
  DownloadService({Dio? client, StorageService? storage})
      : _client = client ?? HttpClientFactory.createDownloadClient(),
        _storage = storage ?? StorageService();

  final Dio _client;
  final StorageService _storage;
  final Map<String, CancelToken> _tokens = {};

  StorageService get storage => _storage;

  DownloadTask createTask({
    required AnalysisResult analysis,
    required MediaVariant variant,
    String? customName,
  }) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final base = (customName == null || customName.trim().isEmpty)
        ? analysis.suggestedFileName
        : customName.trim();
    final quality = variant.height != null ? '_${variant.height}p' : '';
    return DownloadTask(
      id: id,
      fileName: '$base$quality.mp4',
      variant: variant,
      sourceUrl: analysis.link.normalizedUrl,
      platformLabel: analysis.link.platform.label,
      thumbnailUrl: analysis.thumbnailUrl,
      total: variant.sizeBytes ?? 0,
    );
  }

  /// Ejecuta la descarga. [onProgress] se llama en cada bloque recibido para
  /// refrescar la UI.
  Future<void> run(
    DownloadTask task, {
    required String folder,
    required void Function() onProgress,
  }) async {
    final cancelToken = CancelToken();
    _tokens[task.id] = cancelToken;

    try {
      final granted = await _storage.ensurePermissions();
      if (!granted) {
        task
          ..status = DownloadStatus.error
          ..error = 'Se necesita permiso de almacenamiento para guardar el video.';
        onProgress();
        return;
      }

      final dir = await _storage.tempDir();
      final tempPath = '${dir.path}/${task.id}.part';

      task.status = DownloadStatus.descargando;
      onProgress();

      await _client.download(
        task.variant.url,
        tempPath,
        cancelToken: cancelToken,
        options: Options(
          headers: {
            // Referer correcto: los CDN de Meta rechazan peticiones sin el.
            'Referer': task.platformLabel == 'Instagram'
                ? 'https://www.instagram.com/'
                : 'https://www.facebook.com/',
            'Accept': '*/*',
          },
        ),
        onReceiveProgress: (received, total) {
          task.received = received;
          if (total > 0) task.total = total;
          onProgress();
        },
      );

      task.status = DownloadStatus.guardando;
      onProgress();

      final result = await _storage.publish(
        tempFile: File(tempPath),
        fileName: task.fileName,
        folder: folder,
      );

      if (result.success) {
        task
          ..status = DownloadStatus.completado
          ..savedPath = result.displayPath;
      } else {
        task
          ..status = DownloadStatus.error
          ..error = result.error;
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        task.status = DownloadStatus.cancelado;
      } else {
        task
          ..status = DownloadStatus.error
          ..error = _friendlyError(e);
      }
    } catch (e) {
      task
        ..status = DownloadStatus.error
        ..error = e.toString();
    } finally {
      _tokens.remove(task.id);
      onProgress();
    }
  }

  void cancel(String taskId) {
    _tokens[taskId]?.cancel('Cancelado por el usuario');
  }

  String _friendlyError(DioException e) {
    final code = e.response?.statusCode;
    if (code == 403 || code == 401) {
      return 'El enlace de descarga expiro (los enlaces de Meta duran pocos '
          'minutos). Vuelve a analizar la publicacion.';
    }
    if (code == 404) return 'El video ya no esta en el servidor.';
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Se agoto el tiempo de espera. Revisa tu conexion.';
    }
    return e.message ?? 'Error de descarga.';
  }
}
