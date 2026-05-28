import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hermes_wingman/theme/theme_manager.dart';
import 'package:hermes_wingman/theme/app_theme.dart';
import 'package:hermes_wingman/theme/animated_background.dart';
import 'package:hermes_wingman/services/hermes_service.dart';
import 'package:hermes_wingman/services/wingman_settings.dart';
import 'package:hermes_wingman/services/chat_manager.dart';

import 'nav_item.dart';
import 'animated_sidebar_icon.dart';
import 'animated_wingman_mark.dart';
import 'backend_status_dot.dart';
import 'sidebar_button.dart';
import 'theme_switcher_button.dart';

import 'package:hermes_wingman/screens/dashboard/dashboard_screen.dart';
import 'package:hermes_wingman/screens/sessions/sessions_screen.dart';
import 'package:hermes_wingman/screens/config/config_screen.dart';
import 'package:hermes_wingman/screens/logs/logs_screen.dart';
import 'package:hermes_wingman/screens/cron/cron_screen.dart';
import 'package:hermes_wingman/screens/gateway/gateway_screen.dart';
import 'package:hermes_wingman/screens/gateway/gateway_setup_screen.dart';
import 'package:hermes_wingman/screens/chat/chat_screen.dart';
import 'package:hermes_wingman/screens/models/models_screen.dart';
import 'package:hermes_wingman/screens/setup/setup_wizard_screen.dart';
import 'package:hermes_wingman/screens/tools/tools_screen.dart';
import 'package:hermes_wingman/screens/tools/cli_tools_screen.dart';
import 'package:hermes_wingman/screens/skills/skills_screen.dart';
import 'package:hermes_wingman/screens/memory/memory_screen.dart';
import 'package:hermes_wingman/screens/files/files_screen.dart';
import 'package:hermes_wingman/screens/missions/missions_screen.dart';
import 'package:hermes_wingman/screens/profiles/profiles_screen.dart';
import 'package:hermes_wingman/screens/providers/providers_screen.dart';

// System tray — stub on mobile, real on desktop
import 'package:hermes_wingman/services/tray_service_stub.dart'
  if (dart.linux) 'package:hermes_wingman/services/tray_service.dart'
  if (dart.macos) 'package:hermes_wingman/services/tray_service.dart'
  if (dart.windows) 'package:hermes_wingman/services/tray_service.dart';

final bool _isDesktop = !Platform.isAndroid && !Platform.isIOS;

/// Root shell with a persistent sidebar (desktop) or bottom nav (mobile).
class MainShell extends StatefulWidget {
  final TrayService? trayService;

  const MainShell({super.key, this.trayService});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _selectedIndex = 0;

  static const _navItems = <NavItem>[
    NavItem('Dashboard', Icons.dashboard, 'HUD'),
    NavItem('Chat', Icons.chat, 'CHAT'),
    NavItem('Models', Icons.memory_outlined, 'AI'),
    NavItem('Tools', Icons.build_outlined, '⚙'),
    NavItem('CLI Tools', Icons.terminal_outlined, 'CLI'),
    NavItem('Sessions', Icons.chat_bubble_outline, 'LOG'),
    NavItem('Skills', Icons.auto_awesome, 'SKL'),
    NavItem('Memory', Icons.storage, 'MEM'),
    NavItem('Files', Icons.folder_open, 'FIL'),
    NavItem('Missions', Icons.rocket_outlined, 'MIS'),
    NavItem('Profiles', Icons.person_outline, 'PRO'),
    NavItem('Providers', Icons.vpn_key_outlined, 'KEY'),
    NavItem('Config', Icons.settings_outlined, 'CFG'),
    NavItem('Logs', Icons.terminal, 'SYS'),
    NavItem('Cron', Icons.schedule_outlined, '⏰'),
    NavItem('Gateway', Icons.hub_outlined, 'GW'),
    NavItem('Gateway Setup', Icons.tune_outlined, 'GWS'),
    NavItem('Setup', Icons.rocket_outlined, '✨'),
  ];

  static const _mobileNavItems = <NavItem>[
    NavItem('Dashboard', Icons.dashboard, ''),
    NavItem('Chat', Icons.chat, ''),
    NavItem('Models', Icons.memory_outlined, ''),
    NavItem('Sessions', Icons.chat_bubble_outline, ''),
    NavItem('Skills', Icons.auto_awesome, ''),
    NavItem('Files', Icons.folder_open, ''),
    NavItem('Settings', Icons.settings_outlined, ''),
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
                        AnimatedSidebarIcon(scheme: scheme),
                        const SizedBox(height: 12),
                        BackendStatusDot(scheme: scheme, state: state),
                        const SizedBox(height: 12),
                        Expanded(
                          child: Column(
                            children: List.generate(_navItems.length, (i) {
                              final item = _navItems[i];
                              final selected = i == _selectedIndex;
                              return SidebarButton(
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
                        const ThemeSwitcherButton(),
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
            AnimatedWingmanMark(scheme: scheme, size: 22),
            const SizedBox(width: 8),
            Text('Hermes Wingman', style: TextStyle(color: scheme.text, fontSize: 14)),
            const Spacer(),
            BackendStatusDot(scheme: scheme, state: state, dotSize: 6),
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
