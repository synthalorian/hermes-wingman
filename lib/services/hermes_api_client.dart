import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'hermes_service.dart';
import '../models/hermes_models.dart';

// ── Backend Connection State ──────────────────────────────────────────────

enum BackendConnectionState { initializing, connected, failed, notFound }

/// Detects if running on mobile (Android/iOS).
bool get _isMobile => Platform.isAndroid || Platform.isIOS;

/// Manages the Rust backend process lifecycle (desktop) or remote connection (mobile).
/// On desktop: checks if already running, starts if not.
/// On mobile: connects to a user-configured remote backend host.
class BackendService extends ChangeNotifier implements HermesService {
  Process? _process;
  BackendConnectionState _state = BackendConnectionState.initializing;
  String? _lastError;
  final HttpClient _client = HttpClient();
  String _baseUrl = 'http://127.0.0.1:9120';
  bool _started = false;

  BackendConnectionState get state => _state;
  String? get lastError => _lastError;
  bool get isRunning => _state == BackendConnectionState.connected;
  String get baseUrl => _baseUrl;
  bool get isRemote => _isMobile;

  /// Set a custom backend URL (for mobile remote connections).
  void setBaseUrl(String host, int port) {
    _baseUrl = 'http://$host:$port';
    debugPrint('[BackendService] Base URL set to: $_baseUrl');
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────

  /// Start or connect to the backend. Called once from main().
  /// On mobile, just tries to connect to the configured remote URL.
  Future<bool> start({Duration timeout = const Duration(seconds: 8)}) async {
    if (_started) return _state == BackendConnectionState.connected;
    _started = true;

    if (_isMobile) {
      // Mobile: just try to connect to the configured backend
      debugPrint('[BackendService] Mobile mode — connecting to $_baseUrl');
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        if (await _checkHealth()) {
          _state = BackendConnectionState.connected;
          notifyListeners();
          return true;
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
      _state = BackendConnectionState.failed;
      _lastError = 'Could not connect to $_baseUrl — is the backend running?';
      notifyListeners();
      return false;
    }

    // Desktop: check if already running
    if (await _checkPort(9120)) {
      debugPrint('[BackendService] Found existing backend on port 9120');
      _state = BackendConnectionState.connected;
      notifyListeners();
      return true;
    }

    // Desktop: find and start the binary
    final binary = await _findBinary();
    if (binary == null) {
      _state = BackendConnectionState.notFound;
      _lastError = 'Backend binary not found. Run: cd backend && cargo build --release';
      notifyListeners();
      return false;
    }

    debugPrint('[BackendService] Starting backend: $binary');
    try {
      _process = await Process.start(binary, [],
        runInShell: false,
        environment: { 'HOME': Platform.environment['HOME'] ?? '/tmp' },
      );
      _process!.stderr.listen((_) {});

      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        if (await _checkHealth()) {
          _state = BackendConnectionState.connected;
          notifyListeners();
          return true;
        }
        await Future.delayed(const Duration(milliseconds: 200));
      }

      _state = BackendConnectionState.failed;
      _lastError = 'Backend did not become healthy within ${timeout.inSeconds}s';
      notifyListeners();
      return false;
    } catch (e) {
      _state = BackendConnectionState.failed;
      _lastError = 'Failed to start backend: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> stop() async {
    if (_isMobile) {
      // No process to kill on mobile
      _state = BackendConnectionState.initializing;
      _started = false;
      notifyListeners();
      return;
    }
    if (_process != null) {
      _process!.kill();
      await _process!.exitCode.timeout(const Duration(seconds: 3), onTimeout: () => -1);
      _process = null;
    }
    _state = BackendConnectionState.initializing;
    _started = false;
    notifyListeners();
  }

  /// Retry connecting — useful after changing the backend URL on mobile.
  Future<bool> reconnect() async {
    _started = false;
    _state = BackendConnectionState.initializing;
    notifyListeners();
    return start(timeout: const Duration(seconds: 5));
  }

  // ── Binary Discovery (desktop only) ─────────────────────────────────────

  Future<String?> _findBinary() async {
    if (_isMobile) return null;

    final candidates = [
      'backend/target/release/hermes-wingman-backend',
      'backend/target/debug/hermes-wingman-backend',
      'hermes-wingman-backend',
      '../MacOS/hermes-wingman-backend',
      '../hermes-wingman-backend',
      '${Platform.resolvedExecutable.substring(0, Platform.resolvedExecutable.lastIndexOf('/'))}/hermes-wingman-backend',
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) return File(path).absolute.path;
    }

    final home = Platform.environment['HOME'] ?? '/tmp';
    final alt = [
      '$home/projects/hermes_wingman/backend/target/release/hermes-wingman-backend',
      '$home/projects/hermes_wingman/backend/target/debug/hermes-wingman-backend',
      '$home/.local/bin/hermes-wingman-backend',
      '$home/.cargo/bin/hermes-wingman-backend',
      '/opt/homebrew/bin/hermes-wingman-backend',
      '/usr/local/bin/hermes-wingman-backend',
    ];
    for (final path in alt) {
      if (File(path).existsSync()) return path;
    }

    return null;
  }

  // ── Connection Checks ─────────────────────────────────────────────────

  Future<bool> _checkPort(int port) async {
    if (_isMobile) return false;
    try {
      final socket = await Socket.connect('127.0.0.1', port,
        timeout: const Duration(seconds: 1));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _checkHealth() async {
    try {
      final request = await _client.getUrl(Uri.parse('$_baseUrl/health'));
      request.headers.set('Content-Type', 'application/json');
      final response = await request.close();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── HTTP Helpers ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(String path) async {
    final request = await _client.getUrl(Uri.parse('$_baseUrl$path'));
    request.headers.set('Content-Type', 'application/json');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw HermesClientException('HTTP ${response.statusCode}: $body', command: 'GET $path');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final request = await _client.postUrl(Uri.parse('$_baseUrl$path'));
    request.headers.set('Content-Type', 'application/json');
    request.write(jsonEncode(body));
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw HermesClientException('HTTP ${response.statusCode}: $responseBody', command: 'POST $path');
    }
    return jsonDecode(responseBody) as Map<String, dynamic>;
  }

  // ── HermesService Implementation ──────────────────────────────────────

  @override
  Future<bool> isHermesAvailable() async {
    try {
      final data = await _get('/health');
      return data['hermes_installed'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<HermesStatus> getStatus() async {
    String model = '';
    String provider = '';
    try {
      final modelsData = await _get('/models');
      model = modelsData['current'] as String? ?? '';
      provider = modelsData['provider'] as String? ?? '';
    } catch (_) {}

    String version = '';
    try {
      final healthData = await _get('/health');
      version = healthData['hermes_version'] as String? ?? '';
      if (version.contains('\n')) version = version.split('\n').first.trim();
    } catch (_) {}

    return HermesStatus(
      model: model,
      provider: provider,
      isRunning: true,
      version: version,
      pythonVersion: '',
    );
  }

  @override
  Future<String> getStatusRaw() async {
    final data = await _get('/health');
    return jsonEncode(data);
  }

  @override
  Future<List<HermesSession>> listSessions({int limit = 20}) async {
    final data = await _get('/sessions?limit=$limit');
    final list = data['sessions'] as List? ?? [];
    return list.map((s) {
      final m = s as Map<String, dynamic>;
      return HermesSession(
        id: m['id'] ?? '',
        title: m['title'] ?? 'Untitled',
        model: '—',
        provider: '—',
        messageCount: 0,
        createdAt: DateTime.now(),
      );
    }).toList();
  }

  @override
  Future<String> getSessionStats() async {
    final data = await _get('/sessions');
    return '${data['count'] ?? 0} sessions';
  }

  @override
  Future<String> getConfigRaw() async {
    final data = await _get('/config');
    return data['raw'] as String? ?? '';
  }

  @override
  Future<String?> getConfigValue(String key) async {
    final data = await _get('/config');
    final parsed = data['parsed'] as Map<String, dynamic>? ?? {};
    final parts = key.split('.');
    dynamic current = parsed;
    for (final part in parts) {
      if (current is Map && current.containsKey(part)) {
        current = current[part];
      } else {
        return null;
      }
    }
    return current?.toString();
  }

  @override
  Future<void> setConfigValue(String key, String value) async {
    await _post('/config/update', {'updates': {key: value}});
  }

  @override
  Future<List<LogEntry>> readLogs({int lines = 50, String level = 'all'}) async {
    final data = await _get('/logs?lines=$lines&level=$level');
    final entries = data['entries'] as List? ?? [];
    return entries.map((e) {
      final m = e as Map<String, dynamic>;
      return LogEntry(
        level: m['level'] ?? 'INFO',
        message: m['message'] ?? '',
        timestamp: DateTime.tryParse(m['timestamp'] ?? '') ?? DateTime.now(),
      );
    }).toList();
  }

  @override
  Future<List<HermesCronJob>> listCronJobs() async {
    final data = await _get('/cron');
    final jobs = data['jobs'] as List? ?? [];
    return jobs.map((j) {
      final m = j as Map<String, dynamic>;
      return HermesCronJob(
        id: m['raw'] ?? '',
        name: m['raw'] ?? 'Job',
        schedule: '—',
        prompt: '',
      );
    }).toList();
  }

  @override
  Future<List<GatewayPlatform>> getGatewayStatus() async {
    final data = await _get('/gateway');
    final platforms = data['platforms'] as List? ?? [];
    return platforms.map((p) {
      final m = p as Map<String, dynamic>;
      return GatewayPlatform(
        name: m['name'] ?? '',
        isConnected: m['state'] == 'connected',
        icon: _platformIcon(m['name'] ?? ''),
      );
    }).toList();
  }

  String _platformIcon(String name) {
    switch (name) {
      case 'discord': return '💬';
      case 'telegram': return '✈️';
      case 'slack': return '🔲';
      case 'whatsapp': return '📱';
      case 'signal': return '🔒';
      case 'email': return '📧';
      case 'sms': return '💭';
      case 'homeassistant': return '🏠';
      default: return '🔌';
    }
  }

  @override
  Future<void> writeConfig(String content) async {
    await _post('/config/write', {'content': content});
  }

  /// Direct HTTP access for screens that need raw API access.
  Future<Map<String, dynamic>> httpGet(String path) => _get(path);

  /// Direct HTTP POST for screens that need raw API access.
  Future<Map<String, dynamic>> httpPost(String path, Map<String, dynamic> body) => _post(path, body);

  /// Toggle gateway.
  Future<Map<String, dynamic>> gatewayToggle(String action) async {
    return await _post('/gateway/toggle', {'action': action});
  }

  @override
  Future<String> runHermesCommand(List<String> args) async {
    if (args.length == 2 && args[0] == 'gateway' && (args[1] == 'stop' || args[1] == 'start')) {
      final result = await _post('/gateway/toggle', {'action': args[1]});
      return jsonEncode(result);
    }
    // On mobile, shell to hermes CLI is not available
    if (_isMobile) {
      throw HermesClientException('hermes CLI not available on mobile', command: args.join(' '));
    }
    final result = await Process.run('hermes', args, runInShell: false);
    if (result.exitCode != 0) {
      throw HermesClientException(
        'Command failed',
        command: args.join(' '),
        exitCode: result.exitCode,
        stderr: (result.stderr as String?)?.trim(),
      );
    }
    return (result.stdout as String).trim();
  }
}

class HermesClientException implements Exception {
  final String message;
  final String? command;
  final int? exitCode;
  final String? stderr;

  HermesClientException(this.message, {this.command, this.exitCode, this.stderr});

  @override
  String toString() => 'HermesClientException: $message';
}
