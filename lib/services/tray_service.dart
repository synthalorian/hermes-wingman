import 'dart:io';
import 'package:flutter/material.dart';
import 'package:system_tray/system_tray.dart';

/// Manages the system tray icon and menu for Hermes Wingman.
/// Minimizes to tray on close instead of quitting.
class TrayService {
  final SystemTray _tray = SystemTray();
  final AppWindow _appWindow = AppWindow();

  VoidCallback? onShow;
  VoidCallback? onQuit;
  VoidCallback? onSetupWizard;

  bool _initialized = false;

  /// Find the tray icon file from known locations.
  Future<String> _findIcon() async {
    // 1. Development: relative to project root
    if (await _exists('assets/icons/hermes-wingman.png')) {
      return 'assets/icons/hermes-wingman.png';
    }

    // 2. Same directory as the running binary (installed mode)
    final exeDir = Platform.resolvedExecutable
        .substring(0, Platform.resolvedExecutable.lastIndexOf('/'));
    final beside = '$exeDir/hermes-wingman.png';
    if (await _exists(beside)) return beside;

    // 3. XDG icon paths
    final home = Platform.environment['HOME'] ?? '/tmp';
    final xdgPaths = [
      '$home/.local/share/icons/candy-icons/256x256/apps/hermes-wingman.png',
      '$home/.local/share/icons/hicolor/256x256/apps/hermes-wingman.png',
      '$home/.local/share/icons/hicolor/scalable/apps/hermes-wingman.svg',
      '$home/.local/share/icons/hermes-wingman.png',
    ];
    for (final path in xdgPaths) {
      if (await _exists(path)) return path;
    }

    // 4. Absolute fallback
    return '$home/.local/share/icons/hermes-wingman.png';
  }

  Future<bool> _exists(String path) async {
    return File(path).exists();
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Find the icon — try multiple locations
    final iconPath = await _findIcon();
    debugPrint('[TrayService] Using icon: $iconPath');

    await _tray.initSystemTray(
      iconPath: iconPath,
      toolTip: 'Hermes Wingman',
    );

    // Register for tray events (left click, double click)
    _tray.registerSystemTrayEventHandler((eventName) {
      if (eventName == 'leftClick' || eventName == 'doubleClick') {
        onShow?.call();
        _appWindow.show();
      }
    });

    _buildMenu();
  }

  void _buildMenu() {
    final menu = Menu();
    menu.buildFrom([
      MenuItemLabel(
        label: 'Show Hermes Wingman',
        onClicked: (_) {
          onShow?.call();
          _appWindow.show();
        },
      ),
      MenuItemLabel(
        label: 'Setup Wizard',
        onClicked: (_) {
          onShow?.call();
          _appWindow.show();
          onSetupWizard?.call();
        },
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Quit',
        onClicked: (_) {
          _tray.destroy();
          onQuit?.call();
        },
      ),
    ]);

    _tray.setContextMenu(menu);
  }

  void setTooltip(String tip) {
    _tray.setToolTip(tip);
  }

  /// Call this when the app window closes to minimize to tray.
  Future<void> hideWindow() async {
    await _appWindow.hide();
  }

  /// Show the app window.
  Future<void> showWindow() async {
    await _appWindow.show();
  }

  Future<void> destroy() async {
    await _tray.destroy();
  }
}
