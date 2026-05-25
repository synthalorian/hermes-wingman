import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_manager.dart';
import '../../theme/app_theme.dart';
import '../../services/hermes_service.dart';

class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});
  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  List<Map<String, dynamic>> _profiles = [];
  bool _loading = true;

  String get _path => '${Platform.environment['HOME'] ?? '/tmp'}/.hermes/wingman_profiles.json';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _loading = true);
    try {
      final file = File(_path);
      if (file.existsSync()) {
        final data = jsonDecode(file.readAsStringSync()) as List;
        _profiles = data.cast<Map<String, dynamic>>();
      } else {
        _profiles = [];
      }
    } catch (_) {
      _profiles = [];
    }
    setState(() => _loading = false);
  }

  void _save() {
    try {
      final dir = Directory(_path).parent;
      if (!dir.existsSync()) dir.createSync(recursive: true);
      File(_path).writeAsStringSync(jsonEncode(_profiles));
    } catch (_) {}
  }

  Future<void> _saveCurrent() async {
    try {
      final service = context.read<HermesService>();
      final status = await service.getStatus();
      final config = await service.getConfigRaw();
      setState(() {
        _profiles.insert(0, {
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'name': 'Profile ${_profiles.length + 1}',
          'model': status.model,
          'provider': status.provider,
          'config': config,
          'created_at': DateTime.now().toIso8601String(),
        });
      });
      _save();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    }
  }

  Future<void> _applyProfile(int index) async {
    final profile = _profiles[index];
    try {
      final service = context.read<HermesService>();
      if (profile['config'] != null && profile['config'].toString().isNotEmpty) {
        await service.writeConfig(profile['config']);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Applied profile: ${profile['name']}'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Apply failed: $e')));
      }
    }
  }

  void _deleteProfile(int index) {
    _profiles.removeAt(index);
    _save();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.watch<ThemeManager>().currentScheme;

    return Scaffold(
      backgroundColor: scheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: scheme.appBarBackground,
        elevation: 0,
        title: Text('Profiles', style: TextStyle(color: scheme.text, fontSize: 15)),
        actions: [
          TextButton.icon(
            icon: Icon(Icons.save_outlined, size: 16, color: scheme.primary),
            label: Text('Save Current', style: TextStyle(color: scheme.primary, fontSize: 11)),
            onPressed: _saveCurrent,
          ),
          IconButton(icon: Icon(Icons.refresh, color: scheme.textMuted, size: 18), onPressed: _load),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: scheme.primary))
          : _profiles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_outline, size: 48, color: scheme.textMuted.withValues(alpha: 0.3)),
                      const SizedBox(height: 12),
                      Text('No profiles saved', style: TextStyle(color: scheme.textMuted, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text('Tap "Save Current" to save a profile', style: TextStyle(color: scheme.textMuted.withValues(alpha: 0.6), fontSize: 11)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _profiles.length,
                  itemBuilder: (ctx, i) {
                    final p = _profiles[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: scheme.borderDim),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.person, size: 16, color: scheme.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(p['name'] ?? '', style: TextStyle(color: scheme.text, fontSize: 13, fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
                            if ((p['model'] ?? '').isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Row(
                                  children: [
                                    Text('Model: ', style: TextStyle(color: scheme.textMuted, fontSize: 10)),
                                    Text(p['model'], style: TextStyle(color: scheme.accent, fontSize: 10, fontFamily: 'monospace')),
                                    if ((p['provider'] ?? '').isNotEmpty) ...[
                                      Text(' via ', style: TextStyle(color: scheme.textMuted, fontSize: 10)),
                                      Text(p['provider'], style: TextStyle(color: scheme.primary, fontSize: 10, fontFamily: 'monospace')),
                                    ],
                                  ],
                                ),
                              ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                TextButton.icon(
                                  icon: Icon(Icons.play_arrow, size: 14),
                                  label: Text('Apply', style: TextStyle(fontSize: 11)),
                                  onPressed: () => _applyProfile(i),
                                  style: TextButton.styleFrom(foregroundColor: scheme.success, padding: const EdgeInsets.symmetric(horizontal: 8)),
                                ),
                                const Spacer(),
                                Text(p['created_at']?.toString().substring(0, 10) ?? '', style: TextStyle(color: scheme.textMuted, fontSize: 9, fontFamily: 'monospace')),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: Icon(Icons.delete_outline, size: 16, color: scheme.error.withValues(alpha: 0.6)),
                                  onPressed: () => _deleteProfile(i),
                                  padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}