import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/routine.dart';
import '../services/app_settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AppSettingsService _settings = AppSettingsService();
  final TextEditingController _assistantNameController =
      TextEditingController();
  final TextEditingController _userNameController = TextEditingController();
  final TextEditingController _wakeWordController = TextEditingController();
  final TextEditingController _homeAssistantUrlController =
      TextEditingController();
  final TextEditingController _homeAssistantTokenController =
      TextEditingController();

  bool _testingHomeAssistant = false;
  HomeAssistantStatus? _homeAssistantStatus;

  @override
  void initState() {
    super.initState();
    _applyServiceValues();
    unawaited(_loadSettings());
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
    _homeAssistantUrlController.text = _settings.homeAssistantUrl;
    _homeAssistantTokenController.text = _settings.homeAssistantToken;
  }

  Future<void> _saveSettings() async {
    final success = await _settings.saveSettings(
      assistantName: _assistantNameController.text,
      userName: _userNameController.text,
      wakeWordPhrase: _wakeWordController.text,
      homeAssistantUrl: _homeAssistantUrlController.text,
      homeAssistantToken: _homeAssistantTokenController.text,
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
    final saved = await _settings.saveSettings(
      assistantName: _assistantNameController.text,
      userName: _userNameController.text,
      wakeWordPhrase: _wakeWordController.text,
      homeAssistantUrl: _homeAssistantUrlController.text,
      homeAssistantToken: _homeAssistantTokenController.text,
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

  @override
  void dispose() {
    _assistantNameController.dispose();
    _userNameController.dispose();
    _wakeWordController.dispose();
    _homeAssistantUrlController.dispose();
    _homeAssistantTokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 980;
    final topPadding = widget.embedded && isCompact ? 78.0 : 18.0;

    return AnimatedBuilder(
      animation: _settings,
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
                        'Controla a palavra de ativacao usada no agente Windows.',
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
                        _SettingsField(
                          controller: _homeAssistantUrlController,
                          icon: Icons.home_outlined,
                          label: 'URL do Home Assistant',
                          hintText: 'http://192.168.1.163:8123',
                          helperText:
                              'Usa o URL completo do teu servidor, por exemplo http://192.168.1.163:8123.',
                          keyboardType: TextInputType.url,
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
                        ),
                        const SizedBox(height: 12),
                        if (_homeAssistantStatus != null)
                          _HomeAssistantStatusCard(status: _homeAssistantStatus!),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: _settings.saving || _testingHomeAssistant
                                    ? null
                                    : _testHomeAssistant,
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
                                      : 'Guardar e testar',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              tooltip: 'Colar URL',
                              onPressed: () async {
                                final data = await Clipboard.getData(
                                  'text/plain',
                                );
                                final text = data?.text?.trim() ?? '';
                                if (text.isNotEmpty && mounted) {
                                  setState(() {
                                    _homeAssistantUrlController.text = text;
                                  });
                                }
                              },
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
  });

  final TextEditingController controller;
  final IconData icon;
  final String label;
  final String hintText;
  final String helperText;
  final TextInputType? keyboardType;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
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

class _HomeAssistantStatusCard extends StatelessWidget {
  const _HomeAssistantStatusCard({required this.status});

  final HomeAssistantStatus status;

  @override
  Widget build(BuildContext context) {
    final accent = status.connected
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
            status.connected
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
