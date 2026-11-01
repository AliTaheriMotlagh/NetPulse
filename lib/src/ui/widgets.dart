import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../monitor.dart';
import 'theme.dart';

/// Scrollable page body, centred with a readable max width on large screens.
class PageList extends StatelessWidget {
  const PageList({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final side = max(16.0, (box.maxWidth - 1100) / 2);
      return ListView.separated(
        padding: EdgeInsets.fromLTRB(side, 8, side, 24),
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(height: 16),
        itemBuilder: (_, i) => children[i],
      );
    },
  );
}

/// Equal-width responsive grid: as many columns as fit [minWidth].
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children, this.minWidth = 200, this.gap = 12});
  final List<Widget> children;
  final double minWidth, gap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final cols = max(1, ((box.maxWidth + gap) / (minWidth + gap)).floor());
      final w = (box.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final c in children) SizedBox(width: w, child: c)],
      );
    },
  );
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, this.subtitle, this.trailing, required this.child});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: t.titleMedium),
                      if (subtitle != null) Text(subtitle!, style: t.bodySmall?.copyWith(color: Viz.of(context).ink)),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.sub,
    this.iconColor,
    this.onTap,
  });
  final IconData icon;
  final String label, value;
  final String? sub;
  final Color? iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final ink = Viz.of(context).ink;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Semantics(
          label: '$label $value',
          button: onTap != null,
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 20, color: iconColor ?? ink),
                    const SizedBox(width: 8),
                    Text(label, style: t.labelLarge?.copyWith(color: ink)),
                  ],
                ),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w600, fontFeatures: tabular),
                  ),
                ),
                if (sub != null)
                  Text(
                    sub!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(color: ink, fontFeatures: tabular),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class Metric extends StatelessWidget {
  const Metric(this.label, this.value, {super.key});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.labelMedium?.copyWith(color: Viz.of(context).ink)),
        Text(value, style: t.titleMedium?.copyWith(fontFeatures: tabular)),
      ],
    );
  }
}

class LegendDot extends StatelessWidget {
  const LegendDot(this.color, this.label, {super.key});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.labelMedium),
    ],
  );
}

// ---- shared actions ---------------------------------------------------------

void doCheckpoint(BuildContext context, NetMonitor m) {
  final c = m.checkpoint();
  HapticFeedback.mediumImpact();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('${c.label} saved · ${fmtBytes(c.rx + c.tx)} so far'),
      ),
    );
}

Future<void> confirmReset(BuildContext context, NetMonitor m) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.restart_alt_rounded),
      title: const Text('Start a new session?'),
      content: const Text(
        'Totals and the chart go back to zero. The current session and its checkpoints move to history.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reset')),
      ],
    ),
  );
  if (ok == true) {
    m.reset();
    HapticFeedback.heavyImpact();
  }
}

Future<void> copyText(BuildContext context, String text, String what) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text('$what copied')));
}
