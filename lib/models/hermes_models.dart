/// Represents a Hermes agent session.
class HermesSession {
  final String id;
  final String title;
  final String model;
  final String provider;
  final int messageCount;
  final DateTime createdAt;
  final DateTime? lastActivity;
  final String status; // active, idle, completed

  HermesSession({
    required this.id,
    required this.title,
    required this.model,
    required this.provider,
    required this.messageCount,
    required this.createdAt,
    this.lastActivity,
    this.status = 'active',
  });

  factory HermesSession.fromJson(Map<String, dynamic> json) {
    return HermesSession(
      id: json['id'] ?? '',
      title: json['title'] ?? json['name'] ?? 'Untitled',
      model: json['model'] ?? 'unknown',
      provider: json['provider'] ?? 'unknown',
      messageCount: json['message_count'] ?? json['messages'] ?? 0,
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      lastActivity: json['last_activity'] != null
          ? DateTime.tryParse(json['last_activity'])
          : null,
      status: json['status'] ?? 'active',
    );
  }

  String get durationLabel {
    if (lastActivity == null) return '—';
    final diff = DateTime.now().difference(lastActivity!);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes == 1) return '1 min ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes} mins ago';
    if (diff.inHours == 1) return '1 hour ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    if (diff.inDays == 1) return '1 day ago';
    return '${diff.inDays} days ago';
  }

  String get createdLabel {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes == 1) return '1 min ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes} mins ago';
    if (diff.inHours == 1) return '1 hour ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    if (diff.inDays == 1) return '1 day ago';
    return '${diff.inDays} days ago';
  }
}

/// Status snapshot of the Hermes agent itself.
class HermesStatus {
  final String model;
  final String provider;
  final bool isRunning;
  final String version;
  final String pythonVersion;
  final int activeSessions;
  final String uptime;

  HermesStatus({
    required this.model,
    required this.provider,
    this.isRunning = true,
    this.version = '',
    this.pythonVersion = '',
    this.activeSessions = 0,
    this.uptime = '',
  });

  factory HermesStatus.fromJson(Map<String, dynamic> json) {
    return HermesStatus(
      model: json['model'] ?? json['default_model'] ?? 'unknown',
      provider: json['provider'] ?? json['default_provider'] ?? 'unknown',
      isRunning: json['is_running'] ?? true,
      version: json['version'] ?? '',
      pythonVersion: json['python_version'] ?? '',
      activeSessions: json['active_sessions'] ?? 0,
      uptime: json['uptime'] ?? '',
    );
  }
}

/// A configured cron job.
class HermesCronJob {
  final String id;
  final String name;
  final String schedule;
  final String prompt;
  final String status; // active, paused, error
  final DateTime? lastRun;
  final DateTime? nextRun;
  final String? lastOutput;

  HermesCronJob({
    required this.id,
    required this.name,
    required this.schedule,
    required this.prompt,
    this.status = 'active',
    this.lastRun,
    this.nextRun,
    this.lastOutput,
  });

  factory HermesCronJob.fromJson(Map<String, dynamic> json) {
    return HermesCronJob(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unnamed Job',
      schedule: json['schedule'] ?? '—',
      prompt: json['prompt'] ?? '',
      status: json['status'] ?? 'active',
      lastRun: json['last_run'] != null
          ? DateTime.tryParse(json['last_run'])
          : null,
      nextRun: json['next_run'] != null
          ? DateTime.tryParse(json['next_run'])
          : null,
      lastOutput: json['last_output'],
    );
  }
}

/// A connected gateway platform.
class GatewayPlatform {
  final String name;
  final bool isConnected;
  final int messagesProcessed;
  final String? lastActivity;
  final String icon; // emoji or unicode

  GatewayPlatform({
    required this.name,
    this.isConnected = false,
    this.messagesProcessed = 0,
    this.lastActivity,
    this.icon = '🔌',
  });

  factory GatewayPlatform.fromJson(Map<String, dynamic> json) {
    return GatewayPlatform(
      name: json['name'] ?? 'Unknown',
      isConnected: json['is_connected'] ?? json['connected'] ?? false,
      messagesProcessed: json['messages_processed'] ?? 0,
      lastActivity: json['last_activity'],
      icon: json['icon'] ?? '🔌',
    );
  }
}

/// A log entry from agent.log or errors.log.
class LogEntry {
  final String level; // INFO, WARNING, ERROR
  final String message;
  final DateTime timestamp;
  final String? source;

  LogEntry({
    required this.level,
    required this.message,
    required this.timestamp,
    this.source,
  });

  /// Simple parser for Hermes log lines like:
  /// 2026-05-17 12:34:56,789 [INFO] Some message here
  factory LogEntry.fromLogLine(String line) {
    final levelRegex = RegExp(r'\[(INFO|WARNING|ERROR|DEBUG|CRITICAL)\]');
    final timestampRegex =
        RegExp(r'(\d{4}-\d{2}-\d{2}[\sT]\d{2}:\d{2}:\d{2})');

    final levelMatch = levelRegex.firstMatch(line);
    final timestampMatch = timestampRegex.firstMatch(line);

    String level = levelMatch?.group(1) ?? 'INFO';
    DateTime timestamp =
        timestampMatch != null
            ? DateTime.tryParse(timestampMatch.group(1)!.replaceAll('T', ' ')) ??
                DateTime.now()
            : DateTime.now();

    // Remove timestamp and level to get the message
    String message = line;
    if (timestampMatch != null) {
      message = message.replaceFirst(timestampMatch.group(1)!, '').trim();
    }
    if (levelMatch != null) {
      message = message.replaceFirst(levelMatch.group(0)!, '').trim();
    }

    return LogEntry(
      level: level,
      message: message,
      timestamp: timestamp,
    );
  }

  ColorCode get colorCode {
    switch (level) {
      case 'ERROR':
      case 'CRITICAL':
        return ColorCode.error;
      case 'WARNING':
        return ColorCode.warning;
      case 'DEBUG':
        return ColorCode.dim;
      default:
        return ColorCode.normal;
    }
  }
}

enum ColorCode { normal, warning, error, dim }
