import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/theme_manager.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass_card.dart';
import '../../services/hermes_api_client.dart' show BackendService;

/// Provider definition.
class _ProviderDef {
  final String name;
  final String shortName;
  final IconData icon;
  final String description;
  final bool isOAuth;
  final String defaultModel;

  const _ProviderDef({
    required this.name,
    required this.shortName,
    required this.icon,
    required this.description,
    required this.isOAuth,
    this.defaultModel = '',
  });
}

const _allProviders = <_ProviderDef>[
  _ProviderDef(
    name: 'nous',
    shortName: 'Nous',
    icon: Icons.auto_awesome,
    description: 'Nous Research — OAuth login, recommended for Hermes',
    isOAuth: true,
  ),
  _ProviderDef(
    name: 'anthropic',
    shortName: 'Anthropic',
    icon: Icons.shield_outlined,
    description: 'Anthropic API key — Claude models',
    isOAuth: false,
    defaultModel: 'claude-sonnet-4',
  ),
  _ProviderDef(
    name: 'xai-oauth',
    shortName: 'xAI',
    icon: Icons.explore_outlined,
    description: 'xAI — OAuth login for Grok models',
    isOAuth: true,
  ),
  _ProviderDef(
    name: 'xai',
    shortName: 'xAI (API)',
    icon: Icons.vpn_key_outlined,
    description: 'xAI API key — Grok models via API key',
    isOAuth: false,
    defaultModel: 'grok-3',
  ),
  _ProviderDef(
    name: 'gemini',
    shortName: 'Google Gemini',
    icon: Icons.workspace_premium_outlined,
    description: 'Google Gemini API key',
    isOAuth: false,
    defaultModel: 'gemini-2.0-flash',
  ),
  _ProviderDef(
    name: 'openrouter',
    shortName: 'OpenRouter',
    icon: Icons.hub_outlined,
    description: 'OpenRouter API key — multi-model access',
    isOAuth: false,
    defaultModel: 'openrouter/auto',
  ),
  _ProviderDef(
    name: 'deepseek',
    shortName: 'DeepSeek',
    icon: Icons.psychology_outlined,
    description: 'DeepSeek API key',
    isOAuth: false,
    defaultModel: 'deepseek-chat',
  ),
  _ProviderDef(
    name: 'openai-codex',
    shortName: 'OpenAI Codex',
    icon: Icons.code,
    description: 'OpenAI Codex — OAuth login for code generation',
    isOAuth: true,
  ),
  _ProviderDef(
    name: 'zai',
    shortName: 'ZAI',
    icon: Icons.bolt,
    description: 'ZAI API key',
    isOAuth: false,
    defaultModel: 'zai/auto',
  ),
];

/// Providers screen — manage all AI provider credentials.
class ProvidersScreen extends StatefulWidget {
  const ProvidersScreen({super.key});

  @override
  State<ProvidersScreen> createState() => _ProvidersScreenState();
}

class _ProvidersScreenState extends State<ProvidersScreen> {
  Map<String, String> _providerStatuses = {};
  bool _loading = true;
  String? _authingProvider; // provider currently being authenticated
  StreamSubscription<dynamic>? _authPollSub;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _authPollSub?.cancel();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    setState(() => _loading = true);
    try {
      final backend = context.read<BackendService>();
      final data = await backend.getAuthStatus();
      if (!mounted) return;
      final providers = data['providers'] as List? ?? [];
      final statuses = <String, String>{};
      for (final p in providers) {
        if (p is Map) {
          statuses[p['name'] as String? ?? ''] = p['status'] as String? ?? 'not_logged_in';
        }
      }
      setState(() {
        _providerStatuses = statuses;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleLogin(_ProviderDef provider) async {
    if (_authingProvider != null) return;

    if (provider.isOAuth) {
      await _startOAuthLogin(provider);
    } else {
      await _showApiKeyDialog(provider);
    }
  }

  Future<void> _startOAuthLogin(_ProviderDef provider) async {
    setState(() => _authingProvider = provider.name);

    try {
      final backend = context.read<BackendService>();
      final result = await backend.loginOAuth(provider.name);

      if (!mounted) return;

      final status = result['status'] as String? ?? '';

      if (status == 'already_logged_in' || status == 'logged_in') {
        _showSnack('${provider.shortName}: Already authenticated!');
        await _loadStatus();
        setState(() => _authingProvider = null);
        return;
      }

      final url = result['url'] as String?;
      if (url != null && url.isNotEmpty) {
        // Open the auth URL in the browser
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }

        // Show "waiting for auth" dialog
        if (!mounted) return;
        _showAuthWaitingDialog(provider, backend);
      } else {
        _showSnack('${provider.shortName}: Could not get auth URL. Check stderr for details.',
            isError: true);
        setState(() => _authingProvider = null);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Error: $e', isError: true);
        setState(() => _authingProvider = null);
      }
    }
  }

  void _showAuthWaitingDialog(_ProviderDef provider, BackendService backend) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return _AuthWaitingDialog(
          provider: provider,
          backend: backend,
          onDone: () {
            _loadStatus();
            if (mounted) setState(() => _authingProvider = null);
          },
        );
      },
    );
  }

  Future<void> _showApiKeyDialog(_ProviderDef provider) async {
    final scheme = context.read<ThemeManager>().currentScheme;
    final keyCtrl = TextEditingController();
    final modelCtrl = TextEditingController(
      text: provider.defaultModel,
    );

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: scheme.surface.withAlpha(235),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.borderDim.withAlpha(60), width: 0.5),
        ),
        title: Text('${provider.shortName} API Key',
            style: TextStyle(color: scheme.text, fontSize: 15)),
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
                  filled: true,
                  fillColor: scheme.background,
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: scheme.borderDim),
                    borderRadius: BorderRadius.circular(6),
                  ),
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
                  filled: true,
                  fillColor: scheme.background,
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: scheme.borderDim),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: scheme.textDim)),
          ),
          TextButton(
            onPressed: () async {
              if (keyCtrl.text.trim().isEmpty) return;
              try {
                final backend = context.read<BackendService>();
                final res = await backend.loginApiKey(provider.name, keyCtrl.text.trim());
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  if (res['success'] == true) {
                    _showSnack('${provider.shortName}: API key added!');
                    await _loadStatus();
                  } else {
                    _showSnack('${provider.shortName}: ${res['stderr'] ?? res['error'] ?? 'Failed'}',
                        isError: true);
                  }
                }
              } catch (e) {
                if (mounted) _showSnack('Error: $e', isError: true);
              }
            },
            child: Text('Add Provider',
                style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    keyCtrl.dispose();
    modelCtrl.dispose();
  }

  Future<void> _handleLogout(_ProviderDef provider) async {
    final scheme = context.read<ThemeManager>().currentScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: scheme.surface.withAlpha(235),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.borderDim.withAlpha(60), width: 0.5),
        ),
        title: Text('Logout ${provider.shortName}?',
            style: TextStyle(color: scheme.text, fontSize: 15)),
        content: Text('Remove authentication for ${provider.shortName}?',
            style: TextStyle(color: scheme.textDim, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: scheme.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Logout', style: TextStyle(color: scheme.error)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final backend = context.read<BackendService>();
      await backend.logoutProvider(provider.name);
      _showSnack('${provider.shortName}: Logged out');
      await _loadStatus();
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    final scheme = context.read<ThemeManager>().currentScheme;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: TextStyle(color: scheme.text, fontSize: 11)),
      backgroundColor: isError ? scheme.error.withAlpha(200) : scheme.surface,
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.watch<ThemeManager>().currentScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Providers',
            style: TextStyle(color: scheme.text, fontSize: 15)),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, size: 16, color: scheme.textMuted),
            onPressed: _loadStatus,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _allProviders.length,
              itemBuilder: (ctx, i) => _buildProviderCard(scheme, _allProviders[i]),
            ),
    );
  }

  Widget _buildProviderCard(AppColorScheme scheme, _ProviderDef provider) {
    final status = _providerStatuses[provider.name] ?? 'not_logged_in';
    final isLoggedIn = status == 'logged_in';
    final isAuthing = _authingProvider == provider.name;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        scheme: scheme,
        padding: EdgeInsets.zero,
        borderRadius: 10,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: isAuthing ? null : () => _handleLogin(provider),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Provider icon
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isLoggedIn
                          ? scheme.success.withAlpha(20)
                          : scheme.primary.withAlpha(15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: isAuthing
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: scheme.primary,
                              ),
                            )
                          : Icon(
                              provider.icon,
                              size: 18,
                              color: isLoggedIn ? scheme.success : scheme.primary,
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              provider.shortName,
                              style: TextStyle(
                                color: scheme.text,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 6),
                            _StatusBadge(scheme: scheme, status: status),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          provider.description,
                          style: TextStyle(
                            color: scheme.textMuted,
                            fontSize: 10,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Action button
                  if (isLoggedIn)
                    GestureDetector(
                      onTap: () => _handleLogout(provider),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: scheme.error.withAlpha(15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: scheme.error.withAlpha(30), width: 0.5),
                        ),
                        child: Text(
                          'Logout',
                          style: TextStyle(color: scheme.error, fontSize: 10),
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: scheme.primary.withAlpha(15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: scheme.primary.withAlpha(30), width: 0.5),
                      ),
                      child: Text(
                        provider.isOAuth ? 'OAuth Login' : 'Add Key',
                        style: TextStyle(color: scheme.primary, fontSize: 10),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Status badge showing logged_in / not_logged_in state.
class _StatusBadge extends StatelessWidget {
  final AppColorScheme scheme;
  final String status;

  const _StatusBadge({required this.scheme, required this.status});

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = status == 'logged_in';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isLoggedIn ? scheme.success.withAlpha(15) : scheme.textMuted.withAlpha(15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isLoggedIn ? '✓ Active' : '—',
        style: TextStyle(
          color: isLoggedIn ? scheme.success : scheme.textMuted,
          fontSize: 9,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Dialog shown while waiting for OAuth authentication to complete.
class _AuthWaitingDialog extends StatefulWidget {
  final _ProviderDef provider;
  final BackendService backend;
  final VoidCallback onDone;

  const _AuthWaitingDialog({
    required this.provider,
    required this.backend,
    required this.onDone,
  });

  @override
  State<_AuthWaitingDialog> createState() => _AuthWaitingDialogState();
}

class _AuthWaitingDialogState extends State<_AuthWaitingDialog> {
  Timer? _timer;
  int _elapsed = 0;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  void _startPolling() {
    _timer = Timer.periodic(const Duration(seconds: 2), (_) async {
      _elapsed += 2;
      if (_elapsed > 120) {
        // Timeout after 2 minutes
        _timer?.cancel();
        if (mounted) {
          Navigator.of(context).pop();
          widget.onDone();
        }
        return;
      }
      try {
        final data = await widget.backend.getAuthStatus();
        if (!mounted) return;
        final providers = data['providers'] as List? ?? [];
        for (final p in providers) {
          if (p is Map && p['name'] == widget.provider.name) {
            if (p['status'] == 'logged_in') {
              _timer?.cancel();
              Navigator.of(context).pop();
              widget.onDone();
              return;
            }
          }
        }
        if (mounted) setState(() {});
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.watch<ThemeManager>().currentScheme;
    return AlertDialog(
      backgroundColor: scheme.surface.withAlpha(235),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.borderDim.withAlpha(60), width: 0.5),
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Authenticating with ${widget.provider.shortName}',
              style: TextStyle(color: scheme.text, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'A browser window opened for authentication.\nComplete the login in your browser.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.textDim, fontSize: 11, height: 1.4),
            ),
            const SizedBox(height: 16),
            if (_elapsed > 10)
              Text(
                'Waiting... (${_elapsed}s)',
                style: TextStyle(color: scheme.textMuted, fontSize: 10),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                _timer?.cancel();
                Navigator.of(context).pop();
                widget.onDone();
              },
              child: Text('Cancel', style: TextStyle(color: scheme.textMuted, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }
}
