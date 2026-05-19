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

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _loadConfig();
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
              borderRadius: BorderRadius.circular(6),
              onTap: () async {
                final changed = await WingmanSettings.showConnectionDialog(context);
                if (changed == true && context.mounted) {
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
