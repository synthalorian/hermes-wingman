import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_manager.dart';
import '../../theme/app_theme.dart';
import '../../services/hermes_service.dart';
import '../../services/hermes_api_client.dart';
import '../../models/hermes_models.dart';

class GatewayScreen extends StatefulWidget {
  const GatewayScreen({super.key});

  @override
  State<GatewayScreen> createState() => _GatewayScreenState();
}

class _GatewayScreenState extends State<GatewayScreen> {
  List<GatewayPlatform> _platforms = [];
  bool _loading = true;
  bool _serviceRunning = false;
  bool _toggling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadGateways();
  }

  Future<void> _loadGateways() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = context.read<HermesService>();

      // Use the raw gateway API via HTTP if available
      if (client is BackendService) {
        final data = await client.httpGet('/gateway');
        final platforms = (data['platforms'] as List? ?? []).map((p) {
          final m = p as Map<String, dynamic>;
          return GatewayPlatform(
            name: m['name'] ?? '',
            isConnected: m['isConnected'] == true || m['state'] == 'connected',
            icon: _platformIcon(m['name'] ?? ''),
          );
        }).toList();

        if (!mounted) return;
        setState(() {
          _platforms = platforms;
          _serviceRunning = data['running'] == true;
          _loading = false;
        });
      } else {
        // Fallback to CLI-based
        final platforms = await client.getGatewayStatus();
        if (!mounted) return;
        setState(() {
          _platforms = platforms;
          _serviceRunning = platforms.isNotEmpty;
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _platformIcon(String name) {
    switch (name) {
      case 'discord': return '💬';
      case 'telegram': return '✈️';
      case 'slack': return '🔲';
      case 'whatsapp': return '📱';
      case 'signal': return '🔒';
      case 'email': return '📧';
      case 'sms': return '💭';
      case 'homeassistant': return '🏠';
      default: return '🔌';
    }
  }

  Future<void> _toggleService() async {
    setState(() => _toggling = true);

    try {
      final client = context.read<HermesService>();

      if (client is BackendService) {
        // Use API toggle endpoint
        final action = _serviceRunning ? 'stop' : 'start';
        final result = await client.gatewayToggle(action);
        // Immediately update local state from the API response
        if (result['success'] == true) {
          setState(() => _serviceRunning = result['running'] == true);
        } else {
          throw Exception(result['error'] ?? 'Toggle failed');
        }
        // Give state file time to update, then reload
        await Future.delayed(const Duration(milliseconds: 500));
        await _loadGateways();
      } else {
        // Fallback to CLI
        if (_serviceRunning) {
          await client.runHermesCommand(['gateway', 'stop']);
        } else {
          await client.runHermesCommand(['gateway', 'start']);
        }
        await Future.delayed(const Duration(seconds: 1));
        await _loadGateways();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to toggle gateway: $e'),
          backgroundColor: context.read<ThemeManager>().currentScheme.error.withValues(alpha: 0.2),
        ),
      );
    }

    if (mounted) setState(() => _toggling = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.watch<ThemeManager>().currentScheme;

    return Scaffold(
      backgroundColor: scheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('Gateway'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, size: 18, color: scheme.textDim),
            onPressed: _loadGateways,
            tooltip: 'Refresh',
          ),
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
              Text('Could not load gateway status', style: TextStyle(color: scheme.textDim, fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: scheme.textMuted, fontSize: 12, fontFamily: 'monospace'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              MaterialButton(
                color: scheme.primary.withValues(alpha: 0.15),
                onPressed: _loadGateways,
                child: Text('Retry', style: TextStyle(color: scheme.primary)),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Service status card — uses _serviceRunning directly from backend
          _buildServiceCard(scheme),
          const SizedBox(height: 24),

          // Connected platforms
          Text(
            'CONNECTED PLATFORMS',
            style: TextStyle(
              color: scheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),

          if (_platforms.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: scheme.cardBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.borderDim, width: 0.5),
              ),
              child: Column(
                children: [
                  Icon(Icons.hub_outlined, size: 32, color: scheme.textMuted),
                  const SizedBox(height: 12),
                  Text('No platforms configured', style: TextStyle(color: scheme.textDim, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(
                    'Run: hermes gateway setup',
                    style: TextStyle(color: scheme.textMuted, fontSize: 11, fontFamily: 'monospace'),
                  ),
                ],
              ),
            )
          else
            ...List.generate(_platforms.length, (i) {
              final p = _platforms[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.cardBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: p.isConnected
                          ? scheme.success.withValues(alpha: 0.4)
                          : scheme.borderDim,
                      width: p.isConnected ? 1 : 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Platform icon
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: p.isConnected
                              ? scheme.success.withValues(alpha: 0.08)
                              : scheme.error.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(p.icon, style: const TextStyle(fontSize: 20)),
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name[0].toUpperCase() + p.name.substring(1),
                              style: TextStyle(color: scheme.text, fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: p.isConnected ? scheme.success : scheme.error,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  p.isConnected ? 'Connected' : 'Disconnected',
                                  style: TextStyle(
                                    color: p.isConnected ? scheme.success : scheme.error,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: p.isConnected
                              ? scheme.success.withValues(alpha: 0.1)
                              : scheme.surfaceAlt,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: p.isConnected
                                ? scheme.success.withValues(alpha: 0.3)
                                : scheme.borderDim,
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          p.isConnected ? 'ONLINE' : 'OFFLINE',
                          style: TextStyle(
                            color: p.isConnected ? scheme.success : scheme.textMuted,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),

          const SizedBox(height: 24),

          // Setup hint
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceAlt,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: scheme.borderDim, width: 0.5),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: scheme.textDim),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Configure platforms with:  hermes gateway setup',
                    style: TextStyle(color: scheme.textDim, fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceCard(AppColorScheme scheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _serviceRunning ? scheme.success.withValues(alpha: 0.4) : scheme.warning.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Status indicator
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _serviceRunning
                  ? scheme.success.withValues(alpha: 0.1)
                  : scheme.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _serviceRunning ? Icons.check_circle_outline : Icons.cancel_outlined,
              color: _serviceRunning ? scheme.success : scheme.warning,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gateway Service',
                  style: TextStyle(color: scheme.text, fontWeight: FontWeight.w600, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _serviceRunning ? scheme.success : scheme.warning,
                        shape: BoxShape.circle,
                        boxShadow: _serviceRunning
                            ? [BoxShadow(color: scheme.success.withValues(alpha: 0.5), blurRadius: 6)]
                            : [],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _serviceRunning ? 'Running' : 'Stopped',
                      style: TextStyle(
                        color: _serviceRunning ? scheme.success : scheme.warning,
                        fontSize: 13,
                      ),
                    ),
                    if (_platforms.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Text(
                        '${_platforms.where((p) => p.isConnected).length} of ${_platforms.length} platforms online',
                        style: TextStyle(color: scheme.textMuted, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Master toggle
          _toggling
              ? SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: scheme.textMuted)),
                )
              : Switch(
                  value: _serviceRunning,
                  onChanged: (_) => _toggleService(),
                  activeThumbColor: scheme.primary,
                  inactiveThumbColor: scheme.textMuted,
                  inactiveTrackColor: scheme.borderDim,
                ),
        ],
      ),
    );
  }
}
