package com.descvideos.descvideos

import android.content.ContentValues
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Guarda el video descargado en el directorio publico de videos de Android.
 *
 * Se implementa aqui en lugar de usar un plugin porque los paquetes
 * disponibles estan compilados contra APIs antiguas y rompen el build.
 *
 * Android 10 (Q) o superior usa MediaStore: no requiere permiso de escritura
 * y el video aparece en la galeria. Por debajo de Q se escribe la ruta
 * directa y se avisa al escaner de medios.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "descvideos/mediastore"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveVideo" -> {
                        val tempPath = call.argument<String>("tempPath")
                        val fileName = call.argument<String>("fileName")
                        val folder = call.argument<String>("folder")

                        if (tempPath == null || fileName == null || folder == null) {
                            result.error("ARGS", "Faltan argumentos para guardar el video", null)
                            return@setMethodCallHandler
                        }

                        val source = File(tempPath)
                        if (!source.exists()) {
                            result.error("NO_FILE", "El archivo descargado ya no existe", null)
                            return@setMethodCallHandler
                        }

                        try {
                            result.success(saveVideo(source, fileName, folder))
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.message ?: "Error al guardar", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Devuelve la ruta legible donde quedo el archivo. */
    private fun saveVideo(source: File, fileName: String, folder: String): String {
        val relative = "${Environment.DIRECTORY_MOVIES}/$folder"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                put(MediaStore.Video.Media.RELATIVE_PATH, relative)
                // IS_PENDING oculta el archivo a la galeria hasta terminar de
                // copiarlo, para que no aparezca un video a medias.
                put(MediaStore.Video.Media.IS_PENDING, 1)
            }

            val uri = contentResolver.insert(
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                values
            ) ?: throw IllegalStateException("MediaStore no acepto el archivo")

            contentResolver.openOutputStream(uri).use { output ->
                requireNotNull(output) { "No se pudo abrir el destino de escritura" }
                source.inputStream().use { it.copyTo(output) }
            }

            values.clear()
            values.put(MediaStore.Video.Media.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)

            source.delete()
            return "$relative/$fileName"
        }

        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES),
            folder
        )
        if (!dir.exists() && !dir.mkdirs()) {
            throw IllegalStateException("No se pudo crear la carpeta $relative")
        }

        val dest = File(dir, fileName)
        source.copyTo(dest, overwrite = true)
        source.delete()

        MediaScannerConnection.scanFile(
            this,
            arrayOf(dest.absolutePath),
            arrayOf("video/mp4"),
            null
        )
        return "$relative/$fileName"
    }
}
