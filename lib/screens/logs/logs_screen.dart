import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_manager.dart';
import '../../theme/app_theme.dart';
import '../../services/hermes_service.dart';
import '../../models/hermes_models.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  List<LogEntry> _entries = [];
  List<LogEntry> _filtered = [];
  bool _loading = true;
  String? _error;
  String _levelFilter = 'all';
  String _keywordFilter = '';
  bool _autoScroll = true;
  final ScrollController _scrollController = ScrollController();
  Timer? _pollTimer;
  static const _maxEntries = 500;

  final _levels = ['all', 'error', 'warning', 'info'];

  @override
  void initState() {
    super.initState();
    _loadLogs();
    // Poll every 3 seconds
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _loadLogs());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    try {
      final client = context.read<HermesService>();
      final entries = await client.readLogs(lines: 100, level: 'all');

      if (!mounted) return;
      setState(() {
        _entries = entries.take(_maxEntries).toList();
        _loading = false;
        _error = null;
        _applyFilters();
      });

      // Auto-scroll to bottom
      if (_autoScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
            );
          }
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

  void _applyFilters() {
    _filtered = _entries.where((entry) {
      // Level filter
      if (_levelFilter == 'error' && entry.level != 'ERROR' && entry.level != 'CRITICAL') {
        return false;
      }
      if (_levelFilter == 'warning' &&
          entry.level != 'WARNING' &&
          entry.level != 'ERROR' &&
          entry.level != 'CRITICAL') {
        return false;
      }
      if (_levelFilter == 'info' && entry.level != 'INFO') {
        return false;
      }

      // Keyword filter
      if (_keywordFilter.isNotEmpty &&
          !entry.message.toLowerCase().contains(_keywordFilter.toLowerCase())) {
        return false;
      }

      return true;
    }).toList();
  }

  void _setLevelFilter(String level) {
    setState(() {
      _levelFilter = level;
      _applyFilters();
    });
  }

  void _setKeywordFilter(String keyword) {
    setState(() {
      _keywordFilter = keyword;
      _applyFilters();
    });
  }

  Color _colorForLevel(String level, AppColorScheme scheme) {
    switch (level) {
      case 'ERROR':
      case 'CRITICAL':
        return scheme.error;
      case 'WARNING':
        return scheme.warning;
      case 'DEBUG':
        return scheme.textMuted;
      default:
        return scheme.text;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.watch<ThemeManager>().currentScheme;

    return Scaffold(
      backgroundColor: scheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('Logs'),
        actions: [
          IconButton(
            icon: Icon(
              _autoScroll ? Icons.vertical_align_bottom : Icons.vertical_align_center,
              size: 16,
              color: _autoScroll ? scheme.primary : scheme.textMuted,
            ),
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
            tooltip: _autoScroll ? 'Auto-scroll ON' : 'Auto-scroll OFF',
          ),
          IconButton(
            icon: Icon(Icons.refresh, size: 18, color: scheme.textDim),
            onPressed: _loadLogs,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Toolbar
          _LogToolbar(
            scheme: scheme,
            levels: _levels,
            currentLevel: _levelFilter,
            keywordFilter: _keywordFilter,
            onLevelChanged: _setLevelFilter,
            onKeywordChanged: _setKeywordFilter,
            loading: _loading,
            count: _filtered.length,
          ),
          // Log content
          Expanded(child: _buildLogContent(scheme)),
        ],
      ),
    );
  }

  Widget _buildLogContent(AppColorScheme scheme) {
    if (_loading && _entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off, size: 48, color: scheme.error.withValues(alpha: 0.6)),
              const SizedBox(height: 16),
              Text('Could not load logs', style: TextStyle(color: scheme.textDim, fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: scheme.textMuted, fontSize: 12, fontFamily: 'monospace'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              MaterialButton(
                color: scheme.primary.withValues(alpha: 0.15),
                onPressed: _loadLogs,
                child: Text('Retry', style: TextStyle(color: scheme.primary)),
              ),
            ],
          ),
        ),
      );
    }

    if (_filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.terminal, size: 40, color: scheme.textMuted),
            const SizedBox(height: 12),
            Text(
              _keywordFilter.isNotEmpty
                  ? 'No log lines match "$_keywordFilter"'
                  : 'No log lines at this level',
              style: TextStyle(color: scheme.textDim, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      decoration: BoxDecoration(
        color: scheme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.borderDim, width: 0.5),
      ),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        itemCount: _filtered.length,
        itemBuilder: (context, i) {
          final entry = _filtered[i];
          final color = _colorForLevel(entry.level, scheme);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Level badge
                SizedBox(
                  width: 60,
                  child: Text(
                    entry.level.padRight(7),
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // Timestamp
                SizedBox(
                  width: 120,
                  child: Text(
                    '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
                    '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
                    '${entry.timestamp.second.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: scheme.textMuted.withValues(alpha: 0.7),
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                // Message
                Expanded(
                  child: Text(
                    entry.message,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontFamily: 'monospace',
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LogToolbar extends StatelessWidget {
  final AppColorScheme scheme;
  final List<String> levels;
  final String currentLevel;
  final String keywordFilter;
  final ValueChanged<String> onLevelChanged;
  final ValueChanged<String> onKeywordChanged;
  final bool loading;
  final int count;

  const _LogToolbar({
    required this.scheme,
    required this.levels,
    required this.currentLevel,
    required this.keywordFilter,
    required this.onLevelChanged,
    required this.onKeywordChanged,
    required this.loading,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      child: Row(
        children: [
          // Level pills
          ...levels.map((level) {
            final active = level == currentLevel;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Material(
                color: active ? scheme.primary.withValues(alpha: 0.15) : scheme.surfaceAlt,
                borderRadius: BorderRadius.circular(4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => onLevelChanged(level),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: active ? scheme.primary.withValues(alpha: 0.4) : scheme.borderDim,
                        width: active ? 1 : 0.5,
                      ),
                    ),
                    child: Text(
                      level.toUpperCase(),
                      style: TextStyle(
                        color: active ? scheme.primary : scheme.textDim,
                        fontSize: 10,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          // Live indicator
          if (loading)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: scheme.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'LIVE',
                    style: TextStyle(
                      color: scheme.success,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          // Count
          Text(
            '$count lines',
            style: TextStyle(color: scheme.textMuted, fontSize: 11, fontFamily: 'monospace'),
          ),
          const SizedBox(width: 12),
          // Keyword search
          SizedBox(
            width: 180,
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surfaceAlt,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: scheme.borderDim, width: 0.5),
              ),
              child: TextField(
                controller: TextEditingController(text: keywordFilter),
                onChanged: onKeywordChanged,
                style: TextStyle(color: scheme.text, fontSize: 11, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'Filter...',
                  hintStyle: TextStyle(color: scheme.textMuted, fontSize: 11),
                  prefixIcon: Icon(Icons.search, size: 14, color: scheme.textMuted),
                  suffixIcon: keywordFilter.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, size: 12, color: scheme.textDim),
                          onPressed: () => onKeywordChanged(''),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  isDense: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
