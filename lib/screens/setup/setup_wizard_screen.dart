import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/theme_manager.dart';
import '../../theme/app_theme.dart';
import '../../services/hermes_service.dart';
import '../../services/hermes_api_client.dart';

// ── Setup Step Enum ──────────────────────────────────────────────────────

enum SetupStep { detect, install, configure, test, done }

// ── Setup Wizard Screen ──────────────────────────────────────────────────

class SetupWizardScreen extends StatefulWidget {
  final void Function(int tabIndex)? onNavigate;
  const SetupWizardScreen({super.key, this.onNavigate});

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  SetupStep _currentStep = SetupStep.detect;

  // Detection state
  bool _loading = true;
  bool _hermesInstalled = false;
  bool _configExists = false;
  bool _hasApiKeys = false;
  bool _modelConfigured = false;
  List<String> _connectedPlatforms = [];
  String? _hermesBin;

  // Install state
  bool _installing = false;
  String _installOutput = '';
  bool _installDone = false;
  bool _installSuccess = false;

  // Configure state
  bool _configuring = false;
  String _configOutput = '';
  bool _configDone = false;
  bool _configSuccess = false;
  String _defaultModel = '';
  List<Map<String, dynamic>> _discovered = [];

  // Test state
  bool _testing = false;
  String? _testResult;
  bool _testSuccess = false;

  // Backend service reference (cached)
  BackendService? _backend;

  @override
  void initState() {
    super.initState();
    // Start detection immediately
    Future.microtask(_runDetect);
  }

  // ── Detect ─────────────────────────────────────────────────────────

  Future<void> _runDetect() async {
    setState(() => _loading = true);
    try {
      final service = context.read<HermesService>();
      if (service is BackendService) {
        _backend = service;
        final data = await service.httpGet('/setup/detect');
        if (!mounted) return;
        setState(() {
          _hermesInstalled = data['hermes_installed'] == true;
          _configExists = data['config_exists'] == true;
          _hasApiKeys = data['has_api_keys'] == true;
          _modelConfigured = data['model_configured'] == true;
          _connectedPlatforms = (data['connected_platforms'] as List? ?? []).cast<String>();
          _hermesBin = data['hermes_bin'] as String?;
          _loading = false;
        });
      } else {
        // CLI fallback — basic check
        final installed = await service.isHermesAvailable();
        if (!mounted) return;
        setState(() {
          _hermesInstalled = installed;
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ── Install ────────────────────────────────────────────────────────

  Future<void> _runInstall() async {
    setState(() {
      _installing = true;
      _installOutput = '';
      _installDone = false;
    });

    // Try through backend first
    if (_backend != null) {
      try {
        final result = await _backend!.httpPost('/setup/install', {'method': 'pip'});
        if (result['success'] == true) {
          setState(() {
            _installOutput = '✓ Hermes Agent installed successfully!\n${result['output'] ?? ''}';
            _installSuccess = true;
          });
        } else {
          setState(() {
            _installOutput = result['error'] as String? ?? 'Installation failed';
            _installSuccess = false;
          });
        }
      } catch (e) {
        setState(() {
          _installOutput = 'Error: $e';
          _installSuccess = false;
        });
      }
    } else {
      // CLI fallback — try pip3 directly
      await _cliInstall('pip3');
    }

    setState(() {
      _installing = false;
      _installDone = true;
    });

    // Re-detect after install
    await _runDetect();
  }

  Future<void> _cliInstall(String pipCmd) async {
    try {
      // First attempt
      final r1 = await Process.run(pipCmd, ['install', 'hermes-agent']);
      if (r1.exitCode == 0) {
        setState(() {
          _installOutput = '✓ Hermes Agent installed via $pipCmd!\n${r1.stdout as String}';
          _installSuccess = true;
        });
        return;
      }

      final stderr = (r1.stderr as String?)?.toLowerCase() ?? '';
      if (stderr.contains('externally-managed') || stderr.contains('externally managed')) {
        // Try --break-system-packages
        final r2 = await Process.run(pipCmd, ['install', '--break-system-packages', 'hermes-agent']);
        if (r2.exitCode == 0) {
          setState(() {
            _installOutput = '✓ Hermes Agent installed (--break-system-packages)\n${r2.stdout as String}';
            _installSuccess = true;
          });
          return;
        }
        setState(() {
          _installSuccess = false;
          _installOutput = 'Python env is externally managed.\n'
              'Try:\n  $pipCmd install --break-system-packages hermes-agent\n'
              'Or:\n  pipx install hermes-agent\n'
              'Or:\n  python3 -m venv ~/.hermes-venv && ~/.hermes-venv/bin/pip install hermes-agent';
        });
        return;
      }

      setState(() {
        _installOutput = 'Install failed:\n${(r1.stderr as String?)?.trim() ?? "unknown error"}';
        _installSuccess = false;
      });
    } catch (e) {
      // pip3 not found, try pip
      if (pipCmd == 'pip3') {
        await _cliInstall('pip');
      } else {
        setState(() {
          _installSuccess = false;
          _installOutput = 'Python/pip not found.\nInstall python3 and pip for your system.';
        });
      }
    }
  }

  // ── Configure ──────────────────────────────────────────────────────

  Future<void> _runConfigure() async {
    setState(() {
      _configuring = true;
      _configOutput = '';
    });

    try {
      if (_backend != null) {
        final result = await _backend!.httpPost('/setup/auto-configure', {});
        if (result['success'] == true) {
          setState(() {
            _defaultModel = result['default_model'] as String? ?? '';
            _discovered = (result['discovered'] as List? ?? []).cast<Map<String, dynamic>>();
            _configSuccess = true;
            _configOutput = _buildConfigSummary(result);
          });
        } else {
          setState(() {
            _configSuccess = false;
            _configOutput = 'Auto-configure failed: ${result['error']}';
          });
        }
      } else {
        setState(() {
          _configSuccess = false;
          _configOutput = 'Backend not available — configure manually in the Config tab.';
        });
      }
    } catch (e) {
      setState(() {
        _configSuccess = false;
        _configOutput = 'Error: $e';
      });
    }

    setState(() {
      _configuring = false;
      _configDone = true;
    });
  }

  String _buildConfigSummary(Map<String, dynamic> data) {
    final buf = StringBuffer();
    buf.writeln('✓ Config written successfully!');
    buf.writeln('');
    buf.writeln('Default model: ${data['default_model']}');
    buf.writeln('Providers found: ${data['providers_count']}');
    buf.writeln('Fallback models: ${data['fallback_count']}');
    final discovered = data['discovered'] as List? ?? [];
    if (discovered.isNotEmpty) {
      buf.writeln('');
      buf.writeln('Discovered:');
      for (final d in discovered) {
        final name = d['name'] ?? '?';
        final type = d['type'] ?? '?';
        final status = d['status'] ?? '?';
        final src = d['source'] as String?;
        final sourceInfo = src != null ? ' ($src)' : '';
        buf.writeln('  • $name  [$type]  → $status$sourceInfo');
      }
    }
    return buf.toString();
  }

  // ── Test ───────────────────────────────────────────────────────────

  Future<void> _runTest() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });

    try {
      if (_backend != null) {
        // Determine which provider and model to test
        String provider = '';
        if (_discovered.isNotEmpty) {
          // Pick the first cloud provider with a key
          final cloudProv = _discovered.firstWhere(
            (d) => d['type'] == 'cloud' && d['status'] == 'key_found',
            orElse: () => _discovered.isNotEmpty ? _discovered.first : {},
          );
          provider = cloudProv['name'] as String? ?? '';
        }

        if (provider.isNotEmpty) {
          final result = await _backend!.httpPost('/setup/probe-provider', {
            'provider': provider,
          });
          setState(() {
            _testSuccess = result['success'] == true;
            _testResult = result['success'] == true
                ? '✓ Connection to $provider successful!'
                : '✗ $provider: ${result['error'] ?? 'unreachable'}';
          });
        } else {
          // Try probing the default model
          setState(() {
            _testSuccess = false;
            _testResult = 'No cloud provider found to test. Try local models in the Models tab.';
          });
        }
      } else {
        // CLI fallback
        final result = await Process.run('hermes', ['--oneshot', 'say hi']);
        setState(() {
          _testSuccess = result.exitCode == 0;
          _testResult = result.exitCode == 0
              ? '✓ Hermes CLI works!'
              : '✗ ${result.stderr}';
        });
      }
    } catch (e) {
      setState(() {
        _testSuccess = false;
        _testResult = 'Error: $e';
      });
    }

    setState(() => _testing = false);
  }

  // ── Navigation ─────────────────────────────────────────────────────

  void _nextStep() {
    setState(() {
      switch (_currentStep) {
        case SetupStep.detect:
          _currentStep = _hermesInstalled ? SetupStep.configure : SetupStep.install;
          break;
        case SetupStep.install:
          _currentStep = SetupStep.configure;
          break;
        case SetupStep.configure:
          _currentStep = SetupStep.test;
          break;
        case SetupStep.test:
          _currentStep = SetupStep.done;
          break;
        case SetupStep.done:
          break;
      }
    });
  }

  void _skipToEnd() {
    setState(() => _currentStep = SetupStep.done);
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = context.watch<ThemeManager>().currentScheme;
    return Scaffold(
      backgroundColor: scheme.scaffoldBackground,
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.rocket_launch, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Text('Setup Wizard', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          if (_currentStep != SetupStep.done && !_loading)
            TextButton(
              onPressed: _skipToEnd,
              child: Text('Skip to End', style: TextStyle(color: scheme.textMuted, fontSize: 11)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProgressBar(scheme),
                  const SizedBox(height: 24),
                  _buildCurrentStep(scheme),
                ],
              ),
            ),
    );
  }

  Widget _buildProgressBar(AppColorScheme scheme) {
    final steps = [SetupStep.detect, SetupStep.install, SetupStep.configure, SetupStep.test, SetupStep.done];
    final labels = ['Detect', 'Install', 'Configure', 'Test', 'Ready'];
    final icons = [Icons.search, Icons.download, Icons.tune, Icons.sensors, Icons.check_circle];

    final currentIdx = steps.indexOf(_currentStep);

    return Row(
      children: List.generate(steps.length, (i) {
        final isPast = i < currentIdx;
        final isCurrent = i == currentIdx;
        final color = isPast ? scheme.success : (isCurrent ? scheme.primary : scheme.textMuted);

        return Expanded(
          child: Column(
            children: [
              Row(
                children: [
                  if (i > 0)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: isPast ? scheme.success : scheme.borderDim.withValues(alpha: 0.3),
                      ),
                    ),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isPast ? scheme.success : (isCurrent ? scheme.primary.withValues(alpha: 0.15) : scheme.surfaceAlt),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isPast ? scheme.success : (isCurrent ? scheme.primary : scheme.borderDim),
                        width: isCurrent ? 2 : 1,
                      ),
                    ),
                    child: Center(
                      child: isPast
                          ? Icon(Icons.check, size: 14, color: scheme.surface)
                          : Icon(icons[i], size: 12, color: color),
                    ),
                  ),
                  if (i < steps.length - 1)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: isPast ? scheme.success : scheme.borderDim.withValues(alpha: 0.3),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                labels[i],
                style: TextStyle(
                  color: isPast || isCurrent ? scheme.text : scheme.textMuted,
                  fontSize: 9,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildCurrentStep(AppColorScheme scheme) {
    switch (_currentStep) {
      case SetupStep.detect:
        return _buildStepDetect(scheme);
      case SetupStep.install:
        return _buildStepInstall(scheme);
      case SetupStep.configure:
        return _buildStepConfigure(scheme);
      case SetupStep.test:
        return _buildStepTest(scheme);
      case SetupStep.done:
        return _buildStepDone(scheme);
    }
  }

  // ── Step: Detect ───────────────────────────────────────────────────

  Widget _buildStepDetect(AppColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SYSTEM CHECK', style: TextStyle(color: scheme.textMuted, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
        const SizedBox(height: 6),
        Text('Hermes Wingman is checking your system.', style: TextStyle(color: scheme.textDim, fontSize: 14)),
        const SizedBox(height: 24),

        _detectTile(scheme, 'Hermes Agent', _hermesInstalled,
            subtitle: _hermesInstalled
                ? 'Found at ${_hermesBin ?? "PATH"}'
                : 'Not installed'),
        const SizedBox(height: 8),
        _detectTile(scheme, 'Configuration', _configExists,
            subtitle: _configExists ? 'config.yaml exists' : 'No config yet'),
        const SizedBox(height: 8),
        _detectTile(scheme, 'API Keys', _hasApiKeys,
            subtitle: _hasApiKeys ? 'Providers configured' : 'No API keys found'),
        const SizedBox(height: 8),
        _detectTile(scheme, 'Default Model', _modelConfigured,
            subtitle: _modelConfigured ? 'Model is set' : 'No default model'),
        const SizedBox(height: 8),
        _detectTile(scheme, 'Gateway', _connectedPlatforms.isNotEmpty,
            subtitle: _connectedPlatforms.isNotEmpty
                ? 'Connected: ${_connectedPlatforms.join(", ")}'
                : 'No platforms connected'),

        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.surface,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _nextStep,
            child: Text(_hermesInstalled ? 'Continue to Configure' : 'Continue to Install'),
          ),
        ),
      ],
    );
  }

  Widget _detectTile(AppColorScheme scheme, String label, bool checked, {String subtitle = ''}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.cardBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: checked ? scheme.success.withValues(alpha: 0.3) : scheme.borderDim,
          width: checked ? 1 : 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 20, height: 20,
            decoration: BoxDecoration(
              color: checked ? scheme.success : scheme.surfaceAlt,
              shape: BoxShape.circle,
              border: Border.all(color: checked ? scheme.success : scheme.borderDim),
            ),
            child: Center(
              child: checked
                  ? Icon(Icons.check, size: 12, color: scheme.surface)
                  : Icon(Icons.close, size: 12, color: scheme.textMuted),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: scheme.text, fontSize: 12, fontWeight: FontWeight.w500)),
                if (subtitle.isNotEmpty)
                  Text(subtitle, style: TextStyle(color: scheme.textMuted, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Step: Install ──────────────────────────────────────────────────

  Widget _buildStepInstall(AppColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('INSTALL HERMES AGENT', style: TextStyle(color: scheme.textMuted, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
        const SizedBox(height: 6),
        Text('Hermes Agent is not installed on this system.', style: TextStyle(color: scheme.textDim, fontSize: 14)),
        const SizedBox(height: 24),

        if (!_installDone)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.surface,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _installing ? null : _runInstall,
              icon: _installing
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.surface))
                  : Icon(Icons.download, size: 18),
              label: Text(_installing ? 'Installing...' : 'Install Hermes Agent'),
            ),
          ),

        if (_installOutput.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 300),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _installSuccess ? scheme.success.withValues(alpha: 0.08) : scheme.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _installSuccess ? scheme.success.withValues(alpha: 0.3) : scheme.error.withValues(alpha: 0.3),
              ),
            ),
            child: SingleChildScrollView(
              child: Text(
                _installOutput,
                style: TextStyle(
                  color: _installSuccess ? scheme.success : scheme.error,
                  fontSize: 11,
                  fontFamily: 'monospace',
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],

        if (_installDone) ...[
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _installSuccess ? scheme.success : scheme.primary,
                foregroundColor: scheme.surface,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _installSuccess ? _nextStep : null,
              child: Text(_installSuccess ? 'Installation Complete — Next' : 'Fix the issue above, then retry'),
            ),
          ),
          if (!_installSuccess)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton(
                onPressed: _runInstall,
                child: Text('Retry Installation', style: TextStyle(color: scheme.textDim, fontSize: 11)),
              ),
            ),
        ],
      ],
    );
  }

  // ── Step: Configure ────────────────────────────────────────────────

  Widget _buildStepConfigure(AppColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('AUTO-CONFIGURE', style: TextStyle(color: scheme.textMuted, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
        const SizedBox(height: 6),
        Text('Wingman will scan your system for running services and API keys.', style: TextStyle(color: scheme.textDim, fontSize: 14)),
        const SizedBox(height: 24),

        if (!_configDone)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.surface,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _configuring ? null : _runConfigure,
              icon: _configuring
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.surface))
                  : Icon(Icons.auto_fix_high, size: 18),
              label: Text(_configuring ? 'Scanning...' : 'Auto-Configure'),
            ),
          ),

        if (_configOutput.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 300),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _configSuccess ? scheme.success.withValues(alpha: 0.08) : scheme.surfaceAlt,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _configSuccess ? scheme.success.withValues(alpha: 0.3) : scheme.borderDim,
              ),
            ),
            child: SingleChildScrollView(
              child: Text(
                _configOutput,
                style: TextStyle(
                  color: _configSuccess ? scheme.text : scheme.textDim,
                  fontSize: 11,
                  fontFamily: 'monospace',
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],

        if (!_configDone && _configOutput.isEmpty && !_configuring) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceAlt,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: scheme.borderDim),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: scheme.textDim),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Or configure manually in the Config tab',
                    style: TextStyle(color: scheme.textDim, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],

        if (_configDone) ...[
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.surface,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _nextStep,
              child: const Text('Continue to Test'),
            ),
          ),
        ],
      ],
    );
  }

  // ── Step: Test ─────────────────────────────────────────────────────

  Widget _buildStepTest(AppColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('TEST CONNECTION', style: TextStyle(color: scheme.textMuted, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
        const SizedBox(height: 6),
        Text('Let\'s verify your model works by sending a test request.', style: TextStyle(color: scheme.textDim, fontSize: 14)),
        const SizedBox(height: 24),

        if (_testResult == null)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.surface,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _testing ? null : _runTest,
              icon: _testing
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.surface))
                  : Icon(Icons.sensors, size: 18),
              label: Text(_testing ? 'Testing...' : 'Test Connection'),
            ),
          ),

        if (_testResult != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _testSuccess ? scheme.success.withValues(alpha: 0.1) : scheme.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _testSuccess ? scheme.success.withValues(alpha: 0.4) : scheme.warning.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _testSuccess ? Icons.check_circle : Icons.warning_amber_rounded,
                  size: 24,
                  color: _testSuccess ? scheme.success : scheme.warning,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _testResult!,
                    style: TextStyle(color: _testSuccess ? scheme.success : scheme.warning, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.surface,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _nextStep,
              child: const Text('Continue'),
            ),
          ),
        ],
      ],
    );
  }

  // ── Step: Done ─────────────────────────────────────────────────────

  Widget _buildStepDone(AppColorScheme scheme) {
    final allGood = _hermesInstalled && _configExists && (_modelConfigured || _configDone);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 24),
        Center(
          child: Icon(
            allGood ? Icons.check_circle : Icons.rocket_launch,
            size: 64,
            color: allGood ? scheme.success : scheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            allGood ? 'You\'re All Set!' : 'Setup Incomplete',
            style: TextStyle(color: allGood ? scheme.success : scheme.text, fontSize: 24, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            allGood
                ? 'Hermes Wingman is ready to go.'
                : 'Some steps were skipped — you can configure things in the other tabs.',
            style: TextStyle(color: scheme.textDim, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 32),

        // Summary cards
        _summaryTile(scheme, 'Hermes Agent', _hermesInstalled, Icons.check, Icons.close),
        const SizedBox(height: 6),
        _summaryTile(scheme, 'Configuration', _configExists || _configDone, Icons.check, Icons.close),
        const SizedBox(height: 6),
        _summaryTile(scheme, 'API Keys', _hasApiKeys, Icons.check, Icons.close),
        const SizedBox(height: 6),
        _summaryTile(scheme, 'Default Model', _modelConfigured || _configDone,
            Icons.check, Icons.close,
            detail: _defaultModel.isNotEmpty ? _defaultModel : null),
        const SizedBox(height: 6),
        _summaryTile(scheme, 'Connection Test', _testSuccess,
            Icons.check, Icons.warning_amber_rounded),
        const SizedBox(height: 32),

        // Quick links
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.cardBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.borderDim, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('QUICK LINKS', style: TextStyle(color: scheme.textMuted, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
              const SizedBox(height: 12),
              _linkRow(scheme, Icons.chat, 'Start Chatting', 1),
              const SizedBox(height: 6),
              _linkRow(scheme, Icons.memory_outlined, 'Browse Models', 2),
              const SizedBox(height: 6),
              _linkRow(scheme, Icons.settings_outlined, 'Edit Config', 4),
              const SizedBox(height: 6),
              _linkRow(scheme, Icons.hub_outlined, 'Gateways', 7),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryTile(AppColorScheme scheme, String label, bool checked, IconData goodIcon, IconData badIcon, {String? detail}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.cardBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: checked ? scheme.success.withValues(alpha: 0.3) : scheme.borderDim,
          width: checked ? 1 : 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(checked ? goodIcon : badIcon, size: 16, color: checked ? scheme.success : scheme.warning),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: scheme.text, fontSize: 12)),
          if (detail != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(detail, style: TextStyle(color: scheme.textMuted, fontSize: 10, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis),
            ),
          ],
        ],
      ),
    );
  }

  Widget _linkRow(AppColorScheme scheme, IconData icon, String label, int tabIndex) {
    return InkWell(
      onTap: () => widget.onNavigate?.call(tabIndex),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 14, color: scheme.primary),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: scheme.primary, fontSize: 12)),
            const Spacer(),
            Icon(Icons.chevron_right, size: 14, color: scheme.textMuted),
          ],
        ),
      ),
    );
  }
}
