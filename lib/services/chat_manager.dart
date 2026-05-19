import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// A single chat message.
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final String? sessionId;

  ChatMessage({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
    this.sessionId,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'text': text,
    'isUser': isUser,
    'timestamp': timestamp.toIso8601String(),
    'sessionId': sessionId,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    text: json['text'] as String? ?? '',
    isUser: json['isUser'] as bool? ?? false,
    timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    sessionId: json['sessionId'] as String?,
  );
}

/// A chat session with its own conversation.
class ChatSession {
  final String id;
  String title;
  final List<ChatMessage> messages;
  DateTime createdAt;

  ChatSession({
    required this.id,
    this.title = 'New Chat',
    List<ChatMessage>? messages,
    DateTime? createdAt,
  }) : messages = messages ?? [],
       createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'messages': messages.map((m) => m.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
    id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
    title: json['title'] as String? ?? 'New Chat',
    messages: (json['messages'] as List? ?? []).map((m) => ChatMessage.fromJson(m as Map<String, dynamic>)).toList(),
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

/// Manages persistent chat sessions across navigation.
/// Lives as a ChangeNotifier at the app level so switching tabs
/// doesn't destroy chat state.
class ChatManager extends ChangeNotifier {
  List<ChatSession> _sessions = [];
  int _activeIndex = 0;
  static const String _savePath = 'wingman_chats.json';

  ChatManager() {
    _load();
    if (_sessions.isEmpty) {
      _sessions.add(ChatSession(id: _newId(), title: 'Chat 1'));
    }
  }

  List<ChatSession> get sessions => List.unmodifiable(_sessions);
  ChatSession get activeSession => _sessions[_activeIndex];
  int get activeIndex => _activeIndex;
  List<ChatMessage> get activeMessages => activeSession.messages;
  bool get hasMultipleSessions => _sessions.length > 1;

  void createSession({String? title}) {
    final n = _sessions.length + 1;
    _sessions.add(ChatSession(
      id: _newId(),
      title: title ?? 'Chat $n',
    ));
    _activeIndex = _sessions.length - 1;
    _save();
    notifyListeners();
  }

  void switchTo(int index) {
    if (index < 0 || index >= _sessions.length) return;
    _activeIndex = index;
    notifyListeners();
  }

  void deleteSession(int index) {
    if (_sessions.length <= 1) {
      // Clear instead of deleting the last session
      _sessions[0].messages.clear();
      _sessions[0].title = 'Chat 1';
      _activeIndex = 0;
      _save();
      notifyListeners();
      return;
    }
    _sessions.removeAt(index);
    if (_activeIndex >= _sessions.length) {
      _activeIndex = _sessions.length - 1;
    }
    _save();
    notifyListeners();
  }

  void renameSession(int index, String title) {
    if (index < 0 || index >= _sessions.length) return;
    _sessions[index].title = title.trim().isEmpty ? 'Chat ${index + 1}' : title.trim();
    _save();
    notifyListeners();
  }

  void addMessage(String sessionId, ChatMessage message) {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;
    _sessions[idx].messages.add(message);
    _save();
    notifyListeners();
  }

  void updateLastMessage(String sessionId, ChatMessage message) {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0 || _sessions[idx].messages.isEmpty) return;
    _sessions[idx].messages.last = message;
    notifyListeners();
  }

  void clearSession(int index) {
    if (index < 0 || index >= _sessions.length) return;
    _sessions[index].messages.clear();
    _save();
    notifyListeners();
  }

  void clearAll() {
    for (final s in _sessions) {
      s.messages.clear();
    }
    _save();
    notifyListeners();
  }

  // ── Hermes Session Resume ────────────────────────────────────────

  String? _resumeSessionId;
  String? _resumeSessionTitle;

  String? get resumeSessionId => _resumeSessionId;
  String? get resumeSessionTitle => _resumeSessionTitle;

  void setResumeSession(String? id, {String? title}) {
    _resumeSessionId = id;
    _resumeSessionTitle = title;
    notifyListeners();
  }

  void clearResumeSession() {
    _resumeSessionId = null;
    _resumeSessionTitle = null;
    notifyListeners();
  }

  String _newId() => DateTime.now().millisecondsSinceEpoch.toString();

  // ── Persistence ──────────────────────────────────────────────

  String get _saveDir {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '/tmp';
    return '$home/.hermes';
  }

  void _save() {
    try {
      final dir = Directory(_saveDir);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File('${dir.path}/$_savePath');
      file.writeAsStringSync(jsonEncode(_sessions.map((s) => s.toJson()).toList()));
    } catch (e) {
      debugPrint('[ChatManager] Save failed: $e');
    }
  }

  void _load() {
    try {
      final file = File('$_saveDir/$_savePath');
      if (file.existsSync()) {
        final data = jsonDecode(file.readAsStringSync()) as List;
        _sessions = data.map((s) => ChatSession.fromJson(s as Map<String, dynamic>)).toList();
        debugPrint('[ChatManager] Loaded ${_sessions.length} session(s)');
      }
    } catch (e) {
      debugPrint('[ChatManager] Load failed: $e');
    }
  }
}
