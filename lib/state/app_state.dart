import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../models/analysis_result.dart';
import '../models/download_task.dart';
import '../models/link_info.dart';
import '../models/media_variant.dart';
import '../services/download_service.dart';
import '../services/link_detector.dart';
import '../services/resolver_service.dart';
import '../services/resolvers/base_resolver.dart';
import '../services/settings_service.dart';

enum AppStage { inicio, analizando, listo, bloqueado, error }

/// Estado central de la app: enlace detectado, analisis, descargas activas.
class AppState extends ChangeNotifier {
  AppState({
    ResolverService? resolver,
    DownloadService? downloads,
    SettingsService? settings,
  })  : _resolver = resolver ?? ResolverService(),
        _downloads = downloads ?? DownloadService(),
        _settings = settings ?? SettingsService();

  final ResolverService _resolver;
  final DownloadService _downloads;
  final SettingsService _settings;

  StreamSubscription<List<SharedMediaFile>>? _shareSub;

  AppStage stage = AppStage.inicio;
  String input = '';
  LinkInfo? detected;
  AnalysisResult? analysis;
  String? errorMessage;

  final List<DownloadTask> tasks = [];

  String get folder => _settings.folder;
  bool get autoPaste => _settings.autoPaste;
  String? get remoteEndpoint => _settings.remoteEndpoint;

  Future<void> init() async {
    await _settings.load();
    await _downloads.storage.init(folder: _settings.folder);
    _resolver.remoteEndpoint = _settings.remoteEndpoint;
    _resolver.remoteApiKey = _settings.remoteApiKey;
    _listenToShares();
    notifyListeners();
  }

  /// Escucha los enlaces que llegan desde "Compartir" de Facebook/Instagram,
  /// tanto con la app cerrada como abierta.
  void _listenToShares() {
    ReceiveSharingIntent.instance.getInitialMedia().then(_handleShared);
    _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      _handleShared,
      onError: (_) {},
    );
  }

  void _handleShared(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    final text = files
        .map((f) => f.path)
        .firstWhere((p) => LinkDetector.extractUrl(p) != null, orElse: () => '');
    final url = LinkDetector.extractUrl(text);
    if (url == null) return;
    ReceiveSharingIntent.instance.reset();
    setInput(url);
    unawaited(analyze());
  }

  /// Lee el portapapeles al volver a la app: si trae un enlace soportado se
  /// carga solo, que es el flujo mas comun (copiar enlace y abrir la app).
  Future<String?> peekClipboard() async {
    if (!_settings.autoPaste) return null;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final url = LinkDetector.extractUrl(data?.text);
    if (url == null) return null;
    final info = LinkDetector.detect(url);
    if (!info.isSupported) return null;
    if (url == input) return null;
    return url;
  }

  void setInput(String value) {
    input = value;
    detected = value.trim().isEmpty ? null : LinkDetector.detect(value);
    if (stage != AppStage.analizando) {
      stage = AppStage.inicio;
      analysis = null;
      errorMessage = null;
    }
    notifyListeners();
  }

  void clear() {
    input = '';
    detected = null;
    analysis = null;
    errorMessage = null;
    stage = AppStage.inicio;
    notifyListeners();
  }

  Future<void> analyze() async {
    if (input.trim().isEmpty) return;
    stage = AppStage.analizando;
    errorMessage = null;
    analysis = null;
    notifyListeners();

    try {
      final result = await _resolver.analyze(input);
      analysis = result;
      if (result.canDownload) {
        stage = AppStage.listo;
      } else {
        stage = AppStage.bloqueado;
      }
    } on ResolveException catch (e) {
      errorMessage = e.message;
      stage = AppStage.error;
    } catch (e) {
      errorMessage = 'No se pudo analizar el enlace: $e';
      stage = AppStage.error;
    }
    notifyListeners();
  }

  /// Inicia la descarga de la calidad elegida. Devuelve la tarea creada.
  DownloadTask? startDownload(MediaVariant variant, {String? customName}) {
    final current = analysis;
    if (current == null || !current.privacy.allowsDownload) return null;

    final task = _downloads.createTask(
      analysis: current,
      variant: variant,
      customName: customName,
    );
    tasks.insert(0, task);
    notifyListeners();

    unawaited(_downloads.run(task, folder: _settings.folder, onProgress: notifyListeners));
    return task;
  }

  void cancelDownload(DownloadTask task) => _downloads.cancel(task.id);

  void removeTask(DownloadTask task) {
    tasks.remove(task);
    notifyListeners();
  }

  Future<void> setFolder(String value) async {
    _settings.folder = value;
    _downloads.storage.setFolder(value);
    notifyListeners();
  }

  Future<void> setAutoPaste(bool value) async {
    _settings.autoPaste = value;
    notifyListeners();
  }

  Future<void> setRemote(String? endpoint, String? apiKey) async {
    _settings.remoteEndpoint = endpoint;
    _settings.remoteApiKey = apiKey;
    _resolver.remoteEndpoint = endpoint;
    _resolver.remoteApiKey = apiKey;
    notifyListeners();
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }
}
