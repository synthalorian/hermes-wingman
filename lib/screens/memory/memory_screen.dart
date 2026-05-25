import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_manager.dart';
import '../../theme/app_theme.dart';
import '../../services/hermes_service.dart';
import '../../models/hermes_models.dart';

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  List<MemoryEntry> _entries = [];
  List<MemoryEntry> _filtered = [];
  bool _loading = true;
  bool _searching = false;
  String? _error;
  String _searchQuery = '';
  final Set<String> _deleting = {};

  @override
  void initState() {
    super.initState();
    _loadMemory();
  }

  Future<void> _loadMemory() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = context.read<HermesService>();
      final entries = await client.listMemory();

      if (!mounted) return;
      setState(() {
        _entries = entries;
        _filtered = entries;
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

  Future<void> _onSearchChanged(String query) async {
    setState(() {
      _searchQuery = query;
    });

    if (query.isEmpty) {
      setState(() {
        _filtered = _entries;
        _searching = false;
      });
      return;
    }

    setState(() => _searching = true);

    try {
      final client = context.read<HermesService>();
      final results = await client.searchMemory(query);

      if (!mounted) return;
      setState(() {
        _filtered = results;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Fallback: client-side filter
      setState(() {
        final q = query.toLowerCase();
        _filtered = _entries.where((e) =>
          e.key.toLowerCase().contains(q) ||
          e.content.toLowerCase().contains(q)
        ).toList();
        _searching = false;
      });
    }
  }

  Future<void> _deleteEntry(MemoryEntry entry) async {
    final id = entry.id.isNotEmpty ? entry.id : entry.key;
    setState(() => _deleting.add(id));

    try {
      final client = context.read<HermesService>();
      final success = await client.deleteMemory(id);

      if (!mounted) return;
      if (success) {
        setState(() {
          _entries.removeWhere((e) =>
            (e.id.isNotEmpty ? e.id : e.key) == id
          );
          _filtered.removeWhere((e) =>
            (e.id.isNotEmpty ? e.id : e.key) == id
          );
        });
      }
    } catch (_) {}

    if (mounted) setState(() => _deleting.remove(id));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.watch<ThemeManager>().currentScheme;

    return Scaffold(
      backgroundColor: scheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('Memory'),
        actions: [
          Text(
            '${_filtered.length} entries',
            style: TextStyle(color: scheme.textMuted, fontSize: 12),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.refresh, size: 18, color: scheme.textDim),
            onPressed: _loadMemory,
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
              Text('Could not load memory', style: TextStyle(color: scheme.textDim, fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: scheme.textMuted, fontSize: 12, fontFamily: 'monospace'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              MaterialButton(
                color: scheme.primary.withValues(alpha: 0.15),
                onPressed: _loadMemory,
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
                hintText: 'Search memory entries...',
                hintStyle: TextStyle(color: scheme.textMuted, fontSize: 13),
                prefixIcon: _searching
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.primary,
                          ),
                        ),
                      )
                    : Icon(Icons.search, size: 16, color: scheme.textMuted),
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
        // Memory list
        Expanded(
          child: _filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.memory_outlined, size: 40, color: scheme.textMuted),
                      const SizedBox(height: 12),
                      Text(
                        _searchQuery.isNotEmpty
                            ? 'No entries match "$_searchQuery"'
                            : 'No memory entries found',
                        style: TextStyle(color: scheme.textDim, fontSize: 14),
                      ),
                      if (_searchQuery.isNotEmpty)
                        TextButton(
                          onPressed: () => _onSearchChanged(''),
                          child: Text('Clear search', style: TextStyle(color: scheme.primary)),
                        ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: _filtered.length,
                  itemBuilder: (context, i) => _MemoryCard(
                    scheme: scheme,
                    entry: _filtered[i],
                    deleting: _deleting.contains(
                      _filtered[i].id.isNotEmpty ? _filtered[i].id : _filtered[i].key,
                    ),
                    onDelete: () => _deleteEntry(_filtered[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _MemoryCard extends StatelessWidget {
  final AppColorScheme scheme;
  final MemoryEntry entry;
  final bool deleting;
  final VoidCallback onDelete;

  const _MemoryCard({
    required this.scheme,
    required this.entry,
    required this.deleting,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final contentPreview = entry.content.length > 120
        ? '${entry.content.substring(0, 120)}...'
        : entry.content;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.borderDim, width: 0.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: scheme.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.auto_stories_outlined,
                size: 18,
                color: scheme.accent,
              ),
            ),
            const SizedBox(width: 12),
            // Key + content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.key,
                    style: TextStyle(
                      color: scheme.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  if (entry.type != 'unknown') ...[
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: scheme.surfaceAlt,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: scheme.borderDim, width: 0.3),
                      ),
                      child: Text(
                        entry.type,
                        style: TextStyle(
                          color: scheme.textMuted,
                          fontSize: 9,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                  if (contentPreview.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      contentPreview,
                      style: TextStyle(color: scheme.textDim, fontSize: 11, height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Delete button
            if (deleting)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.error,
                ),
              )
            else
              IconButton(
                icon: Icon(Icons.delete_outline, size: 16, color: scheme.error.withValues(alpha: 0.7)),
                onPressed: onDelete,
                tooltip: 'Delete',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
          ],
        ),
      ),
    );
  }
}