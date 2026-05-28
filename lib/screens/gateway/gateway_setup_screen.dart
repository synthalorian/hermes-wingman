import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_manager.dart';
import '../../theme/app_theme.dart';
import '../../services/hermes_api_client.dart' show BackendService;

/// Gateway setup screen — configure all 16 messaging platforms + service.
class GatewaySetupScreen extends StatefulWidget {
  const GatewaySetupScreen({super.key});

  @override
  State<GatewaySetupScreen> createState() => _GatewaySetupScreenState();
}

class _GatewaySetupScreenState extends State<GatewaySetupScreen> {
  List<Map<String, dynamic>>? _platforms;
  bool _loading = true;
  String? _error;
  String? _serviceStatus;
  bool _serviceLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final backend = context.read<BackendService>();
      final raw = await backend.httpGetList('/gateway/platforms');
      if (!mounted) { return; }
      setState(() {
        _platforms = raw.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
    await _checkService();
  }

  Future<void> _checkService() async {
    try {
      final backend = context.read<BackendService>();
      final data = await backend.gatewayServiceAction('status');
      if (!mounted) { return; }
      setState(() => _serviceStatus = data['success'] == true ? 'running' : 'not_running');
    } catch (_) {
      if (mounted) setState(() => _serviceStatus = 'unknown');
    }
  }

  Future<void> _configurePlatform(String key) async {
    final platform = _platforms?.firstWhere(
      (p) => p['key'] == key,
      orElse: () => {},
    );
    if (platform == null || platform.isEmpty) { return; }

    final vars = (platform['vars'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final label = platform['label'] as String? ?? key;
    final emoji = platform['emoji'] as String? ?? '🔌';
    final instructions = (platform['instructions'] as List?)?.cast<String>() ?? [];

    final controllers = <String, TextEditingController>{};
    for (final v in vars) {
      final name = v['name'] as String? ?? '';
      final current = v['current'] as String? ?? '';
      controllers[name] = TextEditingController(text: current);
    }

    if (!mounted) { return; }
    final scheme = context.read<ThemeManager>().currentScheme;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final backendCfg = context.read<BackendService>();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: scheme.surface.withAlpha(235),
        contentPadding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.borderDim.withAlpha(60), width: 0.5),
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('$emoji ', style: const TextStyle(fontSize: 20)),
                    Expanded(
                      child: Text('Configure $label',
                          style: TextStyle(color: scheme.text, fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, size: 16, color: scheme.textMuted),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                if (instructions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceAlt.withAlpha(100),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: scheme.borderDim.withAlpha(40)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Setup Instructions',
                            style: TextStyle(color: scheme.text, fontSize: 11, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        for (final inst in instructions)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(inst,
                                style: TextStyle(color: scheme.textDim, fontSize: 10, height: 1.4)),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                for (final v in vars) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _EnvVarField(
                      scheme: scheme,
                      spec: v,
                      controller: controllers[v['name'] as String? ?? '']!,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Cancel', style: TextStyle(color: scheme.textDim, fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.surface,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      ),
                      onPressed: () {
                        final envVars = <String, String>{};
                        for (final v in vars) {
                          final name = v['name'] as String? ?? '';
                          final val = controllers[name]?.text.trim() ?? '';
                          if (val.isNotEmpty) envVars[name] = val;
                        }
                        Navigator.pop(ctx, envVars);
                      },
                      child: const Text('Save', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        await backendCfg.configureGatewayPlatform(key, result);
        if (mounted) {
          scaffoldMessenger.showSnackBar(SnackBar(
            content: Text('$label configured successfully!',
                style: TextStyle(color: scheme.text, fontSize: 11)),
            backgroundColor: scheme.surface,
            duration: const Duration(seconds: 2),
          ));
          _load();
        }
      } catch (e) {
        if (mounted) {
          scaffoldMessenger.showSnackBar(SnackBar(
            content: Text('Error: $e', style: TextStyle(color: scheme.error, fontSize: 11)),
            backgroundColor: scheme.surface,
          ));
        }
      }
    }

    for (final c in controllers.values) { c.dispose(); }
  }

  Future<void> _serviceAction(String action) async {
    setState(() => _serviceLoading = true);
    final scheme = context.read<ThemeManager>().currentScheme;
    try {
      final backend = context.read<BackendService>();
      await backend.gatewayServiceAction(action);
      await _checkService();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gateway $action ${action == 'stop' ? 'stopped' : action == 'start' ? 'started' : action}'),
          backgroundColor: scheme.surface,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e', style: TextStyle(color: scheme.error)),
        ));
      }
    }
    if (mounted) setState(() => _serviceLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.watch<ThemeManager>().currentScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            const Text('Gateway Setup', style: TextStyle(fontSize: 15)),
            const SizedBox(width: 8),
            _ServiceBadge(scheme: scheme, status: _serviceStatus),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, size: 16, color: scheme.textMuted),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error', style: TextStyle(color: scheme.error)))
              : Column(
                  children: [
                    _buildServiceBar(scheme),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: _platforms?.length ?? 0,
                        itemBuilder: (ctx, i) => _buildPlatformCard(scheme, _platforms![i]),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildServiceBar(AppColorScheme scheme) {
    final String statusLabel;
    if (_serviceStatus == 'running') {
      statusLabel = 'Running';
    } else if (_serviceStatus == 'not_running') {
      statusLabel = 'Stopped';
    } else {
      statusLabel = 'Unknown';
    }
    final statusColor = _serviceStatus == 'running' ? scheme.success : scheme.textMuted;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceAlt.withAlpha(120),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.borderDim.withAlpha(40)),
      ),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
          ),
          const SizedBox(width: 8),
          Text('Gateway Service: $statusLabel',
              style: TextStyle(color: scheme.textDim, fontSize: 11)),
          const Spacer(),
          if (_serviceLoading)
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5))
          else ...[
            _MiniButton(scheme: scheme, label: 'Start', onTap: () => _serviceAction('start')),
            const SizedBox(width: 4),
            _MiniButton(scheme: scheme, label: 'Stop', onTap: () => _serviceAction('stop')),
            const SizedBox(width: 4),
            _MiniButton(scheme: scheme, label: 'Restart', onTap: () => _serviceAction('restart')),
          ],
        ],
      ),
    );
  }

  Widget _buildPlatformCard(AppColorScheme scheme, Map<String, dynamic> platform) {
    final key = platform['key'] as String? ?? '';
    final label = platform['label'] as String? ?? '';
    final emoji = platform['emoji'] as String? ?? '🔌';
    final status = platform['status'] as String? ?? 'not_configured';
    final statusColor = status == 'connected'
        ? scheme.success
        : status == 'error' || status == 'configured'
            ? scheme.warning
            : scheme.textMuted;
    final statusLabel = status == 'connected'
        ? '✓ Connected'
        : status == 'error'
            ? '⚠ Error'
            : status == 'configured'
                ? 'Configured'
                : 'Not Configured';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _configurePlatform(key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.cardBackground.withAlpha(160),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: status == 'connected'
                    ? scheme.success.withAlpha(50)
                    : scheme.borderDim.withAlpha(40),
              ),
            ),
            child: Row(
              children: [
                Text('$emoji ', style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label,
                      style: TextStyle(color: scheme.text, fontSize: 12, fontWeight: FontWeight.w500)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(statusLabel,
                      style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.w500)),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 14, color: scheme.textMuted.withAlpha(102)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Env var field with password toggle for secret fields.
class _EnvVarField extends StatefulWidget {
  final AppColorScheme scheme;
  final Map<String, dynamic> spec;
  final TextEditingController controller;

  const _EnvVarField({
    required this.scheme,
    required this.spec,
    required this.controller,
  });

  @override
  State<_EnvVarField> createState() => _EnvVarFieldState();
}

class _EnvVarFieldState extends State<_EnvVarField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final s = widget.scheme;
    final spec = widget.spec;
    final name = spec['name'] as String? ?? '';
    final prompt = spec['prompt'] as String? ?? name;
    final isPassword = spec['password'] as bool? ?? false;
    final help = spec['help'] as String? ?? '';
    final current = spec['current'] as String? ?? '';
    final isAllowlist = spec['is_allowlist'] as bool? ?? false;
    final hasHelp = help.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(prompt,
            style: TextStyle(color: s.text, fontSize: 11, fontWeight: FontWeight.w500)),
        if (hasHelp)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Text(help,
                style: TextStyle(color: s.textMuted, fontSize: 9, height: 1.3)),
          ),
        if (current.isNotEmpty && isPassword)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('Current: $current',
                style: TextStyle(color: s.textMuted, fontSize: 9, fontFamily: 'monospace')),
          ),
        TextField(
          controller: widget.controller,
          obscureText: isPassword && _obscured,
          style: TextStyle(color: s.text, fontSize: 12, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: isAllowlist ? 'user_ids' : isPassword ? '••••••••' : 'value',
            hintStyle: TextStyle(color: s.textMuted.withAlpha(102), fontSize: 10),
            filled: true,
            fillColor: s.background.withAlpha(120),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderSide: BorderSide(color: s.borderDim.withAlpha(60)),
              borderRadius: BorderRadius.circular(6),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: s.borderDim.withAlpha(40)),
              borderRadius: BorderRadius.circular(6),
            ),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(_obscured ? Icons.visibility_off : Icons.visibility,
                        size: 14, color: s.textMuted),
                    onPressed: () => setState(() => _obscured = !_obscured),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

/// Small inline action button for the service bar.
class _MiniButton extends StatelessWidget {
  final AppColorScheme scheme;
  final String label;
  final VoidCallback onTap;

  const _MiniButton({
    required this.scheme,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.primary.withAlpha(15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: scheme.primary.withAlpha(30), width: 0.5),
        ),
        child: Text(label,
            style: TextStyle(color: scheme.primary, fontSize: 9, fontWeight: FontWeight.w500)),
      ),
    );
  }
}

/// Status badge for the service indicator.
class _ServiceBadge extends StatelessWidget {
  final AppColorScheme scheme;
  final String? status;

  const _ServiceBadge({required this.scheme, required this.status});

  @override
  Widget build(BuildContext context) {
    final running = status == 'running';
    final color = running ? scheme.success : scheme.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(running ? '● Live' : '○ Off',
          style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w500)),
    );
  }
}