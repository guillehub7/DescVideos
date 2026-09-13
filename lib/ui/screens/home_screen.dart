import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/analysis_result.dart';
// Necesarios para las extensiones DownloadStatusX y PlatformX.
import '../../models/download_task.dart';
import '../../models/link_info.dart';
import '../../state/app_state.dart';
import '../widgets/platform_chip.dart';
import '../widgets/quality_sheet.dart';
import 'downloads_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkClipboard());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver de Facebook/Instagram se revisa si el usuario copio un enlace.
    if (state == AppLifecycleState.resumed) _checkClipboard();
  }

  Future<void> _checkClipboard() async {
    final app = context.read<AppState>();
    final url = await app.peekClipboard();
    if (url == null || !mounted) return;
    _controller.text = url;
    app.setInput(url);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Enlace detectado en el portapapeles'),
        action: SnackBarAction(label: 'Analizar', onPressed: app.analyze),
      ),
    );
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty || !mounted) return;
    _controller.text = text;
    context.read<AppState>().setInput(text);
  }

  Future<void> _openQualitySheet(AppState app, AnalysisResult analysis) async {
    final choice = await QualitySheet.show(
      context,
      analysis: analysis,
      folder: app.folder,
      onChangeFolder: () async {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
        );
      },
    );
    if (choice == null || !mounted) return;

    app.startDownload(choice.variant, customName: choice.name);
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const DownloadsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final active = app.tasks.where((t) => t.status.isActive).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('DescVideos'),
        actions: [
          IconButton(
            tooltip: 'Descargas',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const DownloadsScreen()),
            ),
            icon: Badge(
              isLabelVisible: active > 0,
              label: Text('$active'),
              child: const Icon(Icons.download_done_rounded),
            ),
          ),
          IconButton(
            tooltip: 'Ajustes',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'Pega o comparte el enlace',
            style:
                theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'La app reconoce automaticamente si es de Facebook o Instagram y '
            'verifica que la publicacion sea publica antes de descargar.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _controller,
            maxLines: 2,
            minLines: 1,
            keyboardType: TextInputType.url,
            onChanged: app.setInput,
            decoration: InputDecoration(
              hintText: 'https://www.instagram.com/reel/...',
              prefixIcon: const Icon(Icons.link_rounded),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Pegar',
                    icon: const Icon(Icons.content_paste_rounded),
                    onPressed: _paste,
                  ),
                  if (app.input.isNotEmpty)
                    IconButton(
                      tooltip: 'Limpiar',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _controller.clear();
                        app.clear();
                      },
                    ),
                ],
              ),
            ),
          ),
          if (app.detected != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: PlatformChip(link: app.detected!),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: app.stage == AppStage.analizando ||
                    app.detected == null ||
                    !app.detected!.isSupported
                ? null
                : app.analyze,
            icon: app.stage == AppStage.analizando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child:
                        CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.search_rounded),
            label: Text(app.stage == AppStage.analizando
                ? 'Analizando y verificando...'
                : 'Analizar enlace'),
          ),
          const SizedBox(height: 24),
          _ResultArea(onDownload: _openQualitySheet),
        ],
      ),
    );
  }
}

/// Zona que cambia segun el estado: error, bloqueo por privacidad o resultado
/// listo para descargar.
class _ResultArea extends StatelessWidget {
  const _ResultArea({required this.onDownload});

  final Future<void> Function(AppState, AnalysisResult) onDownload;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);

    if (app.stage == AppStage.error) {
      return _InfoCard(
        icon: Icons.error_outline_rounded,
        color: theme.colorScheme.error,
        title: 'No se pudo analizar',
        body: app.errorMessage ?? 'Error desconocido.',
      );
    }

    final analysis = app.analysis;
    if (analysis == null) {
      return _InfoCard(
        icon: Icons.shield_outlined,
        color: theme.colorScheme.primary,
        title: 'Solo contenido publico',
        body: 'Antes de descargar se comprueba que la publicacion se pueda ver '
            'sin iniciar sesion. Las historias y las cuentas privadas quedan '
            'bloqueadas para respetar la privacidad y las condiciones de uso.',
      );
    }

    final ok = analysis.privacy.allowsDownload;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    PrivacyBadge(label: analysis.privacy.label, ok: ok),
                    const Spacer(),
                    Text(
                      analysis.link.platform.label,
                      style: theme.textTheme.labelLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (analysis.thumbnailUrl != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.network(
                        analysis.thumbnailUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.image_not_supported_outlined),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (analysis.title != null)
                  Text(
                    analysis.title!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                if (analysis.author != null) ...[
                  const SizedBox(height: 4),
                  Text('Por ${analysis.author}', style: theme.textTheme.bodySmall),
                ],
                const SizedBox(height: 10),
                Text(analysis.privacy.explanation, style: theme.textTheme.bodySmall),
                if (analysis.diagnostic != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    analysis.diagnostic!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (ok && analysis.downloadable.isNotEmpty)
          FilledButton.icon(
            onPressed: () => onDownload(app, analysis),
            icon: const Icon(Icons.tune_rounded),
            label: Text('Elegir calidad (${analysis.downloadable.length})'),
          )
        else
          OutlinedButton.icon(
            onPressed: app.analyze,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reintentar analisis'),
          ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(body, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
