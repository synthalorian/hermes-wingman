import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_manager.dart';
import '../../theme/app_theme.dart';
import '../../services/hermes_service.dart';
import '../../services/hermes_api_client.dart' show BackendService;

/// Persistent model favorites stored in ~/.hermes/wingman_models.json
class ModelStore {
  static Future<String> get _path async {
    final home = Platform.environment['HOME'] ?? '/home/synth';
    return '$home/.hermes/wingman_models.json';
  }

  static Future<List<String>> loadFavorites() async {
    try {
      final file = File(await _path);
      if (!await file.exists()) return [];
      final json = jsonDecode(await file.readAsString());
      if (json is Map && json['favorites'] is List) {
        return (json['favorites'] as List).cast<String>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveFavorites(List<String> favorites) async {
    try {
      final path = await _path;
      final dir = File(path).parent;
      if (!await dir.exists()) await dir.create(recursive: true);
      await File(path).writeAsString(jsonEncode({
        'favorites': favorites.take(5).toList(),
        'updated_at': DateTime.now().toIso8601String(),
      }));
    } catch (_) {}
  }

  static Future<void> toggleFavorite(String model) async {
    final favs = await loadFavorites();
    if (favs.contains(model)) {
      favs.remove(model);
    } else {
      favs.add(model);
      if (favs.length > 5) favs.removeAt(0);
    }
    await saveFavorites(favs);
  }
}

class ModelsScreen extends StatefulWidget {
  const ModelsScreen({super.key});

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  // Raw data from backend
  List<Map<String, dynamic>> _localModels = [];
  List<Map<String, dynamic>> _cloudModels = [];
  List<String> _fallbackModels = [];
  String _currentModel = '';
  String _currentProvider = '';
  List<String> _favorites = [];
  Map<String, String> _probedStatus = {}; // model -> ok/error
  bool _loading = true;
  bool _probing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  Future<void> _loadModels() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final service = context.read<HermesService>();

      if (service is BackendService) {
        // Use API
        final data = await service.httpGet('/models');
        final local = (data['local'] as List? ?? []);
        final cloud = (data['cloud'] as List? ?? []);
        final fallback = (data['fallback'] as List? ?? []).cast<String>();

        // Load probed status from wingman_probed.json
        final home = Platform.environment['HOME']
            ?? Platform.environment['USERPROFILE']
            ?? '/tmp';
        final probedFile = File('$home/.hermes/wingman_probed.json');
        Map<String, String> probed = {};
        if (await probedFile.exists()) {
          try {
            final probedData = jsonDecode(await probedFile.readAsString()) as Map;
            for (final entry in probedData.entries) {
              if (entry.value is Map) {
                probed[entry.key.toString()] = (entry.value as Map)['status']?.toString() ?? '';
              }
            }
          } catch (_) {}
        }

        final status = await service.httpGet('/health');
        // Also try to read models endpoint again for current model
        final modelsData = data;

        if (!mounted) return;
        setState(() {
          _localModels = local.cast<Map<String, dynamic>>();
          _cloudModels = cloud.cast<Map<String, dynamic>>();
          _fallbackModels = fallback;
          _currentModel = modelsData['current'] as String? ?? status['model'] as String? ?? '';
          _currentProvider = modelsData['provider'] as String? ?? '';
          _probedStatus = probed;
          _loading = false;
        });

        // Auto-probe current model after load
        if (_currentModel.isNotEmpty) {
          _probeModel(_currentModel);
        }
      } else {
        // Fallback: CLI-based parsing
        await _fallbackLoadModels(service);
      }

      // Load favorites
      final favs = await ModelStore.loadFavorites();
      if (mounted) setState(() => _favorites = favs);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _fallbackLoadModels(HermesService service) async {
    final status = await service.getStatus();
    final config = await service.getConfigRaw();

    final fallbackModels = <String>[];
    for (final line in config.split('\n')) {
      final t = line.trim();
      if (t.startsWith('- ')) fallbackModels.add(t.substring(2).trim());
    }

    // Local models from llama-swap
    final local = <Map<String, dynamic>>[];
    try {
      final result = await Process.run('curl', ['-s', 'http://127.0.0.1:8080/v1/models']);
      if (result.exitCode == 0) {
        final body = jsonDecode(result.stdout as String);
        for (final m in (body['data'] as List? ?? [])) {
          local.add({
            'name': 'llama-swap/${m['id']}',
            'source': 'local',
            'provider_name': 'llama-swap',
          });
        }
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _localModels = local;
      _fallbackModels = fallbackModels;
      _currentModel = status.model;
      _currentProvider = status.provider;
      _cloudModels = [];
    });
  }

  /// Probe a single model and update status
  Future<void> _probeModel(String model) async {
    try {
      final service = context.read<HermesService>();
      if (service is BackendService) {
        final result = await service.httpPost('/models/probe', {'model': model});
        final status = result['status'] as String? ?? 'error';
        if (mounted) {
          setState(() {
            _probedStatus[model] = status;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _probeAllModels() async {
    setState(() => _probing = true);
    final allModels = [..._localModels, ..._cloudModels];
    Map<String, String> results = {};

    for (final model in allModels) {
      final name = model['name'] as String;
      try {
        final service = context.read<HermesService>();
        if (service is BackendService) {
          final result = await service.httpPost('/models/probe', {'model': name});
          results[name] = result['status'] as String? ?? 'error';
        } else {
          // CLI fallback — no easy way to probe
          results[name] = 'unknown';
        }
      } catch (_) {
        results[name] = 'error';
      }
      // Update progressively
      if (mounted) setState(() => _probedStatus = Map.from(results));
    }

    if (mounted) setState(() => _probing = false);
  }

  Future<void> _switchModel(String model) async {
    try {
      final service = context.read<HermesService>();
      if (service is BackendService) {
        await service.httpPost('/models/switch', {'model': model});
      } else {
        await service.setConfigValue('model', model);
      }
      setState(() => _currentModel = model);
      if (mounted) {
        final scheme = context.read<ThemeManager>().currentScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Switched to $model', style: TextStyle(color: scheme.text, fontSize: 12)),
            duration: const Duration(seconds: 2),
            backgroundColor: scheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: scheme.primary.withValues(alpha: 0.4), width: 0.5),
            ),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(12),
          ),
        );
      }
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) _loadModels();
    } catch (e) {
      if (mounted) {
        final scheme = context.read<ThemeManager>().currentScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e', style: TextStyle(color: scheme.error, fontSize: 12)),
            backgroundColor: scheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: scheme.error.withValues(alpha: 0.4), width: 0.5),
            ),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(12),
          ),
        );
      }
    }
  }

  Future<void> _toggleFavorite(String model) async {
    await ModelStore.toggleFavorite(model);
    final favs = await ModelStore.loadFavorites();
    if (mounted) setState(() => _favorites = favs);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.watch<ThemeManager>().currentScheme;

    return Scaffold(
      backgroundColor: scheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('Models'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sensors_outlined, size: 18),
            onPressed: _probing ? null : _probeAllModels,
            tooltip: 'Probe all models',
            color: _probing ? scheme.textMuted : scheme.textDim,
          ),
          IconButton(
            icon: Icon(Icons.refresh, size: 18, color: scheme.textDim),
            onPressed: _loadModels,
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
              Icon(Icons.error_outline, size: 48, color: scheme.error.withValues(alpha: 0.6)),
              const SizedBox(height: 16),
              Text('Could not load models', style: TextStyle(color: scheme.textDim, fontSize: 16)),
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: scheme.textMuted, fontSize: 12, fontFamily: 'monospace'), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              MaterialButton(color: scheme.primary.withValues(alpha: 0.15), onPressed: _loadModels, child: Text('Retry', style: TextStyle(color: scheme.primary))),
            ],
          ),
        ),
      );
    }

    final allModels = [..._localModels, ..._cloudModels];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current model card
          _buildCurrentModelCard(scheme),
          const SizedBox(height: 24),

          // Probing indicator
          if (_probing)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: scheme.surfaceAlt, borderRadius: BorderRadius.circular(6)),
              child: Row(
                children: [
                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary)),
                  const SizedBox(width: 10),
                  Text('Probing models...', style: TextStyle(color: scheme.textDim, fontSize: 11)),
                  const Spacer(),
                  Text('${_probedStatus.length}/${allModels.length}', style: TextStyle(color: scheme.textMuted, fontSize: 11, fontFamily: 'monospace')),
                ],
              ),
            ),

          // Favorites
          if (_favorites.isNotEmpty) ...[
            _sectionHeader(scheme, 'TOP 5 FAVORITES'),
            const SizedBox(height: 8),
            ..._favorites.map((m) => _buildModelRow(scheme, m, allModels)),
            const SizedBox(height: 24),
          ],

          // Local models (synthclaw from llama-swap)
          if (_localModels.isNotEmpty) ...[
            _sectionHeader(scheme, '🎹🦞 SYNTHCLAW  (${_localModels.length})'),
            const SizedBox(height: 8),
            ...List.generate(_localModels.length, (i) {
              final m = _localModels[i];
              final name = m['name'] as String? ?? '';
              final source = m['source'] as String? ?? 'local';
              final sublabel = source == 'fallback' ? 'fallback' : (m['provider_name'] as String? ?? '');
              return _buildModelRow(scheme, name, allModels, sublabel: sublabel);
            }),
            const SizedBox(height: 24),
          ],

          // Cloud models grouped by provider
          if (_cloudModels.isNotEmpty) ...[
            _sectionHeader(scheme, 'CLOUD MODELS (${_cloudModels.length})'),
            const SizedBox(height: 8),
            if (_cloudModels.any((m) => m['source'] == 'configured')) ...[
              Text('CONFIGURED PROVIDERS', style: TextStyle(color: scheme.success, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 1)),
              const SizedBox(height: 4),
              ..._buildCloudGroups(scheme, onlyConfigured: true),
              const SizedBox(height: 12),
            ],
            if (_cloudModels.any((m) => m['source'] == 'available')) ...[
              Text('AVAILABLE (add provider)', style: TextStyle(color: scheme.textMuted, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 1)),
              const SizedBox(height: 4),
              ..._buildCloudGroups(scheme, onlyConfigured: false),
            ],
            const SizedBox(height: 24),
          ],

          // Provider info
          _sectionHeader(scheme, 'ACTIVE PROVIDER'),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: scheme.cardBackground, borderRadius: BorderRadius.circular(6), border: Border.all(color: scheme.borderDim, width: 0.5)),
            child: Text(_currentProvider, style: TextStyle(color: scheme.textDim, fontSize: 12, fontFamily: 'monospace')),
          ),
          if (_fallbackModels.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Fallback chain: ${_fallbackModels.join(' → ')}', style: TextStyle(color: scheme.textMuted, fontSize: 10, fontFamily: 'monospace', fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 16),
          // CLI hint
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: scheme.surfaceAlt, borderRadius: BorderRadius.circular(6), border: Border.all(color: scheme.borderDim, width: 0.5)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.terminal, size: 12, color: scheme.textDim),
                  const SizedBox(width: 6),
                  Text('TERMINAL USAGE', style: TextStyle(color: scheme.textMuted, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
                ]),
                const SizedBox(height: 8),
                Text('hermes -m ${_currentModel.isNotEmpty ? _currentModel : "<model>"} "your prompt"', style: TextStyle(color: scheme.primary, fontSize: 10, fontFamily: 'monospace')),
                const SizedBox(height: 4),
                Text('hermes chat --model ${_currentModel.isNotEmpty ? _currentModel : "<model>"}', style: TextStyle(color: scheme.textDim, fontSize: 10, fontFamily: 'monospace')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelRow(AppColorScheme scheme, String name, List<Map<String, dynamic>> allModels, {String? sublabel}) {
    final isActive = name == _currentModel;
    final isFavorite = _favorites.contains(name);
    final modelEntry = allModels.cast<Map<String, dynamic>?>().firstWhere((m) => m?['name'] == name, orElse: () => null);
    final source = modelEntry?['source'] as String? ?? '';
    final isLocal = _localModels.any((m) => m['name'] == name);
    final isConfigured = source == 'configured';
    final isAvailable = source == 'available';
    final probedStatus = _probedStatus[name];

    // Detect synthclaw models by name
    final isSynthclaw = name.contains('synthclaw');
    final isSynthclawLocal = isSynthclaw && isLocal;

    // Determine dot color
    Color dotColor;
    if (isSynthclawLocal) {
      dotColor = const Color(0xFFFF00FF); // hot pink — synthclaw signature
    } else if (isLocal) {
      dotColor = scheme.primary;
    } else if (isConfigured) {
      dotColor = scheme.success;
    } else if (isAvailable) {
      dotColor = scheme.warning;
    } else if (probedStatus == 'ok') {
      dotColor = scheme.success;
    } else if (probedStatus == 'error') {
      dotColor = scheme.error;
    } else {
      dotColor = scheme.textMuted;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: isActive ? scheme.primary.withValues(alpha: 0.06) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _switchModel(name),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isActive ? scheme.primary.withValues(alpha: 0.3) : scheme.borderDim.withValues(alpha: 0.2),
                width: isActive ? 1 : 0.5,
              ),
            ),
            child: Row(
              children: [
                // Source status indicator
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    boxShadow: isSynthclawLocal
                        ? [BoxShadow(color: const Color(0xFFFF00FF).withValues(alpha: 0.6), blurRadius: 4)]
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(name, style: TextStyle(
                              color: isActive ? scheme.primary : scheme.text,
                              fontSize: 12,
                              fontFamily: 'monospace',
                              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                            )),
                          ),
                          if (isSynthclawLocal) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [Color(0xFF8F00FF), Color(0xFFFF00FF)]),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text('🎹🦞', style: TextStyle(fontSize: 8, height: 1.2)),
                            ),
                          ],
                        ],
                      ),
                      if (sublabel != null && sublabel.isNotEmpty)
                        Text(sublabel, style: TextStyle(color: scheme.textMuted, fontSize: 9, fontFamily: 'monospace')),
                    ],
                  ),
                ),
                // Probe badge
                if (probedStatus != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: probedStatus == 'ok' ? scheme.success.withValues(alpha: 0.1) : scheme.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      probedStatus == 'ok' ? 'OK' : 'ERR',
                      style: TextStyle(color: probedStatus == 'ok' ? scheme.success : scheme.error, fontSize: 7, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                // Favorite star
                InkWell(
                  onTap: () => _toggleFavorite(name),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(isFavorite ? Icons.star : Icons.star_border, size: 14, color: isFavorite ? scheme.warning : scheme.textMuted),
                  ),
                ),
                if (isActive) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: scheme.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                    child: Text('ACTIVE', style: TextStyle(color: scheme.success, fontSize: 8, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCloudGroups(AppColorScheme scheme, {bool onlyConfigured = false}) {
    final providerLabels = <String, String>{
      'xai-oauth': 'xAI Grok',
      'xai': 'xAI Grok',
      'x-ai': 'xAI Grok',
      'gemini': 'Google Gemini',
      'google': 'Google Gemini',
      'anthropic': 'Anthropic Claude',
      'openai': 'OpenAI',
      'deepseek': 'DeepSeek',
      'nous': 'Nous Research',
      'meta-llama': 'Meta Llama',
      'mistral': 'Mistral',
      'qwen': 'Qwen',
    };

    final groups = <String, List<Map<String, dynamic>>>{};
    for (final m in _cloudModels) {
      final prov = m['provider_name'] as String? ?? 'other';
      final source = m['source'] as String? ?? 'available';
      // Filter by configured/available
      if (onlyConfigured && source != 'configured') continue;
      if (!onlyConfigured && source == 'configured') continue;
      groups.putIfAbsent(prov, () => []).add(m);
    }

    return groups.entries.map((entry) {
      final label = providerLabels[entry.key] ?? entry.key;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: scheme.textDim, fontSize: 11, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            ...entry.value.map((m) {
              final name = m['name'] as String? ?? '';
              return _buildModelRow(scheme, name, _cloudModels);
            }),
          ],
        ),
      );
    }).toList();
  }

  Widget _sectionHeader(AppColorScheme scheme, String title) {
    return Text(title, style: TextStyle(color: scheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.5));
  }

  Widget _buildCurrentModelCard(AppColorScheme scheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.4), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: scheme.success,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: scheme.success.withValues(alpha: 0.5), blurRadius: 6)],
                ),
              ),
              const SizedBox(width: 8),
              Text('ACTIVE MODEL', style: TextStyle(color: scheme.textMuted, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1)),
              const Spacer(),
              Text('${_localModels.length + _cloudModels.length} available', style: TextStyle(color: scheme.textMuted, fontSize: 10, fontFamily: 'monospace')),
            ],
          ),
          const SizedBox(height: 12),
          Text(_currentModel.isNotEmpty ? _currentModel : '(none selected)', style: TextStyle(color: scheme.primary, fontSize: 18, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
          const SizedBox(height: 4),
          Text(_currentProvider.isNotEmpty ? _currentProvider : '', style: TextStyle(color: scheme.textDim, fontSize: 12, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}
