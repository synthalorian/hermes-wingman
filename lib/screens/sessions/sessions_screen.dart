import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_manager.dart';
import '../../theme/app_theme.dart';
import '../../services/hermes_service.dart';
import '../../services/chat_manager.dart';
import '../../models/hermes_models.dart';

class SessionsScreen extends StatefulWidget {
  final ValueChanged<int>? onNavigate;

  const SessionsScreen({super.key, this.onNavigate});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  List<HermesSession> _sessions = [];
  List<HermesSession> _filtered = [];
  bool _loading = true;
  String? _error;
  String _searchQuery = '';
  String _statsText = '';
  HermesSession? _selectedSession;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = context.read<HermesService>();
      final sessions = await client.listSessions(limit: 50);
      String stats = '';
      try {
        stats = await client.getSessionStats();
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _filtered = sessions;
        _statsText = stats;
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

  void _filter(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filtered = _sessions;
      } else {
        final q = query.toLowerCase();
        _filtered = _sessions.where((s) {
          return s.title.toLowerCase().contains(q) ||
              s.model.toLowerCase().contains(q) ||
              s.provider.toLowerCase().contains(q) ||
              s.id.toLowerCase().contains(q);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.watch<ThemeManager>().currentScheme;

    return Scaffold(
      backgroundColor: scheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('Sessions'),
        actions: [
          if (!_loading && _error == null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${_filtered.length} sessions',
                  style: TextStyle(color: scheme.textMuted, fontSize: 12),
                ),
              ),
            ),
          IconButton(
            icon: Icon(Icons.refresh, size: 18, color: scheme.textDim),
            onPressed: _loadSessions,
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
              Text(
                'Could not load sessions',
                style: TextStyle(color: scheme.textDim, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: scheme.textMuted, fontSize: 12, fontFamily: 'monospace'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              MaterialButton(
                color: scheme.primary.withValues(alpha: 0.15),
                onPressed: _loadSessions,
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
          child: _SearchBar(
            scheme: scheme,
            query: _searchQuery,
            onChanged: _filter,
          ),
        ),
        // Stats row
        if (_statsText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: SizedBox(
              width: double.infinity,
              child: Text(
                _statsText,
                style: TextStyle(color: scheme.textMuted, fontSize: 11, fontFamily: 'monospace'),
              ),
            ),
          ),
        // Sessions list
        Expanded(
          child: _filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox_outlined, size: 40, color: scheme.textMuted),
                      const SizedBox(height: 12),
                      Text(
                        _searchQuery.isNotEmpty ? 'No sessions match "$_searchQuery"' : 'No sessions found',
                        style: TextStyle(color: scheme.textDim, fontSize: 14),
                      ),
                      if (_searchQuery.isNotEmpty)
                        TextButton(
                          onPressed: () => _filter(''),
                          child: Text('Clear filter', style: TextStyle(color: scheme.primary)),
                        ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(24),
                  itemCount: _filtered.length,
                  itemBuilder: (context, i) => _SessionRow(
                    scheme: scheme,
                    session: _filtered[i],
                    selected: _selectedSession?.id == _filtered[i].id,
                    onTap: () => setState(() {
                      _selectedSession = _selectedSession?.id == _filtered[i].id ? null : _filtered[i];
                    }),
                  ),
                ),
        ),
        // Detail panel
        if (_selectedSession != null)
          _SessionDetailPanel(
            scheme: scheme,
            session: _selectedSession!,
            onClose: () => setState(() => _selectedSession = null),
            onResume: () {
              final mgr = context.read<ChatManager>();
              mgr.setResumeSession(
                _selectedSession!.id,
                title: _selectedSession!.title,
              );
              widget.onNavigate?.call(1); // Chat tab
            },
          ),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  final AppColorScheme scheme;
  final String query;
  final ValueChanged<String> onChanged;

  const _SearchBar({
    required this.scheme,
    required this.query,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.borderDim, width: 0.5),
      ),
      child: TextField(
        controller: TextEditingController(text: query),
        onChanged: onChanged,
        style: TextStyle(color: scheme.text, fontSize: 13, fontFamily: 'monospace'),
        decoration: InputDecoration(
          hintText: 'Search sessions by title, model, provider...',
          hintStyle: TextStyle(color: scheme.textMuted, fontSize: 13),
          prefixIcon: Icon(Icons.search, size: 16, color: scheme.textMuted),
          suffixIcon: query.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, size: 14, color: scheme.textDim),
                  onPressed: () => onChanged(''),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  final AppColorScheme scheme;
  final HermesSession session;
  final bool selected;
  final VoidCallback onTap;

  const _SessionRow({
    required this.scheme,
    required this.session,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? scheme.selectedBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: selected ? scheme.primary.withValues(alpha: 0.4) : scheme.borderDim.withValues(alpha: 0.3),
                width: selected ? 1 : 0.5,
              ),
            ),
            child: Row(
              children: [
                // Status indicator
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: session.status == 'active'
                        ? scheme.success
                        : session.status == 'idle'
                            ? scheme.warning
                            : scheme.textMuted,
                    shape: BoxShape.circle,
                    boxShadow: session.status == 'active'
                        ? [BoxShadow(color: scheme.success.withValues(alpha: 0.5), blurRadius: 4)]
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                // Title + ID
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.text,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        session.id.length > 16 ? '${session.id.substring(0, 16)}...' : session.id,
                        style: TextStyle(color: scheme.textMuted, fontSize: 10, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
                // Model
                Expanded(
                  flex: 2,
                  child: Text(
                    session.model,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.textDim, fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
                // Messages
                SizedBox(
                  width: 40,
                  child: Text(
                    '${session.messageCount}',
                    style: TextStyle(color: scheme.textDim, fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
                // Time
                SizedBox(
                  width: 70,
                  child: Text(
                    session.durationLabel,
                    style: TextStyle(color: scheme.textMuted, fontSize: 11),
                    textAlign: TextAlign.right,
                  ),
                ),
                // Expand arrow
                Icon(
                  selected ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: scheme.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionDetailPanel extends StatelessWidget {
  final AppColorScheme scheme;
  final HermesSession session;
  final VoidCallback onClose;
  final VoidCallback? onResume;

  const _SessionDetailPanel({
    required this.scheme,
    required this.session,
    required this.onClose,
    this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.borderDim, width: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Text(
                  session.title,
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                Text(
                  session.status.toUpperCase(),
                  style: TextStyle(
                    color: session.status == 'active' ? scheme.success : scheme.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.close, size: 16, color: scheme.textMuted),
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Details grid
            Row(
              children: [
                _detailTile(scheme, 'Session ID', session.id),
                const SizedBox(width: 32),
                _detailTile(scheme, 'Model', session.model),
                const SizedBox(width: 32),
                _detailTile(scheme, 'Provider', session.provider),
                const SizedBox(width: 32),
                _detailTile(scheme, 'Messages', '${session.messageCount}'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _detailTile(scheme, 'Created', session.createdAt.toIso8601String().split('T').first),
                const SizedBox(width: 32),
                _detailTile(scheme, 'Last Activity', session.durationLabel),
              ],
            ),
            const SizedBox(height: 16),
            // Action buttons
            Row(
              children: [
                _ActionChip(
                  scheme: scheme,
                  label: 'Resume Session',
                  icon: Icons.play_arrow,
                  color: scheme.primary,
                  onTap: () {
                    onResume?.call();
                  },
                ),
                const SizedBox(width: 10),
                _ActionChip(
                  scheme: scheme,
                  label: 'Export Session',
                  icon: Icons.file_download_outlined,
                  color: scheme.secondary,
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailTile(AppColorScheme scheme, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: scheme.textMuted, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(color: scheme.textDim, fontSize: 12, fontFamily: 'monospace'),
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  final AppColorScheme scheme;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionChip({
    required this.scheme,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: scheme.surfaceAlt,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: scheme.borderDim, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(color: scheme.text, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
