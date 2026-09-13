import 'package:dio/dio.dart';

/// Cliente HTTP compartido. Se usa un User-Agent de navegador de escritorio
/// porque tanto Facebook como Instagram devuelven el HTML con los metadatos
/// publicos (og:video, playable_url) solo a clientes que parecen navegador.
class HttpClientFactory {
  HttpClientFactory._();

  static const desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  /// UA de crawler: util como segundo intento porque devuelve la version
  /// "tarjeta de enlace" con las etiquetas Open Graph.
  static const crawlerUserAgent =
      'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)';

  static Dio createHtmlClient({String userAgent = desktopUserAgent}) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 25),
        followRedirects: true,
        maxRedirects: 6,
        // Se aceptan 4xx para poder distinguir "privado" de "error de red".
        validateStatus: (status) => status != null && status < 500,
        responseType: ResponseType.plain,
        headers: {
          'User-Agent': userAgent,
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'es-ES,es;q=0.9,en;q=0.8',
          'Sec-Fetch-Mode': 'navigate',
          'Upgrade-Insecure-Requests': '1',
        },
      ),
    );
    return dio;
  }

  static Dio createDownloadClient() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 10),
        followRedirects: true,
        maxRedirects: 5,
        headers: {'User-Agent': desktopUserAgent},
      ),
    );
  }
}
