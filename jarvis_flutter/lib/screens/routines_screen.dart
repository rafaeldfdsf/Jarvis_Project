import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/routine.dart';
import '../services/routine_service.dart';

class RoutinesScreen extends StatefulWidget {
  const RoutinesScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<RoutinesScreen> createState() => _RoutinesScreenState();
}

class _RoutinesScreenState extends State<RoutinesScreen> {
  final RoutineService _routineService = RoutineService();

  @override
  void initState() {
    super.initState();
    _routineService.load();
  }

  Future<void> _refresh() async {
    await _routineService.refresh();
  }

  Future<void> _openRoutineEditor([Routine? routine]) async {
    final nameController = TextEditingController(text: routine?.name ?? '');
    final descriptionController = TextEditingController(
      text: routine?.description ?? '',
    );
    final triggerController = TextEditingController(
      text: routine?.triggerText ?? '',
    );
    final actionsController = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(
        (routine?.actions ?? const <RoutineAction>[])
            .map((item) => item.toJson())
            .toList(),
      ),
    );
    var enabled = routine?.enabled ?? true;
    String? validationError;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0B1A2A),
              title: Text(routine == null ? 'Nova rotina' : 'Editar rotina'),
              content: SizedBox(
                width: 640,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _RoutineField(
                        controller: nameController,
                        label: 'Nome',
                        hintText: 'Boa noite',
                      ),
                      const SizedBox(height: 12),
                      _RoutineField(
                        controller: descriptionController,
                        label: 'Descricao',
                        hintText: 'Desliga luzes e prepara a casa para dormir',
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),
                      _RoutineField(
                        controller: triggerController,
                        label: 'Trigger em linguagem natural',
                        hintText: 'Quando eu disser "boa noite"',
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        value: enabled,
                        onChanged: (value) {
                          setDialogState(() {
                            enabled = value;
                          });
                        },
                        activeColor: const Color(0xFF42D9FF),
                        title: const Text(
                          'Rotina ativa',
                          style: TextStyle(color: Colors.white),
                        ),
                        subtitle: const Text(
                          'Desativa a rotina sem a apagar.',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _RoutineField(
                        controller: actionsController,
                        label: 'Acoes JSON',
                        hintText:
                            '[{"type":"home_assistant_service","domain":"light","service":"turn_off","entity_id":"light.sala"}]',
                        maxLines: 10,
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Cada acao pode usar `type: "home_assistant_service"` com `domain`, `service`, `entity_id` e `service_data`.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.62),
                            height: 1.45,
                          ),
                        ),
                      ),
                      if (validationError != null) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            validationError!,
                            style: const TextStyle(color: Color(0xFFFF8A80)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    try {
                      final decoded = jsonDecode(actionsController.text);
                      if (decoded is! List) {
                        throw const FormatException(
                          'O campo de acoes tem de ser uma lista JSON.',
                        );
                      }
                      Navigator.of(context).pop(true);
                    } catch (error) {
                      setDialogState(() {
                        validationError = error.toString().replaceFirst(
                              'FormatException: ',
                              '',
                            );
                      });
                    }
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true) {
      nameController.dispose();
      descriptionController.dispose();
      triggerController.dispose();
      actionsController.dispose();
      return;
    }

    final rawActions = jsonDecode(actionsController.text) as List<dynamic>;
    final actions = rawActions
        .whereType<Map<String, dynamic>>()
        .map(RoutineAction.fromJson)
        .toList();

    final success = await _routineService.saveRoutine(
      routineId: routine?.id,
      name: nameController.text,
      description: descriptionController.text,
      triggerText: triggerController.text,
      actions: actions,
      enabled: enabled,
    );

    nameController.dispose();
    descriptionController.dispose();
    triggerController.dispose();
    actionsController.dispose();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Rotina guardada.'
              : (_routineService.error ?? 'Nao foi possivel guardar a rotina.'),
        ),
      ),
    );
  }

  Future<void> _deleteRoutine(Routine routine) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0B1A2A),
          title: const Text('Remover rotina'),
          content: Text(
            'Queres apagar a rotina "${routine.name}"?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('Apagar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final success = await _routineService.deleteRoutine(routine.id);
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Rotina removida.'
              : (_routineService.error ?? 'Nao foi possivel remover a rotina.'),
        ),
      ),
    );
  }

  Future<void> _runRoutine(Routine routine) async {
    final message = await _routineService.runRoutine(routine.id);
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message ??
              _routineService.error ??
              'Nao foi possivel executar a rotina.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 980;
    final topPadding = widget.embedded && isCompact ? 78.0 : 18.0;

    return AnimatedBuilder(
      animation: _routineService,
      builder: (context, _) {
        final routines = _routineService.routines;
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
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, topPadding, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
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
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Rotinas',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.92),
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Cria, edita e executa rotinas persistentes. O assistente tambem pode geri-las via backend.',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.72),
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        FilledButton.icon(
                          onPressed: _routineService.loading
                              ? null
                              : () => _openRoutineEditor(),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Nova rotina'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_routineService.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _routineService.error!,
                        style: const TextStyle(color: Color(0xFFFF8A80)),
                      ),
                    ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _refresh,
                      child: routines.isEmpty && !_routineService.loading
                          ? ListView(
                              children: const [
                                SizedBox(height: 80),
                                _EmptyRoutinesState(),
                              ],
                            )
                          : ListView.separated(
                              itemCount: routines.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final routine = routines[index];
                                return _RoutineCard(
                                  routine: routine,
                                  loading: _routineService.loading,
                                  onEdit: () => _openRoutineEditor(routine),
                                  onDelete: () => _deleteRoutine(routine),
                                  onRun: () => _runRoutine(routine),
                                );
                              },
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

class _RoutineCard extends StatelessWidget {
  const _RoutineCard({
    required this.routine,
    required this.loading,
    required this.onEdit,
    required this.onDelete,
    required this.onRun,
  });

  final Routine routine;
  final bool loading;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xAA07111B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF17324C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  routine.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _RoutineBadge(
                label: routine.enabled ? 'Ativa' : 'Desativada',
                color: routine.enabled
                    ? const Color(0xFF4CE7A7)
                    : const Color(0xFFFFCC80),
              ),
            ],
          ),
          if (routine.description.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              routine.description,
              style: TextStyle(
                color: Colors.white.withOpacity(0.72),
                height: 1.45,
              ),
            ),
          ],
          if (routine.triggerText.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Trigger: ${routine.triggerText}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.64),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RoutineBadge(
                label: '${routine.actions.length} acao${routine.actions.length == 1 ? '' : 'es'}',
                color: const Color(0xFF42D9FF),
              ),
              for (final action in routine.actions.take(3))
                _RoutineBadge(
                  label: action.entityId ?? action.service ?? action.type,
                  color: const Color(0xFF7FDBFF),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: loading ? null : onRun,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Executar'),
              ),
              const SizedBox(width: 10),
              TextButton.icon(
                onPressed: loading ? null : onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Editar'),
              ),
              const SizedBox(width: 6),
              TextButton.icon(
                onPressed: loading ? null : onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Apagar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoutineBadge extends StatelessWidget {
  const _RoutineBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _RoutineField extends StatelessWidget {
  const _RoutineField({
    required this.controller,
    required this.label,
    required this.hintText,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: 1,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        labelStyle: const TextStyle(color: Colors.white70),
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: Colors.white.withOpacity(0.04),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _EmptyRoutinesState extends StatelessWidget {
  const _EmptyRoutinesState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(
            Icons.auto_awesome_motion_rounded,
            size: 46,
            color: Colors.white.withOpacity(0.36),
          ),
          const SizedBox(height: 14),
          const Text(
            'Ainda nao existem rotinas.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Cria rotinas pela interface ou pede ao assistente para as criar automaticamente com acoes do Home Assistant.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.66),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
