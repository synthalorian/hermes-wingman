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
      // If the saved URL didn't work, try LAN discovery
      debugPrint('[BackendService] Saved URL failed — scanning LAN...');
      final discovered = await _discoverOnLAN();
      if (discovered != null) {
        _baseUrl = discovered;
        if (await _checkHealth()) {
          _state = BackendConnectionState.connected;
          notifyListeners();
          return true;
        }
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
        environment: {
          'HOME': Platform.environment['HOME'] ?? '/tmp',
          'PATH': Platform.environment['PATH'] ?? '/usr/local/bin:/usr/bin:/bin',
          'BIND_ADDR': '0.0.0.0:9120',
        },
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

  Future<Map<String, dynamic>> _get(String path, [Map<String, String>? queryParams]) async {
    var uri = Uri.parse('$_baseUrl$path');
    if (queryParams != null && queryParams.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParams);
    }
    final request = await _client.getUrl(uri);
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

  Future<Map<String, dynamic>> _deleteRequest(String path) async {
    final request = await _client.deleteUrl(Uri.parse('$_baseUrl$path'));
    request.headers.set('Content-Type', 'application/json');
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw HermesClientException('HTTP ${response.statusCode}: $responseBody', command: 'DELETE $path');
    }
    return jsonDecode(responseBody) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _put(String path, Map<String, dynamic> body) async {
    final request = await _client.putUrl(Uri.parse('$_baseUrl$path'));
    request.headers.set('Content-Type', 'application/json');
    request.write(jsonEncode(body));
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw HermesClientException('HTTP ${response.statusCode}: $responseBody', command: 'PUT $path');
    }
    return jsonDecode(responseBody) as Map<String, dynamic>;
  }

  // ── HermesService Implementation ──────────────────────────────────────

  /// Try to discover a Hermes Wingman backend on the local network.
  /// Scans common private subnet IPs on port 9120.
  Future<String?> _discoverOnLAN() async {
    // Get our own IP to determine the subnet
    try {
      final interfaces = await NetworkInterface.list();
      String? subnet;
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
              break;
            }
          }
        }
        if (subnet != null) break;
      }
      if (subnet == null) return null;

      // Scan common hosts (1-20, 50-60, 100-110, 200-210) — covers most LANs
      final hosts = [
        for (var i = 1; i <= 20; i++) i,
        for (var i = 50; i <= 60; i++) i,
        for (var i = 100; i <= 110; i++) i,
        for (var i = 200; i <= 210; i++) i,
      ];
      for (final host in hosts) {
        try {
          final url = 'http://$subnet.$host:9120';
          final socket = await Socket.connect('$subnet.$host', 9120,
            timeout: const Duration(milliseconds: 300));
          socket.destroy();
          // If connect succeeded, the port is open — check health
          final request = await _client.getUrl(Uri.parse('$url/health'));
          final response = await request.close();
          if (response.statusCode == 200) {
            debugPrint('[BackendService] Discovered backend at $url');
            return url;
          }
        } catch (_) {
          continue;
        }
      }
    } catch (_) {}
    return null;
  }

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

  /// Direct HTTP GET that returns a list (for array-returning endpoints).
  Future<List<dynamic>> httpGetList(String path) async {
    var uri = Uri.parse('$_baseUrl$path');
    final request = await _client.getUrl(uri);
    request.headers.set('Content-Type', 'application/json');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw HermesClientException('HTTP ${response.statusCode}: $body', command: 'GET $path');
    }
    return jsonDecode(body) as List<dynamic>;
  }

  // ── File Operations ──────────────────────────────────────────────────

  /// Get file info (size, permissions, modified time).
  Future<Map<String, dynamic>> getFileInfo(String path) async {
    return await _get('/files/info', {'path': path});
  }

  /// Delete a file or directory.
  Future<Map<String, dynamic>> deleteFile(String path) async {
    return await _post('/files/delete', {'path': path});
  }

  /// Rename a file or directory.
  Future<Map<String, dynamic>> renameFile(String path, String newName) async {
    return await _post('/files/rename', {'path': path, 'new_name': newName});
  }

  /// Create a directory.
  Future<Map<String, dynamic>> createDirectory(String path, String name) async {
    return await _post('/files/mkdir', {'path': path, 'name': name});
  }

  /// Direct HTTP POST for screens that need raw API access.
  Future<Map<String, dynamic>> httpPost(String path, Map<String, dynamic> body) => _post(path, body);

  /// Direct HTTP PUT for screens that need raw API access.
  Future<Map<String, dynamic>> httpPut(String path, Map<String, dynamic> body) => _put(path, body);

  /// Toggle gateway.
  Future<Map<String, dynamic>> gatewayToggle(String action) async {
    return await _post('/gateway/toggle', {'action': action});
  }

  // ── Gateway Platforms ───────────────────────────────────────────────

  /// Get all gateway platforms with config status.
  Future<Map<String, dynamic>> getGatewayPlatforms() async {
    return await _get('/gateway/platforms');
  }

  /// Configure a gateway platform by saving its env vars.
  Future<Map<String, dynamic>> configureGatewayPlatform(
      String platform, Map<String, String> vars) async {
    return await _post('/gateway/configure/$platform', {'vars': vars});
  }

  /// Gateway service management (install/uninstall/start/stop/restart/status).
  Future<Map<String, dynamic>> gatewayServiceAction(String action) async {
    return await _post('/gateway/service/$action', {});
  }

  // ── Auth / Provider Login ────────────────────────────────────────────

  /// Start OAuth login for a provider (returns auth URL).
  Future<Map<String, dynamic>> loginOAuth(String provider) async {
    return await _post('/auth/login/$provider', {});
  }

  /// Login with an API key for a provider.
  Future<Map<String, dynamic>> loginApiKey(String provider, String apiKey) async {
    return await _post('/auth/api-key', {
      'provider': provider,
      'api_key': apiKey,
    });
  }

  /// Get auth status for all providers.
  Future<Map<String, dynamic>> getAuthStatus() async {
    return await _get('/auth/status');
  }

  /// Logout from a provider.
  Future<Map<String, dynamic>> logoutProvider(String provider) async {
    return await _post('/auth/logout/$provider', {});
  }

  // ── CLI Proxy Commands ────────────────────────────────────────────

  /// Run any hermes CLI command through the backend proxy.
  Future<Map<String, dynamic>> runCliCommand(List<String> args) async {
    return await _post('/hermes/command', {'args': args});
  }

  /// Get fallback provider chain.
  Future<Map<String, dynamic>> getFallbackChain() async {
    return await _get('/cli/fallback');
  }

  /// Add a fallback provider.
  Future<Map<String, dynamic>> addFallback(String provider, String model) async {
    return await _post('/cli/fallback/add', {'provider': provider, 'model': model});
  }

  /// Clear fallback chain.
  Future<Map<String, dynamic>> clearFallback() async {
    return await _post('/cli/fallback/clear', {});
  }

  /// List webhooks.
  Future<Map<String, dynamic>> getWebhooks() async {
    return await _get('/cli/webhooks');
  }

  /// List MCP servers.
  Future<Map<String, dynamic>> getMcpServers() async {
    return await _get('/cli/mcp');
  }

  /// List plugins.
  Future<Map<String, dynamic>> getPlugins() async {
    return await _get('/cli/plugins');
  }

  /// Get curator status.
  Future<Map<String, dynamic>> getCuratorStatus() async {
    return await _get('/cli/curator');
  }

  /// Run hermes doctor.
  Future<Map<String, dynamic>> runDoctor() async {
    return await _get('/cli/doctor');
  }

  /// Run security audit.
  Future<Map<String, dynamic>> runSecurityAudit() async {
    return await _get('/cli/security');
  }

  /// Get setup dump.
  Future<Map<String, dynamic>> getDump() async {
    return await _get('/cli/dump');
  }

  /// Create debug report.
  Future<Map<String, dynamic>> createDebugReport() async {
    return await _get('/cli/debug');
  }

  /// Create backup.
  Future<Map<String, dynamic>> createBackup() async {
    return await _post('/cli/backup', {});
  }

  /// Get checkpoints status.
  Future<Map<String, dynamic>> getCheckpoints() async {
    return await _get('/cli/checkpoints');
  }

  /// List hooks.
  Future<Map<String, dynamic>> getHooks() async {
    return await _get('/cli/hooks');
  }

  /// Get proxy status.
  Future<Map<String, dynamic>> getProxyStatus() async {
    return await _get('/cli/proxy');
  }

  /// Get secrets status.
  Future<Map<String, dynamic>> getSecretsStatus() async {
    return await _get('/cli/secrets');
  }

  /// List pairing users.
  Future<Map<String, dynamic>> getPairingUsers() async {
    return await _get('/cli/pairing');
  }

  /// Get insights.
  Future<Map<String, dynamic>> getInsights() async {
    return await _get('/cli/insights');
  }

  // ── Skills ──────────────────────────────────────────────────────────

  @override
  Future<List<SkillEntry>> listSkills() async {
    final data = await _get('/hermes/skills');
    final list = data['skills'] as List? ?? [];
    return list.map((s) => SkillEntry.fromJson(s as Map<String, dynamic>)).toList();
  }

  @override
  Future<bool> toggleSkill(String name, {String action = 'toggle'}) async {
    final data = await _post('/hermes/skills/$name/toggle', {'action': action});
    return data['success'] == true;
  }

  // ── Memory ──────────────────────────────────────────────────────────

  @override
  Future<List<MemoryEntry>> listMemory() async {
    final data = await _get('/memory');
    final list = data['entries'] as List? ?? [];
    return list.map((e) => MemoryEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<MemoryEntry?> getMemory(String id) async {
    final data = await _get('/memory/$id');
    if (data['success'] == false) return null;
    return MemoryEntry(key: id, content: data['content'] ?? '', id: id);
  }

  @override
  Future<bool> deleteMemory(String id) async {
    final data = await _deleteRequest('/memory/$id');
    return data['success'] == true;
  }

  @override
  Future<List<MemoryEntry>> searchMemory(String query) async {
    final data = await _post('/memory/search', {'query': query});
    final list = data['entries'] as List? ?? [];
    return list.map((e) {
      if (e is Map<String, dynamic>) return MemoryEntry.fromJson(e);
      return MemoryEntry(key: e.toString(), content: e.toString());
    }).toList();
  }

  // ── Files ───────────────────────────────────────────────────────────

  @override
  Future<FileListing> listFiles({String path = ''}) async {
    final data = await _get('/files/list', {'path': path});
    return FileListing.fromJson(data);
  }

  @override
  Future<String?> readFile(String path) async {
    final data = await _get('/files/read', {'path': path});
    if (data['success'] == false) return null;
    return data['content'] as String?;
  }

  @override
  Future<bool> writeFile(String path, String content) async {
    final data = await _put('/files/write', {'path': path, 'content': content});
    return data['success'] == true;
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
