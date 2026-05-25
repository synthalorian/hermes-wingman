import 'dart:convert';
import 'dart:io';

import 'hermes_service.dart';
import '../models/hermes_models.dart';

/// Error thrown when the hermes binary cannot be found or a command fails.
class HermesClientException implements Exception {
  final String message;
  final String? command;
  final int? exitCode;
  final String? stderr;

  HermesClientException(this.message, {this.command, this.exitCode, this.stderr});

  @override
  String toString() => 'HermesClientException: $message'
      '${command != null ? "\n  Command: $command" : ""}'
      '${exitCode != null ? "\n  Exit: $exitCode" : ""}'
      '${stderr != null ? "\n  Stderr: $stderr" : ""}';
}

/// Communication layer between Hermes Wingman and the local Hermes installation.
///
/// Discovers the `hermes` binary, runs CLI commands, reads config files and
/// the SQLite session store, and tails log files — all without needing a server.
class HermesClient implements HermesService {
  String? _hermesPath;
  String? _hermesHome;
  bool _discovered = false;

  /// Find the `hermes` binary in PATH.
  Future<String> _findHermesBinary() async {
    if (_hermesPath != null) return _hermesPath!;

    // Try `which hermes`
    try {
      final result = await Process.run('which', ['hermes']);
      if (result.exitCode == 0) {
        _hermesPath = (result.stdout as String).trim();
        return _hermesPath!;
      }
    } catch (_) {}

    // Try `where hermes` (Windows)
    try {
      final result = await Process.run('where', ['hermes']);
      if (result.exitCode == 0) {
        _hermesPath = (result.stdout as String).trim().split('\n').first;
        return _hermesPath!;
      }
    } catch (_) {}

    // Common locations
    final commonPaths = [
      '/home/synth/.local/bin/hermes',
      '/usr/local/bin/hermes',
      '/opt/homebrew/bin/hermes',
    ];
    for (final path in commonPaths) {
      if (File(path).existsSync()) {
        _hermesPath = path;
        return _hermesPath!;
      }
    }

    throw HermesClientException(
      'Could not find `hermes` binary. '
      'Make sure Hermes Agent is installed and on your PATH.',
    );
  }

  /// Resolve ~/.hermes home directory.
  Future<String> get hermesHome async {
    if (_hermesHome != null) return _hermesHome!;

    // HERMES_HOME env var takes precedence
    final envHome = Platform.environment['HERMES_HOME'];
    if (envHome != null && envHome.isNotEmpty) {
      _hermesHome = envHome;
      return _hermesHome!;
    }

    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '/home/synth';
    _hermesHome = '$home/.hermes';
    return _hermesHome!;
  }

  /// Run a `hermes` CLI command and return stdout.
  Future<String> runHermesCommand(List<String> args) async {
    final binary = await _findHermesBinary();
    try {
      final result = await Process.run(
        binary,
        args,
        runInShell: true,
      );
      if (result.exitCode != 0) {
        throw HermesClientException(
          'Command failed',
          command: [binary, ...args].join(' '),
          exitCode: result.exitCode,
          stderr: (result.stderr as String?)?.trim(),
        );
      }
      return (result.stdout as String).trim();
    } catch (e) {
      if (e is HermesClientException) rethrow;
      throw HermesClientException(
        'Failed to run command: $e',
        command: [binary, ...args].join(' '),
      );
    }
  }

  /// Determine if hermes is installed and accessible.
  Future<bool> isHermesAvailable() async {
    if (_discovered) return _hermesPath != null;
    try {
      await _findHermesBinary();
      _discovered = true;
      return true;
    } catch (_) {
      _discovered = true;
      return false;
    }
  }

  // ── Status ─────────────────────────────────────────────────────────────

  /// Fetch the current status of the Hermes agent.
  Future<HermesStatus> getStatus() async {
    final output = await runHermesCommand(['status']);
    final lines = output.split('\n');

    String model = 'unknown';
    String provider = 'unknown';
    String version = '';
    String pythonVersion = '';

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('Model:')) {
        model = trimmed.split(':').sublist(1).join(':').trim();
      } else if (trimmed.startsWith('Provider:')) {
        provider = trimmed.split(':').sublist(1).join(':').trim();
      } else if (trimmed.startsWith('Version:') ||
          trimmed.startsWith('Hermes')) {
        final parts = trimmed.split('v');
        if (parts.length > 1) {
          version = 'v${parts.last.split(' ').first}';
        }
      } else if (trimmed.startsWith('Python:')) {
        pythonVersion = trimmed.split(':').sublist(1).join(':').trim();
      }
    }

    return HermesStatus(
      model: model,
      provider: provider,
      version: version,
      pythonVersion: pythonVersion,
      isRunning: true,
    );
  }

  /// Get the full status text (raw output) for display.
  Future<String> getStatusRaw() async {
    return runHermesCommand(['status']);
  }

  // ── Sessions ───────────────────────────────────────────────────────────

  /// List recent sessions from the Hermes session store.
  Future<List<HermesSession>> listSessions({int limit = 20}) async {
    try {
      final output = await runHermesCommand(
        ['sessions', 'list', '--limit', limit.toString()],
      );
      return _parseSessionList(output);
    } catch (e) {
      // Fallback: try reading state.db directly
      return _readSessionsFromDb(limit: limit);
    }
  }

  List<HermesSession> _parseSessionList(String output) {
    final sessions = <HermesSession>[];
    final lines = output.split('\n');

    // Try JSON output
    try {
      final json = jsonDecode(output);
      if (json is List) {
        return json
            .map((e) => HermesSession.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    // Column positions: Title[0-32], Preview[33-73], LastActive[74-87], ID[88+]
    const titleEnd = 32;

    for (final line in lines) {
      final trimmed = line.trimRight();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('Title')) continue; // header
      if (trimmed.startsWith('─') || trimmed.startsWith('-')) continue; // separator
      if (trimmed.startsWith('No ') || trimmed.startsWith('No\t')) {
        continue;
      }

      // Fixed-width parsing
      if (trimmed.length < 88) continue; // need at least the ID column
      final title = trimmed.substring(0, titleEnd + 1).trim();
      final id = trimmed.substring(88).trim();
      if (id.isEmpty) continue;
      if (id.startsWith('─') || id.startsWith('-')) continue;

      sessions.add(HermesSession(
        id: id,
        title: title.isNotEmpty ? title : 'Untitled',
        model: '—',
        provider: '—',
        messageCount: 0,
        createdAt: DateTime.now(),
      ));
    }

    return sessions;
  }

  Future<List<HermesSession>> _readSessionsFromDb({int limit = 20}) async {
    // Future: direct SQLite read from state.db
    // For now, return empty — the CLI fallback covers most cases
    return [];
  }

  /// Get the session store stats.
  Future<String> getSessionStats() async {
    try {
      return await runHermesCommand(['sessions', 'stats']);
    } catch (_) {
      return 'Session stats unavailable';
    }
  }

  // ── Config ─────────────────────────────────────────────────────────────

  /// Read the entire config.yaml as a string.
  Future<String> getConfigRaw() async {
    final home = await hermesHome;
    final configFile = File('$home/config.yaml');
    if (await configFile.exists()) {
      return configFile.readAsString();
    }
    throw HermesClientException('config.yaml not found at $home/config.yaml');
  }

  /// Read a specific config value.
  Future<String?> getConfigValue(String key) async {
    try {
      // `hermes config get <key>` might not exist, try generic output
      final raw = await getConfigRaw();
      for (final line in raw.split('\n')) {
        if (line.trimLeft().startsWith('$key:')) {
          return line.split(':').sublist(1).join(':').trim();
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Set a config value via `hermes config set`.
  Future<void> setConfigValue(String key, String value) async {
    await runHermesCommand(['config', 'set', key, value]);
  }

  // ── Logs ───────────────────────────────────────────────────────────────

  /// Read the last N lines of agent.log.
  Future<List<LogEntry>> readLogs({int lines = 50, String level = 'info'}) async {
    try {
      final args = ['logs'];
      if (level != 'all') {
        args.add('--level');
        args.add(level);
      }
      // Append bogus option so we can get the last N lines
      // Actually use tail approach
      final output = await runHermesCommand(args);

      final entries = <LogEntry>[];
      final logLines = output.split('\n').where((l) => l.trim().isNotEmpty);

      for (final line in logLines.take(lines)) {
        entries.add(LogEntry.fromLogLine(line));
      }
      return entries;
    } catch (_) {
      // Fallback: read log files directly
      return _readLogFilesDirectly(lines: lines, level: level);
    }
  }

  Future<List<LogEntry>> _readLogFilesDirectly({
    int lines = 50,
    String level = 'all',
  }) async {
    final home = await hermesHome;
    final logFile = File('$home/logs/agent.log');

    if (!await logFile.exists()) return [];

    final content = await logFile.readAsString();
    final logLines = content.split('\n').where((l) => l.trim().isNotEmpty).toList();

    final entries = <LogEntry>[];
    final reversed = logLines.reversed.take(lines * 3).toList().reversed;

    for (final line in reversed) {
      if (entries.length >= lines) break;
      final entry = LogEntry.fromLogLine(line);
      if (level == 'all' ||
          (level == 'error' && entry.level == 'ERROR') ||
          (level == 'warning' && (entry.level == 'WARNING' || entry.level == 'ERROR')) ||
          (level == 'info' && entry.level == 'INFO')) {
        entries.add(entry);
      }
    }

    return entries;
  }

  // ── Cron Jobs ──────────────────────────────────────────────────────────

  /// List all cron jobs.
  Future<List<HermesCronJob>> listCronJobs() async {
    try {
      final output = await runHermesCommand(['cron', 'list']);
      return _parseCronJobs(output);
    } catch (_) {
      return [];
    }
  }

  List<HermesCronJob> _parseCronJobs(String output) {
    final jobs = <HermesCronJob>[];
    final lines = output.split('\n');

    // Try JSON
    try {
      final json = jsonDecode(output);
      if (json is List) {
        return json
            .map((e) => HermesCronJob.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    // Simple line-based parsing
    for (final line in lines) {
      if (line.trim().isEmpty || line.contains('──') || line.contains('No cron')) {
        continue;
      }
      final parts = line.trim().split(RegExp(r'\s{2,}'));
      if (parts.length >= 2) {
        jobs.add(HermesCronJob(
          id: parts[0],
          name: parts.length > 1 ? parts[1] : 'Job',
          schedule: parts.length > 2 ? parts[2] : '—',
          prompt: '',
        ));
      }
    }

    return jobs;
  }

  // ── Gateway ────────────────────────────────────────────────────────────

  /// Write full config content.
  Future<void> writeConfig(String content) async {
    final home = await hermesHome;
    final configFile = File('$home/config.yaml');
    await configFile.writeAsString(content);
  }

  /// Get gateway status from gateway_state.json
  Future<List<GatewayPlatform>> getGatewayStatus() async {
    try {
      final home = await hermesHome;
      final stateFile = File('$home/gateway_state.json');
      if (!await stateFile.exists()) return [];

      final content = await stateFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final platforms = <GatewayPlatform>[];

      final platformsJson = json['platforms'] as Map<String, dynamic>?;
      if (platformsJson == null) return [];

      for (final entry in platformsJson.entries) {
        final name = entry.key;
        final data = entry.value as Map<String, dynamic>? ?? {};
        final state = data['state'] as String? ?? 'disconnected';
        platforms.add(GatewayPlatform(
          name: name,
          isConnected: state == 'connected',
          messagesProcessed: 0,
          icon: _platformIcon(name),
        ));
      }

      return platforms;
    } catch (_) {
      return [];
    }
  }

  String _platformIcon(String name) {
    switch (name) {
      case 'discord':
        return '💬';
      case 'telegram':
        return '✈️';
      case 'slack':
        return '🔲';
      case 'whatsapp':
        return '📱';
      case 'signal':
        return '🔒';
      case 'email':
        return '📧';
      case 'sms':
        return '💭';
      case 'homeassistant':
        return '🏠';
      default:
        return '🔌';
    }
  }

  // ── Skills ──────────────────────────────────────────────────────────

  @override
  Future<List<SkillEntry>> listSkills() async {
    try {
      final output = await runHermesCommand(['skills', 'list']);
      final lines = output.split('\n');
      final skills = <SkillEntry>[];
      for (final line in lines) {
        if (line.contains('│') && !line.contains('━━━') && !line.contains('───')) {
          final parts = line.split('│');
          if (parts.length >= 2) {
            final name = parts[1].trim();
            if (name.isNotEmpty && !name.startsWith('Name')) {
              skills.add(SkillEntry(
                name: name,
                category: parts.length > 2 ? parts[2].trim() : '',
              ));
            }
          }
        }
      }
      return skills;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<bool> toggleSkill(String name, {String action = 'toggle'}) async {
    try {
      await runHermesCommand(['skills', action, name]);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Memory ──────────────────────────────────────────────────────────

  @override
  Future<List<MemoryEntry>> listMemory() async {
    try {
      final output = await runHermesCommand(['memory', 'list']);
      final lines = output.split('\n');
      return lines
          .where((l) => l.trim().isNotEmpty)
          .map((l) => MemoryEntry(key: l.trim(), content: l.trim()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<MemoryEntry?> getMemory(String id) async {
    try {
      final output = await runHermesCommand(['memory', 'get', id]);
      return MemoryEntry(key: id, content: output.trim(), id: id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> deleteMemory(String id) async {
    try {
      await runHermesCommand(['memory', 'delete', id]);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<MemoryEntry>> searchMemory(String query) async {
    try {
      final output = await runHermesCommand(['memory', 'search', query]);
      return output.split('\n')
          .where((l) => l.trim().isNotEmpty)
          .map((l) => MemoryEntry(key: l.trim(), content: l.trim()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Files ───────────────────────────────────────────────────────────

  @override
  Future<FileListing> listFiles({String path = ''}) async {
    // On desktop, read files directly
    try {
      final dir = Directory('${Platform.environment['HOME'] ?? '/tmp'}/.hermes');
      final target = path.isEmpty ? dir : Directory('${dir.path}/$path');
      if (!target.existsSync()) return FileListing(path: target.path);
      final entries = target.listSync();
      final dirs = <String>[];
      final files = <String>[];
      for (final e in entries) {
        final name = e.path.split('/').last;
        if (name.startsWith('.')) continue;
        if (e is Directory) { dirs.add(name); } else { files.add(name); }
      }
      dirs.sort();
      files.sort();
      return FileListing(
        path: target.path,
        directories: dirs,
        files: files,
        parent: path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '',
      );
    } catch (_) {
      return FileListing();
    }
  }

  @override
  Future<String?> readFile(String path) async {
    try {
      final home = Platform.environment['HOME'] ?? '/tmp';
      final file = File('$home/.hermes/$path');
      if (!file.existsSync()) return null;
      return file.readAsStringSync();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> writeFile(String path, String content) async {
    try {
      final home = Platform.environment['HOME'] ?? '/tmp';
      final file = File('$home/.hermes/$path');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
      return true;
    } catch (_) {
      return false;
    }
  }
}
