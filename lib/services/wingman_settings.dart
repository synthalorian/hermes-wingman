import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/theme_manager.dart';

/// Detects if running on mobile (Android/iOS).
bool get _isMobile => Platform.isAndroid || Platform.isIOS;

/// Persistent settings for Wingman UI.
/// Desktop: stored in ~/.hermes/wingman_settings.json
/// Mobile: stored in app documents directory
class WingmanSettings extends ChangeNotifier {
  String _dashboardTitle = 'Hermes Wingman';
  String _appTitle = 'Hermes Wingman';
  String _backendHost = '127.0.0.1';
  int _backendPort = 9120;

  static String? _cachedPath;

  static Future<String> get _settingsPath async {
    if (_cachedPath != null) return _cachedPath!;
    if (_isMobile) {
      final dir = await getApplicationDocumentsDirectory();
      _cachedPath = '${dir.path}/wingman_settings.json';
    } else {
      final home = Platform.environment['HOME']
          ?? Platform.environment['USERPROFILE']
          ?? '/tmp';
      _cachedPath = '$home/.hermes/wingman_settings.json';
    }
    return _cachedPath!;
  }

  String get dashboardTitle => _dashboardTitle;
  String get appTitle => _appTitle;
  String get backendHost => _backendHost;
  int get backendPort => _backendPort;

  /// The title used in the window/desktop — always the app title
  String get windowTitle => _appTitle;

  WingmanSettings() {
    _load();
  }

  Future<void> _load() async {
    try {
      final path = await _settingsPath;
      final file = File(path);
      if (file.existsSync()) {
        final data = jsonDecode(file.readAsStringSync());
        if (data is Map) {
          _dashboardTitle = data['dashboard_title'] as String? ?? 'Hermes Wingman';
          _appTitle = data['app_title'] as String? ?? 'Hermes Wingman';
          _backendHost = data['backend_host'] as String? ?? '127.0.0.1';
          _backendPort = data['backend_port'] as int? ?? 9120;
        }
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final path = await _settingsPath;
      final dir = File(path).parent;
      if (!dir.existsSync()) dir.createSync(recursive: true);
      File(path).writeAsStringSync(jsonEncode({
        'dashboard_title': _dashboardTitle,
        'app_title': _appTitle,
        'backend_host': _backendHost,
        'backend_port': _backendPort,
        'updated_at': DateTime.now().toIso8601String(),
      }));
    } catch (_) {}
  }

  void setTitle(String title) {
    _dashboardTitle = title;
    _appTitle = title;
    _save();
    notifyListeners();
  }

  /// Set the backend connection details (host/port) and persist.
  Future<void> setBackendUrl(String host, int port) async {
    _backendHost = host;
    _backendPort = port;
    await _save();
    notifyListeners();
  }

  /// Show an edit dialog for the title
  static Future<void> showEditDialog(BuildContext context) async {
    final settings = context.read<WingmanSettings>();
    final controller = TextEditingController(text: settings.dashboardTitle);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final scheme = Provider.of<ThemeManager>(ctx, listen: false).currentScheme;
        return AlertDialog(
          backgroundColor: scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: scheme.borderDim, width: 0.5),
          ),
          title: Text('Dashboard Title', style: TextStyle(color: scheme.text, fontSize: 16)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(color: scheme.text, fontSize: 14, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: 'Enter dashboard title...',
              hintStyle: TextStyle(color: scheme.textMuted, fontSize: 14),
              filled: true,
              fillColor: scheme.surfaceAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: scheme.borderDim),
              ),
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: TextStyle(color: scheme.textDim)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: Text('Save', style: TextStyle(color: scheme.primary)),
            ),
          ],
        );
      },
    );

    if (result != null && result.isNotEmpty) {
      settings.setTitle(result);
    }

    controller.dispose();
  }

  /// Show a dialog to configure the backend connection (mobile).
  static Future<bool?> showConnectionDialog(BuildContext context) async {
    final settings = context.read<WingmanSettings>();
    final hostController = TextEditingController(text: settings.backendHost);
    final portController = TextEditingController(text: settings.backendPort.toString());

    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        final scheme = Provider.of<ThemeManager>(ctx, listen: false).currentScheme;
        return AlertDialog(
          backgroundColor: scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: scheme.borderDim, width: 0.5),
          ),
          title: Text('Backend Connection', style: TextStyle(color: scheme.text, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter the IP address of the machine running Hermes Wingman backend:',
                style: TextStyle(color: scheme.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: hostController,
                style: TextStyle(color: scheme.text, fontSize: 14, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  labelText: 'Host',
                  hintText: '192.168.1.100',
                  labelStyle: TextStyle(color: scheme.textDim, fontSize: 12),
                  filled: true,
                  fillColor: scheme.surfaceAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: scheme.borderDim),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: portController,
                style: TextStyle(color: scheme.text, fontSize: 14, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  labelText: 'Port',
                  hintText: '9120',
                  labelStyle: TextStyle(color: scheme.textDim, fontSize: 12),
                  filled: true,
                  fillColor: scheme.surfaceAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: scheme.borderDim),
                  ),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: TextStyle(color: scheme.textDim)),
            ),
            TextButton(
              onPressed: () {
                final host = hostController.text.trim();
                final port = int.tryParse(portController.text.trim()) ?? 9120;
                if (host.isNotEmpty) {
                  settings.setBackendUrl(host, port);
                  Navigator.of(ctx).pop(true);
                }
              },
              child: Text('Connect', style: TextStyle(color: scheme.primary)),
            ),
          ],
        );
      },
    );
  }
}
