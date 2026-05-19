import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_manager.dart';
import '../../theme/app_theme.dart';
import '../../services/hermes_service.dart';
import '../../models/hermes_models.dart';
import '../../services/wingman_settings.dart';

class DashboardScreen extends StatefulWidget {
  final void Function(int tabIndex)? onNavigate;
  const DashboardScreen({super.key, this.onNavigate});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  HermesStatus? _status;
  List<HermesSession> _recentSessions = [];
  List<HermesCronJob> _cronJobs = [];
  List<GatewayPlatform> _gateways = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = context.read<HermesService>();
      
      // Run all queries in parallel
      final results = await Future.wait([
        client.getStatus(),
        client.listSessions(limit: 5),
        client.listCronJobs(),
        client.getGatewayStatus(),
      ]);

      if (!mounted) return;
      setState(() {
        _status = results[0] as HermesStatus;
        _recentSessions = results[1] as List<HermesSession>;
        _cronJobs = results[2] as List<HermesCronJob>;
        _gateways = results[3] as List<GatewayPlatform>;
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

  @override
  Widget build(BuildContext context) {
    final scheme = context.watch<ThemeManager>().currentScheme;

    return Scaffold(
      backgroundColor: scheme.scaffoldBackground,
      appBar: _buildAppBar(scheme),
      body: _loading && _status == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _status == null
              ? _buildError(scheme)
              : RefreshIndicator(
                  onRefresh: _loadAll,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeaderRow(scheme),
                        const SizedBox(height: 24),
                        _buildStatusGrid(scheme),
                        const SizedBox(height: 24),
                        _buildQuickActions(scheme),
                        const SizedBox(height: 24),
                        _buildRecentActivity(scheme),
                        const SizedBox(height: 24),
                        _buildOpenSourceSection(scheme),
                      ],
                    ),
                  ),
                ),
    );
  }

  PreferredSizeWidget _buildAppBar(AppColorScheme scheme) {
    final settings = context.watch<WingmanSettings>();
    
    return AppBar(
      title: GestureDetector(
        onDoubleTap: () => WingmanSettings.showEditDialog(context),
        child: Row(
          children: [
            Text(
              settings.dashboardTitle,
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
                fontSize: 18,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: scheme.borderDim, width: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'v0.1.0',
                style: TextStyle(
                  color: scheme.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: 'Double-click to rename',
              child: Icon(Icons.edit_outlined, size: 10, color: scheme.textMuted.withValues(alpha: 0.5)),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.refresh, size: 18, color: scheme.textDim),
          onPressed: _loadAll,
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  Widget _buildError(AppColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 48, color: scheme.error.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            Text('Could not reach Hermes', style: TextStyle(color: scheme.textDim, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: scheme.textMuted, fontSize: 12, fontFamily: 'monospace'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Make sure Hermes Agent is installed and on PATH',
              style: TextStyle(color: scheme.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                MaterialButton(
                  color: scheme.primary.withValues(alpha: 0.15),
                  onPressed: _loadAll,
                  child: Text('Retry', style: TextStyle(color: scheme.primary)),
                ),
                const SizedBox(width: 12),
                MaterialButton(
                  color: scheme.accent.withValues(alpha: 0.15),
                  onPressed: () => widget.onNavigate?.call(8), // Setup tab
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.rocket_launch, size: 14, color: scheme.accent),
                      const SizedBox(width: 6),
                      Text('Setup Wizard', style: TextStyle(color: scheme.accent)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderRow(AppColorScheme scheme) {
    final isOnline = _status != null && _status!.isRunning;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isOnline
                ? scheme.success.withValues(alpha: 0.1)
                : scheme.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isOnline
                  ? scheme.success.withValues(alpha: 0.3)
                  : scheme.error.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isOnline ? scheme.success : scheme.error,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                isOnline ? 'AGENT ONLINE' : 'AGENT OFFLINE',
                style: TextStyle(
                  color: isOnline ? scheme.success : scheme.error,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
        if (_status != null) ...[
          const SizedBox(width: 12),
          Text(
            _status!.model,
            style: TextStyle(color: scheme.textDim, fontSize: 11, fontFamily: 'monospace'),
          ),
          if (_status!.version.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              _status!.version,
              style: TextStyle(color: scheme.textMuted, fontSize: 10, fontFamily: 'monospace'),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildStatusGrid(AppColorScheme scheme) {
    final activeSessions = _recentSessions.length;
    final activeCrons = _cronJobs.where((j) => j.status == 'active').length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 48) / 4;
        return Row(
          children: [
            _StatusCard(
              scheme: scheme,
              width: cardWidth,
              label: 'SESSIONS',
              value: '$activeSessions',
              icon: Icons.chat_bubble_outline,
              color: scheme.primary,
              detail: _recentSessions.isNotEmpty
                  ? 'latest ${_recentSessions.first.createdLabel}'
                  : null,
            ),
            const SizedBox(width: 16),
            _StatusCard(
              scheme: scheme,
              width: cardWidth,
              label: 'CRON JOBS',
              value: '${_cronJobs.length}',
              icon: Icons.schedule_outlined,
              color: scheme.accent,
              detail: activeCrons > 0 ? '$activeCrons active' : null,
            ),
            const SizedBox(width: 16),
            _StatusCard(
              scheme: scheme,
              width: cardWidth,
              label: 'GATEWAYS',
              value: '${_gateways.length}',
              icon: Icons.hub_outlined,
              color: scheme.secondary,
              detail: _gateways.any((g) => g.isConnected)
                  ? '${_gateways.where((g) => g.isConnected).length} connected'
                  : null,
            ),
            const SizedBox(width: 16),
            _StatusCard(
              scheme: scheme,
              width: cardWidth,
              label: 'MODEL',
              value: _status?.model ?? '—',
              icon: Icons.memory_outlined,
              color: scheme.success,
              detail: _status?.provider ?? '',
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuickActions(AppColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'QUICK ACTIONS',
            style: TextStyle(
              color: scheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
        ),
        Row(
          children: [
            _ActionButton(
              scheme: scheme,
              label: 'New Chat',
              icon: Icons.add_circle_outline,
              color: scheme.primary,
              onTap: _openTerminal,
            ),
            const SizedBox(width: 10),
            _ActionButton(
              scheme: scheme,
              label: 'Open Logs',
              icon: Icons.terminal,
              color: scheme.secondary,
              onTap: _openLogs,
            ),
            const SizedBox(width: 10),
            _ActionButton(
              scheme: scheme,
              label: 'Edit Config',
              icon: Icons.settings_outlined,
              color: scheme.accent,
              onTap: _openConfig,
            ),
            const SizedBox(width: 10),
            _ActionButton(
              scheme: scheme,
              label: 'Refresh',
              icon: Icons.refresh,
              color: scheme.success,
              onTap: _loadAll,
            ),
          ],
        ),
      ],
    );
  }

  void _openTerminal() {
    widget.onNavigate?.call(1);
  }

  void _openLogs() {
    widget.onNavigate?.call(5);
  }

  void _openConfig() {
    widget.onNavigate?.call(4);
  }

  Widget _buildRecentActivity(AppColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'RECENT SESSIONS',
            style: TextStyle(
              color: scheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
        ),
        if (_recentSessions.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.borderDim, width: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Icon(Icons.inbox_outlined, size: 32, color: scheme.textMuted),
                const SizedBox(height: 8),
                Text('No sessions yet', style: TextStyle(color: scheme.textDim, fontSize: 13)),
              ],
            ),
          )
        else
          ...List.generate(_recentSessions.length, (i) {
            final s = _recentSessions[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: scheme.cardBackground,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: scheme.borderDim.withValues(alpha: 0.3), width: 0.5),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: scheme.text, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      s.id.length > 12 ? s.id.substring(0, 12) : s.id,
                      style: TextStyle(color: scheme.textMuted, fontSize: 10, fontFamily: 'monospace'),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      s.durationLabel,
                      style: TextStyle(color: scheme.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  // ── Open Source & Support ──────────────────────────────────────────────

  Widget _buildOpenSourceSection(AppColorScheme scheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.borderDim, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.code, size: 14, color: scheme.primary),
              const SizedBox(width: 8),
              Text('Open Source', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Hermes Wingman is free and open source software. '
            'Built with Flutter (frontend) and Rust (backend) — '
            'everyone is welcome to contribute, fork, and build.',
            style: TextStyle(color: scheme.textDim, fontSize: 11, height: 1.5),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _SupportButton(
                scheme: scheme,
                icon: Icons.code,
                label: 'View Source',
                onTap: () {},
              ),
              const SizedBox(width: 10),
              _SupportButton(
                scheme: scheme,
                icon: Icons.favorite_outline,
                label: 'Buy Me a Coffee',
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SupportButton extends StatelessWidget {
  final AppColorScheme scheme;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SupportButton({
    required this.scheme,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: scheme.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: scheme.borderDim, width: 0.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: scheme.primary),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(color: scheme.text, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final AppColorScheme scheme;
  final double width;
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? detail;

  const _StatusCard({
    required this.scheme,
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.borderDim, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: scheme.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value.length > 15 ? '${value.substring(0, 15)}…' : value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: scheme.text,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(
              detail!,
              style: TextStyle(color: scheme.textMuted, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final AppColorScheme scheme;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
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
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.borderDim, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: scheme.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
