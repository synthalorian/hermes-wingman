import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_manager.dart';
import '../../theme/app_theme.dart';
import '../../services/hermes_service.dart';
import '../../services/hermes_api_client.dart' show BackendService;
import '../../services/wingman_settings.dart';

final bool _isMobile = Platform.isAndroid || Platform.isIOS;

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  String _configContent = '';
  late TextEditingController _controller;
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;
  String? _error;
  String? _saveError;
  List<String> _localIPs = [];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _loadConfig();
    _discoverIPs();
  }

  Future<void> _discoverIPs() async {
    try {
      final interfaces = await NetworkInterface.list();
      final ips = <String>[];
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            ips.add(addr.address);
          }
        }
      }
      if (mounted) setState(() => _localIPs = ips);
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = context.read<HermesService>();
      final config = await client.getConfigRaw();
      if (!mounted) return;
      setState(() {
        _configContent = config;
        _controller.text = config;
        _editing = false;
        _loading = false;
        _saveError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _saveConfig() async {
    setState(() => _saving = true);

    try {
      final service = context.read<HermesService>();
      if (service is BackendService) {
        await service.writeConfig(_controller.text);
      } else {
        // CLI fallback: write directly to file
        final home = Platform.environment['HOME'] ?? '/home/synth';
        await File('$home/.hermes/config.yaml').writeAsString(_controller.text);
      }

      if (!mounted) return;
      setState(() {
        _configContent = _controller.text;
        _editing = false;
        _saveError = null;
      });

      final scheme = context.read<ThemeManager>().currentScheme;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Config saved', style: TextStyle(color: scheme.text, fontSize: 12)),
            duration: const Duration(seconds: 2),
            backgroundColor: scheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: scheme.success.withValues(alpha: 0.4), width: 0.5),
            ),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(12),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saveError = e.toString());
    }

    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.watch<ThemeManager>().currentScheme;

    return Scaffold(
      backgroundColor: scheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('Config'),
        actions: [
          Text('config.yaml', style: TextStyle(color: scheme.textMuted, fontSize: 12, fontFamily: 'monospace')),
          const SizedBox(width: 16),
          if (_editing) ...[
            // Cancel edit
            IconButton(
              icon: Icon(Icons.close, size: 18, color: scheme.error),
              onPressed: () {
                _controller.text = _configContent;
                setState(() => _editing = false);
              },
              tooltip: 'Cancel',
            ),
            // Save
            _saving
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary))
                : IconButton(
                    icon: Icon(Icons.save_outlined, size: 18, color: scheme.success),
                    onPressed: _saveConfig,
                    tooltip: 'Save',
                  ),
          ] else ...[
            // Edit button
            IconButton(
              icon: Icon(Icons.edit_outlined, size: 18, color: scheme.textDim),
              onPressed: () => setState(() => _editing = true),
              tooltip: 'Edit',
            ),
          ],
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(Icons.refresh, size: 18, color: scheme.textDim),
            onPressed: _loadConfig,
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBody(scheme),
    );
  }

  Widget _buildBody(AppColorScheme scheme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off, size: 48, color: scheme.error.withValues(alpha: 0.6)),
              const SizedBox(height: 16),
              Text('Could not load config', style: TextStyle(color: scheme.textDim, fontSize: 16)),
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: scheme.textMuted, fontSize: 12, fontFamily: 'monospace'), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              MaterialButton(color: scheme.primary.withValues(alpha: 0.15), onPressed: _loadConfig, child: Text('Retry', style: TextStyle(color: scheme.primary))),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Connection settings (mobile)
          if (_isMobile) _buildConnectionSection(scheme),

          // Theme picker (mobile)
          if (_isMobile) ...[
            const SizedBox(height: 8),
            _buildThemeSection(scheme),
          ],

          // Provider management (desktop + mobile)
          if (!_isMobile) ...[
            const SizedBox(height: 8),
            _buildProviderSection(scheme),
          ],

          // Network sharing (desktop only)
          if (!_isMobile) ...[
            const SizedBox(height: 8),
            _buildNetworkSection(scheme),
          ],

          const SizedBox(height: 8),
          // Summary bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.surfaceAlt,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: scheme.borderDim, width: 0.5),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: scheme.textDim),
                const SizedBox(width: 8),
                Text('${_configContent.split('\n').length} lines | ${_configContent.length} bytes', style: TextStyle(color: scheme.textDim, fontSize: 11, fontFamily: 'monospace')),
                const Spacer(),
                Icon(_editing ? Icons.edit_outlined : Icons.lock_outline, size: 12, color: _editing ? scheme.warning : scheme.success),
                const SizedBox(width: 4),
                Text(
                  _editing ? 'EDITING' : (_saving ? 'SAVING...' : 'READ ONLY'),
                  style: TextStyle(color: _editing ? scheme.warning : scheme.success, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1),
                ),
              ],
            ),
          ),
          if (_saveError != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: scheme.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 12, color: scheme.error),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_saveError!, style: TextStyle(color: scheme.error, fontSize: 11, fontFamily: 'monospace'))),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Editor or viewer
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _editing ? scheme.warning.withValues(alpha: 0.4) : scheme.borderDim,
                  width: _editing ? 1.5 : 0.5,
                ),
              ),
              child: _editing
                  ? TextField(
                      controller: _controller,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      style: TextStyle(color: scheme.text, fontSize: 11, fontFamily: 'monospace', height: 1.6),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        hintText: '# Edit config.yaml here...',
                        hintStyle: TextStyle(color: scheme.textMuted.withValues(alpha: 0.5), fontSize: 11, fontFamily: 'monospace'),
                      ),
                      keyboardType: TextInputType.multiline,
                    )
                  : SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: _buildYamlLines(scheme),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Connection Settings (mobile) ────────────────────────────────────────

  Widget _buildConnectionSection(AppColorScheme scheme) {
    final settings = context.watch<WingmanSettings>();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.secondary.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_tethering, size: 14, color: scheme.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Backend: ${settings.backendHost}:${settings.backendPort}',
                  style: TextStyle(color: scheme.text, fontSize: 11, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          Material(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),                          onTap: () async {
                final changed = await WingmanSettings.showConnectionDialog(context);
                if (changed == true && mounted) {
                  // Reconnect backend
                  final backend = context.read<BackendService>();
                  backend.setBaseUrl(settings.backendHost, settings.backendPort);
                  await backend.reconnect();
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit_outlined, size: 12, color: scheme.primary),
                    const SizedBox(width: 4),
                    Text('Change', style: TextStyle(color: scheme.primary, fontSize: 10, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Provider Management Section ────────────────────────────────────────

  Widget _buildProviderSection(AppColorScheme scheme) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_outlined, size: 14, color: scheme.primary),
              const SizedBox(width: 8),
              Text('Providers', style: TextStyle(color: scheme.text, fontSize: 12, fontWeight: FontWeight.w500)),
              const Spacer(),
              Material(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _showAddProviderDialog(scheme),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 12, color: scheme.primary),
                        const SizedBox(width: 4),
                        Text('Add', style: TextStyle(color: scheme.primary, fontSize: 10, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Add API providers (OpenAI, Anthropic, xAI, etc.) to use their models.',
            style: TextStyle(color: scheme.textMuted, fontSize: 10, height: 1.4),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddProviderDialog(AppColorScheme scheme) async {
    final nameCtrl = TextEditingController();
    final keyCtrl = TextEditingController();
    final urlCtrl = TextEditingController(text: 'https://api.openai.com/v1');
    final modelCtrl = TextEditingController(text: 'gpt-4o');
    final isOAuth = ValueNotifier<bool>(false);

    await showDialog(
      context: context,
      builder: (ctx) {
        return ValueListenableBuilder<bool>(
          valueListenable: isOAuth,
          builder: (ctx, oauth, _) {
            return AlertDialog(
              backgroundColor: scheme.surface.withAlpha(235),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: scheme.borderDim.withAlpha(60), width: 0.5),
              ),
              title: Text('Add Provider', style: TextStyle(color: scheme.text, fontSize: 15, fontWeight: FontWeight.w600)),
              content: SizedBox(
                width: 380,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ProviderField(scheme: scheme, label: 'Provider Name', hint: 'e.g. openai, anthropic, xai', ctrl: nameCtrl),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text('OAuth (e.g. Nous, xAI)', style: TextStyle(color: scheme.textDim, fontSize: 11)),
                          const Spacer(),
                          SizedBox(
                            width: 36, height: 20,
                            child: Switch(
                              value: oauth,
                              onChanged: (v) => isOAuth.value = v,
                              activeThumbColor: scheme.primary,
                            ),
                          ),
                        ],
                      ),
                      if (!oauth) ...[
                        const SizedBox(height: 10),
                        _ProviderField(scheme: scheme, label: 'API Key', hint: 'sk-...', ctrl: keyCtrl, obscure: true),
                        const SizedBox(height: 10),
                        _ProviderField(scheme: scheme, label: 'Base URL', hint: 'https://api.openai.com/v1', ctrl: urlCtrl),
                      ],
                      const SizedBox(height: 10),
                      _ProviderField(scheme: scheme, label: 'Default Model', hint: 'gpt-4o', ctrl: modelCtrl),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: TextStyle(color: scheme.textDim)),
                ),
                TextButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    try {
                      final backend = context.read<BackendService>();
                      if (oauth) {
                        await backend.httpPost('/config/update', {
                          'updates': {
                            'providers.$name.type': 'oauth',
                            'providers.$name.model': modelCtrl.text.trim(),
                          }
                        });
                      } else {
                        await backend.httpPost('/config/update', {
                          'updates': {
                            'providers.$name.api_key': keyCtrl.text.trim(),
                            'providers.$name.base_url': urlCtrl.text.trim(),
                            'providers.$name.model': modelCtrl.text.trim(),
                          }
                        });
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Provider "$name" added', style: TextStyle(color: scheme.text, fontSize: 12)),
                            backgroundColor: scheme.surface,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error: $e', style: TextStyle(color: scheme.error, fontSize: 11)),
                            backgroundColor: scheme.surface,
                          ),
                        );
                      }
                    }
                  },
                  child: Text('Add Provider', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600)),
                ),
              ],
            );
          },
        );
      },
    );
    nameCtrl.dispose();
    keyCtrl.dispose();
    urlCtrl.dispose();
    modelCtrl.dispose();
  }

  // ── Network Sharing Section ─────────────────────────────────────────────

  Widget _buildNetworkSection(AppColorScheme scheme) {
    final localIPs = _getLocalIPs();
    final primaryIP = localIPs.isNotEmpty ? localIPs.first : '—';
    final connString = '$primaryIP:9120';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.accent.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.wifi_tethering, size: 14, color: scheme.accent),
              const SizedBox(width: 8),
              Text('Network Share', style: TextStyle(color: scheme.text, fontSize: 12, fontWeight: FontWeight.w500)),
              const Spacer(),
              if (localIPs.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: scheme.success.withAlpha(25),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: scheme.success.withAlpha(60), width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 5, height: 5, decoration: BoxDecoration(color: scheme.success, shape: BoxShape.circle, boxShadow: [BoxShadow(color: scheme.success.withAlpha(128), blurRadius: 3)])),
                      const SizedBox(width: 4),
                      Text('Online', style: TextStyle(color: scheme.success, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 1)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Connect your phone to the desktop backend:',
            style: TextStyle(color: scheme.textMuted, fontSize: 10, height: 1.4),
          ),
          const SizedBox(height: 8),
          // Connection info
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.background,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: scheme.borderDim.withAlpha(60), width: 0.5),
            ),
            child: Row(
              children: [
                Icon(Icons.link, size: 14, color: scheme.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    connString,
                    style: TextStyle(color: scheme.text, fontSize: 13, fontFamily: 'monospace', fontWeight: FontWeight.w600),
                  ),
                ),
                Material(
                  color: scheme.accent.withAlpha(25),
                  borderRadius: BorderRadius.circular(6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      // Copy to clipboard
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.copy, size: 12, color: scheme.accent),
                          const SizedBox(width: 4),
                          Text('Copy', style: TextStyle(color: scheme.accent, fontSize: 10, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (localIPs.length > 1) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: localIPs.map((ip) {
                final isPrimary = ip == primaryIP;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isPrimary ? scheme.primary.withAlpha(15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: isPrimary ? scheme.primary.withAlpha(40) : scheme.borderDim.withAlpha(30), width: 0.5),
                  ),
                  child: Text(ip, style: TextStyle(color: isPrimary ? scheme.primary : scheme.textMuted, fontSize: 9, fontFamily: 'monospace')),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.info_outline, size: 10, color: scheme.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'On your phone, open Config → Backend Connection → enter this IP and port 9120',
                  style: TextStyle(color: scheme.textMuted, fontSize: 9, height: 1.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.warning_amber_outlined, size: 10, color: scheme.warning),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'The backend must bind to 0.0.0.0 to accept network connections. Run:',
                  style: TextStyle(color: scheme.warning, fontSize: 9, height: 1.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.background,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: scheme.borderDim.withAlpha(40), width: 0.5),
            ),
            child: Text(
              'BIND_ADDR=0.0.0.0:9120 hermes-wingman-backend',
              style: TextStyle(color: scheme.accent, fontSize: 10, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _getLocalIPs() {
    return _localIPs;
  }

  // ── Theme Picker (mobile) ───────────────────────────────────────────────

  Widget _buildThemeSection(AppColorScheme scheme) {
    final themeManager = context.watch<ThemeManager>();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.accent.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.palette_outlined, size: 14, color: scheme.accent),
              const SizedBox(width: 8),
              Text('Theme', style: TextStyle(color: scheme.text, fontSize: 12, fontWeight: FontWeight.w500)),
              const Spacer(),
              Text(themeManager.currentThemeName, style: TextStyle(color: scheme.textMuted, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: themeManager.availableThemes.map((name) {
              final isCurrent = name == themeManager.currentThemeName;
              return GestureDetector(
                onTap: () => themeManager.setTheme(name),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isCurrent ? scheme.primary.withValues(alpha: 0.12) : scheme.cardBackground,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: isCurrent ? scheme.primary : scheme.borderDim,
                      width: isCurrent ? 1.5 : 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isCurrent ? Icons.brightness_1 : Icons.circle_outlined, size: 8,
                        color: isCurrent ? scheme.primary : scheme.textMuted),
                      const SizedBox(width: 5),
                      Text(name, style: TextStyle(
                        color: isCurrent ? scheme.primary : scheme.text,
                        fontSize: 10,
                        fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400)),
                      if (isCurrent) ...[
                        const SizedBox(width: 3),
                        Icon(Icons.check, size: 10, color: scheme.primary),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildYamlLines(AppColorScheme scheme) {
    final lines = _configContent.split('\n');
    final lineHeight = 20.0;
    final totalHeight = lines.length * lineHeight;
    return SizedBox(
      height: totalHeight + 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(lines.length, (i) {
          final line = lines[i];
          return _YamlLine(scheme: scheme, line: line, lineNum: i + 1, height: lineHeight);
        }),
      ),
    );
  }
}

class _YamlLine extends StatelessWidget {
  final AppColorScheme scheme;
  final String line;
  final int lineNum;
  final double height;

  const _YamlLine({
    required this.scheme,
    required this.line,
    required this.lineNum,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final trimmed = line.trimLeft();
    final indent = line.length - trimmed.length;
    final indentStr = ' ' * indent;

    final colonIdx = trimmed.indexOf(':');
    final hasComment = trimmed.contains('#');
    final comment = hasComment ? trimmed.substring(trimmed.indexOf('#')) : '';
    final content = hasComment ? trimmed.substring(0, trimmed.indexOf('#')).trimRight() : trimmed;
    final isKeyValue = colonIdx > 0;

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Text('$lineNum', style: TextStyle(color: scheme.textMuted.withValues(alpha: 0.5), fontSize: 11, fontFamily: 'monospace', height: 1.4)),
          ),
          if (trimmed.isEmpty)
            SizedBox(width: 2, child: Text('', style: TextStyle(height: 1.4)))
          else if (trimmed.startsWith('#'))
            Text(indentStr + comment, style: TextStyle(color: scheme.textMuted.withValues(alpha: 0.6), fontSize: 11, fontFamily: 'monospace', fontStyle: FontStyle.italic, height: 1.4))
          else if (isKeyValue) ...[
            Text(indentStr + trimmed.substring(0, colonIdx), style: TextStyle(color: scheme.primary, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.w500, height: 1.4)),
            Text(':', style: TextStyle(color: scheme.textDim, fontSize: 11, fontFamily: 'monospace', height: 1.4)),
            if (colonIdx < trimmed.length - 1)
              Text(trimmed.substring(colonIdx + 1), style: TextStyle(color: scheme.text, fontSize: 11, fontFamily: 'monospace', height: 1.4)),
            if (comment.isNotEmpty)
              Text(' $comment', style: TextStyle(color: scheme.textMuted.withValues(alpha: 0.6), fontSize: 11, fontFamily: 'monospace', fontStyle: FontStyle.italic, height: 1.4)),
          ] else
            Text(indentStr + content + (comment.isNotEmpty ? ' $comment' : ''), style: TextStyle(color: scheme.textDim, fontSize: 11, fontFamily: 'monospace', height: 1.4)),
        ],
      ),
    );
  }
}

// ── Provider Field Widget ────────────────────────────────────────────────

class _ProviderField extends StatelessWidget {
  final AppColorScheme scheme;
  final String label;
  final String hint;
  final TextEditingController ctrl;
  final bool obscure;

  const _ProviderField({
    required this.scheme,
    required this.label,
    required this.hint,
    required this.ctrl,
    this.obscure = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: scheme.textDim, fontSize: 10, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: scheme.background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: scheme.borderDim.withAlpha(60), width: 0.5),
          ),
          child: TextField(
            controller: ctrl,
            obscureText: obscure,
            style: TextStyle(color: scheme.text, fontSize: 12, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: scheme.textMuted.withAlpha(120), fontSize: 11, fontFamily: 'monospace'),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }
}
