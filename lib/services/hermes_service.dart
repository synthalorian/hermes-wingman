import '../models/hermes_models.dart';

/// Common interface for all Hermes API implementations.
/// Both [HermesClient] (CLI-based) and [HermesApiClient] (HTTP-based) implement this.
abstract class HermesService {
  // ── Core ──
  Future<bool> isHermesAvailable();
  Future<HermesStatus> getStatus();
  Future<String> getStatusRaw();
  Future<List<HermesSession>> listSessions({int limit = 20});
  Future<String> getSessionStats();
  Future<String> getConfigRaw();
  Future<String?> getConfigValue(String key);
  Future<void> setConfigValue(String key, String value);
  Future<void> writeConfig(String content);
  Future<List<LogEntry>> readLogs({int lines = 50, String level = 'all'});
  Future<List<HermesCronJob>> listCronJobs();
  Future<List<GatewayPlatform>> getGatewayStatus();
  Future<String> runHermesCommand(List<String> args);

  // ── Skills ──
  Future<List<SkillEntry>> listSkills();
  Future<bool> toggleSkill(String name, {String action = 'toggle'});

  // ── Memory ──
  Future<List<MemoryEntry>> listMemory();
  Future<MemoryEntry?> getMemory(String id);
  Future<bool> deleteMemory(String id);
  Future<List<MemoryEntry>> searchMemory(String query);

  // ── Files ──
  Future<FileListing> listFiles({String path = ''});
  Future<String?> readFile(String path);
  Future<bool> writeFile(String path, String content);
}