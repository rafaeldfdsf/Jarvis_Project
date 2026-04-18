import 'dart:async';

import 'package:flutter/material.dart';

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
  }

  Future<void> _saveSettings() async {
    final success = await _settings.saveSettings(
      assistantName: _assistantNameController.text,
      userName: _userNameController.text,
      wakeWordPhrase: _wakeWordController.text,
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
      setState(_applyServiceValues);
    }
  }

  @override
  void dispose() {
    _assistantNameController.dispose();
    _userNameController.dispose();
    _wakeWordController.dispose();
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
                    title: 'Memoria',
                    subtitle:
                        'Limpa dados persistentes guardados pelo assistente.',
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Apaga nome, preferencias, lembretes e outras entradas guardadas no backend.',
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
                  'Personaliza o nome do assistente, a palavra de ativacao e os dados principais usados pelo sistema.',
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
  });

  final TextEditingController controller;
  final IconData icon;
  final String label;
  final String hintText;
  final String helperText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
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

