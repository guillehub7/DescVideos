# DescVideos

App Flutter (Android) para descargar videos **publicos** de Facebook e Instagram.

Flujo: pegas o compartes un enlace → la app detecta la red social → verifica que
el contenido sea publico → te muestra las calidades disponibles con su peso →
descargas a una carpeta propia dentro del directorio de videos de Android.

## Como levantar el proyecto

No tienes el SDK de Flutter instalado en este equipo. Instalalo desde
<https://docs.flutter.dev/get-started/install/windows> y luego, dentro de esta
carpeta:

```bash
flutter create . --platforms=android --project-name descvideos --org com.descvideos
```

`flutter create` **no sobreescribe los archivos existentes**: genera solo el
andamiaje que falta (gradle, `MainActivity.kt`, iconos, `.gitignore`) y respeta
`lib/`, `pubspec.yaml` y el `AndroidManifest.xml` que ya estan escritos.

Después:

```bash
flutter pub get
```

```bash
flutter test
```

```bash
flutter run
```

Para el APK de release:

```bash
flutter build apk --release
```

### Ajustes de Gradle ya aplicados

`android/app/build.gradle.kts` fija `compileSdk = 37` porque
`receive_sharing_intent` lo exige (el valor por defecto de Flutter es 36). Solo
afecta la compilacion: `minSdk` y `targetSdk` siguen tomando los valores de
Flutter.

## Arquitectura

```
lib/
  core/app_theme.dart              Tema Material 3 (claro/oscuro)
  models/
    link_info.dart                 Plataforma y tipo de contenido detectado
    media_variant.dart             Cada opcion de calidad
    analysis_result.dart           Resultado del analisis + estado de privacidad
    download_task.dart             Tarea de descarga con progreso
  services/
    link_detector.dart             Deteccion de plataforma (sin red, instantanea)
    http_client.dart               Clientes Dio con User-Agent adecuado
    resolver_service.dart          Orquesta analisis + medicion de tamanos
    resolvers/
      base_resolver.dart           Contrato + utilidades de parseo HTML/JSON
      facebook_resolver.dart       Extractor de Facebook
      instagram_resolver.dart      Extractor de Instagram
      remote_resolver.dart         Extractor propio opcional (HTTP)
    storage_service.dart           Permisos + puente al guardado nativo
    download_service.dart          Descarga con progreso y cancelacion
    settings_service.dart          Preferencias persistentes
  state/app_state.dart             Estado central (ChangeNotifier + provider)
  ui/                              Pantallas y widgets

android/app/src/main/kotlin/.../MainActivity.kt
                                   Guardado nativo en MediaStore
tool/diagnose.dart                 Diagnostico de extractores contra un enlace real
```

## Los cuatro requisitos que pediste

1. **Detectar de que aplicacion es.** `LinkDetector` clasifica el enlace por
   host y ruta sin hacer red, asi que el chip de "Facebook - Reel" aparece
   mientras escribes. Acepta ademas `fb.watch`, `fb.me`, `instagr.am`, texto
   compartido con el enlace dentro y limpia los parametros de rastreo
   (`fbclid`, `igshid`, `utm_*`).

2. **Verificar que sea publico.** Cada extractor pide la pagina **sin sesion**.
   Si la respuesta trae un muro de login, marcadores de cuenta privada o de
   contenido no disponible, el resultado es `requiereSesion` / `privado` /
   `noDisponible` y **el boton de descarga no se habilita**. Las historias de
   Instagram se bloquean de entrada porque nunca son publicas.

3. **Preguntar la calidad.** Tras el analisis se abre una hoja inferior con las
   calidades encontradas (HD/SD en Facebook, resoluciones de `video_versions`
   en Instagram). El peso real de cada una se mide con una peticion `HEAD`
   antes de mostrarlas, y ahi mismo puedes renombrar el archivo.

4. **Carpeta en el directorio de videos.** Se guarda en `Movies/<carpeta>` (por
   defecto `DescVideos`, editable en Ajustes). El guardado esta escrito en
   Kotlin dentro de `MainActivity.kt` y se invoca desde `StorageService` por un
   MethodChannel: en Android 10+ usa **MediaStore** (el video aparece en la
   galeria sin pedir permiso de escritura, y se marca `IS_PENDING` mientras se
   copia para que no asome un archivo a medias); en Android 9 o anterior
   escribe la ruta directa pidiendo `WRITE_EXTERNAL_STORAGE` y avisa al escaner
   de medios.

   No se uso ningun plugin de MediaStore a proposito: `media_store_plus`, el
   unico candidato, esta abandonado (compilado contra android-33) y rompe el
   build con el Android Gradle Plugin actual.

## Limitaciones reales (importante)

- **Ni Facebook ni Instagram ofrecen una API publica de descarga.** Los
  extractores leen el HTML publico y las claves JSON embebidas. Meta cambia ese
  front-end a menudo: cuando eso pase, hay que actualizar los patrones en
  `facebook_resolver.dart` / `instagram_resolver.dart`. Para diagnosticar que
  cambio hay una herramienta dedicada:

  ```bash
  dart run tool/diagnose.dart "https://www.instagram.com/reel/XXXX/"
  ```

  Imprime, por cada intento, el codigo HTTP, la URL final, las claves halladas
  y los `.mp4` crudos, y guarda el HTML en la carpeta temporal.

- **Instagram solo publica una calidad con audio.** Verificado contra un reel
  publico real: la pagina trae 10 URLs de video, y el parametro `efg` de cada
  una (JSON en base64) las identifica en su campo `vencode_tag`:

  | `vencode_tag` | Contenido |
  |---|---|
  | `xpv_progressive...C3.720.dash_baseline` | mp4 720p **con audio** (descargable) |
  | `dash_r2evevp9..._q20` a `_q90` | 8 renditions **solo video** |
  | `dash_ln_heaac_vbr3_audio` | **solo audio** |

  Las DASH se listan en el analisis pero quedan deshabilitadas: usarlas
  requeriria unir video y audio con ffmpeg. Por eso un reel ofrece una sola
  opcion de calidad, y eso es lo que Instagram entrega, no una limitacion
  artificial de la app.

- **El endpoint `/embed/captioned/` ya no sirve** y la API
  `i.instagram.com/api/v1/media/<id>/info/` redirige a `/accounts/login/`. Lo
  unico que funciona sin sesion es la pagina del reel pedida con User-Agent de
  navegador de escritorio.
- Por eso existe `RemoteResolver`: si pones un endpoint propio en Ajustes (por
  ejemplo un servidor con `yt-dlp`), la app lo usa primero y el mantenimiento
  se concentra en el servidor. Contrato JSON esperado documentado en
  `lib/services/resolvers/remote_resolver.dart`.
- Solo se descargan **mp4 progresivos** (que es lo que sirven ambas redes para
  contenido publico). Los manifiestos DASH/HLS se listan pero quedan
  deshabilitados porque unir pista de video y audio requiere ffmpeg, que no se
  incluye.
- Los enlaces de los CDN de Meta **caducan en minutos**. Si una descarga falla
  con 403, hay que volver a analizar; la app ya muestra ese mensaje.
- La app no inicia sesion, no guarda cookies ni permite sortear restricciones:
  es una decision de diseno para mantener el alcance en contenido publico.

## Uso responsable

Descargar contenido publico no te da derechos sobre el. Los videos siguen
siendo de su autor y las condiciones de uso de Meta se aplican igual. Usa la
app para tu propio contenido o para material con permiso explicito, y no
redistribuyas videos de terceros.
