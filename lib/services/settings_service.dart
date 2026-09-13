import 'package:shared_preferences/shared_preferences.dart';

import 'storage_service.dart';

/// Preferencias persistentes: carpeta destino, calidad preferida y el
/// endpoint opcional del extractor propio.
class SettingsService {
  static const _kFolder = 'folder_name';
  static const _kAutoPaste = 'auto_paste';
  static const _kEndpoint = 'remote_endpoint';
  static const _kApiKey = 'remote_api_key';

  late SharedPreferences _prefs;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
  }

  String get folder => _prefs.getString(_kFolder) ?? StorageService.defaultFolder;
  set folder(String value) => _prefs.setString(_kFolder, value);

  bool get autoPaste => _prefs.getBool(_kAutoPaste) ?? true;
  set autoPaste(bool value) => _prefs.setBool(_kAutoPaste, value);

  String? get remoteEndpoint => _prefs.getString(_kEndpoint);
  set remoteEndpoint(String? value) =>
      value == null || value.isEmpty ? _prefs.remove(_kEndpoint) : _prefs.setString(_kEndpoint, value);

  String? get remoteApiKey => _prefs.getString(_kApiKey);
  set remoteApiKey(String? value) =>
      value == null || value.isEmpty ? _prefs.remove(_kApiKey) : _prefs.setString(_kApiKey, value);
}
