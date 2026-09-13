// Herramienta de diagnostico: ejecuta las mismas peticiones que hace la app
// contra un enlace real y muestra exactamente que devuelve cada intento.
//
// Uso:
//   dart run tool/diagnose.dart "https://www.instagram.com/reel/XXXX/"
//
// Guarda cada respuesta HTML en la carpeta temporal para poder inspeccionarla
// a mano cuando los patrones de extraccion dejan de coincidir.

import 'dart:io';

import 'package:descvideos/models/link_info.dart';
import 'package:descvideos/services/http_client.dart';
import 'package:descvideos/services/link_detector.dart';
import 'package:descvideos/services/resolver_service.dart';
import 'package:dio/dio.dart';

/// Claves que la app busca dentro del HTML. Si ninguna aparece, el extractor
/// no tiene de donde sacar la URL del video.
const _clavesBuscadas = [
  'playable_url_quality_hd',
  'playable_url',
  'browser_native_hd_url',
  'browser_native_sd_url',
  'hd_src',
  'sd_src',
  'video_url',
  'video_versions',
  'contentUrl',
  'og:video',
  'dash_manifest',
  'shortcode_media',
  'xdt_api__v1__media__shortcode__web_info',
];

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stdout.writeln('Uso: dart run tool/diagnose.dart "<url>"');
    exit(64);
  }

  final entrada = args.first;
  final link = LinkDetector.detect(entrada);

  _titulo('DETECCION');
  stdout.writeln('Entrada      : $entrada');
  stdout.writeln('Plataforma   : ${link.platform.label}');
  stdout.writeln('Tipo         : ${link.kind.label}');
  stdout.writeln('Normalizada  : ${link.normalizedUrl}');
  stdout.writeln('Shortcode    : ${link.shortcode ?? "-"}');
  stdout.writeln('Video id     : ${link.videoId ?? "-"}');
  stdout.writeln('Enlace corto : ${link.isShortLink}');

  if (!link.isSupported) {
    stdout.writeln('\nEl enlace no es de Facebook ni de Instagram.');
    exit(1);
  }

  final intentos = _intentosPara(link);

  for (final intento in intentos) {
    await _probar(intento);
  }

  _titulo('RESULTADO DEL EXTRACTOR REAL');
  try {
    final resultado = await ResolverService().analyze(entrada);
    stdout.writeln('Privacidad   : ${resultado.privacy.name}');
    stdout.writeln('Titulo       : ${resultado.title ?? "-"}');
    stdout.writeln('Autor        : ${resultado.author ?? "-"}');
    stdout.writeln('Calidades    : ${resultado.variants.length}');
    for (final v in resultado.variants) {
      stdout.writeln('  - ${v.label} | ${v.sizeLabel} | ${v.format.name}');
      stdout.writeln('    ${v.url.substring(0, v.url.length.clamp(0, 110))}');
    }
    stdout.writeln('Diagnostico  : ${resultado.diagnostic ?? "-"}');
  } catch (e) {
    stdout.writeln('Excepcion    : $e');
  }
}

List<_Intento> _intentosPara(LinkInfo link) {
  if (link.platform == Platform.instagram) {
    final code = link.shortcode;
    return [
      if (code != null)
        _Intento(
          'embed reel',
          'https://www.instagram.com/reel/$code/embed/captioned/',
          HttpClientFactory.desktopUserAgent,
        ),
      if (code != null)
        _Intento(
          'embed post',
          'https://www.instagram.com/p/$code/embed/captioned/',
          HttpClientFactory.desktopUserAgent,
        ),
      _Intento('pagina + crawler UA', link.normalizedUrl,
          HttpClientFactory.crawlerUserAgent),
      _Intento('pagina + navegador UA', link.normalizedUrl,
          HttpClientFactory.desktopUserAgent),
    ];
  }

  final uri = Uri.parse(link.normalizedUrl);
  final mbasic = uri.host.contains('facebook.com')
      ? uri.replace(host: 'mbasic.facebook.com').toString()
      : link.normalizedUrl;

  return [
    _Intento('mbasic', mbasic, HttpClientFactory.desktopUserAgent),
    _Intento('www + navegador UA', link.normalizedUrl,
        HttpClientFactory.desktopUserAgent),
    _Intento('www + crawler UA', link.normalizedUrl,
        HttpClientFactory.crawlerUserAgent),
  ];
}

Future<void> _probar(_Intento intento) async {
  _titulo('INTENTO: ${intento.nombre}');
  stdout.writeln('URL : ${intento.url}');

  final dio = HttpClientFactory.createHtmlClient(userAgent: intento.userAgent);

  try {
    final res = await dio.get<String>(
      intento.url,
      options: Options(headers: {'User-Agent': intento.userAgent}),
    );
    final html = res.data ?? '';

    stdout.writeln('HTTP: ${res.statusCode}');
    stdout.writeln('URL final: ${res.realUri}');
    stdout.writeln('Bytes: ${html.length}');

    final encontradas = _clavesBuscadas.where(html.contains).toList();
    stdout.writeln('Claves encontradas: '
        '${encontradas.isEmpty ? "NINGUNA" : encontradas.join(", ")}');

    // Cualquier .mp4 presente, aunque este bajo una clave que no conocemos.
    final mp4 = RegExp(r'https?:[^"\s]{0,400}?\.mp4[^"\s]{0,200}')
        .allMatches(html)
        .map((m) => m.group(0)!)
        .toSet()
        .toList();
    stdout.writeln('URLs .mp4 crudas: ${mp4.length}');
    for (final u in mp4.take(3)) {
      stdout.writeln('  ${u.substring(0, u.length.clamp(0, 120))}');
    }

    final archivo = File(
      '${Directory.systemTemp.path}/descvideos_${intento.nombre.replaceAll(RegExp(r"[^a-zA-Z0-9]"), "_")}.html',
    );
    await archivo.writeAsString(html);
    stdout.writeln('HTML guardado en: ${archivo.path}');
  } catch (e) {
    stdout.writeln('ERROR: $e');
  }
}

void _titulo(String texto) {
  stdout.writeln('\n${"=" * 70}\n$texto\n${"=" * 70}');
}

class _Intento {
  const _Intento(this.nombre, this.url, this.userAgent);
  final String nombre;
  final String url;
  final String userAgent;
}
