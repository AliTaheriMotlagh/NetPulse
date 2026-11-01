import 'package:flutter/material.dart';

import 'src/monitor.dart';
import 'src/ui/shell.dart';
import 'src/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(NetPulseApp(await NetMonitor.create()));
}

class NetPulseApp extends StatelessWidget {
  const NetPulseApp(this.monitor, {super.key});
  final NetMonitor monitor;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: monitor.settings,
    builder: (context, _) => MaterialApp(
      title: 'NetPulse',
      debugShowCheckedModeBanner: false,
      themeMode: monitor.settings.theme,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: Shell(monitor),
    ),
  );
}
