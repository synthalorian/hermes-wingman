import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/theme_manager.dart';
import '../../theme/app_theme.dart';
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
  int _step = 0;
  bool _hermesInstalled = false;
  String _hermesVersion = '';
  bool _checking = true;
  bool _installing = false;
  String? _installError;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    setState(() => _checking = true);
    try {
      final backend = context.read<BackendService>();
      final health = await backend.httpGet('/health');
      _hermesInstalled = health['hermes_installed'] == true;
      _hermesVersion = health['hermes_version']?.toString() ?? '';
    } catch (_) {}
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _installHermes() async {
    setState(() {
      _installing = true;
      _installError = null;
    });
    try {
      final backend = context.read<BackendService>();
      await backend.httpPost('/setup/install', {'method': 'pip'});
      await _checkStatus();
    } catch (e) {
      if (mounted) setState(() => _installError = e.toString());
    }
    if (mounted) setState(() => _installing = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.watch<ThemeManager>().currentScheme;
    final backendState = context.watch<BackendService>().state;
    final settings = context.watch<WingmanSettings>();

    return Scaffold(
      backgroundColor: scheme.scaffoldBackground,
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.rocket_launch, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Text('Setup Hermes', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Step indicator
            _buildStepIndicator(scheme),
            const SizedBox(height: 24),
            // Current step content
            _buildStepContent(scheme, settings, backendState),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator(AppColorScheme scheme) {
    final steps = ['Setup', 'Provider', 'Model', 'Done'];
    return Row(
      children: List.generate(steps.length, (i) {
        final isActive = i == _step;
        final isDone = i < _step;
        return Expanded(
          child: Column(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone
                      ? scheme.success
                      : isActive
                          ? scheme.primary
                          : scheme.surfaceAlt,
                ),
                child: Center(
                  child: isDone
                      ? Icon(Icons.check, size: 14, color: scheme.surface)
                      : Text('${i + 1}', style: TextStyle(color: isActive ? scheme.surface : scheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 4),
              Text(steps[i], style: TextStyle(color: isActive ? scheme.text : scheme.textMuted, fontSize: 9, fontWeight: isActive ? FontWeight.w600 : FontWeight.w400)),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildStepContent(AppColorScheme scheme, WingmanSettings settings, BackendConnectionState backendState) {
    switch (_step) {
      case 0: return _stepSetup(scheme);
      case 1: return _stepProvider(scheme);
      case 2: return _stepModel(scheme);
      case 3: return _stepDone(scheme, settings, backendState);
      default: return const SizedBox();
    }
  }

  // ── Step 1: Hermes Setup ────────────────────────────────────────────

  Widget _stepSetup(AppColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('1. Install Hermes Agent', style: TextStyle(color: scheme.text, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text('Hermes Agent is the AI engine that powers everything. We need to install it before we can continue.', style: TextStyle(color: scheme.textDim, fontSize: 12, height: 1.5)),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.cardBackground,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.borderDim, width: 0.5),
          ),
          child: Column(
            children: [
              Icon(
                _checking ? Icons.hourglass_empty : (_hermesInstalled ? Icons.check_circle : Icons.error_outline),
                size: 40,
                color: _checking ? scheme.textMuted : (_hermesInstalled ? scheme.success : scheme.error),
              ),
              const SizedBox(height: 12),
              if (_checking)
                Text('Checking...', style: TextStyle(color: scheme.textDim, fontSize: 14))
              else if (_hermesInstalled) ...[
                Text('Hermes Agent is installed!', style: TextStyle(color: scheme.success, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(_hermesVersion, style: TextStyle(color: scheme.textMuted, fontSize: 10, fontFamily: 'monospace'), textAlign: TextAlign.center),
              ] else ...[
                Text('Hermes Agent is not installed', style: TextStyle(color: scheme.textDim, fontSize: 14)),
                const SizedBox(height: 4),
                Text('We will install it for you automatically.', style: TextStyle(color: scheme.textMuted, fontSize: 11)),
              ],
              if (_installError != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: scheme.error.withAlpha(15), borderRadius: BorderRadius.circular(4)),
                  child: Text(_installError!, style: TextStyle(color: scheme.error, fontSize: 10, fontFamily: 'monospace')),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.primary,
              side: BorderSide(color: scheme.primary.withAlpha(80)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _checking || _installing ? null : (_hermesInstalled ? () => setState(() => _step = 1) : _installHermes),
            child: Text(
              _installing ? 'Installing...' : (_hermesInstalled ? 'Continue →' : 'Install Hermes Agent'),
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  // ── Step 2: Add Provider ────────────────────────────────────────────

  Widget _stepProvider(AppColorScheme scheme) {
    final providers = [
      ['Nous', 'nous', 'Nous Research (OAuth) — recommended for Hermes', true],
      ['Anthropic', 'anthropic', 'Anthropic API key — Claude models', false],
      ['xAI', 'xai-oauth', 'xAI (OAuth) — Grok models', true],
      ['xAI (API)', 'xai', 'xAI API key — Grok models', false],
      ['Google Gemini', 'gemini', 'Google Gemini API key', false],
      ['OpenRouter', 'openrouter', 'OpenRouter API key — multi-model', false],
      ['DeepSeek', 'deepseek', 'DeepSeek API key', false],
      ['Skip', 'skip', 'Set up a provider later', false],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('2. Add an AI Provider', style: TextStyle(color: scheme.text, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text('Choose a provider to power your Hermes Agent. You can add more later.', style: TextStyle(color: scheme.textDim, fontSize: 12, height: 1.5)),
        const SizedBox(height: 16),
        ...providers.map((p) {
          final name = p[0] as String;
          final key = p[1] as String;
          final desc = p[2] as String;
          final oauth = p[3] as bool;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _handleProviderSelect(scheme, key, name, oauth),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.cardBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: scheme.borderDim.withAlpha(50), width: 0.5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: scheme.primary.withAlpha(15), borderRadius: BorderRadius.circular(8)),
                        child: Center(child: Text(name[0], style: TextStyle(color: scheme.primary, fontSize: 16, fontWeight: FontWeight.w700))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: TextStyle(color: scheme.text, fontSize: 13, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(desc, style: TextStyle(color: scheme.textMuted, fontSize: 10, height: 1.3)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 18, color: scheme.textMuted),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Future<void> _handleProviderSelect(AppColorScheme scheme, String key, String name, bool oauth) async {
    if (key == 'skip') {
      setState(() => _step = 3);
      return;
    }
    if (oauth) {
      // OAuth providers: launch in-app auth flow
      try {
        final backend = context.read<BackendService>();
        final result = await backend.loginOAuth(key);

        if (!mounted) return;

        final status = result['status'] as String? ?? '';
        if (status == 'logged_in' || status == 'already_logged_in') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('$name authenticated!', style: TextStyle(color: scheme.text, fontSize: 11)),
              backgroundColor: scheme.surface,
              duration: const Duration(seconds: 3),
            ));
            setState(() => _step = 2);
          }
          return;
        }

        final url = result['url'] as String?;
        if (url != null && url.isNotEmpty) {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }

          if (!mounted) return;
          // Show waiting dialog
          await _showAuthWaitingDialog(scheme, key, name, backend);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('$name authenticated!', style: TextStyle(color: scheme.text, fontSize: 11)),
              backgroundColor: scheme.surface,
            ));
            setState(() => _step = 2);
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('$name: Could not get auth URL. ${result['stderr'] ?? result['error'] ?? ''}',
                  style: TextStyle(color: scheme.error, fontSize: 11)),
              backgroundColor: scheme.surface,
            ));
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e', style: TextStyle(color: scheme.error, fontSize: 11)),
            backgroundColor: scheme.surface,
          ));
        }
      }
    } else {
      // API key providers: show a dialog to enter the key
      final keyCtrl = TextEditingController();
      final modelCtrl = TextEditingController(
        text: key == 'openai' ? 'gpt-4o' : key == 'anthropic' ? 'claude-sonnet-4' : key == 'xai' ? 'grok-3' : 'gemini-2.0-flash',
      );
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: scheme.surface.withAlpha(235),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: scheme.borderDim.withAlpha(60), width: 0.5)),
          title: Text('$name API Key', style: TextStyle(color: scheme.text, fontSize: 15)),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: keyCtrl,
                  obscureText: true,
                  style: TextStyle(color: scheme.text, fontSize: 12, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: 'sk-...',
                    labelText: 'API Key',
                    labelStyle: TextStyle(color: scheme.textDim, fontSize: 11),
                    filled: true, fillColor: scheme.background,
                    border: OutlineInputBorder(borderSide: BorderSide(color: scheme.borderDim), borderRadius: BorderRadius.circular(6)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: modelCtrl,
                  style: TextStyle(color: scheme.text, fontSize: 12, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: 'gpt-4o',
                    labelText: 'Default Model',
                    labelStyle: TextStyle(color: scheme.textDim, fontSize: 11),
                    filled: true, fillColor: scheme.background,
                    border: OutlineInputBorder(borderSide: BorderSide(color: scheme.borderDim), borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: scheme.textDim))),
            TextButton(
              onPressed: () async {
                if (keyCtrl.text.trim().isEmpty) return;
                try {
                  final backend = context.read<BackendService>();
                  await backend.httpPost('/config/update', {
                    'updates': {
                      'providers.$key.api_key': keyCtrl.text.trim(),
                      'providers.$key.model': modelCtrl.text.trim(),
                    }
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('$name provider added!', style: TextStyle(color: scheme.text, fontSize: 11)),
                      backgroundColor: scheme.surface,
                    ));
                    setState(() => _step = 2);
                  }
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e', style: TextStyle(color: scheme.error, fontSize: 11)), backgroundColor: scheme.surface));
                }
              },
              child: Text('Add Provider', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
      keyCtrl.dispose();
      modelCtrl.dispose();
    }
  }

  // ── Step 3: Select Model ────────────────────────────────────────

  Widget _stepModel(AppColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('3. Select Default Model', style: TextStyle(color: scheme.text, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text('Choose which model Hermes will use by default. You can switch anytime.', style: TextStyle(color: scheme.textDim, fontSize: 12, height: 1.5)),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.cardBackground,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.borderDim, width: 0.5),
          ),
          child: Column(
            children: [
              Icon(Icons.memory_outlined, size: 40, color: scheme.primary.withAlpha(150)),
              const SizedBox(height: 12),
              Text('Model selection available in the', style: TextStyle(color: scheme.textDim, fontSize: 12)),
              Text('Models tab once providers are configured.', style: TextStyle(color: scheme.textDim, fontSize: 12)),
              const SizedBox(height: 16),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: scheme.primary, side: BorderSide(color: scheme.primary.withAlpha(80))),
                onPressed: () => widget.onNavigate?.call(2),
                child: const Text('Open Models', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.primary,
              side: BorderSide(color: scheme.primary.withAlpha(80)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => setState(() => _step = 3),
            child: Text('Continue →', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ),
      ],
    );
  }

  // ── Step 4: Done ────────────────────────────────────────────────────

  Widget _stepDone(AppColorScheme scheme, WingmanSettings settings, BackendConnectionState backendState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle, size: 48, color: scheme.success),
        const SizedBox(height: 16),
        Text('Setup Complete!', style: TextStyle(color: scheme.text, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Hermes Agent is ready to go. Here\'s what\'s available:', style: TextStyle(color: scheme.textDim, fontSize: 13, height: 1.5)),
        const SizedBox(height: 20),
        _setupItem(scheme, Icons.chat, 'Chat with Hermes', 'Ask questions, run code, browse the web'),
        _setupItem(scheme, Icons.memory_outlined, 'Switch Models', 'Pick from 166+ skills-powered models'),
        _setupItem(scheme, Icons.auto_awesome, 'Manage Skills', 'Enable/disable agent capabilities'),
        _setupItem(scheme, Icons.folder_open, 'Browse Files', 'Read and edit workspace files'),
        _setupItem(scheme, Icons.schedule_outlined, 'Cron Jobs', 'Schedule recurring AI tasks'),
        _setupItem(scheme, Icons.hub_outlined, 'Gateway', 'Connect Discord, Telegram, etc.'),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.primary,
              side: BorderSide(color: scheme.primary.withAlpha(80)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => widget.onNavigate?.call(0),
            child: const Text('Start Using Hermes Wingman', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ),
        if (_isMobile) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.accent,
                side: BorderSide(color: scheme.accent.withAlpha(80)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => widget.onNavigate?.call(10),
              icon: const Icon(Icons.settings_outlined, size: 16),
              label: const Text('Configure Backend Connection', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _showAuthWaitingDialog(
      AppColorScheme scheme, String provider, String name, BackendService backend) async {
    final completer = Completer<void>();
    Timer? timer;
    int elapsed = 0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        timer = Timer.periodic(const Duration(seconds: 2), (_) async {
          elapsed += 2;
          if (elapsed > 120) {
            timer?.cancel();
            if (ctx.mounted) Navigator.pop(ctx);
            if (!completer.isCompleted) completer.complete();
            return;
          }
          try {
            final data = await backend.getAuthStatus();
            if (!ctx.mounted) return;
            final providers = data['providers'] as List? ?? [];
            for (final p in providers) {
              if (p is Map && p['name'] == provider && p['status'] == 'logged_in') {
                timer?.cancel();
                Navigator.pop(ctx);
                if (!completer.isCompleted) completer.complete();
                return;
              }
            }
          } catch (_) {}
          if (ctx.mounted && mounted) {
            (ctx as dynamic).setState(() {});
          }
        });

        return AlertDialog(
          backgroundColor: scheme.surface.withAlpha(235),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: scheme.borderDim.withAlpha(60), width: 0.5),
          ),
          content: SizedBox(
            width: 300,
            child: StatefulBuilder(
              builder: (ctx, setInnerState) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 48, height: 48,
                    child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
                  ),
                  const SizedBox(height: 16),
                  Text('Authenticating with $name',
                      style: TextStyle(color: scheme.text, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                    'A browser window opened for authentication.\nComplete the login in your browser.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.textDim, fontSize: 11, height: 1.4),
                  ),
                  if (elapsed > 10) ...[
                    const SizedBox(height: 12),
                    Text('Waiting... (${elapsed}s)',
                        style: TextStyle(color: scheme.textMuted, fontSize: 10)),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      timer?.cancel();
                      Navigator.pop(ctx);
                      if (!completer.isCompleted) completer.complete();
                    },
                    child: Text('Cancel', style: TextStyle(color: scheme.textMuted, fontSize: 11)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    return completer.future;
  }

  Widget _setupItem(AppColorScheme scheme, IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: scheme.primary.withAlpha(12), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 15, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: scheme.text, fontSize: 13, fontWeight: FontWeight.w500)),
                Text(desc, style: TextStyle(color: scheme.textMuted, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}