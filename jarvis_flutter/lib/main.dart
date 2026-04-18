import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'screens/app_shell.dart';
import 'services/app_settings_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      minimumSize: Size(360, 640),
      center: true,
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.normal,
    );
    unawaited(
      windowManager.waitUntilReadyToShow(
        windowOptions,
        () async {
          await windowManager.show();
          await windowManager.focus();
        },
      ),
    );
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsService();
    settings.load();

    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: '${settings.assistantName} Codex',
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF02060C),
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF42D9FF),
              secondary: Color(0xFF0E2238),
              surface: Color(0xFF07111B),
            ),
          ),
          home: const AppShell(),
        );
      },
    );
  }
}
