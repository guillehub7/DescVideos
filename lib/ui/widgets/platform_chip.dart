import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../models/link_info.dart';

/// Chip que muestra en tiempo real que red social se detecto en el enlace.
class PlatformChip extends StatelessWidget {
  const PlatformChip({super.key, required this.link});

  final LinkInfo link;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.platformColor(link.platform.label);
    final supported = link.isSupported;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            supported ? Icons.verified_outlined : Icons.help_outline,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            supported
                ? '${link.platform.label} - ${link.kind.label}'
                : 'Enlace no soportado',
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Insignia del estado de privacidad verificado durante el analisis.
class PrivacyBadge extends StatelessWidget {
  const PrivacyBadge({super.key, required this.label, required this.ok});

  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = ok ? const Color(0xFF17A34A) : scheme.error;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(ok ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
            size: 18, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14)),
      ],
    );
  }
}
