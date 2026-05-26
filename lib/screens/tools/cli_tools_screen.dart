import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_manager.dart';
import '../../theme/app_theme.dart';
import '../../services/hermes_api_client.dart' show BackendService;

/// Unified CLI Tools screen — doctor, security, backup, proxy, insights, etc.
class CliToolsScreen extends StatefulWidget {
  const CliToolsScreen({super.key});

  @override
  State<CliToolsScreen> createState() => _CliToolsScreenState();
}

class _CliToolsScreenState extends State<CliToolsScreen> {
  String? _doctorOutput;
  String? _securityOutput;
  String? _dumpOutput;
  String? _backupOutput;
  String? _proxyOutput;
  String? _secretsOutput;
  String? _insightsOutput;
  String? _hooksOutput;
  String? _pairingOutput;
  String? _checkpointsOutput;
  String? _debugOutput;
  bool _working = false;
  bool _expanded = false; // which section is showing output
  String _activeSection = '';

  @override
  Widget build(BuildContext context) {
    final scheme = context.watch<ThemeManager>().currentScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('CLI Tools', style: TextStyle(fontSize: 15)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader(scheme, '🩺 Diagnostics'),
          _actionTile(scheme, 'Run Doctor', Icons.health_and_safety_outlined,
              'Check configuration and fix issues', 'doctor', _runDoctor),
          _actionTile(scheme, 'Security Audit', Icons.shield_outlined,
              'Scan dependencies for vulnerabilities', 'security', _runSecurity),
          _actionTile(scheme, 'Setup Dump', Icons.description_outlined,
              'Summary of your Hermes setup for support', 'dump', _runDump),
          _actionTile(scheme, 'Debug Report', Icons.bug_report_outlined,
              'Generate local debug report', 'debug', _runDebug),

          const SizedBox(height: 16),
          _sectionHeader(scheme, '💾 Data Management'),
          _actionTile(scheme, 'Quick Backup', Icons.backup_outlined,
              'Create a zip archive of config + data', 'backup', _runBackup),
          _actionTile(scheme, 'Checkpoints', Icons.restore_outlined,
              'View checkpoint storage status', 'checkpoints', _runCheckpoints),

          const SizedBox(height: 16),
          _sectionHeader(scheme, '🔌 Integrations'),
          _actionTile(scheme, 'Proxy Status', Icons.swap_horiz,
              'Local OpenAI-compatible proxy status', 'proxy', _runProxy),
          _actionTile(scheme, 'Secrets Manager', Icons.lock_outlined,
              'Bitwarden Secrets Manager status', 'secrets', _runSecrets),
          _actionTile(scheme, 'Pairing Codes', Icons.qr_code_outlined,
              'DM pairing user management', 'pairing', _runPairing),
          _actionTile(scheme, 'Shell Hooks', Icons.terminal_outlined,
              'List configured shell-script hooks', 'hooks', _runHooks),

          const SizedBox(height: 16),
          _sectionHeader(scheme, '📊 Analytics'),
          _actionTile(scheme, 'Insights', Icons.insights_outlined,
              'Token usage, costs, activity trends (7 days)', 'insights', _runInsights),

          if (_expanded && _activeSection.isNotEmpty) ...[
            const SizedBox(height: 16),
            _outputBox(scheme),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(AppColorScheme scheme, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title,
          style: TextStyle(color: scheme.text, fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }

  Widget _actionTile(AppColorScheme scheme, String title, IconData icon,
      String subtitle, String section, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _working ? null : onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _activeSection == section
                  ? scheme.primary.withAlpha(12)
                  : scheme.cardBackground.withAlpha(160),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _activeSection == section
                    ? scheme.primary.withAlpha(40)
                    : scheme.borderDim.withAlpha(30),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(color: scheme.text, fontSize: 12, fontWeight: FontWeight.w500)),
                      Text(subtitle,
                          style: TextStyle(color: scheme.textMuted, fontSize: 9)),
                    ],
                  ),
                ),
                if (_working && _activeSection == section)
                  const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.5))
                else
                  Icon(Icons.play_arrow_outlined, size: 16, color: scheme.textMuted.withAlpha(150)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _outputBox(AppColorScheme scheme) {
    String? content;
    switch (_activeSection) {
      case 'doctor': content = _doctorOutput;
      case 'security': content = _securityOutput;
      case 'dump': content = _dumpOutput;
      case 'debug': content = _debugOutput;
      case 'backup': content = _backupOutput;
      case 'checkpoints': content = _checkpointsOutput;
      case 'proxy': content = _proxyOutput;
      case 'secrets': content = _secretsOutput;
      case 'pairing': content = _pairingOutput;
      case 'hooks': content = _hooksOutput;
      case 'insights': content = _insightsOutput;
    }
    if (content == null || content.isEmpty) return const SizedBox();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.background.withAlpha(180),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.borderDim.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Output',
                  style: TextStyle(color: scheme.textDim, fontSize: 10, fontWeight: FontWeight.w600)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _expanded = false),
                child: Text('Close',
                    style: TextStyle(color: scheme.textMuted, fontSize: 9)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(content,
              style: TextStyle(color: scheme.textDim, fontSize: 10, fontFamily: 'monospace', height: 1.4)),
        ],
      ),
    );
  }

  Future<void> _run(String section, Future<Map<String, dynamic>> Function() call) async {
    setState(() { _working = true; _expanded = true; _activeSection = section; });
    try {
      final result = await call();
      if (!mounted) return;
      final output = result['output'] as String? ?? result['dump'] as String? ??
                     result['status'] as String? ?? result['insights'] as String? ??
                     result['webhooks'] as String? ?? result['hooks'] as String? ??
                     result['users'] as String? ?? result['plugins'] as String? ??
                     result['servers'] as String? ??
                     (result['success'] == true ? 'Done' : result['error'] as String? ?? 'Error');

      setState(() {
        switch (section) {
          case 'doctor': _doctorOutput = output;
          case 'security': _securityOutput = output;
          case 'dump': _dumpOutput = output;
          case 'debug': _debugOutput = output;
          case 'backup': _backupOutput = output;
          case 'checkpoints': _checkpointsOutput = output;
          case 'proxy': _proxyOutput = output;
          case 'secrets': _secretsOutput = output;
          case 'pairing': _pairingOutput = output;
          case 'hooks': _hooksOutput = output;
          case 'insights': _insightsOutput = output;
        }
        _working = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        switch (section) {
          case 'doctor': _doctorOutput = 'Error: $e';
          case 'security': _securityOutput = 'Error: $e';
          case 'dump': _dumpOutput = 'Error: $e';
          case 'debug': _debugOutput = 'Error: $e';
          case 'backup': _backupOutput = 'Error: $e';
          case 'checkpoints': _checkpointsOutput = 'Error: $e';
          case 'proxy': _proxyOutput = 'Error: $e';
          case 'secrets': _secretsOutput = 'Error: $e';
          case 'pairing': _pairingOutput = 'Error: $e';
          case 'hooks': _hooksOutput = 'Error: $e';
          case 'insights': _insightsOutput = 'Error: $e';
        }
        _working = false;
      });
    }
  }

  Future<void> _runDoctor() => _run('doctor', () => context.read<BackendService>().runDoctor());
  Future<void> _runSecurity() => _run('security', () => context.read<BackendService>().runSecurityAudit());
  Future<void> _runDump() => _run('dump', () => context.read<BackendService>().getDump());
  Future<void> _runDebug() => _run('debug', () => context.read<BackendService>().createDebugReport());
  Future<void> _runBackup() => _run('backup', () => context.read<BackendService>().createBackup());
  Future<void> _runCheckpoints() => _run('checkpoints', () => context.read<BackendService>().getCheckpoints());
  Future<void> _runProxy() => _run('proxy', () => context.read<BackendService>().getProxyStatus());
  Future<void> _runSecrets() => _run('secrets', () => context.read<BackendService>().getSecretsStatus());
  Future<void> _runPairing() => _run('pairing', () => context.read<BackendService>().getPairingUsers());
  Future<void> _runHooks() => _run('hooks', () => context.read<BackendService>().getHooks());
  Future<void> _runInsights() => _run('insights', () => context.read<BackendService>().getInsights());
}