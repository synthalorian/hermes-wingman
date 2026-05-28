import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_manager.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass_card.dart';
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

  String? get _resumedSessionId => context.read<ChatManager>().resumeSessionId;
  String? get _resumedSessionTitle => context.read<ChatManager>().resumeSessionTitle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

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
      _confirmClear(mgr);
      return;
    }
    _showDeleteConfirm(mgr, index);
  }

  void _confirmClear(ChatManager mgr) {
    final scheme = context.read<ThemeManager>().currentScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: scheme.surface.withAlpha(230),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.borderDim.withAlpha(60), width: 0.5),
        ),
        title: Text('Clear Chat', style: TextStyle(color: scheme.text, fontSize: 15)),
        content: Text('Clear all messages in this chat?', style: TextStyle(color: scheme.textDim, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: scheme.textDim))),
          TextButton(
            onPressed: () {
              mgr.clearSession(mgr.activeIndex);
              Navigator.pop(ctx);
            },
            child: Text('Clear', style: TextStyle(color: scheme.error)),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(ChatManager mgr, int index) {
    final scheme = context.read<ThemeManager>().currentScheme;
    final session = mgr.sessions[index];
    final hasMessages = session.messages.isNotEmpty;
    if (!hasMessages) {
      mgr.deleteSession(index);
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: scheme.surface.withAlpha(230),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.borderDim.withAlpha(60), width: 0.5),
        ),
        title: Text('Delete Chat', style: TextStyle(color: scheme.text, fontSize: 15)),
        content: Text('Delete "${session.title}" and all its messages?', style: TextStyle(color: scheme.textDim, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: scheme.textDim))),
          TextButton(
            onPressed: () {
              mgr.deleteSession(index);
              Navigator.pop(ctx);
            },
            child: Text('Delete', style: TextStyle(color: scheme.error)),
          ),
        ],
      ),
    );
  }

  void _renameSession(int index) {
    final scheme = context.read<ThemeManager>().currentScheme;
    final mgr = context.read<ChatManager>();
    final currentName = mgr.sessions[index].title;
    final controller = TextEditingController(text: currentName);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: scheme.surface.withAlpha(230),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.borderDim.withAlpha(60), width: 0.5),
        ),
        title: Text('Rename Chat', style: TextStyle(color: scheme.text, fontSize: 15)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: scheme.text, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Chat name',
            hintStyle: TextStyle(color: scheme.textMuted, fontSize: 13),
            filled: true,
            fillColor: scheme.surfaceAlt,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: scheme.borderDim),
            ),
          ),
          onSubmitted: (v) {
            mgr.renameSession(index, v);
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: scheme.textDim))),
          TextButton(
            onPressed: () {
              mgr.renameSession(index, controller.text);
              Navigator.pop(ctx);
            },
            child: Text('Rename', style: TextStyle(color: scheme.primary)),
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

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
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
                return ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Container(
                        decoration: BoxDecoration(
                          color: s.surface.withAlpha(220),
                          border: Border(
                            top: BorderSide(color: s.borderDim.withAlpha(50), width: 0.5),
                          ),
                        ),
                        child: Column(
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 10),
                              width: 40, height: 4,
                              decoration: BoxDecoration(
                                color: s.textDim.withAlpha(80),
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
                                      Icon(Icons.inbox_outlined, size: 36, color: s.textMuted.withAlpha(102)),
                                      const SizedBox(height: 8),
                                      Text('No Hermes sessions found', style: TextStyle(color: s.textMuted, fontSize: 13)),
                                      const SizedBox(height: 4),
                                      Text('Chat with Hermes to create sessions', style: TextStyle(color: s.textMuted.withAlpha(153), fontSize: 10)),
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
                                    return _GlassSessionRow(
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
                        ),
                      ),
                    ),
                  ),
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

    mgr.addMessage(session.id, ChatMessage(text: text.trim(), isUser: true));
    _scrollToBottom();

    setState(() => _sending = true);

    try {
      final service = context.read<HermesService>();

      if (service is BackendService) {
        final placeholder = ChatMessage(text: '…', isUser: false);
        mgr.addMessage(session.id, placeholder);
        _scrollToBottom();

        await _streamChat(service, text.trim(), session.id,
            resumeSessionId: _resumedSessionId);
      } else {
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
    final uri = Uri.parse('${service.baseUrl}/chat/stream')
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
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            const Text('Chat', style: TextStyle(fontSize: 15)),
            if (_hermesVersion != null) ...[
              const SizedBox(width: 8),
              _GlassChatBadge(scheme: scheme, label: _hermesVersion!),
            ],
          ],
        ),
        actions: [
          if (_resumedSessionId != null)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: GestureDetector(
                onTap: _showSessionPicker,
                child: _GlassChatBadge(
                  scheme: scheme,
                  label: _resumedSessionTitle ?? 'Session',
                  icon: Icons.replay,
                  color: scheme.secondary,
                ),
              ),
            ),
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
                bottom: BorderSide(color: scheme.borderDim.withAlpha(40), width: 0.5),
              ),
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: mgr.sessions.length + 1,
              itemBuilder: (context, i) {
                if (i == mgr.sessions.length) {
                  return _GlassAddTab(scheme: scheme, mgr: mgr);
                }
                return _GlassTab(scheme: scheme, mgr: mgr, index: i, sending: _sending);
              },
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessageArea(scheme, mgr)),
          _GlassInputBar(scheme: scheme, mgr: mgr, sending: _sending, onSend: _sendMessage, inputController: _inputController),
        ],
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
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: scheme.surface.withAlpha(100),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.chat_bubble_outline, size: 40, color: scheme.textMuted.withAlpha(100)),
            ),
            const SizedBox(height: 20),
            Text(
              'Send a message to start chatting',
              style: TextStyle(color: scheme.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 6),
            GlassCard(
              scheme: scheme,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              borderRadius: 6,
              blurSigma: 4,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tab, size: 10, color: scheme.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    'Tab ${mgr.activeIndex + 1} — "${mgr.activeSession.title}"',
                    style: TextStyle(color: scheme.textMuted.withAlpha(153), fontSize: 10, fontFamily: 'monospace'),
                  ),
                ],
              ),
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
        return _GlassChatBubble(scheme: scheme, message: msg);
      },
    );
  }
}

// ── Glass Chat Badge ────────────────────────────────────────────────────

class _GlassChatBadge extends StatelessWidget {
  final AppColorScheme scheme;
  final String label;
  final IconData? icon;
  final Color? color;

  const _GlassChatBadge({
    required this.scheme,
    required this.label,
    this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? scheme.borderDim;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: c.withAlpha(25),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: c.withAlpha(50), width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 10, color: c),
                const SizedBox(width: 3),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c, fontSize: 9, fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

// ── Glass Tab ───────────────────────────────────────────────────────────

class _GlassTab extends StatelessWidget {
  final AppColorScheme scheme;
  final ChatManager mgr;
  final int index;
  final bool sending;

  const _GlassTab({
    required this.scheme,
    required this.mgr,
    required this.index,
    required this.sending,
  });

  @override
  Widget build(BuildContext context) {
    final session = mgr.sessions[index];
    final isActive = index == mgr.activeIndex;
    final isStreaming = sending && isActive;

    return GestureDetector(
      onTap: () => mgr.switchTo(index),
      onLongPress: () => context.findAncestorStateOfType<_ChatScreenState>()?._renameSession(index),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 160),
        margin: const EdgeInsets.only(right: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        decoration: BoxDecoration(
          color: isActive
              ? scheme.surface.withAlpha(150)
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
            GestureDetector(
              onTap: () => context.findAncestorStateOfType<_ChatScreenState>()?._deleteSession(index),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.close, size: 12,
                  color: isActive ? scheme.textMuted : scheme.textDim),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Glass Add Tab ──────────────────────────────────────────────────────

class _GlassAddTab extends StatelessWidget {
  final AppColorScheme scheme;
  final ChatManager mgr;

  const _GlassAddTab({required this.scheme, required this.mgr});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.findAncestorStateOfType<_ChatScreenState>()?._createNewChat(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.transparent, width: 2)),
        ),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: scheme.surfaceAlt.withAlpha(100),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(Icons.add, size: 14, color: scheme.textMuted),
          ),
        ),
      ),
    );
  }
}

// ── Glass Chat Bubble ─────────────────────────────────────────────────

class _GlassChatBubble extends StatelessWidget {
  final AppColorScheme scheme;
  final ChatMessage message;

  const _GlassChatBubble({required this.scheme, required this.message});

  @override
  Widget build(BuildContext context) {
    if (message.isUser) {
      return _GlassUserBubble(scheme: scheme, message: message);
    }
    return _GlassAiBubble(scheme: scheme, message: message);
  }
}

class _GlassUserBubble extends StatelessWidget {
  final AppColorScheme scheme;
  final ChatMessage message;
  const _GlassUserBubble({required this.scheme, required this.message});

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
                color: scheme.primary.withAlpha(25),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(4),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
                border: Border.all(color: scheme.primary.withAlpha(30), width: 0.5),
              ),
              child: Text(message.text, style: TextStyle(color: scheme.text, fontSize: 13, height: 1.4)),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: scheme.primary.withAlpha(30),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.primary.withAlpha(40), width: 0.5),
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

class _GlassAiBubble extends StatelessWidget {
  final AppColorScheme scheme;
  final ChatMessage message;
  const _GlassAiBubble({required this.scheme, required this.message});

  @override
  Widget build(BuildContext context) {
    final isError = message.text.startsWith('Error:') || message.text.startsWith('Connection error:');
    final isSystem = message.text.startsWith('Chat cleared') || message.text.startsWith('Hermes Wingman Chat');

    final bubbleColor = isError
        ? scheme.error.withAlpha(15)
        : isSystem
            ? scheme.surfaceAlt.withAlpha(150)
            : scheme.surface.withAlpha(180);

    final borderColor = isError
        ? scheme.error.withAlpha(25)
        : isSystem
            ? scheme.borderDim.withAlpha(20)
            : scheme.borderDim.withAlpha(30);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: isError
                  ? scheme.error.withAlpha(25)
                  : isSystem
                      ? scheme.textMuted.withAlpha(20)
                      : scheme.success.withAlpha(20),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isError
                    ? scheme.error.withAlpha(30)
                    : isSystem
                        ? scheme.textMuted.withAlpha(20)
                        : scheme.success.withAlpha(25),
                width: 0.5,
              ),
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
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    border: Border.all(color: borderColor, width: 0.5),
                    boxShadow: [
                      BoxShadow(
                        color: isError
                            ? scheme.error.withAlpha(8)
                            : scheme.primary.withAlpha(6),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Text(
                    message.text,
                    style: TextStyle(
                      color: isError ? scheme.error : scheme.text,
                      fontSize: 13,
                      height: 1.4,
                      fontStyle: isSystem ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Glass Input Bar ────────────────────────────────────────────────────

class _GlassInputBar extends StatefulWidget {
  final AppColorScheme scheme;
  final ChatManager mgr;
  final bool sending;
  final Function(String) onSend;
  final TextEditingController inputController;

  const _GlassInputBar({
    required this.scheme,
    required this.mgr,
    required this.sending,
    required this.onSend,
    required this.inputController,
  });

  @override
  State<_GlassInputBar> createState() => _GlassInputBarState();
}

class _GlassInputBarState extends State<_GlassInputBar> with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      decoration: BoxDecoration(
        color: widget.scheme.surface.withAlpha(150),
        border: Border(
          top: BorderSide(color: widget.scheme.borderDim.withAlpha(40), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: AnimatedBuilder(
              animation: _glowController,
              builder: (context, child) {
                return Container(
                  decoration: BoxDecoration(
                    color: widget.scheme.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: widget.sending
                          ? widget.scheme.borderDim
                          : widget.scheme.primary.withAlpha((20 * _glowAnim.value).round()),
                      width: widget.sending ? 0.5 : 1.0,
                    ),
                    boxShadow: widget.sending
                        ? null
                        : [
                            BoxShadow(
                              color: widget.scheme.primary.withAlpha((8 * _glowAnim.value).round()),
                              blurRadius: 8,
                              spreadRadius: 0.5,
                            ),
                          ],
                  ),
                  child: TextField(
                    controller: widget.inputController,
                    textInputAction: TextInputAction.send,
                    minLines: 1,
                    maxLines: 5,
                    onSubmitted: widget.sending ? null : (v) => widget.onSend(v),
                    style: TextStyle(color: widget.scheme.text, fontSize: 13, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      hintText: widget.sending ? 'Waiting for response...' : 'Message Hermes...',
                      hintStyle: TextStyle(color: widget.scheme.textMuted, fontSize: 13),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      enabled: !widget.sending,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: widget.sending ? null : () => widget.onSend(widget.inputController.text),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: widget.sending
                      ? widget.scheme.surfaceAlt
                      : widget.scheme.primary.withAlpha(30),
                  border: Border.all(
                    color: widget.sending
                        ? widget.scheme.borderDim
                        : widget.scheme.primary.withAlpha(50),
                    width: 0.5,
                  ),
                  boxShadow: widget.sending
                      ? null
                      : [
                          BoxShadow(
                            color: widget.scheme.primary.withAlpha(15),
                            blurRadius: 6,
                          ),
                        ],
                ),
                child: widget.sending
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: widget.scheme.textMuted,
                        ),
                      )
                    : Icon(Icons.arrow_upward, size: 18, color: widget.scheme.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Glass Session Row ──────────────────────────────────────────────────

class _GlassSessionRow extends StatelessWidget {
  final AppColorScheme scheme;
  final HermesSession session;
  final bool isSelected;
  final VoidCallback onTap;

  const _GlassSessionRow({
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
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? scheme.selectedBackground.withAlpha(180)
                      : scheme.surfaceAlt.withAlpha(120),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? scheme.secondary.withAlpha(60)
                        : scheme.borderDim.withAlpha(25),
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
                            session.id.length > 16 ? '...${session.id.substring(session.id.length - 16)}' : session.id,
                            style: TextStyle(color: scheme.textMuted, fontSize: 9, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ),
                    Text(                          '${session.messageCount} msgs',
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
        ),
      ),
    );
  }
}