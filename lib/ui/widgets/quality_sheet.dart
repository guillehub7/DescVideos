import 'package:flutter/material.dart';

import '../../models/analysis_result.dart';
import '../../models/media_variant.dart';

/// Hoja inferior donde el usuario elige la calidad, el nombre del archivo y
/// confirma la carpeta destino antes de descargar.
class QualitySheet extends StatefulWidget {
  const QualitySheet({
    super.key,
    required this.analysis,
    required this.folder,
    required this.onChangeFolder,
  });

  final AnalysisResult analysis;
  final String folder;
  final Future<void> Function() onChangeFolder;

  /// Devuelve la calidad elegida y el nombre del archivo, o null si se cancela.
  static Future<({MediaVariant variant, String name})?> show(
    BuildContext context, {
    required AnalysisResult analysis,
    required String folder,
    required Future<void> Function() onChangeFolder,
  }) {
    return showModalBottomSheet<({MediaVariant variant, String name})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => QualitySheet(
        analysis: analysis,
        folder: folder,
        onChangeFolder: onChangeFolder,
      ),
    );
  }

  @override
  State<QualitySheet> createState() => _QualitySheetState();
}

class _QualitySheetState extends State<QualitySheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.analysis.suggestedFileName);
  int _selected = 0;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final variants = widget.analysis.downloadable;
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('En que calidad quieres descargarlo?',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              '${variants.length} ${variants.length == 1 ? 'opcion disponible' : 'opciones disponibles'}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            RadioGroup<int>(
              groupValue: _selected,
              onChanged: (value) => setState(() => _selected = value ?? 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(variants.length, (i) {
                  final v = variants[i];
                  return RadioListTile<int>(
                    value: i,
                    contentPadding: EdgeInsets.zero,
                    title: Text(v.label,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '${v.sizeLabel} - ${v.container.toUpperCase()}'
                      '${v.height != null ? ' - ${v.height}p' : ''}',
                    ),
                    secondary: Icon(
                      i == 0 ? Icons.hd_rounded : Icons.sd_rounded,
                      color: theme.colorScheme.primary,
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nombre del archivo',
                suffixText: '.mp4',
                prefixIcon: Icon(Icons.drive_file_rename_outline),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_open_rounded),
              title: const Text('Guardar en'),
              subtitle: Text('Movies/${widget.folder}'),
              trailing: TextButton(
                onPressed: () async {
                  await widget.onChangeFolder();
                  if (mounted) setState(() {});
                },
                child: const Text('Cambiar'),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: variants.isEmpty
                  ? null
                  : () => Navigator.pop(
                        context,
                        (variant: variants[_selected], name: _name.text),
                      ),
              icon: const Icon(Icons.download_rounded),
              label: const Text('Descargar'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
