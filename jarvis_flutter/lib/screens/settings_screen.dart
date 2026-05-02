import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/registered_device.dart';
import '../models/routine.dart';
import '../services/api_service.dart';
import '../services/app_settings_service.dart';
import '../services/device_registry_service.dart';
import '../services/voice_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ApiService _api = ApiService();
  final AppSettingsService _settings = AppSettingsService();
  final DeviceRegistryService _deviceRegistry = DeviceRegistryService();
  final VoiceService _voiceService = VoiceService();
  final TextEditingController _assistantNameController =
      TextEditingController();
  final TextEditingController _userNameController = TextEditingController();
  final TextEditingController _wakeWordController = TextEditingController();
  final TextEditingController _homeAssistantUrlController =
      TextEditingController();
  final TextEditingController _homeAssistantTokenController =
      TextEditingController();

  bool _testingHomeAssistant = false;
  bool _loadingMicrophones = false;
  bool _testingMicrophone = false;
  bool _homeAssistantEnabled = false;
  HomeAssistantStatus? _homeAssistantStatus;
  List<MicrophoneDevice> _microphones = const <MicrophoneDevice>[];
  String _selectedMicrophoneId = '';
  String? _microphoneStatusMessage;
  bool _microphoneStatusOk = false;

  @override
  void initState() {
    super.initState();
    _applyServiceValues();
    unawaited(_loadSettings());
    unawaited(_deviceRegistry.load());
    unawaited(_loadMicrophones());
  }

  Future<void> _loadSettings() async {
    await _settings.load();
    if (!mounted) {
      return;
    }
    setState(_applyServiceValues);
  }

  void _applyServiceValues() {
    _assistantNameController.text = _settings.assistantName;
    _userNameController.text = _settings.userName;
    _wakeWordController.text = _settings.wakeWordPhrase;
    _homeAssistantEnabled = _settings.homeAssistantEnabled;
    _homeAssistantUrlController.text = _settings.homeAssistantUrl;
    _homeAssistantTokenController.text = _settings.homeAssistantToken;
    _selectedMicrophoneId = _settings.microphoneDeviceId;
  }

  Future<void> _loadMicrophones() async {
    setState(() {
      _loadingMicrophones = true;
    });

    final devices = await _voiceService.listAvailableMicrophones();
    if (!mounted) {
      return;
    }

    setState(() {
      _microphones = devices;
      _loadingMicrophones = false;
      final selectedExists = devices.any(
        (device) => device.id == _selectedMicrophoneId,
      );
      if (!selectedExists) {
        _selectedMicrophoneId = '';
      }
    });
  }

  Future<void> _saveSettings() async {
    MicrophoneDevice? selectedMicrophone;
    for (final device in _microphones) {
      if (device.id == _selectedMicrophoneId) {
        selectedMicrophone = device;
        break;
      }
    }
    final success = await _settings.saveSettings(
      assistantName: _assistantNameController.text,
      userName: _userNameController.text,
      wakeWordPhrase: _wakeWordController.text,
      homeAssistantEnabled: _homeAssistantEnabled,
      homeAssistantUrl: _homeAssistantUrlController.text,
      homeAssistantToken: _homeAssistantTokenController.text,
      microphoneDeviceId: _selectedMicrophoneId,
      microphoneDeviceLabel: selectedMicrophone?.displayLabel ?? '',
    );

    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success
              ? (_settings.warning == null
                    ? 'Configuracoes guardadas.'
                    : 'Configuracoes guardadas localmente. Nao consegui sincronizar tudo com a memoria do backend.')
              : (_settings.error ?? 'Nao foi possivel guardar as configuracoes.'),
        ),
      ),
    );

    if (success) {
      setState(_applyServiceValues);
    }
  }

  Future<void> _testHomeAssistant() async {
    MicrophoneDevice? selectedMicrophone;
    for (final device in _microphones) {
      if (device.id == _selectedMicrophoneId) {
        selectedMicrophone = device;
        break;
      }
    }
    final saved = await _settings.saveSettings(
      assistantName: _assistantNameController.text,
      userName: _userNameController.text,
      wakeWordPhrase: _wakeWordController.text,
      homeAssistantEnabled: _homeAssistantEnabled,
      homeAssistantUrl: _homeAssistantUrlController.text,
      homeAssistantToken: _homeAssistantTokenController.text,
      microphoneDeviceId: _selectedMicrophoneId,
      microphoneDeviceLabel: selectedMicrophone?.displayLabel ?? '',
    );
    if (!saved || !mounted) {
      return;
    }

    setState(() {
      _testingHomeAssistant = true;
    });

    try {
      final status = await _settings.testHomeAssistantConnection();
      if (!mounted) {
        return;
      }
      setState(() {
        _homeAssistantStatus = status;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(status.message)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _testingHomeAssistant = false;
        });
      }
    }
  }

  Future<void> _clearMemory() async {
    final success = await _settings.clearAssistantMemory();

    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success
              ? (_settings.warning == null
                    ? 'Memoria do assistente limpa.'
                    : 'Memoria local limpa. Nao consegui limpar toda a memoria no backend.')
              : (_settings.error ?? 'Nao foi possivel limpar a memoria.'),
        ),
      ),
    );

    if (success) {
      setState(() {
        _homeAssistantStatus = null;
        _applyServiceValues();
      });
    }
  }

  Future<void> _testMicrophone() async {
    setState(() {
      _testingMicrophone = true;
      _microphoneStatusMessage = 'A testar o microfone durante 3 segundos...';
      _microphoneStatusOk = false;
    });

    final result = await _voiceService.testMicrophone(
      inputDeviceId: _selectedMicrophoneId,
    );

    String transcript = '';
    if (result.wavBytes.isNotEmpty) {
      try {
        transcript = await _api.transcribeAudio(result.wavBytes);
      } catch (error) {
        transcript = 'Falha ao transcrever o teste: ${error.toString().replaceFirst('Exception: ', '')}';
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _testingMicrophone = false;
      final transcriptText = transcript.trim().isEmpty
          ? 'Sem transcricao util.'
          : transcript.trim();
      final transcriptOk =
          transcriptText != 'Sem transcricao util.' &&
          !transcriptText.startsWith('Falha ao transcrever o teste:');
      final sensitivityOk =
          result.sensitivityLabel != 'Muito baixo' &&
          result.sensitivityLabel != 'Demasiado alto';
      _microphoneStatusMessage = [
        result.message,
        'Sensibilidade: ${result.sensitivityLabel}. ${result.sensitivityHint}',
        'Pico: ${(result.peakLevel * 100).toStringAsFixed(0)}% | Media: ${(result.averageLevel * 100).toStringAsFixed(0)}%',
        'Transcricao: $transcriptText',
      ].join('\n');
      _microphoneStatusOk = result.ok && transcriptOk && sensitivityOk;
    });
  }

  Future<void> _refreshDevices() async {
    await _deviceRegistry.load();
    if (!mounted) {
      return;
    }

    if (_deviceRegistry.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_deviceRegistry.error!)),
      );
    }
  }

  Future<void> _updateDeviceRole(
    String deviceId, {
    bool? isActive,
    bool? preferredForWakeWord,
    bool? preferredForTts,
    bool? preferredForDesktopControl,
  }) async {
    final success = await _deviceRegistry.updateDevice(
      deviceId,
      isActive: isActive,
      preferredForWakeWord: preferredForWakeWord,
      preferredForTts: preferredForTts,
      preferredForDesktopControl: preferredForDesktopControl,
    );

    if (!mounted) {
      return;
    }

    if (!success && _deviceRegistry.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_deviceRegistry.error!)),
      );
    }
  }

  @override
  void dispose() {
    _assistantNameController.dispose();
    _userNameController.dispose();
    _wakeWordController.dispose();
    _homeAssistantUrlController.dispose();
    _homeAssistantTokenController.dispose();
    _deviceRegistry.dispose();
    _voiceService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 980;
    final topPadding = widget.embedded && isCompact ? 78.0 : 18.0;

    return AnimatedBuilder(
      animation: Listenable.merge([_settings, _deviceRegistry]),
      builder: (context, _) {
        return Container(
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
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(18, topPadding, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SettingsHeroCard(
                    assistantName: _settings.assistantName,
                    wakeWordPhrase: _settings.wakeWordPhrase,
                    loading: _settings.loading,
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Identidade',
                    subtitle:
                        'Define como o assistente se apresenta e como te deve reconhecer.',
                    child: Column(
                      children: [
                        _SettingsField(
                          controller: _assistantNameController,
                          icon: Icons.smart_toy_outlined,
                          label: 'Nome do assistente',
                          hintText: 'Ex.: Daniel',
                          helperText:
                              'Exemplo: Daniel. Este nome passa a ser usado na interface e no prompt do backend.',
                        ),
                        const SizedBox(height: 14),
                        _SettingsField(
                          controller: _userNameController,
                          icon: Icons.person_outline_rounded,
                          label: 'O teu nome',
                          hintText: 'Rafael',
                          helperText:
                              'Opcional. Ajuda o assistente a personalizar respostas.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Voz',
                    subtitle:
                        'Controla a palavra de ativacao central e o dispositivo que deve ouvir.',
                    child: Column(
                      children: [
                        _SettingsField(
                          controller: _wakeWordController,
                          icon: Icons.hearing_rounded,
                          label: 'Palavra de ativacao',
                          hintText: _settings.assistantName,
                          helperText:
                              'Se deixares igual ao nome do assistente, a experiencia fica coerente no modo voz.',
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.03),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.08),
                            ),
                          ),
                          child: Text(
                            'A nova wake word sera usada na proxima escuta do agente Windows. Em dispositivos sem agente, a ativacao continua manual.',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.68),
                              height: 1.45,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _MicrophoneSelectorCard(
                          microphones: _microphones,
                          selectedMicrophoneId: _selectedMicrophoneId,
                          loading: _loadingMicrophones,
                          testing: _testingMicrophone,
                          statusMessage: _microphoneStatusMessage,
                          statusOk: _microphoneStatusOk,
                          onRefresh: _loadingMicrophones ? null : _loadMicrophones,
                          onChanged: (value) {
                            setState(() {
                              _selectedMicrophoneId = value ?? '';
                              _microphoneStatusMessage = null;
                            });
                          },
                          onTest: _testingMicrophone ? null : _testMicrophone,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Dispositivos',
                    subtitle:
                        'Gere agentes ligados ao core e define quem ouve, responde e controla o computador.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _deviceRegistry.loading
                                    ? 'A carregar dispositivos...'
                                    : '${_deviceRegistry.devices.length} dispositivo(s) registado(s).',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.72),
                                  height: 1.4,
                                ),
                              ),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: _deviceRegistry.loading
                                  ? null
                                  : _refreshDevices,
                              icon: const Icon(Icons.sync_rounded),
                              label: const Text('Atualizar'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_deviceRegistry.error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              _deviceRegistry.error!,
                              style: const TextStyle(
                                color: Color(0xFFFFCC80),
                                height: 1.35,
                              ),
                            ),
                          ),
                        if (_deviceRegistry.devices.isEmpty &&
                            !_deviceRegistry.loading)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.03),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.08),
                              ),
                            ),
                            child: Text(
                              'Ainda nao ha agentes ligados ao core. Quando o Windows agent ou o Raspberry Pi agent se registarem, aparecem aqui.',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.68),
                                height: 1.45,
                              ),
                            ),
                          ),
                        for (final device in _deviceRegistry.devices) ...[
                          _RegisteredDeviceCard(
                            device: device,
                            saving: _deviceRegistry.saving,
                            onActiveChanged: (value) {
                              unawaited(
                                _updateDeviceRole(
                                  device.deviceId,
                                  isActive: value,
                                ),
                              );
                            },
                            onWakeWordChanged: (value) {
                              unawaited(
                                _updateDeviceRole(
                                  device.deviceId,
                                  preferredForWakeWord: value,
                                ),
                              );
                            },
                            onTtsChanged: (value) {
                              unawaited(
                                _updateDeviceRole(
                                  device.deviceId,
                                  preferredForTts: value,
                                ),
                              );
                            },
                            onDesktopChanged: (value) {
                              unawaited(
                                _updateDeviceRole(
                                  device.deviceId,
                                  preferredForDesktopControl: value,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Home Assistant',
                    subtitle:
                        'Configura a ligacao para o assistente descobrir entidades e controlar a tua casa.',
                    child: Column(
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: _homeAssistantEnabled,
                          onChanged: _settings.saving || _testingHomeAssistant
                              ? null
                              : (value) {
                                  setState(() {
                                    _homeAssistantEnabled = value;
                                    _homeAssistantStatus = null;
                                  });
                                },
                          title: const Text(
                            'Ativar integracao Home Assistant',
                            style: TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            _homeAssistantEnabled
                                ? 'Quando ativo, o assistente pode testar a ligacao, sincronizar entidades e usar tools da casa.'
                                : 'Quando desligado, o assistente deixa de tentar usar o Home Assistant e evita erros de ligacao no log.',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.68),
                              height: 1.4,
                            ),
                          ),
                          activeColor: const Color(0xFF7AE7C7),
                        ),
                        const SizedBox(height: 12),
                        _SettingsField(
                          controller: _homeAssistantUrlController,
                          icon: Icons.home_outlined,
                          label: 'URL do Home Assistant',
                          hintText: 'http://192.168.1.163:8123',
                          helperText:
                              'Usa o URL completo do teu servidor, por exemplo http://192.168.1.163:8123.',
                          keyboardType: TextInputType.url,
                          enabled: _homeAssistantEnabled,
                        ),
                        const SizedBox(height: 14),
                        _SettingsField(
                          controller: _homeAssistantTokenController,
                          icon: Icons.key_outlined,
                          label: 'Token do Home Assistant',
                          hintText: 'Long-lived access token',
                          helperText:
                              'Cria um long-lived access token no perfil do Home Assistant. O assistente usa este token para autenticar pedidos.',
                          obscureText: true,
                          enabled: _homeAssistantEnabled,
                        ),
                        const SizedBox(height: 12),
                        if (!_homeAssistantEnabled)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.03),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.08),
                              ),
                            ),
                            child: Text(
                              'Integracao desativada. Podes manter a URL e o token guardados sem o assistente tentar ligar-se ao Home Assistant.',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.68),
                                height: 1.45,
                              ),
                            ),
                          ),
                        if (_homeAssistantStatus != null)
                          _HomeAssistantStatusCard(status: _homeAssistantStatus!),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: _settings.saving || _testingHomeAssistant
                                    ? null
                                    : (_homeAssistantEnabled
                                          ? _testHomeAssistant
                                          : _saveSettings),
                                icon: _testingHomeAssistant
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.link_rounded),
                                label: Text(
                                  _testingHomeAssistant
                                      ? 'A testar...'
                                      : (_homeAssistantEnabled
                                            ? 'Guardar e testar'
                                            : 'Guardar estado'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              tooltip: 'Colar URL',
                              onPressed: _homeAssistantEnabled ? () async {
                                final data = await Clipboard.getData(
                                  'text/plain',
                                );
                                final text = data?.text?.trim() ?? '';
                                if (text.isNotEmpty && mounted) {
                                  setState(() {
                                    _homeAssistantUrlController.text = text;
                                  });
                                }
                              } : null,
                              icon: const Icon(
                                Icons.content_paste_rounded,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Memoria',
                    subtitle:
                        'Limpa dados persistentes guardados pelo assistente.',
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Apaga nome, preferencias, lembretes, credenciais e outras entradas guardadas no backend.',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.72),
                              height: 1.45,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.tonalIcon(
                          onPressed: _settings.saving ? null : _clearMemory,
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('Limpar'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (_settings.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _settings.error!,
                        style: const TextStyle(
                          color: Color(0xFFFF8A80),
                          height: 1.4,
                        ),
                      ),
                    ),
                  if (_settings.warning != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _settings.warning!,
                        style: const TextStyle(
                          color: Color(0xFFFFCC80),
                          height: 1.4,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _settings.saving ? null : _saveSettings,
                      icon: _settings.saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        _settings.saving
                            ? 'A guardar...'
                            : 'Guardar configuracoes',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RegisteredDeviceCard extends StatelessWidget {
  const _RegisteredDeviceCard({
    required this.device,
    required this.saving,
    required this.onActiveChanged,
    required this.onWakeWordChanged,
    required this.onTtsChanged,
    required this.onDesktopChanged,
  });

  final RegisteredDevice device;
  final bool saving;
  final ValueChanged<bool> onActiveChanged;
  final ValueChanged<bool> onWakeWordChanged;
  final ValueChanged<bool> onTtsChanged;
  final ValueChanged<bool> onDesktopChanged;

  @override
  Widget build(BuildContext context) {
    final badgeColor = device.connected
        ? const Color(0xFF63E6BE)
        : const Color(0xFFFF8A80);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name.isEmpty ? device.deviceId : device.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${device.deviceType} • ${device.platform.isEmpty ? 'plataforma nao definida' : device.platform}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: badgeColor.withOpacity(0.35),
                  ),
                ),
                child: Text(
                  device.connected ? 'Ligado' : 'Offline',
                  style: TextStyle(
                    color: badgeColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            device.capabilities.isEmpty
                ? 'Sem capacidades anunciadas.'
                : 'Capacidades: ${device.capabilities.join(', ')}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.66),
              height: 1.4,
            ),
          ),
          if (device.lastError.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Ultimo erro: ${device.lastError}',
              style: const TextStyle(
                color: Color(0xFFFFB4A8),
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RoleToggleChip(
                label: 'Ativo',
                value: device.isActive,
                enabled: !saving,
                onChanged: onActiveChanged,
              ),
              _RoleToggleChip(
                label: 'Ouve wake word',
                value: device.preferredForWakeWord,
                enabled: !saving,
                onChanged: onWakeWordChanged,
              ),
              _RoleToggleChip(
                label: 'Fala resposta',
                value: device.preferredForTts,
                enabled: !saving,
                onChanged: onTtsChanged,
              ),
              _RoleToggleChip(
                label: 'Controla desktop',
                value: device.preferredForDesktopControl,
                enabled: !saving,
                onChanged: onDesktopChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleToggleChip extends StatelessWidget {
  const _RoleToggleChip({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: value,
      onSelected: enabled ? onChanged : null,
      label: Text(label),
      labelStyle: TextStyle(
        color: value ? const Color(0xFF041018) : Colors.white.withOpacity(0.86),
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: Colors.white.withOpacity(0.04),
      selectedColor: const Color(0xFF7AE7C7),
      checkmarkColor: const Color(0xFF041018),
      side: BorderSide(
        color: value
            ? const Color(0xFF7AE7C7).withOpacity(0.7)
            : Colors.white.withOpacity(0.08),
      ),
    );
  }
}

class _SettingsHeroCard extends StatelessWidget {
  const _SettingsHeroCard({
    required this.assistantName,
    required this.wakeWordPhrase,
    required this.loading,
  });

  final String assistantName;
  final String wakeWordPhrase;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0C2236), Color(0xFF091521)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF17324C)),
      ),
      child: Wrap(
        runSpacing: 16,
        spacing: 16,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Configuracoes',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Personaliza o nome do assistente, a palavra de ativacao e a ligacao ao Home Assistant.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.72),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeroMetric(
                  label: 'Assistente',
                  value: assistantName,
                ),
                const SizedBox(height: 10),
                _HeroMetric(
                  label: 'Wake word',
                  value: wakeWordPhrase,
                ),
                const SizedBox(height: 10),
                _HeroMetric(
                  label: 'Estado',
                  value: loading ? 'A sincronizar...' : 'Pronto',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xAA07111B),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFF17324C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.68),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _SettingsField extends StatelessWidget {
  const _SettingsField({
    required this.controller,
    required this.icon,
    required this.label,
    required this.hintText,
    required this.helperText,
    this.keyboardType,
    this.obscureText = false,
    this.enabled = true,
  });

  final TextEditingController controller;
  final IconData icon;
  final String label;
  final String hintText;
  final String helperText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        helperText: helperText,
        prefixIcon: Icon(icon),
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.82)),
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.36)),
        helperStyle: TextStyle(
          color: Colors.white.withOpacity(0.56),
          height: 1.45,
        ),
        filled: true,
        fillColor: Colors.white.withOpacity(0.04),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _MicrophoneSelectorCard extends StatelessWidget {
  const _MicrophoneSelectorCard({
    required this.microphones,
    required this.selectedMicrophoneId,
    required this.loading,
    required this.testing,
    required this.statusMessage,
    required this.statusOk,
    required this.onRefresh,
    required this.onChanged,
    required this.onTest,
  });

  final List<MicrophoneDevice> microphones;
  final String selectedMicrophoneId;
  final bool loading;
  final bool testing;
  final String? statusMessage;
  final bool statusOk;
  final Future<void> Function()? onRefresh;
  final ValueChanged<String?> onChanged;
  final Future<void> Function()? onTest;

  @override
  Widget build(BuildContext context) {
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(
        value: '',
        child: Text('Sistema (microfone predefinido)'),
      ),
      ...microphones.map(
        (device) => DropdownMenuItem<String>(
          value: device.id,
          child: Text(device.displayLabel),
        ),
      ),
    ];

    final accent = statusOk
        ? const Color(0xFF4CE7A7)
        : const Color(0xFFFFCC80);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: items.any((item) => item.value == selectedMicrophoneId)
              ? selectedMicrophoneId
              : '',
          items: items,
          onChanged: loading ? null : onChanged,
          dropdownColor: const Color(0xFF08111B),
          iconEnabledColor: Colors.white70,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Microfone',
            helperText:
                'Escolhe o microfone usado na captura de voz nesta maquina. O valor "Sistema" usa o dispositivo predefinido do Windows.',
            prefixIcon: const Icon(Icons.mic_external_on_outlined),
            labelStyle: TextStyle(color: Colors.white.withOpacity(0.82)),
            helperStyle: TextStyle(
              color: Colors.white.withOpacity(0.56),
              height: 1.45,
            ),
            filled: true,
            fillColor: Colors.white.withOpacity(0.04),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: onRefresh == null ? null : () => unawaited(onRefresh!()),
                icon: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: Text(loading ? 'A carregar...' : 'Atualizar lista'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: onTest == null ? null : () => unawaited(onTest!()),
                icon: testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.graphic_eq_rounded),
                label: Text(testing ? 'A testar...' : 'Testar microfone'),
              ),
            ),
          ],
        ),
        if (statusMessage != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: accent.withOpacity(0.35)),
            ),
            child: Text(
              statusMessage!,
              style: TextStyle(
                color: statusOk ? Colors.white : accent,
                height: 1.4,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _HomeAssistantStatusCard extends StatelessWidget {
  const _HomeAssistantStatusCard({required this.status});

  final HomeAssistantStatus status;

  @override
  Widget build(BuildContext context) {
    final accent = !status.enabled
        ? const Color(0xFFFFCC80)
        : status.connected
        ? const Color(0xFF4CE7A7)
        : status.configured
            ? const Color(0xFFFFCC80)
            : const Color(0xFFFF8A80);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            !status.enabled
                ? 'Integracao desativada'
                : status.connected
                ? 'Ligacao ativa'
                : status.configured
                    ? 'Ligacao com erro'
                    : 'Ligacao em falta',
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            status.message,
            style: const TextStyle(color: Colors.white, height: 1.4),
          ),
          if (status.locationName != null || status.entityCount > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Casa: ${status.locationName ?? '-'} | Entidades: ${status.entityCount}',
              style: TextStyle(color: Colors.white.withOpacity(0.72)),
            ),
          ],
        ],
      ),
    );
  }
}
