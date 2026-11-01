import 'package:flutter/material.dart';

import '../counters/apps.dart';
import '../format.dart';
import '../monitor.dart';
import 'theme.dart';
import 'widgets.dart';

enum _Sort { now, session, total }

class AppsPage extends StatefulWidget {
  const AppsPage(this.m, {super.key});
  final NetMonitor m;

  @override
  State<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends State<AppsPage> {
  _Sort _sort = _Sort.session;
  String _query = '';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.m,
    builder: (context, _) {
      final m = widget.m;
      final ink = Viz.of(context).ink;
      Widget note(IconData icon, String text, [Widget? action]) => Card(
        child: ListTile(leading: Icon(icon), title: Text(text), trailing: action),
      );

      if (m.appSource == null) {
        return PageList(children: [note(Icons.info_outline_rounded, AppSource.unsupportedReason)]);
      }
      if (!m.settings.trackApps) {
        return PageList(
          children: [
            note(
              Icons.pause_circle_outline_rounded,
              'Per-app tracking is off.',
              FilledButton.tonal(
                onPressed: () => m.settings.update((s) => s.trackApps = true),
                child: const Text('Turn on'),
              ),
            ),
          ],
        );
      }
      if (m.appsNeedAccess) {
        return PageList(
          children: [
            note(
              Icons.lock_open_rounded,
              'Allow Usage access so Android can report traffic per app.',
              FilledButton(onPressed: m.requestAppAccess, child: const Text('Allow')),
            ),
          ],
        );
      }
      final apps = m.apps;
      if (apps == null) {
        return PageList(
          children: [
            if (m.appsError != null) note(Icons.error_outline_rounded, m.appsError!),
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        );
      }

      final s = m.session.apps;
      int sessionOf(String n) => (s[n]?[0] ?? 0) + (s[n]?[1] ?? 0);
      final q = _query.toLowerCase();
      // Apps that already exited still have session totals; keep them listed.
      final names = {...apps.keys, ...s.keys}.where((n) => n.toLowerCase().contains(q)).toList();
      double key(String n) => switch (_sort) {
        _Sort.now => (apps[n]?.down ?? 0) + (apps[n]?.up ?? 0),
        _Sort.session => sessionOf(n).toDouble(),
        _Sort.total => ((apps[n]?.rx ?? 0) + (apps[n]?.tx ?? 0)).toDouble(),
      };
      names
        ..removeWhere((n) => key(n) == 0 && sessionOf(n) == 0 && (apps[n]?.rx ?? 0) + (apps[n]?.tx ?? 0) == 0)
        ..sort((a, b) => key(b).compareTo(key(a)));
      final top = names.isEmpty ? 1.0 : key(names.first).clamp(1, double.infinity).toDouble();

      return PageList(
        children: [
          Text(
            'Measured from the OS (${m.appSource!.description}) every ${m.appSource!.interval.inSeconds} s while NetPulse is open. '
            '“Session” resets with the session; “Since start” is each process’s own lifetime total.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ink),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Filter apps',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              SegmentedButton<_Sort>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: _Sort.now, label: Text('Now')),
                  ButtonSegment(value: _Sort.session, label: Text('Session')),
                  ButtonSegment(value: _Sort.total, label: Text('Since start')),
                ],
                selected: {_sort},
                onSelectionChanged: (v) => setState(() => _sort = v.first),
              ),
            ],
          ),
          if (names.isEmpty) note(Icons.hourglass_empty_rounded, 'No app traffic yet.'),
          for (final n in names.take(200)) _AppRow(n, apps[n], s[n], key(n) / top, m.settings.bits),
        ],
      );
    },
  );
}

class _AppRow extends StatelessWidget {
  const _AppRow(this.name, this.live, this.session, this.share, this.bits);
  final String name;
  final AppUsage? live;
  final List<int>? session;
  final double share;
  final bool bits;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final viz = Viz.of(context);
    final a = live;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    a == null || a.procs < 2 ? name : '$name  ·  ${a.procs} processes',
                    style: t.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  fmtBytes((session?[0] ?? 0) + (session?[1] ?? 0)),
                  style: t.titleSmall?.copyWith(fontFeatures: tabular),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: share.clamp(0, 1),
                minHeight: 4,
                color: viz.down,
                backgroundColor: viz.grid,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              a == null
                  ? 'Not running · session ↓ ${fmtBytes(session?[0] ?? 0)} ↑ ${fmtBytes(session?[1] ?? 0)}'
                  : 'Now ↓ ${fmtRate(a.down, bits: bits)} ↑ ${fmtRate(a.up, bits: bits)}  ·  '
                        'Session ↓ ${fmtBytes(session?[0] ?? 0)} ↑ ${fmtBytes(session?[1] ?? 0)}  ·  '
                        'Since start ↓ ${fmtBytes(a.rx)} ↑ ${fmtBytes(a.tx)}',
              style: t.bodySmall?.copyWith(color: viz.ink, fontFeatures: tabular),
            ),
          ],
        ),
      ),
    );
  }
}
