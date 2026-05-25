import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_manager.dart';
import '../../theme/app_theme.dart';
import '../../services/hermes_service.dart';
import '../../models/hermes_models.dart';

class MissionsScreen extends StatefulWidget {
  const MissionsScreen({super.key});
  @override
  State<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends State<MissionsScreen> {
  List<Map<String, dynamic>> _missions = [];
  bool _loading = true;
  String? _error;
  final _nameCtrl = TextEditingController();
  final _promptCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String get _path => '${Platform.environment['HOME'] ?? '/tmp'}/.hermes/wingman_missions.json';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _promptCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _load() {
    setState(() => _loading = true);
    try {
      final file = File(_path);
      if (file.existsSync()) {
        final data = jsonDecode(file.readAsStringSync()) as List;
        _missions = data.cast<Map<String, dynamic>>();
      } else {
        _missions = [];
      }
      _error = null;
    } catch (e) {
      _error = 'Failed to load missions: $e';
    }
    setState(() => _loading = false);
  }

  void _save() {
    try {
      final dir = Directory(_path).parent;
      if (!dir.existsSync()) dir.createSync(recursive: true);
      File(_path).writeAsStringSync(jsonEncode(_missions));
    } catch (e) {
      _error = 'Failed to save: $e';
    }
  }

  void _add() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    _missions.insert(0, {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'name': name,
      'description': _descCtrl.text.trim(),
      'prompt': _promptCtrl.text.trim(),
      'status': 'draft',
      'created_at': DateTime.now().toIso8601String(),
    });
    _nameCtrl.clear();
    _descCtrl.clear();
    _promptCtrl.clear();
    _save();
    setState(() {});
    Navigator.pop(context);
  }

  Future<void> _showAddDialog() async {
    final scheme = context.read<ThemeManager>().currentScheme;
    _nameCtrl.clear();
    _descCtrl.clear();
    _promptCtrl.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: scheme.surface,
        title: Text('New Mission', style: TextStyle(color: scheme.text)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _nameCtrl, style: TextStyle(color: scheme.text),
            decoration: InputDecoration(labelText: 'Name', labelStyle: TextStyle(color: scheme.textMuted),
              border: OutlineInputBorder(), filled: true, fillColor: scheme.surfaceAlt)),
          const SizedBox(height: 8),
          TextField(controller: _descCtrl, style: TextStyle(color: scheme.text),
            decoration: InputDecoration(labelText: 'Description', labelStyle: TextStyle(color: scheme.textMuted),
              border: OutlineInputBorder(), filled: true, fillColor: scheme.surfaceAlt)),
          const SizedBox(height: 8),
          TextField(controller: _promptCtrl, style: TextStyle(color: scheme.text), maxLines: 3,
            decoration: InputDecoration(labelText: 'Prompt', labelStyle: TextStyle(color: scheme.textMuted),
              border: OutlineInputBorder(), filled: true, fillColor: scheme.surfaceAlt)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
          TextButton(onPressed: _add, child: Text('Create', style: TextStyle(color: scheme.primary))),
        ],
      ),
    );
  }

  Future<void> _runMission(int index) async {
    final mission = _missions[index];
    setState(() => _missions[index]['status'] = 'running');
    try {
      final service = context.read<HermesService>();
      final result = await service.runHermesCommand(['-z', mission['prompt'] ?? '']);
      _missions[index]['status'] = 'completed';
      _missions[index]['last_output'] = result;
      _missions[index]['last_run_at'] = DateTime.now().toIso8601String();
    } catch (e) {
      _missions[index]['status'] = 'failed';
      _missions[index]['last_output'] = 'Error: $e';
    }
    _save();
    if (mounted) setState(() {});
  }

  void _deleteMission(int index) {
    _missions.removeAt(index);
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
        title: Text('Missions', style: TextStyle(color: scheme.text, fontSize: 15)),
        actions: [
          IconButton(icon: Icon(Icons.add, color: scheme.primary, size: 20),
            onPressed: _showAddDialog),
          IconButton(icon: Icon(Icons.refresh, color: scheme.textMuted, size: 18),
            onPressed: _load),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: scheme.primary))
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: scheme.error)))
              : _missions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.rocket_outlined, size: 48, color: scheme.textMuted.withValues(alpha: 0.3)),
                          const SizedBox(height: 12),
                          Text('No missions yet', style: TextStyle(color: scheme.textMuted, fontSize: 14)),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            icon: Icon(Icons.add, size: 16),
                            label: Text('Create Mission'),
                            onPressed: _showAddDialog,
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _missions.length,
                      itemBuilder: (ctx, i) {
                        final m = _missions[i];
                        final statusColors = <String, Color>{
                          'running': scheme.warning, 'completed': scheme.success,
                          'failed': scheme.error, 'draft': scheme.textMuted,
                        };
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
                                    Expanded(
                                      child: Text(m['name'] ?? '', style: TextStyle(color: scheme.text, fontSize: 13, fontWeight: FontWeight.w600)),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: (statusColors[m['status']] ?? scheme.textMuted).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(m['status'] ?? 'draft', style: TextStyle(
                                        color: statusColors[m['status']] ?? scheme.textMuted, fontSize: 9, fontFamily: 'monospace')),
                                    ),
                                  ],
                                ),
                                if ((m['description'] ?? '').isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(m['description'], style: TextStyle(color: scheme.textDim, fontSize: 11)),
                                  ),
                                if ((m['prompt'] ?? '').isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(m['prompt'], maxLines: 2, overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: scheme.textMuted, fontSize: 10, fontFamily: 'monospace')),
                                  ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    if (m['status'] != 'running')
                                      TextButton.icon(
                                        icon: Icon(Icons.play_arrow, size: 14),
                                        label: Text('Run', style: TextStyle(fontSize: 11)),
                                        onPressed: () => _runMission(i),
                                        style: TextButton.styleFrom(foregroundColor: scheme.success, padding: const EdgeInsets.symmetric(horizontal: 8)),
                                      ),
                                    const Spacer(),
                                    if (m['last_run_at'] != null)
                                      Text(m['last_run_at'].toString().substring(0, 16), style: TextStyle(color: scheme.textMuted, fontSize: 9, fontFamily: 'monospace')),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: Icon(Icons.delete_outline, size: 16, color: scheme.error.withValues(alpha: 0.6)),
                                      onPressed: () => _deleteMission(i),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
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