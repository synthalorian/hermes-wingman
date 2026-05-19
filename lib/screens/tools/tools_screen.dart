import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_manager.dart';
import '../../theme/app_theme.dart';
import '../../services/hermes_api_client.dart';

/// Tools screen: Hermes version/update + available skills.
class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key});

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  // ── State ─────────────────────────────────────────────────────────────
  String? _hermesVersion;
  bool _versionLoading = true;
  String? _versionError;

  bool _updating = false;
  String? _updateResult;

  List<Map<String, String>> _skills = [];
  bool _skillsLoading = true;
  String? _skillsError;

  StreamSubscription? _updateSub;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadSkills();
  }

  @override
  void dispose() {
    _updateSub?.cancel();
    super.dispose();
  }

  // ── Data Loading ──────────────────────────────────────────────────────

  Future<void> _loadVersion() async {
    setState(() {
      _versionLoading = true;
      _versionError = null;
    });
    try {
      final backend = context.read<BackendService>();
      final data = await backend.httpGet('/hermes/version');
      if (!mounted) return;
      setState(() {
        _hermesVersion = data['version'] as String? ?? 'Unknown';
        _versionLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _versionError = e.toString();
        _versionLoading = false;
      });
    }
  }

  Future<void> _doUpdate() async {
    setState(() {
      _updating = true;
      _updateResult = null;
    });
    try {
      final backend = context.read<BackendService>();
      final data = await backend.httpPost('/hermes/update', {});
      if (!mounted) return;
      setState(() {
        _updateResult = data['output'] as String? ?? (data['success'] == true ? 'Update complete.' : 'Update failed.');
        _updating = false;
      });
      // Refresh version after update
      await _loadVersion();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _updateResult = 'Error: $e';
        _updating = false;
      });
    }
  }

  Future<void> _loadSkills() async {
    setState(() {
      _skillsLoading = true;
      _skillsError = null;
    });
    try {
      final backend = context.read<BackendService>();
      final data = await backend.httpGet('/hermes/skills');
      if (!mounted) return;
      final raw = data['skills'] as List? ?? [];
      setState(() {
        _skills = raw.map((s) {
          final m = s as Map<String, dynamic>;
          return {
            'name': (m['name'] as String? ?? '').trim(),
            'description': (m['description'] as String? ?? '').trim(),
          };
        }).where((s) => s['name']!.isNotEmpty).toList();
        _skillsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _skillsError = e.toString();
        _skillsLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.watch<ThemeManager>().currentScheme;

    return Scaffold(
      backgroundColor: scheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('Tools'),
        backgroundColor: scheme.appBarBackground,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, size: 16, color: scheme.textMuted),
            onPressed: () { _loadVersion(); _loadSkills(); },
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildSection(scheme, 'Hermes Agent', _buildVersionCard(scheme)),
          const SizedBox(height: 24),
          _buildSection(scheme, 'Installed Skills', _buildSkillsCard(scheme)),
        ],
      ),
    );
  }

  Widget _buildSection(AppColorScheme scheme, String title, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  color: scheme.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
        content,
      ],
    );
  }

  Widget _buildVersionCard(AppColorScheme scheme) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.borderDim, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Version info
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow(scheme, 'Version', _versionLoading
                    ? 'Loading...'
                    : _versionError ?? _hermesVersion ?? 'Not detected',
                    _versionError != null),
                const SizedBox(height: 4),
                Text(
                  'pip3 install --upgrade hermes-agent',
                  style: TextStyle(
                    color: scheme.textMuted,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          // Divider
          Container(height: 0.5, color: scheme.borderDim),
          // Action row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Row(
              children: [
                _buildActionButton(
                  scheme: scheme,
                  icon: Icons.update,
                  label: _updating ? 'Updating...' : 'Update Hermes',
                  loading: _updating,
                  onTap: _updating ? null : _doUpdate,
                ),
                const SizedBox(width: 10),
                _buildActionButton(
                  scheme: scheme,
                  icon: Icons.refresh,
                  label: 'Refresh',
                  onTap: _loadVersion,
                ),
              ],
            ),
          ),
          // Update result
          if (_updateResult != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.borderDim, width: 0.5),
                ),
                child: Text(
                  _updateResult!,
                  style: TextStyle(
                    color: scheme.textMuted,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSkillsCard(AppColorScheme scheme) {
    if (_skillsLoading) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.borderDim, width: 0.5),
        ),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: scheme.textMuted,
          ),
        ),
      );
    }

    if (_skillsError != null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.error.withValues(alpha: 0.3), width: 0.5),
        ),
        child: Column(
          children: [
            Icon(Icons.error_outline, size: 28, color: scheme.error.withValues(alpha: 0.6)),
            const SizedBox(height: 8),
            Text(
              _skillsError!,
              style: TextStyle(color: scheme.textMuted, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            _buildTinyButton(scheme, 'Retry', _loadSkills),
          ],
        ),
      );
    }

    if (_skills.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.borderDim, width: 0.5),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.extension_off_outlined, size: 32, color: scheme.textMuted.withValues(alpha: 0.4)),
              const SizedBox(height: 8),
              Text(
                'No skills installed',
                style: TextStyle(color: scheme.textMuted, fontSize: 13),
              ),
              Text(
                'Install skills via: hermes skills install <name>',
                style: TextStyle(color: scheme.textMuted.withValues(alpha: 0.6), fontSize: 10, fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
      );
    }

    // Skills list
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.borderDim, width: 0.5),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Text(
                  '${_skills.length} skill${_skills.length == 1 ? '' : 's'} installed',
                  style: TextStyle(color: scheme.textMuted, fontSize: 10, letterSpacing: 0.5),
                ),
                const Spacer(),
                _buildTinyButton(scheme, 'Refresh', _loadSkills),
              ],
            ),
          ),
          // Skills
          ..._skills.map((s) => _buildSkillRow(scheme, s)),
          // Bottom padding
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildSkillRow(AppColorScheme scheme, Map<String, String> skill) {
    final name = skill['name'] ?? '';
    final description = skill['description'] ?? '';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: scheme.borderDim.withValues(alpha: 0.3), width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: scheme.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(color: scheme.textMuted, fontSize: 11, height: 1.3),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(AppColorScheme scheme, String label, String value, bool isError) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: TextStyle(color: scheme.textMuted, fontSize: 12),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: isError ? scheme.error : scheme.text,
              fontSize: 12,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required AppColorScheme scheme,
    required IconData icon,
    required String label,
    bool loading = false,
    VoidCallback? onTap,
  }) {
    return Material(
      color: scheme.surfaceAlt,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.borderDim, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                SizedBox(
                  width: 12, height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: scheme.textMuted),
                )
              else
                Icon(icon, size: 14, color: scheme.textMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(color: scheme.text, fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTinyButton(AppColorScheme scheme, String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            label,
            style: TextStyle(
              color: scheme.primary,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
