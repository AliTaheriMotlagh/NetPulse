import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../format.dart';
import '../monitor.dart';
import 'chart.dart';
import 'theme.dart';
import 'widgets.dart';

class LivePage extends StatefulWidget {
  const LivePage(this.m, {super.key});
  final NetMonitor m;

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  Duration _window = const Duration(minutes: 1);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.m,
    builder: (context, _) {
      final m = widget.m;
      final bits = m.settings.bits;
      final cur = m.current;
      final viz = Viz.of(context);
      return PageList(
        children: [
          if (m.error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(leading: const Icon(Icons.error_outline_rounded), title: Text(m.error!)),
            ),
          TileGrid(
            minWidth: 220,
            children: [
              StatTile(
                icon: Icons.arrow_downward_rounded,
                iconColor: viz.down,
                label: 'Download',
                value: fmtRate(cur.down, bits: bits),
                sub: '${m.pktDown.round()} pkt/s · Peak ${fmtRate(m.session.peakDown, bits: bits)}',
              ),
              StatTile(
                icon: Icons.arrow_upward_rounded,
                iconColor: viz.up,
                label: 'Upload',
                value: fmtRate(cur.up, bits: bits),
                sub: '${m.pktUp.round()} pkt/s · Peak ${fmtRate(m.session.peakUp, bits: bits)}',
              ),
              _latencyTile(context, m),
              _connectionTile(m),
            ],
          ),
          SectionCard(
            title: 'Throughput',
            trailing: SegmentedButton<Duration>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: Duration(minutes: 1), label: Text('1m')),
                ButtonSegment(value: Duration(minutes: 5), label: Text('5m')),
                ButtonSegment(value: Duration(minutes: 10), label: Text('10m')),
              ],
              selected: {_window},
              onSelectionChanged: (s) => setState(() => _window = s.first),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(spacing: 16, children: [LegendDot(viz.down, 'Download'), LegendDot(viz.up, 'Upload')]),
                const SizedBox(height: 8),
                RepaintBoundary(
                  child: TrafficChart(samples: m.history, window: _window, bits: bits),
                ),
              ],
            ),
          ),
          SessionCard(m),
        ],
      );
    },
  );

  Widget _latencyTile(BuildContext context, NetMonitor m) {
    final h = m.health;
    final ms = m.latencyMs;
    final jitter = m.jitter;
    final measured = m.latency.isNotEmpty;
    return StatTile(
      icon: h.icon,
      iconColor: h.color(context),
      label: 'Latency · ${h.label}',
      value: m.testingLatency && !measured
          ? 'Testing…'
          : (!measured ? 'Tap to test' : (ms == null ? '—' : '${ms.round()} ms')),
      sub: measured
          ? 'Jitter ${jitter == null ? '—' : '${jitter.round()} ms'} · Loss ${(m.loss * 100).round()}%'
          : 'Uses no data until you tap',
      onTap: m.settings.probe ? null : m.testLatency,
    );
  }

  Widget _connectionTile(NetMonitor m) {
    final active = m.links.where((l) => l != ConnectivityResult.none).toList();
    final ip = m.addresses
        .expand((i) => i.addresses)
        .where((a) => a.type == InternetAddressType.IPv4)
        .map((a) => a.address)
        .firstOrNull;
    return StatTile(
      icon: switch (active.firstOrNull) {
        ConnectivityResult.wifi => Icons.wifi_rounded,
        ConnectivityResult.mobile => Icons.signal_cellular_alt_rounded,
        ConnectivityResult.ethernet => Icons.settings_ethernet_rounded,
        ConnectivityResult.vpn => Icons.vpn_lock_outlined,
        null => Icons.signal_wifi_off_rounded,
        _ => Icons.lan_outlined,
      },
      label: 'Connection',
      value: active.isEmpty ? 'Offline' : active.map(_linkName).join(' + '),
      sub: ip ?? 'No IPv4 address',
    );
  }

  static String _linkName(ConnectivityResult r) => switch (r) {
    ConnectivityResult.wifi => 'Wi-Fi',
    ConnectivityResult.mobile => 'Cellular',
    ConnectivityResult.ethernet => 'Ethernet',
    ConnectivityResult.vpn => 'VPN',
    ConnectivityResult.bluetooth => 'Bluetooth',
    _ => 'Other',
  };
}

class SessionCard extends StatelessWidget {
  const SessionCard(this.m, {super.key});
  final NetMonitor m;

  @override
  Widget build(BuildContext context) {
    final s = m.session;
    final bits = m.settings.bits;
    final total = s.rx + s.tx;
    final avg = s.avgRate;
    final limit = m.limitBytes;
    final t = Theme.of(context).textTheme;
    final warming = s.elapsed() < const Duration(minutes: 1);
    return SectionCard(
      title: 'Session',
      subtitle: 'Since ${fmtDate(s.start)}',
      trailing: Text(fmtDuration(s.elapsed()), style: t.titleLarge?.copyWith(fontFeatures: tabular)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TileGrid(
            minWidth: 130,
            children: [
              Metric('Downloaded', fmtBytes(s.rx)),
              Metric('Uploaded', fmtBytes(s.tx)),
              Metric('Total', fmtBytes(total)),
              Metric('Average', fmtRate(avg, bits: bits)),
              Metric('Packets ↓', '${s.rxPk}'),
              Metric('Packets ↑', '${s.txPk}'),
            ],
          ),
          if (limit != null) ...[const SizedBox(height: 16), _LimitBar(used: total, limit: limit)],
          const Divider(height: 32),
          Text(
            warming ? 'Projection (needs ~1 min of data)' : 'Projected at this pace',
            style: t.labelLarge?.copyWith(color: Viz.of(context).ink),
          ),
          const SizedBox(height: 8),
          TileGrid(
            minWidth: 130,
            children: [
              Metric('Per hour', fmtBytes(avg * 3600)),
              Metric('Per day', fmtBytes(avg * 86400)),
              Metric('Per 30 days', fmtBytes(avg * 86400 * 30)),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => doCheckpoint(context, m),
                icon: const Icon(Icons.flag_rounded),
                label: Text('Checkpoint${s.laps.isEmpty ? '' : ' (${s.laps.length})'}'),
              ),
              OutlinedButton.icon(
                onPressed: () => confirmReset(context, m),
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Reset'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LimitBar extends StatelessWidget {
  const _LimitBar({required this.used, required this.limit});
  final int used, limit;

  @override
  Widget build(BuildContext context) {
    final f = used / limit;
    final h = f >= 1 ? Health.offline : (f >= .8 ? Health.fair : Health.good);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(h.icon, size: 16, color: h.color(context)),
            const SizedBox(width: 6),
            Text(
              '${fmtBytes(used)} of ${fmtBytes(limit)} limit · ${(f * 100).toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: f.clamp(0, 1), minHeight: 8, color: h.color(context)),
        ),
      ],
    );
  }
}
