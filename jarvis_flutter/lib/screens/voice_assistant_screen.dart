import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/assistant_state.dart';
import '../models/chat_response.dart';
import '../services/agent_service.dart';
import '../services/activity_history_service.dart';
import '../services/assistant_runtime_service.dart';
import '../services/api_service.dart';
import '../services/app_settings_service.dart';
import '../services/app_shell_service.dart';
import '../services/conversation_service.dart';
import '../services/memory_service.dart';
import '../services/tts_service.dart';
import '../services/voice_service.dart';
import '../widgets/jarvis_orb.dart';

class VoiceAssistantScreen extends StatefulWidget {
  const VoiceAssistantScreen({
    super.key,
    this.embedded = false,
    this.overlayOnly = false,
  });

  final bool embedded;
  final bool overlayOnly;

  @override
  State<VoiceAssistantScreen> createState() => _VoiceAssistantScreenState();
}

class _VoiceAssistantScreenState extends State<VoiceAssistantScreen> {
  final ApiService api = ApiService();
  final AssistantRuntimeService runtime = AssistantRuntimeService();
  final AppSettingsService settings = AppSettingsService();
  final AppShellService shellService = AppShellService();
  final ConversationService conversation = ConversationService();
  final VoiceService voiceService = VoiceService();
  final TtsService ttsService = TtsService();
  final ActivityHistoryService activityHistory = ActivityHistoryService();

  AssistantState assistantState = AssistantState.idle;
  String statusText = 'A iniciar...';

  bool isBusy = false;
  bool isListening = false;
  bool _continuousConversationEnabled = false;
  bool _showTranscriptInspector = false;
  String _lastWakeWordPhrase = AppSettingsService.defaultAssistantName;
  String _lastHeardTranscript = '';
  int _lastVoiceCaptureToken = 0;

  static const Set<String> _continuousStopPhrases = <String>{
    'parar escuta',
    'para escuta',
    'parar conversa',
    'terminar conversa',
    'desligar conversa continua',
    'desliga conversa continua',
    'parar de ouvir',
    'deixa de ouvir',
    'podes parar',
    'pode parar',
    'ja podes parar',
  };

  String get _assistantName => settings.assistantName;
  String get _wakeWordPhrase => settings.wakeWordPhrase;
  bool get wakeWordEnabled => runtime.wakeWordEnabled;
  bool get wakeWordReady => runtime.wakeWordReady;

  String get _idleStatusText {
    if (wakeWordEnabled && wakeWordReady) {
      return "Diz '$_wakeWordPhrase' ou toca para falar";
    }

    return 'Pronto para conversar';
  }

  String get _idleFooterText {
    if (wakeWordEnabled && wakeWordReady) {
      return "Diz '$_wakeWordPhrase' ou toca para falar";
    }

    return 'Toque para falar';
  }

  String get _wakeWordBadgeText {
    if (!Platform.isWindows) {
      return 'Wake word: manual neste dispositivo';
    }

    if (!wakeWordEnabled) {
      return "Wake word '$_wakeWordPhrase': desligada";
    }

    if (wakeWordReady) {
      return "Wake word '$_wakeWordPhrase': ativa";
    }

    return "Wake word '$_wakeWordPhrase': indisponivel";
  }

  Color get _wakeWordBadgeColor {
    if (wakeWordReady) {
      return Colors.cyanAccent;
    }

    return Colors.white70;
  }

  @override
  void initState() {
    super.initState();
    _lastVoiceCaptureToken = shellService.voiceCaptureToken;
    settings.addListener(_handleSettingsChanged);
    runtime.addListener(_handleRuntimeChanged);
    shellService.addListener(_handleShellEvents);
    _init();
  }

  Future<void> _init() async {
    await settings.load();
    await runtime.initialize();
    _lastWakeWordPhrase = _wakeWordPhrase;
    await conversation.ensureSession();
    await ttsService.init();

    if (mounted) {
      setState(() {
        statusText = _idleStatusText;
      });
    }
  }

  void _handleSettingsChanged() {
    if (!mounted) {
      return;
    }

    _lastWakeWordPhrase = _wakeWordPhrase;

    if (!isBusy && !isListening && assistantState == AssistantState.idle) {
      setState(() {
        statusText = _idleStatusText;
      });
    }
  }

  void _handleRuntimeChanged() {
    if (!mounted) {
      return;
    }

    if (!isBusy && !isListening && assistantState == AssistantState.idle) {
      setState(() {
        statusText = _idleStatusText;
      });
      return;
    }

    setState(() {});
  }

  void _handleShellEvents() {
    final captureToken = shellService.voiceCaptureToken;
    if (captureToken == _lastVoiceCaptureToken) {
      return;
    }

    _lastVoiceCaptureToken = captureToken;
    if (!mounted || isBusy || isListening) {
      return;
    }

    unawaited(_startListening(triggeredByWakeWord: true));
  }

  Future<void> onMicPressed() async {
    if (isBusy && !isListening) return;

    if (!isListening) {
      await _startListening();
    } else {
      setState(() {
        statusText = 'A terminar...';
      });
      await voiceService.finishCapture();
    }
  }

  Future<void> _toggleWakeWord() async {
    await runtime.setWakeWordEnabled(!wakeWordEnabled);

    if (mounted && !isBusy && !isListening) {
      setState(() {
        statusText = _idleStatusText;
      });
    }
  }

  Future<void> _startListening({
    bool triggeredByWakeWord = false,
    bool isFollowUp = false,
  }) async {
    if (!mounted || isBusy || isListening) {
      return;
    }

    setState(() {
      isListening = true;
      assistantState = AssistantState.listening;
      statusText = isFollowUp
          ? 'Conversa continua ativa. Estou a ouvir...'
          : triggeredByWakeWord
          ? 'Pode falar. Estou a ouvir...'
          : 'Estou a ouvir...';
    });

    unawaited(runtime.beginVoiceCaptureSession());
    unawaited(_captureAndProcessSpeech(isFollowUp: isFollowUp));
  }

  Future<void> _captureAndProcessSpeech({required bool isFollowUp}) async {
    final capture = await voiceService.captureSpeechTurn(
      maxInitialWait: isFollowUp
          ? const Duration(seconds: 8)
          : const Duration(seconds: 4),
      inputDeviceId: settings.microphoneDeviceId,
      onSpeechStart: () {
        if (!mounted || !isListening) {
          return;
        }

        setState(() {
          statusText = 'Fala...';
        });
      },
    );

    if (!mounted) {
      return;
    }

    setState(() {
      isListening = false;
    });

    if (capture == null || !capture.hasAudio) {
      setState(() {
        assistantState = AssistantState.idle;
        statusText = isFollowUp
            ? 'Conversa continua em pausa. Toca para retomar.'
            : 'Nao percebi o que disseste.';
        isBusy = false;
      });
      await runtime.endVoiceCaptureSession();
      if (widget.overlayOnly) {
        shellService.requestVoiceOverlayDismiss();
      }
      return;
    }

    setState(() {
      isBusy = true;
      assistantState = AssistantState.thinking;
      statusText = 'A processar...';
    });

    final stoppedLocally = await _handleContinuousStopCommand(
      capture.wavBytes,
      isFollowUp: isFollowUp,
    );
    if (stoppedLocally) {
      await runtime.endVoiceCaptureSession();
      return;
    }

    final response = await conversation.sendVoiceTurn(
      capture.wavBytes,
      platform: Platform.operatingSystem,
      locale: Platform.localeName,
    );
    final transcript = response.transcript.trim();

    if (!mounted) {
      return;
    }

    setState(() {
      _lastHeardTranscript = transcript;
      assistantState = AssistantState.speaking;
      statusText = response.reply;
    });

    unawaited(_runPostResponseTasks(response));
    await ttsService.speak(response.reply);
    final shouldContinueConversation =
        _continuousConversationEnabled &&
        !widget.overlayOnly &&
        transcript.isNotEmpty;

    if (mounted) {
      setState(() {
        assistantState = AssistantState.idle;
        statusText = shouldContinueConversation
            ? 'A preparar o seguimento...'
            : _idleStatusText;
        isBusy = false;
      });
    }

    await runtime.endVoiceCaptureSession();
    if (shouldContinueConversation) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (mounted &&
          _continuousConversationEnabled &&
          !isBusy &&
          !isListening) {
        unawaited(_startListening(isFollowUp: true));
        return;
      }
    }
    if (widget.overlayOnly) {
      await Future<void>.delayed(const Duration(milliseconds: 650));
      shellService.requestVoiceOverlayDismiss();
    }
  }

  Future<bool> _handleContinuousStopCommand(
    List<int> wavBytes, {
    required bool isFollowUp,
  }) async {
    if ((!_continuousConversationEnabled && !isFollowUp) ||
        widget.overlayOnly) {
      return false;
    }

    String transcript;
    try {
      transcript = (await api.transcribeAudio(
        Uint8List.fromList(wavBytes),
      )).trim();
    } catch (_) {
      return false;
    }

    if (!_isContinuousStopCommand(transcript)) {
      return false;
    }

    conversation.appendLocalExchange(
      userText: transcript,
      assistantReply: 'Conversa continua desligada.',
    );

    if (mounted) {
      setState(() {
        _lastHeardTranscript = transcript;
        _continuousConversationEnabled = false;
        assistantState = AssistantState.idle;
        statusText = 'Conversa continua desligada.';
        isBusy = false;
      });
    }

    await ttsService.speak('Conversa continua desligada.');
    return true;
  }

  bool _isContinuousStopCommand(String transcript) {
    final normalized = _normalizeCommandText(transcript);
    if (normalized.isEmpty) {
      return false;
    }

    for (final phrase in _continuousStopPhrases) {
      if (normalized.contains(phrase)) {
        return true;
      }
    }
    return false;
  }

  String _normalizeCommandText(String input) {
    const replacements = <String, String>{
      'á': 'a',
      'à': 'a',
      'ã': 'a',
      'â': 'a',
      'é': 'e',
      'ê': 'e',
      'í': 'i',
      'ó': 'o',
      'ô': 'o',
      'õ': 'o',
      'ú': 'u',
      'ç': 'c',
    };

    var normalized = input.toLowerCase();
    replacements.forEach((key, value) {
      normalized = normalized.replaceAll(key, value);
    });
    normalized = normalized.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized;
  }

  void _toggleContinuousConversation() {
    setState(() {
      _continuousConversationEnabled = !_continuousConversationEnabled;
      if (!_continuousConversationEnabled &&
          !isListening &&
          !isBusy &&
          assistantState == AssistantState.idle) {
        statusText = _idleStatusText;
      }
    });
  }

  Future<void> _runPostResponseTasks(ChatResponseModel response) async {
    try {
      await Future.wait([
        MemoryService().refresh(),
        _recordResponseHistory(response),
        _handleClientAction(response.clientAction),
      ]);
    } catch (_) {
      // O turno de voz nao deve falhar por efeitos secundarios.
    }
  }

  Future<void> _handleClientAction(ClientAction? action) async {
    if (action == null) {
      return;
    }

    if (Platform.isWindows) {
      if (action.type == 'pc_action' && action.action != null) {
        final result = await sendPcAction(
          action.action!,
          extra: action.arguments.isEmpty ? null : action.arguments,
        );
        await activityHistory.recordClientAction(
          origin: 'voice',
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
        final result = await sendPcAction(
          'open_app',
          extra: {'app_name': action.appName!.toLowerCase()},
        );
        await activityHistory.recordClientAction(
          origin: 'voice',
          action: action,
          success: result.ok,
          detail: result.error,
          resolvedTarget: result.app ?? result.url ?? action.appName,
        );
        return;
      }

      if (action.type == 'open_url' && action.url != null) {
        final result = await sendPcAction(
          'open_url',
          extra: {'url': action.url},
        );
        await activityHistory.recordClientAction(
          origin: 'voice',
          action: action,
          success: result.ok,
          detail: result.error,
          resolvedTarget: result.url ?? action.url,
        );
        return;
      }
    }

    if (action.type == 'open_url' && action.url != null) {
      final uri = Uri.tryParse(action.url!);
      final opened = uri != null
          ? await launchUrl(uri, mode: LaunchMode.externalApplication)
          : false;
      await activityHistory.recordClientAction(
        origin: 'voice',
        action: action,
        success: opened,
        resolvedTarget: action.url,
      );
      return;
    }

    if (action.type == 'open_app' && action.appName != null) {
      final fallbackUrl =
          'https://www.google.com/search?q=${Uri.encodeComponent(action.appName!)}';
      final uri = Uri.parse(fallbackUrl);
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      await activityHistory.recordClientAction(
        origin: 'voice',
        action: action,
        success: opened,
        detail: 'A app nao abriu localmente; foi aberta uma pesquisa web.',
        resolvedTarget: fallbackUrl,
      );
    }
  }

  Future<void> _recordResponseHistory(ChatResponseModel response) async {
    if (response.toolCall == null || response.clientAction != null) {
      return;
    }

    await activityHistory.recordToolUsage(
      origin: 'voice',
      toolCall: response.toolCall!,
      toolResult: response.toolResult,
    );
  }

  @override
  void dispose() {
    settings.removeListener(_handleSettingsChanged);
    runtime.removeListener(_handleRuntimeChanged);
    shellService.removeListener(_handleShellEvents);
    voiceService.dispose();
    ttsService.stop();
    super.dispose();
  }

  Widget _buildMainUI() {
    final isActive = assistantState == AssistantState.listening;
    final isOverlayOnly = widget.overlayOnly;
    final orbSize = isOverlayOnly ? 210.0 : 260.0;
    final statusFontSize = isOverlayOnly ? 16.0 : 18.0;
    final micSize = isOverlayOnly
        ? (isActive ? 82.0 : 70.0)
        : (isActive ? 90.0 : 76.0);
    final micIconSize = isOverlayOnly ? 30.0 : 34.0;
    final topSpacing = isOverlayOnly ? 20.0 : 32.0;
    final middleSpacing = isOverlayOnly ? 28.0 : 40.0;
    final bottomSpacing = isOverlayOnly ? 12.0 : 16.0;

    return Stack(
      children: [
        if (!isOverlayOnly)
          const Positioned.fill(child: _VoiceAmbientBackground()),
        SafeArea(
          child: Center(
            child: Container(
              width: isOverlayOnly ? 360 : null,
              padding: EdgeInsets.symmetric(
                horizontal: isOverlayOnly ? 18 : 0,
                vertical: isOverlayOnly ? 18 : 0,
              ),
              decoration: isOverlayOnly
                  ? BoxDecoration(
                      color: const Color(0xEE07111B),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: const Color(0xFF42D9FF).withOpacity(0.32),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.28),
                          blurRadius: 34,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    )
                  : null,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  JarvisOrb(
                    state: assistantState,
                    assistantName: _assistantName,
                    size: orbSize,
                  ),
                  SizedBox(height: topSpacing),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isOverlayOnly ? 8 : 24,
                    ),
                    child: Text(
                      statusText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.90),
                        fontSize: statusFontSize,
                      ),
                    ),
                  ),
                  SizedBox(height: middleSpacing),
                  GestureDetector(
                    onTap: onMicPressed,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: micSize,
                      height: micSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: isActive
                              ? [
                                  const Color(0xFF00E5FF),
                                  const Color(0xFF00B0FF),
                                ]
                              : [
                                  const Color(0xFF162033),
                                  const Color(0xFF0B1A2A),
                                ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF00E5FF,
                            ).withOpacity(isActive ? 0.6 : 0.2),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Icon(
                        isActive ? Icons.stop : Icons.mic,
                        color: Colors.white,
                        size: micIconSize,
                      ),
                    ),
                  ),
                  SizedBox(height: bottomSpacing),
                  Text(
                    isListening ? 'A ouvir...' : _idleFooterText,
                    style: TextStyle(color: Colors.white.withOpacity(0.7)),
                  ),
                  if (!isOverlayOnly) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _DebugActionChip(
                          icon: _continuousConversationEnabled
                              ? Icons.hearing_rounded
                              : Icons.hearing_disabled_rounded,
                          label: _continuousConversationEnabled
                              ? 'Conversa continua ligada'
                              : 'Conversa continua desligada',
                          onTap: _toggleContinuousConversation,
                        ),
                        _DebugActionChip(
                          icon: wakeWordEnabled
                              ? Icons.hearing_rounded
                              : Icons.hearing_disabled_rounded,
                          label: wakeWordEnabled
                              ? 'Wake word ligada'
                              : 'Wake word desligada',
                          onTap: _toggleWakeWord,
                        ),
                        _DebugActionChip(
                          icon: _showTranscriptInspector
                              ? Icons.visibility_off_outlined
                              : Icons.subtitles_outlined,
                          label: _showTranscriptInspector
                              ? 'Esconder transcricao'
                              : 'Mostrar transcricao',
                          onTap: () {
                            setState(() {
                              _showTranscriptInspector =
                                  !_showTranscriptInspector;
                            });
                          },
                        ),
                        if (_lastHeardTranscript.isNotEmpty)
                          _DebugActionChip(
                            icon: Icons.cleaning_services_outlined,
                            label: 'Limpar texto',
                            onTap: () {
                              setState(() {
                                _lastHeardTranscript = '';
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: wakeWordReady
                              ? Colors.cyanAccent.withOpacity(0.35)
                              : Colors.white.withOpacity(0.12),
                        ),
                      ),
                      child: Text(
                        _wakeWordBadgeText,
                        style: TextStyle(
                          color: _wakeWordBadgeColor,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (!isOverlayOnly)
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: !_showTranscriptInspector
                      ? const SizedBox.shrink()
                      : ConstrainedBox(
                          key: const ValueKey('transcript_inspector'),
                          constraints: const BoxConstraints(
                            maxWidth: 520,
                            maxHeight: 170,
                          ),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xF0101722),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(
                                  0xFF42D9FF,
                                ).withOpacity(0.22),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.22),
                                  blurRadius: 22,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Ultimo texto reconhecido',
                                  style: TextStyle(
                                    color: Colors.cyanAccent.withOpacity(0.92),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: Text(
                                      _lastHeardTranscript.isEmpty
                                          ? 'Ainda nao ha nenhuma transcricao desta sessao.'
                                          : _lastHeardTranscript,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.88),
                                        fontSize: 14,
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _continuousConversationEnabled
                                      ? "Diz 'parar conversa' para sair da escuta continua."
                                      : "Ativa a conversa continua para falar sem repetir a wake word.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.56),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildMainUI();

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text('Modo Voz'),
      ),
      body: content,
    );
  }
}

class _DebugActionChip extends StatelessWidget {
  const _DebugActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.22),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: const Color(0xFF42D9FF).withOpacity(0.16),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.cyanAccent, size: 16),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.82),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceAmbientBackground extends StatelessWidget {
  const _VoiceAmbientBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF040812), Color(0xFF08111C), Color(0xFF050914)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        Align(
          alignment: const Alignment(0, -0.25),
          child: Container(
            width: 520,
            height: 520,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF31D6FF).withOpacity(0.18),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
