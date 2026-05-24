import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';

import 'activity_history_screen.dart';
import 'assistant_memory_screen.dart';
import '../services/auth_service.dart';
import '../services/assistant_runtime_service.dart';
import '../services/app_settings_service.dart';
import '../services/app_shell_service.dart';
import 'chat_screen.dart';
import 'home_assistant_devices_screen.dart';
import 'routines_screen.dart';
import 'settings_screen.dart';
import 'system_logs_screen.dart';
import 'voice_assistant_screen.dart';

enum AppSection {
  voice,
  chat,
  devices,
  routines,
  memory,
  history,
  logs,
  settings,
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with WindowListener, tray.TrayListener {
  final AuthService _auth = AuthService();
  final AssistantRuntimeService _runtime = AssistantRuntimeService();
  final AppSettingsService _settings = AppSettingsService();
  final AppShellService _shellService = AppShellService();
  final GlobalKey _contentHostKey = GlobalKey();
  final GlobalKey _voiceScreenKey = GlobalKey();

  AppSection _selectedSection = AppSection.voice;
  bool _trayReady = false;
  bool _isQuitting = false;
  bool _sidebarVisible = false;
  bool _isFullscreen = false;
  int _lastWakePromptToken = 0;
  int _lastVoiceOverlayDismissToken = 0;
  Rect? _normalWindowBounds;

  bool get _supportsDesktopRuntime => Platform.isWindows;

  @override
  void initState() {
    super.initState();
    _settings.load();
    unawaited(_runtime.initialize());
    _settings.addListener(_handleSettingsChanged);
    _shellService.addListener(_handleShellServiceChanged);
    unawaited(_initDesktopRuntime());
  }

  @override
  void dispose() {
    _settings.removeListener(_handleSettingsChanged);
    _shellService.removeListener(_handleShellServiceChanged);

    if (_supportsDesktopRuntime) {
      windowManager.removeListener(this);
      tray.trayManager.removeListener(this);
      if (_trayReady) {
        unawaited(tray.trayManager.destroy());
      }
    }

    super.dispose();
  }

  void _selectSection(AppSection section) {
    if (_selectedSection == section) {
      return;
    }

    setState(() {
      _selectedSection = section;
    });
  }

  void _handleSettingsChanged() {
    final visibleSections = _visibleSections;
    if (!visibleSections.contains(_selectedSection)) {
      setState(() {
        _selectedSection = AppSection.voice;
      });
    }

    if (_supportsDesktopRuntime && _trayReady) {
      unawaited(_syncTray());
    }
  }

  void _handleShellServiceChanged() {
    final wakePromptToken = _shellService.wakePromptToken;
    if (wakePromptToken != _lastWakePromptToken) {
      _lastWakePromptToken = wakePromptToken;
      _selectSection(AppSection.voice);

      if (_supportsDesktopRuntime) {
        unawaited(_handleWakePromptWindowMode());
      }
    }

    final overlayDismissToken = _shellService.voiceOverlayDismissToken;
    if (overlayDismissToken != _lastVoiceOverlayDismissToken) {
      _lastVoiceOverlayDismissToken = overlayDismissToken;
      if (_supportsDesktopRuntime) {
        unawaited(_dismissVoiceOverlayWindow());
      }
    }
  }

  Future<void> _initDesktopRuntime() async {
    if (!_supportsDesktopRuntime) {
      return;
    }

    windowManager.addListener(this);
    tray.trayManager.addListener(this);
    await windowManager.setPreventClose(true);
    await _syncTray();
    await _syncWindowState();

    if (mounted) {
      setState(() {
        _trayReady = true;
      });
    } else {
      _trayReady = true;
    }
  }

  Future<void> _syncTray() async {
    if (!_supportsDesktopRuntime) {
      return;
    }

    await tray.trayManager.setIcon(_trayIconPath());
    await tray.trayManager.setToolTip(
      '${_settings.assistantName} em segundo plano',
    );
    await tray.trayManager.setContextMenu(
      tray.Menu(
        items: [
          tray.MenuItem(key: 'show_window', label: 'Abrir assistente'),
          tray.MenuItem(key: 'open_voice', label: 'Abrir modo voz'),
          tray.MenuItem(key: 'hide_window', label: 'Manter em segundo plano'),
          tray.MenuItem.separator(),
          tray.MenuItem(key: 'exit_app', label: 'Sair'),
        ],
      ),
    );
  }

  String _trayIconPath() {
    final separator = Platform.pathSeparator;
    final executableDirectory = File(Platform.resolvedExecutable).parent.path;
    final bundledAssetPath =
        '$executableDirectory${separator}data${separator}flutter_assets${separator}assets${separator}tray_icon.ico';
    if (File(bundledAssetPath).existsSync()) {
      return bundledAssetPath;
    }
    return 'assets${separator}tray_icon.ico';
  }

  Future<void> _restoreWindow() async {
    if (!_supportsDesktopRuntime) {
      return;
    }

    _shellService.exitVoiceOverlayMode();
    await _applyNormalWindowPresentation();
    await windowManager.setSkipTaskbar(false);

    final isVisible = await windowManager.isVisible();
    if (!isVisible) {
      await windowManager.show();
    }

    final isMinimized = await windowManager.isMinimized();
    if (isMinimized) {
      await windowManager.restore();
    }

    await windowManager.focus();
    await _syncWindowState();
  }

  Future<void> _handleWakePromptWindowMode() async {
    if (!_supportsDesktopRuntime) {
      return;
    }

    final isMinimized = await windowManager.isMinimized();
    if (isMinimized) {
      await _restoreWindow();
      return;
    }

    final isVisible = await windowManager.isVisible();
    if (!isVisible) {
      await _showVoiceOverlayWindow();
      return;
    }

    final isFocused = await windowManager.isFocused();
    if (!isFocused || _shellService.voiceOverlayMode) {
      await _restoreWindow();
    }
  }

  Future<void> _showVoiceOverlayWindow() async {
    if (!_supportsDesktopRuntime) {
      return;
    }

    if (!_shellService.voiceOverlayMode) {
      await _prepareVoiceOverlayWindow(activateOverlayMode: true);
    }
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _dismissVoiceOverlayWindow() async {
    if (!_supportsDesktopRuntime || !_shellService.voiceOverlayMode) {
      return;
    }

    _shellService.dismissWakePrompt();
    _shellService.exitVoiceOverlayMode();
    await _hideToTray(prepareForWakeOverlay: false);
  }

  Future<void> _hideToTray({bool prepareForWakeOverlay = true}) async {
    if (!_supportsDesktopRuntime) {
      return;
    }

    _shellService.dismissWakePrompt();
    if (prepareForWakeOverlay) {
      await _prepareVoiceOverlayWindow();
    }
    await windowManager.setSkipTaskbar(true);
    await windowManager.hide();
  }

  Future<void> _applyNormalWindowPresentation() async {
    if (!_supportsDesktopRuntime) {
      return;
    }

    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(const Size(360, 640));

    final normalBounds = _normalWindowBounds;
    if (normalBounds != null) {
      await windowManager.setBounds(normalBounds);
      _normalWindowBounds = null;
    }
  }

  Future<void> _syncWindowState() async {
    if (!_supportsDesktopRuntime) {
      return;
    }

    final isFullscreen = await windowManager.isFullScreen();
    if (!mounted) {
      _isFullscreen = isFullscreen;
      return;
    }

    setState(() {
      _isFullscreen = isFullscreen;
    });
  }

  Future<void> _toggleFullscreen() async {
    if (!_supportsDesktopRuntime || _shellService.voiceOverlayMode) {
      return;
    }

    final next = !_isFullscreen;
    await windowManager.setFullScreen(next);
    if (!mounted) {
      _isFullscreen = next;
      return;
    }

    setState(() {
      _isFullscreen = next;
    });
  }

  void _toggleSidebar() {
    setState(() {
      _sidebarVisible = !_sidebarVisible;
    });
  }

  List<AppSection> get _visibleSections {
    return <AppSection>[
      AppSection.voice,
      AppSection.chat,
      if (_settings.homeAssistantEnabled) AppSection.devices,
      AppSection.routines,
      AppSection.memory,
      AppSection.history,
      AppSection.logs,
      AppSection.settings,
    ];
  }

  AppSection _resolveSelectedSection(List<AppSection> visibleSections) {
    if (visibleSections.contains(_selectedSection)) {
      return _selectedSection;
    }
    return AppSection.voice;
  }

  List<Widget> _buildSectionViews({
    required List<AppSection> visibleSections,
    required bool isVoiceOverlayMode,
  }) {
    return visibleSections.map((section) {
      switch (section) {
        case AppSection.voice:
          return VoiceAssistantScreen(
            key: _voiceScreenKey,
            embedded: true,
            overlayOnly: isVoiceOverlayMode,
          );
        case AppSection.chat:
          return ChatScreen(embedded: true);
        case AppSection.devices:
          return const HomeAssistantDevicesScreen(embedded: true);
        case AppSection.routines:
          return const RoutinesScreen(embedded: true);
        case AppSection.memory:
          return AssistantMemoryScreen(embedded: true);
        case AppSection.history:
          return ActivityHistoryScreen(embedded: true);
        case AppSection.logs:
          return SystemLogsScreen(embedded: true);
        case AppSection.settings:
          return SettingsScreen(embedded: true);
      }
    }).toList();
  }

  Future<void> _prepareVoiceOverlayWindow({
    bool activateOverlayMode = false,
  }) async {
    if (!_supportsDesktopRuntime) {
      return;
    }

    if (_isFullscreen) {
      await windowManager.setFullScreen(false);
      _isFullscreen = false;
    }
    _normalWindowBounds ??= await windowManager.getBounds();
    if (activateOverlayMode) {
      _shellService.enterVoiceOverlayMode();
    }
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.setResizable(false);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setMinimumSize(const Size(420, 520));
    await windowManager.setSize(const Size(420, 520));
    await windowManager.center();
  }

  Future<void> _exitApplication() async {
    if (!_supportsDesktopRuntime) {
      return;
    }

    _isQuitting = true;
    await tray.trayManager.destroy();
    _trayReady = false;
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  @override
  void onWindowClose() {
    if (!_supportsDesktopRuntime || _isQuitting) {
      return;
    }

    unawaited(_hideToTray());
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_restoreWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    tray.trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(tray.MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_window':
        unawaited(_restoreWindow());
        return;
      case 'open_voice':
        _selectSection(AppSection.voice);
        unawaited(_restoreWindow());
        return;
      case 'hide_window':
        unawaited(_hideToTray());
        return;
      case 'exit_app':
        unawaited(_exitApplication());
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_settings, _shellService, _auth]),
      builder: (context, _) {
        final isWide = MediaQuery.sizeOf(context).width >= 980;
        final isVoiceOverlayMode = _shellService.voiceOverlayMode;
        final assistantName = _settings.assistantName;
        final accountName = (_auth.user?.displayName ?? '').trim().isNotEmpty
            ? _auth.user!.displayName
            : (_auth.user?.email ?? '');
        final visibleSections = _visibleSections;
        final activeSection = isVoiceOverlayMode
            ? AppSection.voice
            : _resolveSelectedSection(visibleSections);
        final selectedIndex = isVoiceOverlayMode
            ? visibleSections.indexOf(AppSection.voice)
            : visibleSections.indexOf(activeSection);
        final sectionTitle = _sectionTitle(activeSection);
        final sectionSubtitle = _sectionSubtitle(
          activeSection,
          assistantName,
        );
        final content = KeyedSubtree(
          key: _contentHostKey,
          child: IndexedStack(
            index: selectedIndex,
            children: _buildSectionViews(
              visibleSections: visibleSections,
              isVoiceOverlayMode: isVoiceOverlayMode,
            ),
          ),
        );

        if (isVoiceOverlayMode) {
          return Scaffold(backgroundColor: Colors.transparent, body: content);
        }

        return Scaffold(
          backgroundColor: const Color(0xFF02060C),
          drawer: isWide
              ? null
              : Drawer(
                  width: 340,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  child: _DrawerMenu(
                    assistantName: assistantName,
                    accountName: accountName,
                    onLogout: _auth.loading
                        ? null
                        : () => unawaited(_auth.logout()),
                    sections: visibleSections,
                    selectedSection: _selectedSection,
                    onSectionSelected: (section) {
                      Navigator.of(context).pop();
                      _selectSection(section);
                    },
                  ),
                ),
          body: Stack(
            children: [
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF02060C),
                        Color(0xFF07111B),
                        Color(0xFF040916),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
              if (isWide)
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        _DesktopSidebarRail(
                          sections: visibleSections,
                          selectedSection: _selectedSection,
                          sidebarVisible: _sidebarVisible,
                          onMenuTap: _toggleSidebar,
                          onSectionSelected: (section) {
                            _selectSection(section);
                          },
                        ),
                        const SizedBox(width: 18),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          width: _sidebarVisible ? 312 : 0,
                          child: ClipRect(
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 180),
                              opacity: _sidebarVisible ? 1 : 0,
                              child: IgnorePointer(
                                ignoring: !_sidebarVisible,
                                child: _SidebarMenu(
                                  assistantName: assistantName,
                                  accountName: accountName,
                                  onLogout: _auth.loading
                                      ? null
                                      : () => unawaited(_auth.logout()),
                                  sections: visibleSections,
                                  selectedSection: _selectedSection,
                                  onSectionSelected: (section) {
                                    _selectSection(section);
                                    setState(() {
                                      _sidebarVisible = false;
                                    });
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (_sidebarVisible) const SizedBox(width: 18),
                        Expanded(
                          child: _WorkspaceFrame(
                            title: sectionTitle,
                            subtitle: sectionSubtitle,
                            onMenuTap: _toggleSidebar,
                            showMenuAction: false,
                            showFullscreenAction: _supportsDesktopRuntime,
                            isFullscreen: _isFullscreen,
                            onFullscreenTap: _toggleFullscreen,
                            child: content,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Builder(
                      builder: (context) {
                        return _WorkspaceFrame(
                          title: sectionTitle,
                          subtitle: sectionSubtitle,
                          onMenuTap: () => Scaffold.of(context).openDrawer(),
                          showMenuAction: true,
                          showFullscreenAction: false,
                          isFullscreen: false,
                          onFullscreenTap: null,
                          child: content,
                        );
                      },
                    ),
                  ),
                ),
              if (_shellService.wakePromptVisible && !isVoiceOverlayMode)
                IgnorePointer(
                  child: SafeArea(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: isWide ? 26 : 84,
                          left: 18,
                          right: 18,
                        ),
                        child: _WakePromptBanner(
                          message: _shellService.wakePromptMessage,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SidebarMenu extends StatelessWidget {
  const _SidebarMenu({
    required this.assistantName,
    required this.accountName,
    required this.onLogout,
    required this.sections,
    required this.selectedSection,
    required this.onSectionSelected,
  });

  final String assistantName;
  final String accountName;
  final VoidCallback? onLogout;
  final List<AppSection> sections;
  final AppSection selectedSection;
  final ValueChanged<AppSection> onSectionSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: const Color(0xCC08121D),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFF183753)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Scrollbar(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BrandPanel(
                assistantName: assistantName,
                accountName: accountName,
                onLogout: onLogout,
              ),
              const SizedBox(height: 24),
              Text(
                'NAVEGACAO',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.52),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(height: 12),
              for (final section in sections) ...[
                _NavButton(
                  icon: _sectionIcon(section),
                  title: _sectionTitle(section),
                  subtitle: _sectionSubtitle(section, assistantName),
                  selected: selectedSection == section,
                  onTap: () => onSectionSelected(section),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Entrada principal',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.62),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'O modo voz abre primeiro e as restantes areas disponiveis ficam sempre acessiveis no menu lateral.',
                      style: const TextStyle(color: Colors.white, height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerMenu extends StatelessWidget {
  const _DrawerMenu({
    required this.assistantName,
    required this.accountName,
    required this.onLogout,
    required this.sections,
    required this.selectedSection,
    required this.onSectionSelected,
  });

  final String assistantName;
  final String accountName;
  final VoidCallback? onLogout;
  final List<AppSection> sections;
  final AppSection selectedSection;
  final ValueChanged<AppSection> onSectionSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF07111B), Color(0xFF02060C)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          child: Scrollbar(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BrandPanel(
                    assistantName: assistantName,
                    accountName: accountName,
                    onLogout: onLogout,
                    compact: true,
                  ),
                  const SizedBox(height: 24),
                  for (final section in sections) ...[
                    _NavButton(
                      icon: _sectionIcon(section),
                      title: _sectionTitle(section),
                      subtitle: _sectionSubtitle(section, assistantName),
                      selected: selectedSection == section,
                      onTap: () => onSectionSelected(section),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({
    required this.assistantName,
    required this.accountName,
    required this.onLogout,
    this.compact = false,
  });

  final String assistantName;
  final String accountName;
  final VoidCallback? onLogout;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 16 : 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF11243A), Color(0xFF09121D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFF1D3C59)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            assistantName.toUpperCase(),
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 24 : 28,
              fontWeight: FontWeight.w700,
              letterSpacing: 4.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Workspace principal do assistente com voz, chat, rotinas, memoria, historico, logs e configuracoes.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              height: 1.5,
            ),
          ),
          if (accountName.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    accountName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: onLogout,
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Terminar sessao'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF102B42)
                : Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? const Color(0xFF42D9FF)
                  : Colors.white.withOpacity(0.08),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF42D9FF).withOpacity(0.16)
                      : Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  color: selected ? const Color(0xFF42D9FF) : Colors.white70,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.62),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopSidebarRail extends StatelessWidget {
  const _DesktopSidebarRail({
    required this.sections,
    required this.selectedSection,
    required this.sidebarVisible,
    required this.onMenuTap,
    required this.onSectionSelected,
  });

  final List<AppSection> sections;
  final AppSection selectedSection;
  final bool sidebarVisible;
  final VoidCallback onMenuTap;
  final ValueChanged<AppSection> onSectionSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 86,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xB308121D),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFF183753)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          _RailIconButton(
            icon: sidebarVisible ? Icons.close_rounded : Icons.menu_rounded,
            tooltip: sidebarVisible ? 'Fechar menu' : 'Abrir menu',
            selected: sidebarVisible,
            onTap: onMenuTap,
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Column(
              children: [
                for (final section in sections) ...[
                  _RailIconButton(
                    icon: _sectionIcon(section),
                    tooltip: _sectionTitle(section),
                    selected: selectedSection == section,
                    onTap: () => onSectionSelected(section),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RailIconButton extends StatelessWidget {
  const _RailIconButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Ink(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF102B42)
                  : Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? const Color(0xFF42D9FF)
                    : Colors.white.withOpacity(0.08),
              ),
            ),
            child: Icon(
              icon,
              color: selected ? const Color(0xFF42D9FF) : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceFrame extends StatelessWidget {
  const _WorkspaceFrame({
    required this.title,
    required this.subtitle,
    required this.onMenuTap,
    required this.showMenuAction,
    required this.showFullscreenAction,
    required this.isFullscreen,
    required this.onFullscreenTap,
    required this.child,
  });

  final String title;
  final String subtitle;
  final VoidCallback onMenuTap;
  final bool showMenuAction;
  final bool showFullscreenAction;
  final bool isFullscreen;
  final VoidCallback? onFullscreenTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: const Color(0xFF17324C)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(33),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xE709111B), Color(0xF4060B13)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              children: [
                _ShellTopBar(
                  title: title,
                  subtitle: subtitle,
                  onMenuTap: onMenuTap,
                  showMenuAction: showMenuAction,
                  showFullscreenAction: showFullscreenAction,
                  isFullscreen: isFullscreen,
                  onFullscreenTap: onFullscreenTap,
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(28),
                    ),
                    child: child,
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

class _ShellTopBar extends StatelessWidget {
  const _ShellTopBar({
    required this.title,
    required this.subtitle,
    required this.onMenuTap,
    required this.showMenuAction,
    required this.showFullscreenAction,
    required this.isFullscreen,
    required this.onFullscreenTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onMenuTap;
  final bool showMenuAction;
  final bool showFullscreenAction;
  final bool isFullscreen;
  final VoidCallback? onFullscreenTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          if (showMenuAction) ...[
            _TopBarActionButton(
              icon: Icons.menu_rounded,
              tooltip: 'Abrir navegacao',
              onTap: onMenuTap,
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.62),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const _ClockChip(),
          if (showFullscreenAction) ...[
            const SizedBox(width: 10),
            _TopBarActionButton(
              icon: isFullscreen
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              tooltip: isFullscreen ? 'Sair de ecrã inteiro' : 'Ecrã inteiro',
              onTap: onFullscreenTap,
            ),
          ],
        ],
      ),
    );
  }
}

class _ClockChip extends StatefulWidget {
  const _ClockChip();

  @override
  State<_ClockChip> createState() => _ClockChipState();
}

class _ClockChipState extends State<_ClockChip> {
  late final Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _now = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String get _formattedTime {
    final hour = _now.hour.toString().padLeft(2, '0');
    final minute = _now.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule_rounded, color: Colors.white70, size: 16),
          const SizedBox(width: 8),
          Text(
            _formattedTime,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBarActionButton extends StatelessWidget {
  const _TopBarActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Icon(icon, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _WakePromptBanner extends StatelessWidget {
  const _WakePromptBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xEE07111B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF42D9FF).withOpacity(0.55)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF42D9FF).withOpacity(0.14),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mic_none_rounded, color: Color(0xFF42D9FF)),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _sectionIcon(AppSection section) {
  switch (section) {
    case AppSection.voice:
      return Icons.graphic_eq_rounded;
    case AppSection.chat:
      return Icons.chat_bubble_outline_rounded;
    case AppSection.devices:
      return Icons.devices_other_rounded;
    case AppSection.routines:
      return Icons.auto_awesome_motion_rounded;
    case AppSection.memory:
      return Icons.storage_rounded;
    case AppSection.history:
      return Icons.history_rounded;
    case AppSection.logs:
      return Icons.receipt_long_rounded;
    case AppSection.settings:
      return Icons.tune_rounded;
  }
}

String _sectionTitle(AppSection section) {
  switch (section) {
    case AppSection.voice:
      return 'Modo Voz';
    case AppSection.chat:
      return 'Modo Chat';
    case AppSection.devices:
      return 'Dispositivos';
    case AppSection.routines:
      return 'Rotinas';
    case AppSection.memory:
      return 'Memoria';
    case AppSection.history:
      return 'Historico';
    case AppSection.logs:
      return 'Logs';
    case AppSection.settings:
      return 'Configuracoes';
  }
}

String _sectionSubtitle(AppSection section, String assistantName) {
  switch (section) {
    case AppSection.voice:
      return 'Interface principal do $assistantName com controlo por voz.';
    case AppSection.chat:
      return 'Conversas por texto com o mesmo backend e contexto.';
    case AppSection.devices:
      return 'Mapa de dispositivos e aliases do Home Assistant.';
    case AppSection.routines:
      return 'Gestao de rotinas persistentes e automacoes da casa.';
    case AppSection.memory:
      return 'Tabela da memoria persistente com filtros e pesquisa.';
    case AppSection.history:
      return 'Sites, tools e acoes executadas pelo assistente.';
    case AppSection.logs:
      return 'Tabela dedicada com os logs tecnicos do sistema.';
    case AppSection.settings:
      return 'Nome, wake word e memoria persistente do assistente.';
  }
}
