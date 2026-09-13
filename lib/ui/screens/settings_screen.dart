import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';

/// Ajustes: carpeta de destino dentro de Movies, pegado automatico y el
/// extractor remoto opcional.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _folder;
  late final TextEditingController _endpoint;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _folder = TextEditingController(text: app.folder);
    _endpoint = TextEditingController(text: app.remoteEndpoint ?? '');
  }

  @override
  void dispose() {
    _folder.dispose();
    _endpoint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Carpeta de descarga',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _folder,
            decoration: const InputDecoration(
              prefixText: 'Movies/',
              prefixIcon: Icon(Icons.folder_rounded),
              helperText: 'Se crea automaticamente dentro del directorio de '
                  'videos de Android y aparece en la galeria.',
              helperMaxLines: 3,
            ),
            onSubmitted: app.setFolder,
            onChanged: app.setFolder,
          ),
          const SizedBox(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: app.autoPaste,
            onChanged: app.setAutoPaste,
            title: const Text('Detectar enlace del portapapeles'),
            subtitle: const Text(
              'Al abrir la app se revisa si copiaste un enlace de Facebook o '
              'Instagram.',
            ),
          ),
          const Divider(height: 32),
          Text('Extractor propio (opcional)',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Facebook e Instagram cambian su sitio con frecuencia y eso puede '
            'romper el analisis local. Si tienes un servicio propio (por '
            'ejemplo un servidor con yt-dlp), indicalo aqui y se usara primero.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _endpoint,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'URL del endpoint',
              hintText: 'https://mi-servidor.com/api/resolve',
              prefixIcon: Icon(Icons.cloud_outlined),
            ),
            onSubmitted: (value) => app.setRemote(value.trim(), null),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              app.setRemote(_endpoint.text.trim(), null);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Ajustes guardados')),
              );
            },
            child: const Text('Guardar'),
          ),
          const Divider(height: 40),
          Text('Uso responsable',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'La app solo descarga contenido publico. No guardes ni redistribuyas '
            'videos de terceros sin permiso: los derechos siguen siendo de su '
            'autor y las condiciones de uso de Meta se aplican igual.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
