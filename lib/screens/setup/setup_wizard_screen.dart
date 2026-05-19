import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_manager.dart';
import '../../theme/app_theme.dart';
import '../../services/hermes_service.dart';
import '../../services/hermes_api_client.dart' show BackendService, BackendConnectionState;
import '../../services/wingman_settings.dart';

final bool _isMobile = Platform.isAndroid || Platform.isIOS;

class SetupWizardScreen extends StatefulWidget {
  final void Function(int tabIndex)? onNavigate;
  const SetupWizardScreen({super.key, this.onNavigate});

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  @override
  Widget build(BuildContext context) {
    final scheme = context.watch<ThemeManager>().currentScheme;
    final backendState = context.watch<BackendService>().state;
    final settings = context.watch<WingmanSettings>();
    final themeManager = context.watch<ThemeManager>();

    return Scaffold(
      backgroundColor: scheme.scaffoldBackground,
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.rocket_launch, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Text('Setup', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Connection Card ────────────────────────────────────────
            _SectionCard(
              scheme: scheme,
              icon: Icons.wifi_tethering,
              iconColor: scheme.secondary,
              title: 'Backend Connection',
              subtitle: backendState == BackendConnectionState.connected
                  ? 'Connected to ${settings.backendHost}:${settings.backendPort}'
                  : backendState == BackendConnectionState.initializing
                      ? 'Connecting...'
                      : 'Not connected',
              trailing: _BackendStatusBadge(scheme: scheme, state: backendState),
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (backendState == BackendConnectionState.failed ||
                      backendState == BackendConnectionState.notFound)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: scheme.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: scheme.warning.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 14, color: scheme.warning),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Set up a backend server on your desktop, then connect from here.',
                                style: TextStyle(color: scheme.warning, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Text(
                    'Host: ${settings.backendHost}',
                    style: TextStyle(color: scheme.textDim, fontSize: 11, fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Port: ${settings.backendPort}',
                    style: TextStyle(color: scheme.textDim, fontSize: 11, fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: scheme.primary,
                        side: BorderSide(color: scheme.primary.withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: () async {
                        final changed = await WingmanSettings.showConnectionDialog(context);
                        if (changed == true && context.mounted) {
                          final backend = context.read<BackendService>();
                          backend.setBaseUrl(settings.backendHost, settings.backendPort);
                          await backend.reconnect();
                        }
                      },
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Change Backend', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Theme Card ─────────────────────────────────────────────
            _SectionCard(
              scheme: scheme,
              icon: Icons.palette_outlined,
              iconColor: scheme.accent,
              title: 'Theme',
              subtitle: 'Current: ${themeManager.currentThemeName}',
              body: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: themeManager.availableThemes.map((name) {
                  final isCurrent = name == themeManager.currentThemeName;
                  return GestureDetector(
                    onTap: () => themeManager.setTheme(name),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? scheme.primary.withValues(alpha: 0.12)
                            : scheme.surfaceAlt,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isCurrent ? scheme.primary : scheme.borderDim,
                          width: isCurrent ? 1.5 : 0.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isCurrent ? Icons.brightness_1 : Icons.circle_outlined,
                            size: 10,
                            color: isCurrent ? scheme.primary : scheme.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            name,
                            style: TextStyle(
                              color: isCurrent ? scheme.primary : scheme.text,
                              fontSize: 11,
                              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                          if (isCurrent) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.check, size: 12, color: scheme.primary),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),

            // ── Status Card ────────────────────────────────────────────
            if (_isMobile) ...[
              _SectionCard(
                scheme: scheme,
                icon: Icons.info_outline,
                iconColor: scheme.textDim,
                title: 'How It Works',
                subtitle: 'Mobile connects to a desktop backend',
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow(scheme, '1', 'Install and run the backend on your desktop'),
                    const SizedBox(height: 6),
                    _infoRow(scheme, '2', 'Note your desktop IP address on your LAN'),
                    const SizedBox(height: 6),
                    _infoRow(scheme, '3', 'Enter the IP and port in "Change Backend" above'),
                    const SizedBox(height: 6),
                    _infoRow(scheme, '4', 'The app connects and all features work remotely'),
                    const SizedBox(height: 16),
                    Text(
                      'Default port: 9120',
                      style: TextStyle(color: scheme.textMuted, fontSize: 10, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(AppColorScheme scheme, String num, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18, height: 18,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              num,
              style: TextStyle(
                color: scheme.primary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: scheme.textDim, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

// ── Shared Components ─────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final AppColorScheme scheme;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Widget body;

  const _SectionCard({
    required this.scheme,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailing,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.borderDim, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: scheme.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: scheme.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          body,
        ],
      ),
    );
  }
}

class _BackendStatusBadge extends StatelessWidget {
  final AppColorScheme scheme;
  final BackendConnectionState state;

  const _BackendStatusBadge({required this.scheme, required this.state});

  @override
  Widget build(BuildContext context) {
    Color color = scheme.error;
    String label = 'OFFLINE';
    switch (state) {
      case BackendConnectionState.connected:
        color = scheme.success;
        label = 'LIVE';
      case BackendConnectionState.initializing:
        color = scheme.warning;
        label = '...';
      case BackendConnectionState.failed:
      case BackendConnectionState.notFound:
        color = scheme.error;
        label = 'OFFLINE';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
