import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_manager.dart';
import '../../theme/app_theme.dart';
import '../../services/hermes_service.dart';
import '../../models/hermes_models.dart';

class CronScreen extends StatefulWidget {
  const CronScreen({super.key});

  @override
  State<CronScreen> createState() => _CronScreenState();
}

class _CronScreenState extends State<CronScreen> {
  List<HermesCronJob> _jobs = [];
  bool _loading = true;
  String? _error;
  HermesCronJob? _selectedJob;

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  Future<void> _loadJobs() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = context.read<HermesService>();
      final jobs = await client.listCronJobs();

      if (!mounted) return;
      setState(() {
        _jobs = jobs;
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
      appBar: AppBar(
        title: const Text('Cron'),
        actions: [
          if (!_loading)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${_jobs.length} jobs',
                  style: TextStyle(color: scheme.textMuted, fontSize: 12),
                ),
              ),
            ),
          IconButton(
            icon: Icon(Icons.refresh, size: 18, color: scheme.textDim),
            onPressed: _loadJobs,
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
              Text('Could not load cron jobs', style: TextStyle(color: scheme.textDim, fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: scheme.textMuted, fontSize: 12, fontFamily: 'monospace'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              MaterialButton(
                color: scheme.primary.withValues(alpha: 0.15),
                onPressed: _loadJobs,
                child: Text('Retry', style: TextStyle(color: scheme.primary)),
              ),
            ],
          ),
        ),
      );
    }

    if (_jobs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.schedule_outlined, size: 48, color: scheme.textMuted),
            const SizedBox(height: 16),
            Text('No cron jobs configured', style: TextStyle(color: scheme.textDim, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              'Use `hermes cron create` in the terminal to add one',
              style: TextStyle(color: scheme.textMuted, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Column headers
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: Text('NAME', style: TextStyle(color: scheme.textMuted, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1)),
                ),
                Expanded(
                  flex: 2,
                  child: Text('SCHEDULE', style: TextStyle(color: scheme.textMuted, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1)),
                ),
                Expanded(
                  flex: 2,
                  child: Text('PROMPT', style: TextStyle(color: scheme.textMuted, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1)),
                ),
                SizedBox(
                  width: 80,
                  child: Text('STATUS', style: TextStyle(color: scheme.textMuted, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1)),
                ),
                const SizedBox(width: 70),
              ],
            ),
          ),
          // Job rows
          Expanded(
            child: ListView.builder(
              itemCount: _jobs.length,
              itemBuilder: (context, i) {
                final job = _jobs[i];
                final selected = _selectedJob?.id == job.id;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Material(
                    color: selected ? scheme.selectedBackground : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => setState(() => _selectedJob = selected ? null : job),
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
                            // Status dot
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: job.status == 'active'
                                    ? scheme.success
                                    : job.status == 'paused'
                                        ? scheme.warning
                                        : scheme.error,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: Text(
                                job.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: scheme.text, fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                job.schedule,
                                style: TextStyle(color: scheme.textDim, fontSize: 11, fontFamily: 'monospace'),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                job.prompt.length > 40 ? '${job.prompt.substring(0, 40)}...' : job.prompt,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: scheme.textDim, fontSize: 11),
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: Text(
                                job.status.toUpperCase(),
                                style: TextStyle(
                                  color: job.status == 'active' ? scheme.success : scheme.textMuted,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            // Toggle
                            SizedBox(
                              width: 60,
                              child: Switch(
                                value: job.status == 'active',
                                onChanged: (_) {},
activeThumbColor: scheme.primary,
                                inactiveTrackColor: scheme.borderDim,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
