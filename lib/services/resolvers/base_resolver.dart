import '../../models/analysis_result.dart';
import '../../models/link_info.dart';
import '../../models/media_variant.dart';

/// Contrato comun de los extractores. Cada plataforma implementa el suyo y el
/// [ResolverService] elige cual usar segun la deteccion del enlace.
abstract class BaseResolver {
  Future<AnalysisResult> resolve(LinkInfo link);
}

/// Utilidades de parseo compartidas por los extractores. Facebook e Instagram
/// entregan las URLs dentro de JSON embebido en el HTML, escapadas con
/// secuencias `\/`, `%`, etc.
class HtmlParseUtils {
  HtmlParseUtils._();

  /// Deshace el escapado tipo JSON/JS de una URL embebida en el HTML.
  static String unescape(String input) {
    var out = input.replaceAll(r'\/', '/').replaceAll(r'\\', r'\');
    out = out.replaceAllMapped(
      RegExp(r'\\u([0-9a-fA-F]{4})'),
      (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
    );
    out = out
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
    // Entidades numericas: Instagram escribe los acentos del pie de foto como
    // `&#xf3;` (hex) o `&#243;` (decimal).
    out = out.replaceAllMapped(
      RegExp(r'&#x([0-9a-fA-F]+);'),
      (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
    );
    out = out.replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (m) => String.fromCharCode(int.parse(m.group(1)!)),
    );
    return out;
  }

  /// Lee una etiqueta meta de Open Graph (`og:video`, `og:title`, ...).
  static String? metaContent(String html, String property) {
    final patterns = [
      RegExp(
        '<meta[^>]+(?:property|name)=["\']$property["\'][^>]*content=["\']([^"\']*)["\']',
        caseSensitive: false,
      ),
      RegExp(
        '<meta[^>]+content=["\']([^"\']*)["\'][^>]*(?:property|name)=["\']$property["\']',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      final value = match?.group(1);
      if (value != null && value.isNotEmpty) return unescape(value);
    }
    return null;
  }

  /// Busca el valor de una clave JSON de tipo string dentro del HTML.
  /// Ej: `"playable_url_quality_hd":"https:\/\/video.xx.fbcdn.net\/..."`.
  static List<String> jsonStringValues(String html, String key) {
    final regex = RegExp('"${RegExp.escape(key)}"\\s*:\\s*"(.*?)"');
    return regex
        .allMatches(html)
        .map((m) => unescape(m.group(1) ?? ''))
        .where((v) => v.startsWith('http'))
        .toSet()
        .toList();
  }

  static String? firstJsonString(String html, String key) {
    final values = jsonStringValues(html, key);
    return values.isEmpty ? null : values.first;
  }

  /// Igual que [jsonStringValues] pero para valores que no son URLs (nombre de
  /// usuario, titulo, etc.), donde el filtro de `http` no aplica.
  static String? jsonTextValue(String html, String key) {
    final match =
        RegExp('"${RegExp.escape(key)}"\\s*:\\s*"([^"]*)"').firstMatch(html);
    final value = match?.group(1);
    return (value == null || value.isEmpty) ? null : unescape(value);
  }

  /// Senales de que la pagina exige sesion: es el criterio principal para
  /// clasificar un contenido como no publico.
  static bool looksLikeLoginWall(String html, String? finalUrl) {
    final url = (finalUrl ?? '').toLowerCase();
    if (url.contains('/login') ||
        url.contains('/accounts/login') ||
        url.contains('login.php') ||
        url.contains('/checkpoint')) {
      return true;
    }
    final markers = [
      'you must log in to continue',
      'inicia sesion para continuar',
      'debes iniciar sesion',
      'log into facebook',
      'inicia sesion en facebook',
      'log in to instagram',
      'inicia sesion en instagram',
      'please log in',
      '"is_logged_out":true,"login_required":true',
    ];
    final lower = html.toLowerCase();
    return markers.any(lower.contains);
  }

  static bool looksUnavailable(String html) {
    final markers = [
      "sorry, this page isn't available",
      'esta pagina no esta disponible',
      'contenido no disponible',
      'this content isn\'t available',
      'el contenido no esta disponible en este momento',
      'video unavailable',
    ];
    final lower = html.toLowerCase();
    return markers.any(lower.contains);
  }

  /// Ordena las calidades de mejor a peor y elimina duplicados por URL.
  static List<MediaVariant> normalize(List<MediaVariant> variants) {
    final seen = <String>{};
    final unique = <MediaVariant>[];
    for (final v in variants) {
      if (v.url.isEmpty) continue;
      final key = v.url.split('?').first;
      if (seen.add(key)) unique.add(v);
    }
    unique.sort((a, b) => b.rank.compareTo(a.rank));
    return unique;
  }
}

/// Excepcion de negocio para reportar fallos del extractor con un mensaje util.
class ResolveException implements Exception {
  ResolveException(this.message, {this.privacy = PrivacyStatus.desconocido});

  final String message;
  final PrivacyStatus privacy;

  @override
  String toString() => message;
}
