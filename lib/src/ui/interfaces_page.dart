import 'dart:io';

import 'package:flutter/material.dart';

import '../format.dart';
import '../monitor.dart';
import 'theme.dart';
import 'widgets.dart';

class InterfacesPage extends StatefulWidget {
  const InterfacesPage(this.m, {super.key});
  final NetMonitor m;

  @override
  State<InterfacesPage> createState() => _InterfacesPageState();
}

class _InterfacesPageState extends State<InterfacesPage> {
  bool _all = false;

  @override
  void initState() {
    super.initState();
    widget.m.refreshAddresses();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.m,
    builder: (context, _) {
      final m = widget.m;
      final list =
          m.ifaces.values.where((i) => _all || (i.counter.kind.counted && i.counter.rx + i.counter.tx > 0)).toList()
            ..sort((a, b) => (b.counter.rx + b.counter.tx).compareTo(a.counter.rx + a.counter.tx));
      return PageList(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${list.length} of ${m.ifaces.length} interfaces',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              FilterChip(
                label: const Text('Virtual & idle'),
                selected: _all,
                onSelected: (v) => setState(() => _all = v),
              ),
            ],
          ),
          for (final i in list) _IfaceCard(i, m.session.ifaces[i.counter.id], m.settings.bits),
          SectionCard(
            title: 'IP addresses',
            trailing: IconButton(
              tooltip: 'Refresh',
              onPressed: m.refreshAddresses,
              icon: const Icon(Icons.refresh_rounded),
            ),
            child: Column(
              children: [
                if (m.addresses.isEmpty) const ListTile(title: Text('No addresses')),
                for (final ni in m.addresses)
                  for (final a in ni.addresses)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(a.address, style: const TextStyle(fontFeatures: tabular)),
                      subtitle: Text('${ni.name} · ${a.type == InternetAddressType.IPv4 ? 'IPv4' : 'IPv6'}'),
                      trailing: IconButton(
                        tooltip: 'Copy',
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        onPressed: () => copyText(context, a.address, 'Address'),
                      ),
                    ),
              ],
            ),
          ),
          SectionCard(
            title: 'Public IP',
            subtitle: 'Looked up via api.ipify.org only when you tap',
            trailing: FilledButton.tonal(onPressed: m.fetchPublicIp, child: const Text('Look up')),
            child: SelectableText(m.publicIp ?? '—', style: Theme.of(context).textTheme.titleMedium),
          ),
        ],
      );
    },
  );
}

class _IfaceCard extends StatelessWidget {
  const _IfaceCard(this.i, this.session, this.bits);
  final IfaceState i;
  final List<int>? session;
  final bool bits;

  @override
  Widget build(BuildContext context) {
    final c = i.counter;
    final t = Theme.of(context).textTheme;
    final ink = Viz.of(context).ink;
    final up = c.up;
    final state = up == null ? null : (up ? Health.good : Health.offline);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(c.kind.icon, color: ink),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.id, style: t.titleMedium),
                      Text(
                        '${c.kind.label}${c.kind.counted ? '' : ' · not in totals'}',
                        style: t.bodySmall?.copyWith(color: ink),
                      ),
                    ],
                  ),
                ),
                if (state != null) ...[
                  Icon(state.icon, size: 16, color: state.color(context)),
                  const SizedBox(width: 4),
                  Text(up! ? 'Up' : 'Down', style: t.labelLarge),
                ],
              ],
            ),
            const SizedBox(height: 12),
            TileGrid(
              minWidth: 120,
              children: [
                Metric('↓ Now', fmtRate(i.down, bits: bits)),
                Metric('↑ Now', fmtRate(i.up, bits: bits)),
                Metric('↓ Session', fmtBytes(session?[0] ?? 0)),
                Metric('↑ Session', fmtBytes(session?[1] ?? 0)),
                Metric('↓ OS counter', fmtBytes(c.rx)),
                Metric('↑ OS counter', fmtBytes(c.tx)),
                Metric('Packets ↓', '${c.rxPackets}'),
                Metric('Packets ↑', '${c.txPackets}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
