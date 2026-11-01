import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../monitor.dart';
import 'apps_page.dart';
import 'interfaces_page.dart';
import 'live_page.dart';
import 'sessions_page.dart';
import 'settings_page.dart';
import 'widgets.dart';

typedef _Dest = (String label, IconData icon, IconData selected);

const _dests = <_Dest>[
  ('Live', Icons.speed_outlined, Icons.speed_rounded),
  ('Apps', Icons.apps_outlined, Icons.apps_rounded),
  ('Interfaces', Icons.lan_outlined, Icons.lan_rounded),
  ('Sessions', Icons.flag_outlined, Icons.flag_rounded),
  ('Settings', Icons.tune_outlined, Icons.tune_rounded),
];

/// Bottom navigation on phones, a navigation rail on tablets and desktops.
class Shell extends StatefulWidget {
  const Shell(this.m, {super.key});
  final NetMonitor m;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    final page = switch (_index) {
      0 => LivePage(m),
      1 => AppsPage(m),
      2 => InterfacesPage(m),
      3 => SessionsPage(m),
      _ => SettingsPage(m),
    };
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 840;
        final body = SafeArea(
          top: false,
          bottom: false,
          child: KeyedSubtree(key: ValueKey(_index), child: page),
        );
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () => doCheckpoint(context, m),
            const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => doCheckpoint(context, m),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              appBar: AppBar(title: Text(_index == 0 ? 'NetPulse' : _dests[_index].$1)),
              body: wide
                  ? Row(
                      children: [
                        NavigationRail(
                          extended: box.maxWidth >= 1200,
                          labelType: box.maxWidth >= 1200 ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                          selectedIndex: _index,
                          onDestinationSelected: (i) => setState(() => _index = i),
                          destinations: [
                            for (final d in _dests)
                              NavigationRailDestination(icon: Icon(d.$2), selectedIcon: Icon(d.$3), label: Text(d.$1)),
                          ],
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(child: body),
                      ],
                    )
                  : body,
              bottomNavigationBar: wide
                  ? null
                  : NavigationBar(
                      selectedIndex: _index,
                      onDestinationSelected: (i) => setState(() => _index = i),
                      destinations: [
                        for (final d in _dests)
                          NavigationDestination(icon: Icon(d.$2), selectedIcon: Icon(d.$3), label: d.$1),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}
