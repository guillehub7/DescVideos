import 'package:descvideos/models/link_info.dart';
import 'package:descvideos/services/link_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Deteccion de plataforma', () {
    test('reconoce un reel de Instagram', () {
      final info = LinkDetector.detect('https://www.instagram.com/reel/CabcD12eFg/?igshid=xyz');
      expect(info.platform, Platform.instagram);
      expect(info.kind, ContentKind.reel);
      expect(info.shortcode, 'CabcD12eFg');
      expect(info.normalizedUrl, 'https://www.instagram.com/reel/CabcD12eFg/');
    });

    test('reconoce una publicacion de Instagram', () {
      final info = LinkDetector.detect('https://instagram.com/p/XyZ123/');
      expect(info.platform, Platform.instagram);
      expect(info.kind, ContentKind.post);
      expect(info.shortcode, 'XyZ123');
    });

    test('marca las historias de Instagram', () {
      final info = LinkDetector.detect('https://www.instagram.com/stories/usuario/12345/');
      expect(info.kind, ContentKind.story);
    });

    test('reconoce un video de Facebook con id', () {
      final info = LinkDetector.detect('https://www.facebook.com/pagina/videos/1234567890/');
      expect(info.platform, Platform.facebook);
      expect(info.kind, ContentKind.video);
      expect(info.videoId, '1234567890');
    });

    test('reconoce watch con parametro v', () {
      final info = LinkDetector.detect('https://www.facebook.com/watch/?v=987654321&fbclid=abc');
      expect(info.platform, Platform.facebook);
      expect(info.videoId, '987654321');
      expect(info.normalizedUrl.contains('fbclid'), isFalse);
    });

    test('marca fb.watch como enlace corto', () {
      final info = LinkDetector.detect('https://fb.watch/aB9cD-e/');
      expect(info.platform, Platform.facebook);
      expect(info.isShortLink, isTrue);
    });

    test('rechaza enlaces de otras plataformas', () {
      final info = LinkDetector.detect('https://www.youtube.com/watch?v=abc');
      expect(info.platform, Platform.unknown);
      expect(info.isSupported, isFalse);
    });

    test('extrae la URL de un texto compartido', () {
      const shared = 'Mira esto https://www.instagram.com/reel/AbC123/ increible';
      final info = LinkDetector.detect(shared);
      expect(info.platform, Platform.instagram);
      expect(info.shortcode, 'AbC123');
    });
  });
}
