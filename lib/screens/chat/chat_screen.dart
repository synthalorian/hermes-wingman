import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_manager.dart';
import '../../theme/app_theme.dart';
import '../../services/chat_manager.dart';
import '../../services/hermes_service.dart';
import '../../services/hermes_api_client.dart' show BackendService;
import '../../models/hermes_models.dart';

/// Chat screen with tabbed persistent sessions.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final PageController _pageController = PageController();
  bool _sending = false;
  String? _hermesVersion;
  int _streamingSessionIdx = -1;
  List<HermesSession> _recentSessions = [];
  bool _loadingSessions = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /// Read the resumed session from ChatManager.
  String? get _resumedSessionId => context.read<ChatManager>().resumeSessionId;
  String? get _resumedSessionTitle => context.read<ChatManager>().resumeSessionTitle;

  Future<void> _loadVersion() async {
    try {
      final client = context.read<HermesService>();
      final status = await client.getStatus();
      if (status.version.isNotEmpty && mounted) {
        setState(() => _hermesVersion = status.version);
      }
    } catch (_) {}
  }

  // ── Tab Actions ───────────────────────────────────────────────────────

  void _createNewChat() {
    final mgr = context.read<ChatManager>();
    mgr.createSession();
    _scrollToBottom();
  }

  void _deleteSession(int index) {
    final mgr = context.read<ChatManager>();
    if (mgr.sessions.length <= 1) {
      // Clear messages on last session
      _confirmClear(mgr);
      return;
    }
    _showDeleteConfirm(mgr, index);
  }

  void _confirmClear(ChatManager mgr) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Clear Chat', style: TextStyle(color: Theme.of(ctx).textTheme.bodyLarge?.color)),
        content: Text('Clear all messages in this chat?', style: TextStyle(color: Theme.of(ctx).textTheme.bodyMedium?.color?.withValues(alpha: 0.7))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
          TextButton(
            onPressed: () {
              mgr.clearSession(mgr.activeIndex);
              Navigator.pop(ctx);
            },
            child: Text('Clear', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(ChatManager mgr, int index) {
    final session = mgr.sessions[index];
    final hasMessages = session.messages.isNotEmpty;
    if (!hasMessages) {
      mgr.deleteSession(index);
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Delete Chat', style: TextStyle(color: Theme.of(ctx).textTheme.bodyLarge?.color)),
        content: Text('Delete "${session.title}" and all its messages?', style: TextStyle(color: Theme.of(ctx).textTheme.bodyMedium?.color?.withValues(alpha: 0.7))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
          TextButton(
            onPressed: () {
              mgr.deleteSession(index);
              Navigator.pop(ctx);
            },
            child: Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _renameSession(int index) {
    final mgr = context.read<ChatManager>();
    final currentName = mgr.sessions[index].title;
    final controller = TextEditingController(text: currentName);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Rename Chat', style: TextStyle(color: Theme.of(ctx).textTheme.bodyLarge?.color)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: Theme.of(ctx).textTheme.bodyLarge?.color),
          decoration: InputDecoration(
            hintText: 'Chat name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            mgr.renameSession(index, v);
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
          TextButton(
            onPressed: () {
              mgr.renameSession(index, controller.text);
              Navigator.pop(ctx);
            },
            child: Text('Rename'),
          ),
        ],
      ),
    );
  }

  // ── Session Resume ──────────────────────────────────────────────────

  Future<void> _loadRecentSessions() async {
    setState(() => _loadingSessions = true);
    try {
      final client = context.read<HermesService>();
      final sessions = await client.listSessions(limit: 30);
      if (!mounted) return;
      setState(() {
        _recentSessions = sessions;
        _loadingSessions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingSessions = false);
    }
  }

  void _showSessionPicker() {
    _loadRecentSessions();
    final scheme = context.read<ThemeManager>().currentScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Consumer<ThemeManager>(
          builder: (ctx, tm, _) {
            final s = tm.currentScheme;
            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              maxChildSize: 0.8,
              minChildSize: 0.3,
              expand: false,
              builder: (ctx, scrollController) {
                return Column(
                  children: [
                    // Handle bar
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: s.textDim,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Row(
                        children: [
                          Text(
                            'Resume Hermes Session',
                            style: TextStyle(color: s.text, fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          if (_resumedSessionId != null)
                            TextButton(
                              onPressed: () {
                                context.read<ChatManager>().clearResumeSession();
                                Navigator.pop(ctx);
                              },
                              child: Text('Clear Resume', style: TextStyle(color: s.error, fontSize: 11)),
                            ),
                          if (_loadingSessions)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: SizedBox(width: 14, height: 14,
                                child: CircularProgressIndicator(strokeWidth: 1.5, color: s.textMuted)),
                            ),
                        ],
                      ),
                    ),
                    if (_recentSessions.isEmpty && !_loadingSessions)
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.inbox_outlined, size: 36, color: s.textMuted.withValues(alpha: 0.4)),
                              const SizedBox(height: 8),
                              Text('No Hermes sessions found', style: TextStyle(color: s.textMuted, fontSize: 13)),
                              const SizedBox(height: 4),
                              Text('Chat with Hermes to create sessions', style: TextStyle(color: s.textMuted.withValues(alpha: 0.6), fontSize: 10)),
                            ],
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _recentSessions.length,
                          itemBuilder: (ctx, i) {
                            final sess = _recentSessions[i];
                            final isCurrent = sess.id == _resumedSessionId;
                            return _SessionResumeRow(
                              scheme: s,
                              session: sess,
                              isSelected: isCurrent,
                              onTap: () {
                                context.read<ChatManager>().setResumeSession(
                                  sess.id,
                                  title: sess.title,
                                );
                                Navigator.pop(ctx);
                              },
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  // ── Sending Messages ──────────────────────────────────────────────────

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _sending) return;
    _inputController.clear();

    final mgr = context.read<ChatManager>();
    final session = mgr.activeSession;

    // Add user message
    mgr.addMessage(session.id, ChatMessage(text: text.trim(), isUser: true));
    _scrollToBottom();

    setState(() => _sending = true);

    try {
      final service = context.read<HermesService>();

      if (service is BackendService) {
        // SSE streaming
        final placeholder = ChatMessage(text: '…', isUser: false);
        mgr.addMessage(session.id, placeholder);
        _scrollToBottom();

        await _streamChat(service, text.trim(), session.id,
            resumeSessionId: _resumedSessionId);
      } else {
        // Fallback CLI
        String response;
        final result = await Process.run('hermes', ['--oneshot', text.trim()]);
        if (result.exitCode != 0) {
          throw Exception((result.stderr as String?)?.trim() ?? 'Command failed');
        }
        response = (result.stdout as String).trim();
        final responseMsg = ChatMessage(
          text: response.isNotEmpty ? response : '(empty response)',
          isUser: false,
        );
        mgr.addMessage(session.id, responseMsg);
        _scrollToBottom();
      }
    } catch (e) {
      if (!mounted) return;
      final mgr = context.read<ChatManager>();
      final activeId = mgr.activeSession.id;
      mgr.addMessage(activeId, ChatMessage(text: 'Connection error: $e', isUser: false));
      _scrollToBottom();
    }

    if (mounted) setState(() => _sending = false);
  }

  Future<void> _streamChat(BackendService service, String message, String sessionId, {String? resumeSessionId}) async {
    final queryParams = <String, String>{'message': message};
    if (resumeSessionId != null && resumeSessionId.isNotEmpty) {
      queryParams['session_id'] = resumeSessionId;
    }
    final uri = Uri.parse('http://127.0.0.1:9120/chat/stream')
        .replace(queryParameters: queryParams);
    final client = HttpClient();
    final request = await client.getUrl(uri);
    final response = await request.close();

    final buffer = StringBuffer();
    String line = '';

    await for (final chunk in response.transform(utf8.decoder)) {
      for (var i = 0; i < chunk.length; i++) {
        final c = chunk[i];
        if (c == '\n') {
          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            if (data == '[DONE]') {
              if (!mounted) return;
              final mgr = context.read<ChatManager>();
              final msgs = mgr.activeSession.messages;
              if (msgs.isNotEmpty) {
                mgr.updateLastMessage(sessionId, ChatMessage(
                  text: buffer.toString().trim(),
                  isUser: false,
                ));
              }
              _scrollToBottom();
              return;
            }
            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              // Surface backend error events instead of silently dropping them
              final error = json['error'] as String?;
              if (error != null && error.isNotEmpty) {
                buffer.write('\n[Error: $error]\n');
                if (mounted) {
                  final mgr = context.read<ChatManager>();
                  final msgs = mgr.activeSession.messages;
                  if (msgs.isNotEmpty) {
                    mgr.updateLastMessage(sessionId, ChatMessage(
                      text: buffer.toString().trim(),
                      isUser: false,
                    ));
                  }
                  _scrollToBottom();
                }
              }
              final content = json['content'] as String? ?? '';
              if (content.isNotEmpty) {
                buffer.write(content);
                if (mounted) {
                  final mgr = context.read<ChatManager>();
                  final msgs = mgr.activeSession.messages;
                  if (msgs.isNotEmpty) {
                    mgr.updateLastMessage(sessionId, ChatMessage(
                      text: buffer.toString().trim(),
                      isUser: false,
                    ));
                  }
                  _scrollToBottom();
                }
              }
            } catch (_) {}
          }
          line = '';
        } else {
          line += c;
        }
      }
    }

    // Stream ended without [DONE]
    if (mounted) {
      final mgr = context.read<ChatManager>();
      final msgs = mgr.activeSession.messages;
      if (msgs.isNotEmpty) {
        mgr.updateLastMessage(sessionId, ChatMessage(
          text: buffer.toString().trim().isNotEmpty ? buffer.toString().trim() : '(no response)',
          isUser: false,
        ));
      }
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = context.watch<ThemeManager>().currentScheme;
    final mgr = context.watch<ChatManager>();

    return Scaffold(
      backgroundColor: scheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: scheme.appBarBackground,
        elevation: 0,
        title: Row(
          children: [
            const Text('Chat', style: TextStyle(fontSize: 15)),
            if (_hermesVersion != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.borderDim, width: 0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _hermesVersion!,
                  style: TextStyle(color: scheme.textMuted, fontSize: 9, fontFamily: 'monospace'),
                ),
              ),
            ],
          ],
        ),
        actions: [
          // Resume session badge
          if (_resumedSessionId != null)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: GestureDetector(
                onTap: _showSessionPicker,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.secondary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: scheme.secondary.withValues(alpha: 0.3), width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.replay, size: 10, color: scheme.secondary),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          _resumedSessionTitle ?? 'Session',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.secondary, fontSize: 9, fontFamily: 'monospace'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Load session button
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: IconButton(
              icon: Icon(Icons.history, size: 15, color: _resumedSessionId != null ? scheme.secondary : scheme.textMuted),
              onPressed: _showSessionPicker,
              tooltip: 'Resume Session',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(32),
          child: Container(
            height: 32,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: scheme.borderDim, width: 0.5),
              ),
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: mgr.sessions.length + 1,
              itemBuilder: (context, i) {
                if (i == mgr.sessions.length) {
                  return _buildAddTab(scheme, mgr);
                }
                return _buildTab(scheme, mgr, i);
              },
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Messages
          Expanded(child: _buildMessageArea(scheme, mgr)),
          // Input bar
          _buildInputBar(scheme, mgr),
        ],
      ),
    );
  }

  // ── Tabs ───────────────────────────────────────────────────────────────

  Widget _buildTab(AppColorScheme scheme, ChatManager mgr, int index) {
    final session = mgr.sessions[index];
    final isActive = index == mgr.activeIndex;
    final isStreaming = _sending && isActive;

    return GestureDetector(
      onTap: () => mgr.switchTo(index),
      onLongPress: () => _renameSession(index),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 160),
        margin: const EdgeInsets.only(right: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        decoration: BoxDecoration(
          color: isActive
              ? scheme.surface
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isActive ? scheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Stream indicator
            if (isStreaming)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: SizedBox(
                  width: 8, height: 8,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: scheme.success,
                  ),
                ),
              ),
            // Title
            Flexible(
              child: Text(
                session.title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isActive ? scheme.text : scheme.textMuted,
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Close button
            GestureDetector(
              onTap: () => _deleteSession(index),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.close,
                  size: 12,
                  color: isActive ? scheme.textMuted : scheme.textDim,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddTab(AppColorScheme scheme, ChatManager mgr) {
    return GestureDetector(
      onTap: _createNewChat,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.transparent, width: 2),
          ),
        ),
        child: Center(
          child: Icon(Icons.add, size: 16, color: scheme.textMuted),
        ),
      ),
    );
  }

  // ── Messages ──────────────────────────────────────────────────────────

  Widget _buildMessageArea(AppColorScheme scheme, ChatManager mgr) {
    final messages = mgr.activeMessages;

    if (messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: scheme.textMuted.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              'Send a message to start chatting',
              style: TextStyle(color: scheme.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'Tab ${mgr.activeIndex + 1} — "${mgr.activeSession.title}"',
              style: TextStyle(color: scheme.textMuted.withValues(alpha: 0.5), fontSize: 11, fontFamily: 'monospace'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      itemCount: messages.length,
      itemBuilder: (context, i) {
        final msg = messages[i];
        return _ChatBubble(scheme: scheme, message: msg);
      },
    );
  }

  // ── Input ──────────────────────────────────────────────────────────────

  Widget _buildInputBar(AppColorScheme scheme, ChatManager mgr) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.borderDim, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.borderDim, width: 0.5),
              ),
              child: TextField(
                controller: _inputController,
                textInputAction: TextInputAction.send,
                minLines: 1,
                maxLines: 5,
                onSubmitted: _sending ? null : (v) => _sendMessage(v),
                style: TextStyle(color: scheme.text, fontSize: 13, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: _sending ? 'Waiting for response...' : 'Message Hermes...',
                  hintStyle: TextStyle(color: scheme.textMuted, fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  enabled: !_sending,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: _sending ? scheme.surfaceAlt : scheme.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _sending ? null : () => _sendMessage(_inputController.text),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _sending ? scheme.borderDim : scheme.primary.withValues(alpha: 0.3),
                    width: 0.5,
                  ),
                ),
                child: _sending
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.textMuted,
                        ),
                      )
                    : Icon(Icons.arrow_upward, size: 18, color: scheme.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Chat Bubbles ─────────────────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  final AppColorScheme scheme;
  final ChatMessage message;

  const _ChatBubble({required this.scheme, required this.message});

  @override
  Widget build(BuildContext context) {
    if (message.isUser) {
      return _UserBubble(scheme: scheme, message: message);
    }
    return _AiBubble(scheme: scheme, message: message);
  }
}

class _UserBubble extends StatelessWidget {
  final AppColorScheme scheme;
  final ChatMessage message;
  const _UserBubble({required this.scheme, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(4),
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: _buildEmojiText(
                message.text,
                TextStyle(color: scheme.text, fontSize: 13, height: 1.4),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text('U', style: TextStyle(color: scheme.primary, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiBubble extends StatelessWidget {
  final AppColorScheme scheme;
  final ChatMessage message;
  const _AiBubble({required this.scheme, required this.message});

  @override
  Widget build(BuildContext context) {
    final isError = message.text.startsWith('Error:') || message.text.startsWith('Connection error:');
    final isSystem = message.text.startsWith('Chat cleared') || message.text.startsWith('Hermes Wingman Chat');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isError
                  ? scheme.error.withValues(alpha: 0.2)
                  : isSystem
                      ? scheme.textMuted.withValues(alpha: 0.2)
                      : scheme.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                isError ? '!' : isSystem ? 'i' : 'H',
                style: TextStyle(
                  color: isError ? scheme.error : isSystem ? scheme.textMuted : scheme.success,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isError
                    ? scheme.error.withValues(alpha: 0.06)
                    : isSystem
                        ? scheme.surfaceAlt
                        : scheme.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                border: isSystem
                    ? Border.all(color: scheme.borderDim.withValues(alpha: 0.3), width: 0.5)
                    : null,
              ),
              child: _buildEmojiText(
                message.text,
                TextStyle(
                  color: isError ? scheme.error : scheme.text,
                  fontSize: 13,
                  height: 1.4,
                  fontStyle: isSystem ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Build a [Text] widget — emoji are now properly encoded from the backend.
Widget _buildEmojiText(String text, TextStyle baseStyle) {
  return Text(text, style: baseStyle);
}

/// A row in the session resume picker.
class _SessionResumeRow extends StatelessWidget {
  final AppColorScheme scheme;
  final HermesSession session;
  final bool isSelected;
  final VoidCallback onTap;

  const _SessionResumeRow({
    required this.scheme,
    required this.session,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: isSelected ? scheme.selectedBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? scheme.secondary.withValues(alpha: 0.5) : scheme.borderDim.withValues(alpha: 0.2),
                width: isSelected ? 1 : 0.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    color: isSelected ? scheme.secondary : scheme.textMuted,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected ? scheme.text : scheme.textDim,
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${session.id.length > 16 ? '...${session.id.substring(session.id.length - 16)}' : session.id}',
                        style: TextStyle(color: scheme.textMuted, fontSize: 9, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${session.messageCount} msgs',
                  style: TextStyle(color: scheme.textMuted, fontSize: 9, fontFamily: 'monospace'),
                ),
                const SizedBox(width: 8),
                if (isSelected)
                  Icon(Icons.check_circle, size: 14, color: scheme.secondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
