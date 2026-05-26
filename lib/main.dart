import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/theme_manager.dart';
import 'theme/hermes_splash.dart';
import 'theme/animated_background.dart';
import 'theme/page_transitions.dart';
import 'services/hermes_service.dart';
import 'services/hermes_api_client.dart';
import 'services/hermes_client.dart';
import 'services/wingman_settings.dart';
import 'services/chat_manager.dart';
import 'theme/app_theme.dart';
import 'widgets/wingman_icon.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/sessions/sessions_screen.dart';
import 'screens/config/config_screen.dart';
import 'screens/logs/logs_screen.dart';
import 'screens/cron/cron_screen.dart';
import 'screens/gateway/gateway_screen.dart';
import 'screens/gateway/gateway_setup_screen.dart';
import 'screens/chat/chat_screen.dart';
import 'screens/models/models_screen.dart';
import 'screens/setup/setup_wizard_screen.dart';
import 'screens/tools/tools_screen.dart';
import 'screens/tools/cli_tools_screen.dart';
import 'screens/skills/skills_screen.dart';
import 'screens/memory/memory_screen.dart';
import 'screens/files/files_screen.dart';
import 'screens/missions/missions_screen.dart';
import 'screens/profiles/profiles_screen.dart';
import 'screens/providers/providers_screen.dart';

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

/// Root shell with a persistent sidebar (desktop) or bottom nav (mobile).
class MainShell extends StatefulWidget {
  final TrayService? trayService;

  const MainShell({super.key, this.trayService});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _selectedIndex = 0;

  static const _navItems = <_NavItem>[
    _NavItem('Dashboard', Icons.dashboard, 'HUD'),
    _NavItem('Chat', Icons.chat, 'CHAT'),
    _NavItem('Models', Icons.memory_outlined, 'AI'),
    _NavItem('Tools', Icons.build_outlined, '⚙'),
    _NavItem('CLI Tools', Icons.terminal_outlined, 'CLI'),
    _NavItem('Sessions', Icons.chat_bubble_outline, 'LOG'),
    _NavItem('Skills', Icons.auto_awesome, 'SKL'),
    _NavItem('Memory', Icons.storage, 'MEM'),
    _NavItem('Files', Icons.folder_open, 'FIL'),
    _NavItem('Missions', Icons.rocket_outlined, 'MIS'),
    _NavItem('Profiles', Icons.person_outline, 'PRO'),
    _NavItem('Providers', Icons.vpn_key_outlined, 'KEY'),
    _NavItem('Config', Icons.settings_outlined, 'CFG'),
    _NavItem('Logs', Icons.terminal, 'SYS'),
    _NavItem('Cron', Icons.schedule_outlined, '⏰'),
    _NavItem('Gateway', Icons.hub_outlined, 'GW'),
    _NavItem('Gateway Setup', Icons.tune_outlined, 'GWS'),
    _NavItem('Setup', Icons.rocket_outlined, '✨'),
  ];

  static const _mobileNavItems = <_NavItem>[
    _NavItem('Dashboard', Icons.dashboard, ''),
    _NavItem('Chat', Icons.chat, ''),
    _NavItem('Models', Icons.memory_outlined, ''),
    _NavItem('Sessions', Icons.chat_bubble_outline, ''),
    _NavItem('Skills', Icons.auto_awesome, ''),
    _NavItem('Files', Icons.folder_open, ''),
    _NavItem('Settings', Icons.settings_outlined, ''),
  ];

  static const _mobileIndexMap = [0, 1, 2, 4, 5, 7, 10];

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _screens = [
      DashboardScreen(onNavigate: (i) => setState(() => _selectedIndex = i)),
      const ChatScreen(),
      const ModelsScreen(),
      const ToolsScreen(),
      const CliToolsScreen(),
      SessionsScreen(onNavigate: (i) => setState(() => _selectedIndex = i)),
      const SkillsScreen(),
      const MemoryScreen(),
      const FilesScreen(),
      const MissionsScreen(),
      const ProfilesScreen(),
      const ProvidersScreen(),
      const ConfigScreen(),
      const LogsScreen(),
      const CronScreen(),
      const GatewayScreen(),
      const GatewaySetupScreen(),
      SetupWizardScreen(onNavigate: (i) => setState(() => _selectedIndex = i)),
    ];

    if (widget.trayService != null) {
      widget.trayService!.onShow = () => widget.trayService!.showWindow();
      widget.trayService!.onSetupWizard = () {
        if (mounted) setState(() => _selectedIndex = 9);
      };
    }

    _checkFirstRun();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkFirstRun() async {
    try {
      final backend = context.read<BackendService>();
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      final status = await backend.httpGet('/setup/detect');
      final installed = status['hermes_installed'] == true;
      final hasConfig = status['config_exists'] == true;
      if (!installed || !hasConfig) {
        if (mounted) setState(() => _selectedIndex = 9);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.watch<ThemeManager>().currentScheme;
    final backendState = context.watch<BackendService>().state;

    final body = _isDesktop
        ? _buildDesktopLayout(scheme, backendState)
        : _buildMobileLayout(scheme, backendState);

    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedBackground(
            primaryColor: scheme.primary,
            accentColor: scheme.accent,
            baseColor: scheme.background,
          ),
        ),
        body,
      ],
    );
  }

  Widget _buildDesktopLayout(AppColorScheme scheme, BackendConnectionState state) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && widget.trayService != null) {
          widget.trayService!.hideWindow();
        }
      },
      child: Container(
        color: scheme.scaffoldBackground.withAlpha(200),
        width: double.infinity,
        height: double.infinity,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Material(
                  type: MaterialType.transparency,
                  child: Container(
                    width: 68,
                    decoration: BoxDecoration(
                      color: scheme.appBarBackground.withAlpha(180),
                      border: Border(
                        right: BorderSide(color: scheme.borderDim.withAlpha(50), width: 0.5),
                      ),
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        _AnimatedSidebarIcon(scheme: scheme),
                        const SizedBox(height: 12),
                        _BackendStatusDot(scheme: scheme, state: state),
                        const SizedBox(height: 12),
                        Expanded(
                          child: Column(
                            children: List.generate(_navItems.length, (i) {
                              final item = _navItems[i];
                              final selected = i == _selectedIndex;
                              return _SidebarButton(
                                icon: item.icon,
                                label: item.label,
                                badge: item.badge,
                                selected: selected,
                                color: selected ? scheme.primary : scheme.textMuted,
                                bgColor: selected ? scheme.primary.withAlpha(18) : Colors.transparent,
                                onTap: () => setState(() => _selectedIndex = i),
                              );
                            }),
                          ),
                        ),
                        _ThemeSwitcherButton(),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.04, 0),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: anim,
                      curve: Curves.easeOutCubic,
                    )),
                    child: FadeTransition(opacity: anim, child: child),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey(_selectedIndex),
                  child: _screens[_selectedIndex],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout(AppColorScheme scheme, BackendConnectionState state) {
    final currentMobileIdx = _mobileIndexMap.indexOf(_selectedIndex);
    final effectiveIdx = currentMobileIdx >= 0 ? currentMobileIdx : 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: scheme.appBarBackground.withAlpha(200),
        elevation: 0,
        title: Row(
          children: [
            _AnimatedWingmanMark(scheme: scheme, size: 22),
            const SizedBox(width: 8),
            Text('Hermes Wingman', style: TextStyle(color: scheme.text, fontSize: 14)),
            const Spacer(),
            _BackendStatusDot(scheme: scheme, state: state, dotSize: 6),
          ],
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (child, anim) {
          return FadeTransition(opacity: anim, child: child);
        },
        child: KeyedSubtree(
          key: ValueKey(effectiveIdx),
          child: IndexedStack(
            index: effectiveIdx,
            children: _mobileIndexMap.map((i) => _screens[i]).toList(),
          ),
        ),
      ),
      bottomNavigationBar: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Material(
            type: MaterialType.transparency,
            child: BottomNavigationBar(
            backgroundColor: scheme.bottomNavBackground.withAlpha(200),
            selectedItemColor: scheme.primary,
            unselectedItemColor: scheme.textMuted,
            type: BottomNavigationBarType.fixed,
            currentIndex: effectiveIdx,
            onTap: (i) => setState(() => _selectedIndex = _mobileIndexMap[i]),
            items: _mobileNavItems.map((item) {
              return BottomNavigationBarItem(
                icon: Icon(item.icon, size: 20),
                activeIcon: Icon(item.icon, size: 22),
                label: item.label,
              );
}).toList(),
          ),
        ),
      ),
    ),
  );
}
}

// ── Animated Sidebar Icon ──────────────────────────────────────────────────

class _AnimatedSidebarIcon extends StatefulWidget {
  final AppColorScheme scheme;
  const _AnimatedSidebarIcon({required this.scheme});

  @override
  State<_AnimatedSidebarIcon> createState() => _AnimatedSidebarIconState();
}

class _AnimatedSidebarIconState extends State<_AnimatedSidebarIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulse.value,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: widget.scheme.primary.withAlpha(20),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: Material(
                  type: MaterialType.transparency,
                  child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/icons/hermes-wingman.png',
                width: 40,
                height: 40,
                fit: BoxFit.cover,
              ),
            ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AnimatedWingmanMark extends StatelessWidget {
  final AppColorScheme scheme;
  final double size;
  const _AnimatedWingmanMark({required this.scheme, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withAlpha(15),
            blurRadius: 4,
          ),
        ],
      ),
      child: WingmanIcon(size: size, showBackground: false),
    );
  }
}

// ── Reusable Components ─────────────────────────────────────────────────────

class _NavItem {
  final String label;
  final IconData icon;
  final String badge;
  const _NavItem(this.label, this.icon, this.badge);
}

class _BackendStatusDot extends StatelessWidget {
  final AppColorScheme scheme;
  final BackendConnectionState state;
  final double dotSize;

  const _BackendStatusDot({
    required this.scheme,
    required this.state,
    this.dotSize = 8,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    String tooltip;
    switch (state) {
      case BackendConnectionState.connected:
        color = scheme.success;
        tooltip = 'Backend connected';
      case BackendConnectionState.initializing:
        color = scheme.warning;
        tooltip = 'Backend initializing...';
      case BackendConnectionState.failed:
      case BackendConnectionState.notFound:
        color = scheme.error;
        tooltip = 'Backend offline: ${context.read<BackendService>().lastError ?? "unknown"}';
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        width: dotSize,
        height: dotSize,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color.withAlpha(153), blurRadius: 6, spreadRadius: 1),
          ],
        ),
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String badge;
  final bool selected;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  const _SidebarButton({
    required this.icon,
    required this.label,
    required this.badge,
    required this.selected,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
        child: Material(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Container(
              width: 52, height: 48,
              padding: const EdgeInsets.only(left: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: selected ? Border(left: BorderSide(color: color, width: 2)) : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(height: 2),
                  Text(
                    badge,
                    style: TextStyle(
                      fontSize: 8, color: color,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeSwitcherButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final themeManager = context.watch<ThemeManager>();
    final scheme = themeManager.currentScheme;

    return PopupMenuButton<String>(
      tooltip: 'Switch Theme',
      offset: const Offset(0, -40),
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.borderDim.withAlpha(60), width: 0.5),
      ),
      color: scheme.surface.withAlpha(230),
      onSelected: (name) => themeManager.setTheme(name),
      itemBuilder: (context) => themeManager.availableThemes.map((name) {
        final current = name == themeManager.currentThemeName;
        return PopupMenuItem<String>(
          value: name,
          child: Row(
            children: [
              Icon(current ? Icons.brightness_1 : Icons.circle_outlined, size: 10,
                color: current ? scheme.primary : scheme.textMuted),
              const SizedBox(width: 10),
              Text(name, style: TextStyle(
                color: current ? scheme.primary : scheme.text,
                fontWeight: current ? FontWeight.w600 : FontWeight.w400)),
              if (current) ...[const Spacer(), Icon(Icons.check, size: 14, color: scheme.primary)],
            ],
          ),
        );
      }).toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Container(
          width: 52, height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.borderDim.withAlpha(40), width: 0.5),
          ),
          child: Icon(Icons.palette_outlined, size: 18, color: scheme.textMuted),
        ),
      ),
    );
  }
}