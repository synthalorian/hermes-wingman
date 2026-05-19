import 'dart:ui' show VoidCallback;

/// Stub for unsupported platforms (mobile).
/// Replaced by the real tray_service.dart on desktop via conditional import.
class TrayService {
  VoidCallback? onShow;
  VoidCallback? onQuit;
  VoidCallback? onSetupWizard;

  Future<void> init() async {}
  void setTooltip(String tip) {}
  Future<void> hideWindow() async {}
  Future<void> showWindow() async {}
  Future<void> destroy() async {}
}
