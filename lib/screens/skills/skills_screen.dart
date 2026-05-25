import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_manager.dart';
import '../../theme/app_theme.dart';
import '../../services/hermes_service.dart';
import '../../models/hermes_models.dart';

class SkillsScreen extends StatefulWidget {
  const SkillsScreen({super.key});

  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  List<SkillEntry> _skills = [];
  List<SkillEntry> _filtered = [];
  bool _loading = true;
  String? _error;
  String _searchQuery = '';
  final Set<String> _toggling = {};

  @override
  void initState() {
    super.initState();
    _loadSkills();
  }

  Future<void> _loadSkills() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = context.read<HermesService>();
      final skills = await client.listSkills();

      if (!mounted) return;
      setState(() {
        _skills = skills;
        _filtered = skills;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _toggleSkill(String name) async {
    setState(() => _toggling.add(name));

    try {
      final client = context.read<HermesService>();
      await client.toggleSkill(name, action: 'toggle');

      if (!mounted) return;
      setState(() {
        _skills = _skills.map((s) {
          if (s.name == name) {
            return SkillEntry(
              name: s.name,
              category: s.category,
              description: s.description,
              enabled: !s.enabled,
            );
          }
          return s;
        }).toList();
        _applyFilter();
      });
    } catch (_) {
      // Silently handle toggle errors
    }

    if (mounted) setState(() => _toggling.remove(name));
  }

  void _applyFilter() {
    if (_searchQuery.isEmpty) {
      _filtered = _skills;
    } else {
      final q = _searchQuery.toLowerCase();
      _filtered = _skills.where((s) => s.name.toLowerCase().contains(q)).toList();
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _applyFilter();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.watch<ThemeManager>().currentScheme;

    return Scaffold(
      backgroundColor: scheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('Skills'),
        actions: [
          Text(
            '${_filtered.length} skills',
            style: TextStyle(color: scheme.textMuted, fontSize: 12),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.refresh, size: 18, color: scheme.textDim),
            onPressed: _loadSkills,
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 4),
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
              Text('Could not load skills', style: TextStyle(color: scheme.textDim, fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: scheme.textMuted, fontSize: 12, fontFamily: 'monospace'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              MaterialButton(
                color: scheme.primary.withValues(alpha: 0.15),
                onPressed: _loadSkills,
                child: Text('Retry', style: TextStyle(color: scheme.primary)),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.borderDim, width: 0.5),
            ),
            child: TextField(
              controller: TextEditingController(text: _searchQuery),
              onChanged: _onSearchChanged,
              style: TextStyle(color: scheme.text, fontSize: 13, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'Search skills by name...',
                hintStyle: TextStyle(color: scheme.textMuted, fontSize: 13),
                prefixIcon: Icon(Icons.search, size: 16, color: scheme.textMuted),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, size: 14, color: scheme.textDim),
                        onPressed: () => _onSearchChanged(''),
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Skills list
        Expanded(
          child: _filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.extension_off_outlined, size: 40, color: scheme.textMuted),
                      const SizedBox(height: 12),
                      Text(
                        _searchQuery.isNotEmpty
                            ? 'No skills match "$_searchQuery"'
                            : 'No skills found',
                        style: TextStyle(color: scheme.textDim, fontSize: 14),
                      ),
                      if (_searchQuery.isNotEmpty)
                        TextButton(
                          onPressed: () => _onSearchChanged(''),
                          child: Text('Clear filter', style: TextStyle(color: scheme.primary)),
                        ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: _filtered.length,
                  itemBuilder: (context, i) => _SkillCard(
                    scheme: scheme,
                    skill: _filtered[i],
                    toggling: _toggling.contains(_filtered[i].name),
                    onToggle: () => _toggleSkill(_filtered[i].name),
                  ),
                ),
        ),
      ],
    );
  }
}

class _SkillCard extends StatelessWidget {
  final AppColorScheme scheme;
  final SkillEntry skill;
  final bool toggling;
  final VoidCallback onToggle;

  const _SkillCard({
    required this.scheme,
    required this.skill,
    required this.toggling,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: skill.enabled ? scheme.primary.withValues(alpha: 0.3) : scheme.borderDim,
            width: skill.enabled ? 1 : 0.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Skill icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: skill.enabled
                    ? scheme.primary.withValues(alpha: 0.12)
                    : scheme.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.psychology_outlined,
                size: 18,
                color: skill.enabled ? scheme.primary : scheme.textMuted,
              ),
            ),
            const SizedBox(width: 12),
            // Name, category, description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    skill.name,
                    style: TextStyle(
                      color: scheme.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  if (skill.category.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: scheme.surfaceAlt,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: scheme.borderDim, width: 0.3),
                      ),
                      child: Text(
                        skill.category,
                        style: TextStyle(
                          color: scheme.textMuted,
                          fontSize: 9,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                  if (skill.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      skill.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.textDim, fontSize: 11, height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Toggle button
            SizedBox(
              width: 60,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (toggling)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.primary,
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: onToggle,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 42,
                        height: 22,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(11),
                          color: skill.enabled ? scheme.primary : scheme.surfaceAlt,
                          border: Border.all(
                            color: skill.enabled ? scheme.primary : scheme.borderDim,
                            width: 0.5,
                          ),
                        ),
                        child: AnimatedAlign(
                          duration: const Duration(milliseconds: 200),
                          alignment: skill.enabled ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            width: 16,
                            height: 16,
                            margin: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: skill.enabled ? scheme.surface : scheme.textMuted,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    skill.enabled ? 'ON' : 'OFF',
                    style: TextStyle(
                      color: skill.enabled ? scheme.primary : scheme.textMuted,
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}