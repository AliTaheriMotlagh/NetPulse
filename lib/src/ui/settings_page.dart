import 'package:flutter/material.dart';

import '../monitor.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage(this.m, {super.key});
  final NetMonitor m;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final _host = TextEditingController(text: widget.m.settings.probeHost);
  late final _limit = TextEditingController(text: _fmtLimit(widget.m.settings.limitGb));

  static String _fmtLimit(double gb) => gb == 0 ? '' : gb.toString().replaceFirst(RegExp(r'\.0$'), '');

  @override
  void dispose() {
    _host.dispose();
    _limit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.m.settings;
    final ink = Viz.of(context).ink;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => PageList(
        children: [
          SectionCard(
            title: 'Appearance',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label(context, 'Theme'),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_rounded),
                      label: Text('System'),
                    ),
                    ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded), label: Text('Light')),
                    ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded), label: Text('Dark')),
                  ],
                  selected: {s.theme},
                  onSelectionChanged: (v) => s.update((s) => s.theme = v.first),
                ),
                const SizedBox(height: 16),
                _label(context, 'Units'),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Bytes · MB/s')),
                    ButtonSegment(value: true, label: Text('Bits · Mbps')),
                  ],
                  selected: {s.bits},
                  onSelectionChanged: (v) => s.update((s) => s.bits = v.first),
                ),
              ],
            ),
          ),
          SectionCard(
            title: 'Sampling',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label(context, 'Update interval'),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 500, label: Text('0.5 s')),
                    ButtonSegment(value: 1000, label: Text('1 s')),
                    ButtonSegment(value: 2000, label: Text('2 s')),
                    ButtonSegment(value: 5000, label: Text('5 s')),
                  ],
                  selected: {s.intervalMs},
                  onSelectionChanged: (v) => s.update((s) => s.intervalMs = v.first),
                ),
                const SizedBox(height: 8),
                if (widget.m.appSource != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Per-app traffic'),
                    subtitle: const Text('Reads OS counters locally while NetPulse is visible; uses no data'),
                    value: s.trackApps,
                    onChanged: (v) => s.update((s) => s.trackApps = v),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Continuous latency monitor'),
                  subtitle: Text(
                    'Off by default so NetPulse sends nothing. When on: one TCP handshake '
                    'to the host every ${NetMonitor.probeEvery.inSeconds} s. You can also tap the Latency tile to test once.',
                  ),
                  value: s.probe,
                  onChanged: (v) => s.update((s) => s.probe = v),
                ),
                TextField(
                  controller: _host,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Probe host',
                    hintText: '1.1.1.1',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (v) => s.update((s) => s.probeHost = v.trim().isEmpty ? '1.1.1.1' : v.trim()),
                  onTapOutside: (_) {
                    FocusScope.of(context).unfocus();
                    if (_host.text.trim().isNotEmpty) s.update((s) => s.probeHost = _host.text.trim());
                  },
                ),
              ],
            ),
          ),
          SectionCard(
            title: 'Data limit',
            subtitle: 'Shows progress and warns at 80% of the session total',
            child: TextField(
              controller: _limit,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Limit in GB',
                hintText: 'Empty = no limit',
                suffixText: 'GB',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => s.update((s) => s.limitGb = double.tryParse(v.replaceAll(',', '.')) ?? 0),
            ),
          ),
          SectionCard(
            title: 'About',
            child: Text(
              'NetPulse reads byte and packet counters straight from the OS (${widget.m.source.description}) and '
              'makes no network requests of its own unless you test latency or look up your public IP.\n\n'
              'Totals count physical interfaces only (Wi-Fi, Ethernet, cellular). VPN and virtual adapters are listed '
              'but excluded, because their traffic also crosses a physical link and would otherwise be counted twice.\n\n'
              'Traffic while the app is closed is added on the next launch, unless the device restarted in between.\n\n'
              'Shortcut: ⌘K / Ctrl+K adds a checkpoint.',
              style: TextStyle(color: ink),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.labelLarge),
  );
}
