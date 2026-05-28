import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/theme_manager.dart';
import 'theme/hermes_splash.dart';
import 'theme/page_transitions.dart';
import 'services/hermes_service.dart';
import 'services/hermes_api_client.dart';
import 'services/hermes_client.dart';
import 'services/wingman_settings.dart';
import 'services/chat_manager.dart';
import 'widgets/main_shell.dart';

// System tray — stub on mobile, real on desktop
import 'services/tray_service_stub.dart'
  if (dart.linux) 'services/tray_service.dart'
  if (dart.macos) 'services/tray_service.dart'
  if (dart.windows) 'services/tray_service.dart';

final bool _isDesktop = !Platform.isAndroid && !Platform.isIOS;

// ── App Entry Point ─────────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Provider.debugCheckInvalidValueType = null;

  TrayService? trayService;
  if (_isDesktop) {
    trayService = TrayService();
    trayService.onShow = () {};
    trayService.onQuit = () {};
    trayService.init().then((_) => debugPrint('System tray initialized'));
  }

  final backend = BackendService();

  if (!_isDesktop) {
    final settings = WingmanSettings();
    await Future.delayed(const Duration(milliseconds: 100));
    if (settings.backendHost != '127.0.0.1') {
      backend.setBaseUrl(settings.backendHost, settings.backendPort);
      debugPrint('[Main] Using remote backend: ${settings.backendHost}:${settings.backendPort}');
    }
  }

  final started = await backend.start(
    timeout: _isDesktop
        ? const Duration(seconds: 8)
        : const Duration(seconds: 1),
  );

  if (!started) {
    debugPrint('WARNING: Backend failed to start: ${backend.lastError}');
    debugPrint('Falling back to CLI-based HermesClient');

    if (!_isDesktop) {
      Future.delayed(const Duration(milliseconds: 100), () {
        backend.start(timeout: const Duration(seconds: 5)).then((ok) {
          if (ok) debugPrint('[Main] Background reconnect succeeded');
        });
      });
    }
  } else {
    debugPrint('Backend connected. State: ${backend.state}');
  }

  final HermesService hermesService = started ? backend : HermesClient();

  if (trayService != null) {
    trayService.onShow = () {};
    trayService.onQuit = () => backend.stop().then((_) => debugPrint('Backend stopped'));
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeManager()),
        ChangeNotifierProvider(create: (_) => WingmanSettings()),
        ChangeNotifierProvider(create: (_) => ChatManager()),
        ChangeNotifierProvider<BackendService>.value(value: backend),
        Provider<HermesService>.value(value: hermesService),
      ],
      child: HermesWingmanApp(trayService: trayService),
    ),
  );
}

/// Root app shell with splash → main flow.
class HermesWingmanApp extends StatefulWidget {
  final TrayService? trayService;
  const HermesWingmanApp({super.key, this.trayService});

  @override
  State<HermesWingmanApp> createState() => _HermesWingmanAppState();
}

class _HermesWingmanAppState extends State<HermesWingmanApp> {
  bool _showSplash = true;

  void _onSplashComplete() {
    setState(() => _showSplash = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorSchemeSeed: const Color(0xFF4A6B5D),
        ),
        home: HermesSplashScreen(onComplete: _onSplashComplete),
      );
    }

    final themeManager = context.watch<ThemeManager>();
    return MaterialApp(
      title: 'Hermes Wingman',
      debugShowCheckedModeBanner: false,
      theme: themeManager.themeData.copyWith(
        pageTransitionsTheme: hermeticTransitions,
      ),
      home: MainShell(trayService: widget.trayService),
    );
  }
}
