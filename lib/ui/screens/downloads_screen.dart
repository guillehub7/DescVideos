import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../../models/download_task.dart';
import '../../state/app_state.dart';

/// Lista de descargas en curso e historial de la sesion.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final tasks = app.tasks;

    return Scaffold(
      appBar: AppBar(title: const Text('Descargas')),
      body: tasks.isEmpty
          ? const _EmptyState()
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: tasks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _TaskTile(task: tasks[i]),
            ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (task.status.isActive)
                  IconButton(
                    tooltip: 'Cancelar',
                    icon: const Icon(Icons.stop_circle_outlined),
                    onPressed: () => app.cancelDownload(task),
                  )
                else
                  IconButton(
                    tooltip: 'Quitar de la lista',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => app.removeTask(task),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${task.platformLabel} - ${task.variant.label}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            if (task.status.isActive) ...[
              LinearProgressIndicator(
                value: task.total > 0 ? task.progress : null,
                minHeight: 6,
                borderRadius: BorderRadius.circular(6),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(task.status.label, style: theme.textTheme.bodySmall),
                  Text(task.progressLabel, style: theme.textTheme.bodySmall),
                ],
              ),
            ] else
              Row(
                children: [
                  Icon(
                    switch (task.status) {
                      DownloadStatus.completado => Icons.check_circle_rounded,
                      DownloadStatus.error => Icons.error_outline_rounded,
                      _ => Icons.info_outline_rounded,
                    },
                    size: 18,
                    color: task.status == DownloadStatus.completado
                        ? const Color(0xFF17A34A)
                        : theme.colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      task.status == DownloadStatus.completado
                          ? 'Guardado en ${task.savedPath}'
                          : (task.error ?? task.status.label),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            if (task.status == DownloadStatus.completado &&
                task.savedPath != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => OpenFilex.open(
                    '/storage/emulated/0/${task.savedPath}',
                    type: 'video/mp4',
                  ),
                  icon: const Icon(Icons.play_circle_outline_rounded),
                  label: const Text('Reproducir'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_rounded,
                size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('Todavia no hay descargas', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Analiza un enlace publico de Facebook o Instagram y elige la '
              'calidad para empezar.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
