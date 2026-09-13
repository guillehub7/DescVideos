import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Resultado de guardar un archivo en el almacenamiento publico.
class SaveResult {
  const SaveResult({required this.success, this.displayPath, this.error});

  final bool success;

  /// Ruta legible para el usuario: `Movies/DescVideos/archivo.mp4`.
  final String? displayPath;
  final String? error;
}

/// Se encarga de permisos y de escribir el video en el directorio publico de
/// videos de Android, creando la carpeta elegida por el usuario.
///
/// El guardado real lo hace [MainActivity] en Kotlin a traves de un
/// MethodChannel: Android 10+ usa MediaStore (sin permiso de escritura y el
/// video aparece en la galeria) y Android 9 o anterior escribe la ruta directa.
class StorageService {
  StorageService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('descvideos/mediastore');

  final MethodChannel _channel;
  int? _sdkInt;

  static const defaultFolder = 'DescVideos';

  String _folder = defaultFolder;

  Future<void> init({String folder = defaultFolder}) async {
    _folder = _sanitizeFolder(folder);
  }

  void setFolder(String folder) => _folder = _sanitizeFolder(folder);

  Future<int> androidSdk() async {
    if (_sdkInt != null) return _sdkInt!;
    if (!Platform.isAndroid) return 0;
    final info = await DeviceInfoPlugin().androidInfo;
    return _sdkInt = info.version.sdkInt;
  }

  /// Pide el permiso minimo necesario segun la version de Android.
  Future<bool> ensurePermissions() async {
    if (!Platform.isAndroid) return true;
    final sdk = await androidSdk();

    if (sdk >= 33) {
      // Android 13+: MediaStore escribe en Movies sin permiso. Se pide
      // READ_MEDIA_VIDEO solo para poder abrir lo ya descargado.
      final status = await Permission.videos.request();
      return status.isGranted || status.isLimited || status.isPermanentlyDenied;
    }
    if (sdk >= 29) {
      // Android 10-12: MediaStore alcanza para escribir.
      return true;
    }
    final status = await Permission.storage.request();
    return status.isGranted;
  }

  /// Carpeta temporal donde se descarga antes de publicar el archivo.
  Future<Directory> tempDir() async {
    final dir = await getTemporaryDirectory();
    final target = Directory('${dir.path}/descargas');
    if (!await target.exists()) await target.create(recursive: true);
    return target;
  }

  /// Publica el archivo temporal en Movies/<carpeta>/<nombre>.
  Future<SaveResult> publish({
    required File tempFile,
    required String fileName,
    required String folder,
  }) async {
    final safeFolder = _sanitizeFolder(folder);
    final safeName = _sanitizeFileName(fileName);

    if (!Platform.isAndroid) {
      // En escritorio/iOS se deja el archivo en el directorio de documentos.
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/$safeFolder');
      if (!await dir.exists()) await dir.create(recursive: true);
      final dest = File('${dir.path}/$safeName');
      await tempFile.copy(dest.path);
      if (await tempFile.exists()) await tempFile.delete();
      return SaveResult(success: true, displayPath: dest.path);
    }

    try {
      final path = await _channel.invokeMethod<String>('saveVideo', {
        'tempPath': tempFile.path,
        'fileName': safeName,
        'folder': safeFolder,
      });
      if (path != null && path.isNotEmpty) {
        return SaveResult(success: true, displayPath: path);
      }
      return const SaveResult(
        success: false,
        error: 'El sistema no devolvio la ruta del archivo guardado.',
      );
    } on PlatformException catch (e) {
      return SaveResult(
        success: false,
        error: 'No se pudo guardar en Movies/$safeFolder: ${e.message}',
      );
    } catch (e) {
      return SaveResult(success: false, error: 'No se pudo guardar: $e');
    }
  }

  String _sanitizeFolder(String folder) {
    final clean = folder
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
    return clean.isEmpty ? defaultFolder : clean;
  }

  String _sanitizeFileName(String name) {
    var clean = name.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (clean.isEmpty) clean = 'video_${DateTime.now().millisecondsSinceEpoch}';
    if (!clean.toLowerCase().endsWith('.mp4')) clean = '$clean.mp4';
    return clean;
  }

  /// Carpeta actualmente configurada (ya saneada).
  String get folder => _folder;
}
