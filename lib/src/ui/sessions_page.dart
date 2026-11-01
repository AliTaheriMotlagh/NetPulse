import 'package:flutter/material.dart';

import '../format.dart';
import '../monitor.dart';
import 'theme.dart';
import 'widgets.dart';

class SessionsPage extends StatelessWidget {
  const SessionsPage(this.m, {super.key});
  final NetMonitor m;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: m,
    builder: (context, _) {
      final s = m.session;
      final bits = m.settings.bits;
      final ink = Viz.of(context).ink;
      return PageList(
        children: [
          SectionCard(
            title: 'Current session',
            subtitle: 'Started ${fmtDate(s.start)} · ${fmtDuration(s.elapsed())} · ${fmtBytes(s.rx + s.tx)}',
            trailing: IconButton(
              tooltip: 'Copy as CSV',
              icon: const Icon(Icons.table_view_rounded),
              onPressed: () => copyText(context, m.exportCsv(), 'CSV'),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => doCheckpoint(context, m),
                      icon: const Icon(Icons.flag_rounded),
                      label: const Text('Checkpoint'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => confirmReset(context, m),
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('Reset'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (s.laps.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Add checkpoints to measure usage between moments — before and after a download, '
                      'a video call or a game. Each one shows the time and data since the previous one.',
                      style: TextStyle(color: ink),
                    ),
                  ),
                for (var i = s.laps.length - 1; i >= 0; i--) _lapTile(context, s, i, bits),
              ],
            ),
          ),
          SectionCard(
            title: 'History',
            subtitle: '${m.past.length} past sessions',
            trailing: m.past.isEmpty ? null : TextButton(onPressed: m.clearPast, child: const Text('Clear all')),
            child: Column(
              children: [
                if (m.past.isEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Reset a session to archive it here.', style: TextStyle(color: ink)),
                  ),
                for (final p in m.past)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${fmtBytes(p.rx + p.tx)} in ${fmtDuration(p.elapsed())}',
                      style: const TextStyle(fontFeatures: tabular),
                    ),
                    subtitle: Text(
                      '${fmtDate(p.start)} → ${fmtClock(p.end!)}\n'
                      '↓ ${fmtBytes(p.rx)} · ↑ ${fmtBytes(p.tx)} · avg ${fmtRate(p.avgRate, bits: bits)} · ${p.laps.length} checkpoints',
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => m.deletePast(p),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget _lapTile(BuildContext context, Session s, int i, bool bits) {
    final lap = s.laps[i];
    final prevAt = i == 0 ? s.start : s.laps[i - 1].at;
    final prevRx = i == 0 ? 0 : s.laps[i - 1].rx;
    final prevTx = i == 0 ? 0 : s.laps[i - 1].tx;
    final dur = lap.at.difference(prevAt);
    final dRx = lap.rx - prevRx, dTx = lap.tx - prevTx;
    final avg = (dRx + dTx) / (dur.inMilliseconds / 1000).clamp(1, double.infinity);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Text('${i + 1}')),
      title: Text(lap.label),
      subtitle: Text(
        '${fmtClock(lap.at)} · +${fmtDuration(dur)}\n↓ ${fmtBytes(dRx)} · ↑ ${fmtBytes(dTx)} · ${fmtRate(avg, bits: bits)} avg',
        style: const TextStyle(fontFeatures: tabular),
      ),
      isThreeLine: true,
      trailing: Text(
        fmtBytes(lap.rx + lap.tx),
        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontFeatures: tabular),
      ),
      onTap: () => _rename(context, lap),
    );
  }

  Future<void> _rename(BuildContext context, Checkpoint lap) async {
    final ctrl = TextEditingController(text: lap.label);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename checkpoint'),
        content: TextField(controller: ctrl, autofocus: true, onSubmitted: (v) => Navigator.pop(context, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Save')),
        ],
      ),
    );
    if (name != null) m.renameCheckpoint(lap, name);
  }
}
