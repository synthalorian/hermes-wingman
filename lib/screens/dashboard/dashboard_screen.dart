import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/theme_manager.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass_card.dart';
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
      backgroundColor: Colors.transparent,
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
      backgroundColor: Colors.transparent,
      elevation: 0,
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
            _GlassVersionBadge(scheme: scheme),
            const SizedBox(width: 6),
            Tooltip(
              message: 'Double-click to rename',
              child: Icon(Icons.edit_outlined, size: 10, color: scheme.textMuted.withAlpha(128)),
            ),
          ],
        ),
      ),
      actions: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: scheme.borderDim.withAlpha(40), width: 0.5),
          ),
          child: IconButton(
            icon: Icon(Icons.refresh, size: 16, color: scheme.textDim),
            onPressed: _loadAll,
            tooltip: 'Refresh',
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _goldSectionHeader(AppColorScheme scheme, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primary, scheme.accent],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: scheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(AppColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 48, color: scheme.error.withAlpha(153)),
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
                  color: scheme.primary.withAlpha(38),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: scheme.primary.withAlpha(50), width: 0.5),
                  ),
                  onPressed: _loadAll,
                  child: Text('Retry', style: TextStyle(color: scheme.primary)),
                ),
                const SizedBox(width: 12),
                MaterialButton(
                  color: scheme.accent.withAlpha(38),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: scheme.accent.withAlpha(50), width: 0.5),
                  ),
                  onPressed: () => widget.onNavigate?.call(8),
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
        GlassCard(
          scheme: scheme,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          blurSigma: 8,
          borderRadius: 6,
          tintColor: isOnline
              ? scheme.success.withAlpha(25)
              : scheme.error.withAlpha(25),
          borderColor: isOnline
              ? scheme.success.withAlpha(50)
              : scheme.error.withAlpha(50),
          glowColor: isOnline ? scheme.success : scheme.error,
          glowRadius: 6,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  color: isOnline ? scheme.success : scheme.error,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (isOnline ? scheme.success : scheme.error).withAlpha(128),
                      blurRadius: 4,
                    ),
                  ],
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
          GlassCard(
            scheme: scheme,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            blurSigma: 6,
            borderRadius: 6,
            child: Text(
              _status!.model,
              style: TextStyle(color: scheme.textDim, fontSize: 10, fontFamily: 'monospace'),
            ),
          ),
          if (_status!.version.isNotEmpty) ...[
            const SizedBox(width: 8),
            GlassCard(
              scheme: scheme,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              blurSigma: 4,
              borderRadius: 4,
              child: Text(
                _status!.version,
                style: TextStyle(color: scheme.textMuted, fontSize: 9, fontFamily: 'monospace'),
              ),
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
            _GlassStatusCard(
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
            _GlassStatusCard(
              scheme: scheme,
              width: cardWidth,
              label: 'CRON JOBS',
              value: '${_cronJobs.length}',
              icon: Icons.schedule_outlined,
              color: scheme.accent,
              detail: activeCrons > 0 ? '$activeCrons active' : null,
            ),
            const SizedBox(width: 16),
            _GlassStatusCard(
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
            _GlassStatusCard(
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
        _goldSectionHeader(scheme, 'QUICK ACTIONS'),
        Row(
          children: [
            _GlassActionButton(
              scheme: scheme,
              label: 'New Chat',
              icon: Icons.add_circle_outline,
              color: scheme.primary,
              onTap: _openTerminal,
            ),
            const SizedBox(width: 10),
            _GlassActionButton(
              scheme: scheme,
              label: 'Open Logs',
              icon: Icons.terminal,
              color: scheme.secondary,
              onTap: _openLogs,
            ),
            const SizedBox(width: 10),
            _GlassActionButton(
              scheme: scheme,
              label: 'Edit Config',
              icon: Icons.settings_outlined,
              color: scheme.accent,
              onTap: _openConfig,
            ),
            const SizedBox(width: 10),
            _GlassActionButton(
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

  void _openTerminal() => widget.onNavigate?.call(1);
  void _openLogs() => widget.onNavigate?.call(5);
  void _openConfig() => widget.onNavigate?.call(4);

  Widget _buildRecentActivity(AppColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _goldSectionHeader(scheme, 'RECENT SESSIONS'),
        if (_recentSessions.isEmpty)
          GlassCard(
            scheme: scheme,
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            borderRadius: 8,
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
              child: GlassCard(
                scheme: scheme,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                borderRadius: 6,
                blurSigma: 6,
                tintColor: scheme.cardBackground.withAlpha(180),
                child: Row(
                  children: [
                    Container(
                      width: 4, height: 4,
                      decoration: BoxDecoration(
                        color: scheme.primary.withAlpha(120),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: scheme.surfaceAlt.withAlpha(120),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        s.durationLabel,
                        style: TextStyle(color: scheme.textMuted, fontSize: 10),
                      ),
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
    return GlassCard(
      scheme: scheme,
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      borderRadius: 10,
      blurSigma: 8,
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
          const SizedBox(height: 10),
          Text(
            'Hermes Wingman is free and open source software. '
            'Built with Flutter (frontend) and Rust (backend) — '
            'everyone is welcome to contribute, fork, and build.',
            style: TextStyle(color: scheme.textDim, fontSize: 11, height: 1.6),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _GlassSupportBtn(
                  scheme: scheme,
                  icon: Icons.code,
                  label: 'View Source',
                  onTap: () => launchUrl(Uri.parse('https://github.com/synthalorian/hermes-wingman')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _GlassSupportBtn(
                  scheme: scheme,
                  icon: Icons.favorite_outline,
                  label: 'Buy Me a Coffee',
                  onTap: () => launchUrl(Uri.parse('https://buymeacoffee.com/yourusername')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Glass-themed Status Card ──────────────────────────────────────────────

class _GlassStatusCard extends StatelessWidget {
  final AppColorScheme scheme;
  final double width;
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? detail;

  const _GlassStatusCard({
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
    return AccentGlassCard(
      scheme: scheme,
      width: width,
      accentColor: color,
      padding: const EdgeInsets.all(16),
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

// ── Glass Action Button ──────────────────────────────────────────────────

class _GlassActionButton extends StatelessWidget {
  final AppColorScheme scheme;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _GlassActionButton({
    required this.scheme,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceAlt.withAlpha(150),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: scheme.borderDim.withAlpha(40), width: 0.5),
                    boxShadow: [
                      BoxShadow(color: color.withAlpha(15), blurRadius: 6),
                    ],
                  ),
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border(top: BorderSide(color: color.withAlpha(40), width: 0.5)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 15, color: color),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: TextStyle(
                          color: scheme.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Glass Version Badge ─────────────────────────────────────────────────

class _GlassVersionBadge extends StatelessWidget {
  final AppColorScheme scheme;
  const _GlassVersionBadge({required this.scheme});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.borderDim.withAlpha(30),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: scheme.borderDim.withAlpha(50), width: 0.5),
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
        ),
      ),
    );
  }
}

// ── Glass Support Button ─────────────────────────────────────────────────

class _GlassSupportBtn extends StatelessWidget {
  final AppColorScheme scheme;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _GlassSupportBtn({
    required this.scheme,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: scheme.surfaceAlt.withAlpha(150),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: scheme.borderDim.withAlpha(40), width: 0.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 13, color: scheme.primary),
                    const SizedBox(width: 6),
                    Text(label, style: TextStyle(color: scheme.text, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}