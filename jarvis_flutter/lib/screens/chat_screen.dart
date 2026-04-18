import 'dart:async';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/chat_message.dart';
import '../models/chat_response.dart';
import '../services/agent_service.dart';
import '../services/activity_history_service.dart';
import '../services/api_service.dart';
import '../services/app_settings_service.dart';
import '../services/memory_service.dart';
import '../services/voice_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final api = ApiService();
  final settings = AppSettingsService();
  final controller = TextEditingController();
  final scrollController = ScrollController();
  final voiceService = VoiceService();
  final activityHistory = ActivityHistoryService();

  List<ChatMessage> messages = [];
  String? sessionId;
  bool loading = false;
  bool isListening = false;
  bool isRecording = false;

  @override
  void initState() {
    super.initState();
    startSession();
  }

  String _formatError(Object error) {
    final text = error.toString();
    return text.startsWith('Exception: ')
        ? text.substring('Exception: '.length)
        : text;
  }

  Future<bool> _ensureSession() async {
    if (sessionId != null) {
      return true;
    }

    try {
      sessionId = await api.createSession();
      if (mounted) {
        setState(() {});
      }
      return true;
    } catch (error) {
      if (!mounted) {
        return false;
      }

      setState(() {
        loading = false;
        isListening = false;
        isRecording = false;
        messages.add(ChatMessage(_formatError(error), false));
      });
      return false;
    }
  }

  void startSession() async {
    await _ensureSession();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) {
        return;
      }

      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> sendMessage([String? input]) async {
    final text = (input ?? controller.text).trim();

    if (text.isEmpty) return;
    if (!await _ensureSession()) return;

    controller.clear();

    setState(() {
      messages.add(ChatMessage(text, true));
      loading = true;
    });
    _scrollToBottom();

    try {
      final response = await api.sendMessage(sessionId!, text);
      await MemoryService().refresh();
      await _recordResponseHistory(response, origin: 'chat');

      if (!mounted) return;

      setState(() {
        messages.add(ChatMessage(response.reply, false));
        loading = false;
      });
      _scrollToBottom();

      await handleClientAction(response.clientAction, origin: 'chat');
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        messages.add(ChatMessage(_formatError(error), false));
        loading = false;
      });
      _scrollToBottom();
    }
  }

  Future<void> _recordResponseHistory(
    ChatResponseModel response, {
    required String origin,
  }) async {
    if (response.toolCall == null || response.clientAction != null) {
      return;
    }

    await activityHistory.recordToolUsage(
      origin: origin,
      toolCall: response.toolCall!,
      toolResult: response.toolResult,
    );
  }

  Future<void> handleClientAction(
    ClientAction? action, {
    required String origin,
  }) async {
    if (action == null) return;

    if (action.type == 'pc_action' && action.action != null) {
      final result = await sendPcAction(
        action.action!,
        extra: action.arguments.isEmpty ? null : action.arguments,
      );
      await activityHistory.recordClientAction(
        origin: origin,
        action: action,
        success: result.ok,
        detail: result.error,
        resolvedTarget:
            result.url ??
            result.app ??
            action.arguments['app_name']?.toString() ??
            action.arguments['url']?.toString() ??
            action.arguments['query']?.toString() ??
            action.arguments['window_title']?.toString() ??
            action.action,
      );
      return;
    }

    if (action.type == 'open_app' && action.appName != null) {
      final app = action.appName!.toLowerCase();

      if (Platform.isWindows) {
        final result = await sendPcAction('open_app', extra: {'app_name': app});
        await activityHistory.recordClientAction(
          origin: origin,
          action: action,
          success: result.ok,
          detail: result.error,
          resolvedTarget: result.app ?? result.url ?? app,
        );
        return;
      }

      var opened = false;
      String? detail;
      String? resolvedTarget = app;

      if (Platform.isAndroid) {
        opened = await _openAndroidApp(app);
      } else if (Platform.isIOS) {
        opened = await _openIOSApp(app);
      }

      if (!opened) {
        final fallbackUrl = 'https://www.google.com/search?q=$app';
        final uri = Uri.parse(fallbackUrl);
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
        resolvedTarget = fallbackUrl;
        detail = 'A app nao abriu localmente; foi aberta uma pesquisa web.';
      }

      await activityHistory.recordClientAction(
        origin: origin,
        action: action,
        success: opened,
        detail: detail,
        resolvedTarget: resolvedTarget,
      );
      return;
    }

    if (action.type == 'open_url' && action.url != null) {
      if (Platform.isWindows) {
        final result = await sendPcAction('open_url', extra: {'url': action.url});
        await activityHistory.recordClientAction(
          origin: origin,
          action: action,
          success: result.ok,
          detail: result.error,
          resolvedTarget: result.url ?? action.url,
        );
        return;
      }

      final uri = Uri.tryParse(action.url!);
      final opened = uri != null
          ? await launchUrl(uri, mode: LaunchMode.externalApplication)
          : false;
      await activityHistory.recordClientAction(
        origin: origin,
        action: action,
        success: opened,
        resolvedTarget: action.url,
      );
    }
  }

  Future<bool> _openAndroidApp(String app) async {
    final package = _guessPackageName(app);

    if (package == null) return false;

    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: package,
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );

      await intent.launch();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _openIOSApp(String app) async {
    final url = _iosScheme(app);

    if (url == null) return false;

    final uri = Uri.parse(url);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return true;
    }

    return false;
  }

  Future<void> startVoiceInput() async {
    if (!isListening) {
      setState(() {
        isListening = true;
        isRecording = true;
      });
      unawaited(_captureVoiceInput());
    } else {
      await voiceService.finishCapture();
    }
  }

  Future<void> _captureVoiceInput() async {
    final capture = await voiceService.captureSpeechTurn(
      maxInitialWait: const Duration(seconds: 6),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      isListening = false;
      isRecording = false;
    });

    if (capture == null || !capture.hasAudio) {
      return;
    }

    if (!await _ensureSession()) return;

    setState(() {
      loading = true;
    });

    try {
      final response = await api.sendVoiceTurn(
        sessionId!,
        capture.wavBytes,
        platform: Platform.operatingSystem,
        locale: Platform.localeName,
      );
      await MemoryService().refresh();
      await _recordResponseHistory(response, origin: 'voice');

      if (!mounted) {
        return;
      }

      setState(() {
        final transcript = response.transcript.trim();
        if (transcript.isNotEmpty) {
          messages.add(ChatMessage(transcript, true));
        }
        messages.add(ChatMessage(response.reply, false));
        loading = false;
      });
      _scrollToBottom();

      await handleClientAction(response.clientAction, origin: 'voice');
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        messages.add(ChatMessage(_formatError(error), false));
        loading = false;
      });
      _scrollToBottom();
    }
  }

  String? _guessPackageName(String app) {
    final map = {
      'youtube': 'com.google.android.youtube',
      'instagram': 'com.instagram.android',
      'whatsapp': 'com.whatsapp',
      'chrome': 'com.android.chrome',
      'maps': 'com.google.android.apps.maps',
      'spotify': 'com.spotify.music',
    };

    return map[app];
  }

  String? _iosScheme(String app) {
    final map = {
      'youtube': 'youtube://',
      'instagram': 'instagram://',
      'whatsapp': 'whatsapp://',
      'maps': 'maps://',
    };

    return map[app];
  }

  @override
  void dispose() {
    controller.dispose();
    scrollController.dispose();
    voiceService.dispose();
    super.dispose();
  }

  Widget _buildEmptyState() {
    final assistantName = settings.assistantName;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: const Color(0xFF0E2238),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF17324C)),
              ),
              child: const Icon(
                Icons.forum_rounded,
                color: Color(0xFF42D9FF),
                size: 34,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Abre uma conversa com o $assistantName',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Podes escrever ou usar o microfone. O modo chat partilha o mesmo backend e contexto do $assistantName.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.68),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(BuildContext context, ChatMessage msg) {
    final isUser = msg.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.62,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isUser
                  ? [const Color(0xFF1C9CC5), const Color(0xFF0C6D8F)]
                  : [const Color(0xFF0A1622), const Color(0xFF07111B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isUser
                  ? const Color(0xFF42D9FF).withOpacity(0.22)
                  : Colors.white.withOpacity(0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.14),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Text(
            msg.text,
            style: TextStyle(
              color: Colors.white.withOpacity(isUser ? 0.96 : 0.88),
              height: 1.45,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xCC07111B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF17324C)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          _ComposerButton(
            icon: isRecording ? Icons.stop_rounded : Icons.mic_rounded,
            backgroundColor: isRecording
                ? const Color(0xFFB32942)
                : const Color(0xFF0E2238),
            onTap: startVoiceInput,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => sendMessage(),
              decoration: InputDecoration(
                hintText: 'Escreve uma mensagem...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.42)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.04),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _ComposerButton(
            icon: Icons.send_rounded,
            backgroundColor: const Color(0xFF1C9CC5),
            onTap: () => sendMessage(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        final assistantName = settings.assistantName;
        final isCompact = MediaQuery.sizeOf(context).width < 980;
        final topPadding = widget.embedded && isCompact ? 78.0 : 18.0;
        final content = Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF08111B), Color(0xFF03070D)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            top: widget.embedded,
            bottom: true,
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, topPadding, 18, 14),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xAA07111B),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFF17324C)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0E2238),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            color: Color(0xFF42D9FF),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Modo Chat',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Conversa por texto com o $assistantName sem sair da shell principal.',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.68),
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: sessionId != null
                                  ? const Color(0xFF42D9FF).withOpacity(0.24)
                                  : Colors.white.withOpacity(0.08),
                            ),
                          ),
                          child: Text(
                            sessionId != null ? 'Sessao ativa' : 'A ligar...',
                            style: TextStyle(
                              color: sessionId != null
                                  ? const Color(0xFF42D9FF)
                                  : Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: const Color(0xFF17324C)),
                      ),
                      child: messages.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
                              itemCount: messages.length,
                              itemBuilder: (context, index) {
                                return _buildMessageBubble(
                                  context,
                                  messages[index],
                                );
                              },
                            ),
                    ),
                  ),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(0, 12, 0, 4),
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        color: Color(0xFF42D9FF),
                        backgroundColor: Color(0x33000000),
                      ),
                    ),
                  const SizedBox(height: 14),
                  _buildComposer(),
                ],
              ),
            ),
          ),
        );

        if (widget.embedded) {
          return content;
        }

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: const Text('Modo Chat'),
            backgroundColor: const Color(0xFF06111B),
          ),
          body: content,
        );
      },
    );
  }
}

class _ComposerButton extends StatelessWidget {
  const _ComposerButton({
    required this.icon,
    required this.backgroundColor,
    required this.onTap,
  });

  final IconData icon;
  final Color backgroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}
