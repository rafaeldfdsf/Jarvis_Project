import 'package:flutter/material.dart';

import '../models/activity_history_entry.dart';
import '../services/activity_history_service.dart';

class ActivityHistoryPanel extends StatefulWidget {
  const ActivityHistoryPanel({
    super.key,
    this.title = 'Historico do Assistente',
  });

  final String title;

  @override
  State<ActivityHistoryPanel> createState() => _ActivityHistoryPanelState();
}

class _ActivityHistoryPanelState extends State<ActivityHistoryPanel> {
  static const String _allCategories = 'all';
  static const String _allOrigins = 'all';
  static const String _allStatuses = 'all';

  final ActivityHistoryService historyService = ActivityHistoryService();
  final TextEditingController _searchController = TextEditingController();

  bool _filtersExpanded = false;
  String _selectedCategory = _allCategories;
  String _selectedOrigin = _allOrigins;
  String _selectedStatus = _allStatuses;

  @override
  void initState() {
    super.initState();
    historyService.addListener(_onHistoryUpdated);
    _searchController.addListener(_onFiltersChanged);
    historyService.load();
  }

  @override
  void dispose() {
    historyService.removeListener(_onHistoryUpdated);
    _searchController.removeListener(_onFiltersChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onHistoryUpdated() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onFiltersChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _clearHistory() async {
    await historyService.clear();
  }

  void _clearFilters() {
    _searchController.clear();
    if (_selectedCategory != _allCategories ||
        _selectedOrigin != _allOrigins ||
        _selectedStatus != _allStatuses) {
      setState(() {
        _selectedCategory = _allCategories;
        _selectedOrigin = _allOrigins;
        _selectedStatus = _allStatuses;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = historyService.entries;
    final filteredEntries = _filteredEntries(entries);
    final availableCategories = _availableCategories(entries);
    final availableOrigins = _availableOrigins(entries);
    final availableStatuses = _availableStatuses(entries);

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.25)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.cyanAccent.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.history_rounded, color: Colors.cyanAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.title} (${filteredEntries.length}/${entries.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: entries.isEmpty ? null : _clearHistory,
                  child: const Text('Limpar'),
                ),
              ],
            ),
          ),
          if (historyService.error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.redAccent.withOpacity(0.12),
              child: Text(
                historyService.error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
          _buildFilters(
            entries,
            filteredEntries,
            availableCategories,
            availableOrigins,
            availableStatuses,
          ),
          Expanded(child: _buildBody(entries, filteredEntries)),
        ],
      ),
    );
  }

  Widget _buildFilters(
    List<ActivityHistoryEntry> entries,
    List<ActivityHistoryEntry> filteredEntries,
    List<String> availableCategories,
    List<String> availableOrigins,
    List<String> availableStatuses,
  ) {
    final isCompact = MediaQuery.sizeOf(context).width < 1100;
    final hasActiveFilters = _searchController.text.trim().isNotEmpty ||
        _selectedCategory != _allCategories ||
        _selectedOrigin != _allOrigins ||
        _selectedStatus != _allStatuses;
    final showFilters = !isCompact || _filtersExpanded;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isCompact)
            Row(
              children: [
                Expanded(
                  child: Text(
                    hasActiveFilters
                        ? 'Existem filtros ativos. ${showFilters ? 'Podes ajusta-los abaixo.' : 'Mostra os filtros para os alterar.'}'
                        : 'Esconde os filtros para dar mais espaco a lista.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.64),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _filtersExpanded = !_filtersExpanded;
                    });
                  },
                  icon: Icon(
                    showFilters
                        ? Icons.expand_less_rounded
                        : Icons.filter_alt_rounded,
                    size: 18,
                  ),
                  label: Text(showFilters ? 'Esconder filtros' : 'Mostrar filtros'),
                ),
              ],
            ),
          if (showFilters) ...[
            TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Pesquisar por acao, site, aplicacao ou detalhe...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.cyanAccent),
                suffixIcon: _searchController.text.trim().isEmpty
                    ? null
                    : IconButton(
                        onPressed: () => _searchController.clear(),
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.white70,
                      ),
                filled: true,
                fillColor: Colors.white.withOpacity(0.03),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                  borderSide: BorderSide(color: Colors.cyanAccent),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Usa os filtros abaixo para escolher o que queres ver.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.60),
                fontSize: 12,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 14.0;
                final filterGroups = <Widget>[
                  _buildFilterGroup(
                    title: 'Tipo de atividade',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Tudo'),
                          selected: _selectedCategory == _allCategories,
                          onSelected: (_) {
                            setState(() {
                              _selectedCategory = _allCategories;
                            });
                          },
                          labelStyle: TextStyle(
                            color: _selectedCategory == _allCategories
                                ? const Color(0xFF05131F)
                                : Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                          selectedColor: Colors.cyanAccent,
                          backgroundColor: Colors.white.withOpacity(0.04),
                          side: BorderSide(
                            color: _selectedCategory == _allCategories
                                ? Colors.cyanAccent
                                : Colors.white.withOpacity(0.08),
                          ),
                        ),
                        for (final category in availableCategories)
                          ChoiceChip(
                            label: Text(_categoryLabel(category)),
                            selected: _selectedCategory == category,
                            onSelected: (_) {
                              setState(() {
                                _selectedCategory = category;
                              });
                            },
                            labelStyle: TextStyle(
                              color: _selectedCategory == category
                                  ? const Color(0xFF05131F)
                                  : _categoryColor(category),
                              fontWeight: FontWeight.w600,
                            ),
                            selectedColor: _categoryColor(category),
                            backgroundColor: _categoryColor(category).withOpacity(0.12),
                            side: BorderSide(
                              color: _categoryColor(category).withOpacity(0.35),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (availableOrigins.isNotEmpty)
                    _buildFilterGroup(
                      title: 'De onde veio',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Qualquer origem'),
                            selected: _selectedOrigin == _allOrigins,
                            onSelected: (_) {
                              setState(() {
                                _selectedOrigin = _allOrigins;
                              });
                            },
                            labelStyle: TextStyle(
                              color: _selectedOrigin == _allOrigins
                                  ? const Color(0xFF05131F)
                                  : Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                            selectedColor: Colors.cyanAccent,
                            backgroundColor: Colors.white.withOpacity(0.04),
                            side: BorderSide(
                              color: _selectedOrigin == _allOrigins
                                  ? Colors.cyanAccent
                                  : Colors.white.withOpacity(0.08),
                            ),
                          ),
                          for (final origin in availableOrigins)
                            ChoiceChip(
                              label: Text(_originLabel(origin)),
                              selected: _selectedOrigin == origin,
                              onSelected: (_) {
                                setState(() {
                                  _selectedOrigin = origin;
                                });
                              },
                              labelStyle: TextStyle(
                                color: _selectedOrigin == origin
                                    ? const Color(0xFF05131F)
                                    : _originColor(origin),
                                fontWeight: FontWeight.w600,
                              ),
                              selectedColor: _originColor(origin),
                              backgroundColor: _originColor(origin).withOpacity(0.12),
                              side: BorderSide(
                                color: _originColor(origin).withOpacity(0.35),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (availableStatuses.isNotEmpty)
                    _buildFilterGroup(
                      title: 'Resultado',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Qualquer resultado'),
                            selected: _selectedStatus == _allStatuses,
                            onSelected: (_) {
                              setState(() {
                                _selectedStatus = _allStatuses;
                              });
                            },
                            labelStyle: TextStyle(
                              color: _selectedStatus == _allStatuses
                                  ? const Color(0xFF05131F)
                                  : Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                            selectedColor: Colors.cyanAccent,
                            backgroundColor: Colors.white.withOpacity(0.04),
                            side: BorderSide(
                              color: _selectedStatus == _allStatuses
                                  ? Colors.cyanAccent
                                  : Colors.white.withOpacity(0.08),
                            ),
                          ),
                          for (final status in availableStatuses)
                            ChoiceChip(
                              label: Text(_statusLabel(status)),
                              selected: _selectedStatus == status,
                              onSelected: (_) {
                                setState(() {
                                  _selectedStatus = status;
                                });
                              },
                              labelStyle: TextStyle(
                                color: _selectedStatus == status
                                    ? const Color(0xFF05131F)
                                    : _statusColor(status),
                                fontWeight: FontWeight.w600,
                              ),
                              selectedColor: _statusColor(status),
                              backgroundColor: _statusColor(status).withOpacity(0.12),
                              side: BorderSide(
                                color: _statusColor(status).withOpacity(0.35),
                              ),
                            ),
                        ],
                      ),
                    ),
                ];

                final maxWidth = constraints.maxWidth;
                final hasThreeColumns = maxWidth >= 1180 && filterGroups.length >= 3;
                final hasTwoColumns = maxWidth >= 760 && filterGroups.length >= 2;
                final groupWidth = hasThreeColumns
                    ? (maxWidth - (spacing * 2)) / 3
                    : hasTwoColumns
                        ? (maxWidth - spacing) / 2
                        : maxWidth;

                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final group in filterGroups)
                      SizedBox(
                        width: groupWidth,
                        child: group,
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  'A mostrar ${filteredEntries.length} de ${entries.length} atividades.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.64),
                    fontSize: 12,
                  ),
                ),
              ),
              if (hasActiveFilters)
                TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                  label: const Text('Limpar filtros'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterGroup({
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildBody(
    List<ActivityHistoryEntry> entries,
    List<ActivityHistoryEntry> filteredEntries,
  ) {
    if (historyService.loading && entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (entries.isEmpty) {
      return Center(
        child: Text(
          'Sem historico ainda.',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
      );
    }

    if (filteredEntries.isEmpty) {
      return Center(
        child: Text(
          'Nenhum evento corresponde aos filtros atuais.',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: filteredEntries.length,
      separatorBuilder: (_, __) => Divider(
        color: Colors.white.withOpacity(0.08),
        height: 16,
      ),
      itemBuilder: (context, index) {
        final entry = filteredEntries[index];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HistoryChip(
              label: _categoryLabel(entry.category),
              color: _categoryColor(entry.category),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        entry.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      _HistoryChip(
                        label: entry.origin.toUpperCase(),
                        color: Colors.blueGrey,
                        compact: true,
                      ),
                      _HistoryChip(
                        label: entry.status.toUpperCase(),
                        color: _statusColor(entry.status),
                        compact: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    entry.detail,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.78),
                      height: 1.45,
                    ),
                  ),
                  if (entry.target != null && entry.target!.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      entry.target!,
                      style: TextStyle(
                        color: Colors.cyanAccent.withOpacity(0.78),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _formatTime(entry.timestamp),
              style: TextStyle(
                color: Colors.white.withOpacity(0.52),
                fontSize: 11,
              ),
            ),
          ],
        );
      },
    );
  }

  List<ActivityHistoryEntry> _filteredEntries(List<ActivityHistoryEntry> entries) {
    final query = _normalizeText(_searchController.text);

    return entries.where((entry) {
      final matchesCategory =
          _selectedCategory == _allCategories || entry.category == _selectedCategory;
      final matchesOrigin =
          _selectedOrigin == _allOrigins || entry.origin == _selectedOrigin;
      final matchesStatus =
          _selectedStatus == _allStatuses || entry.status == _selectedStatus;
      if (!matchesCategory || !matchesOrigin || !matchesStatus) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      final haystack = _normalizeText(
        '${entry.title} ${entry.detail} ${entry.target ?? ''} ${entry.source ?? ''} ${entry.origin} ${entry.category}',
      );
      return haystack.contains(query);
    }).toList();
  }

  List<String> _availableCategories(List<ActivityHistoryEntry> entries) {
    final categories = entries.map((entry) => entry.category).toSet();
    const preferredOrder = ['tool', 'site', 'app', 'system'];
    final extra = categories.where((item) => !preferredOrder.contains(item)).toList()
      ..sort();

    return <String>[
      for (final category in preferredOrder)
        if (categories.contains(category)) category,
      ...extra,
    ];
  }

  List<String> _availableOrigins(List<ActivityHistoryEntry> entries) {
    final origins = entries.map((entry) => entry.origin).toSet();
    const preferredOrder = ['voice', 'chat', 'app'];
    final extra = origins.where((item) => !preferredOrder.contains(item)).toList()
      ..sort();

    return <String>[
      for (final origin in preferredOrder)
        if (origins.contains(origin)) origin,
      ...extra,
    ];
  }

  List<String> _availableStatuses(List<ActivityHistoryEntry> entries) {
    final statuses = entries.map((entry) => entry.status).toSet();
    const preferredOrder = ['success', 'error', 'info'];
    final extra = statuses.where((item) => !preferredOrder.contains(item)).toList()
      ..sort();

    return <String>[
      for (final status in preferredOrder)
        if (statuses.contains(status)) status,
      ...extra,
    ];
  }

  String _normalizeText(String value) {
    return value
        .toLowerCase()
        .replaceAll('\u00E1', 'a')
        .replaceAll('\u00E0', 'a')
        .replaceAll('\u00E2', 'a')
        .replaceAll('\u00E3', 'a')
        .replaceAll('\u00E9', 'e')
        .replaceAll('\u00EA', 'e')
        .replaceAll('\u00ED', 'i')
        .replaceAll('\u00F3', 'o')
        .replaceAll('\u00F4', 'o')
        .replaceAll('\u00F5', 'o')
        .replaceAll('\u00FA', 'u')
        .replaceAll('\u00E7', 'c')
        .trim();
  }

  String _categoryLabel(String category) {
    switch (category) {
      case 'tool':
        return 'Ferramentas usadas';
      case 'site':
        return 'Sites abertos';
      case 'app':
        return 'Aplicacoes abertas';
      default:
        return 'Acoes do sistema';
    }
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'tool':
        return Colors.cyanAccent;
      case 'site':
        return Colors.greenAccent;
      case 'app':
        return Colors.orangeAccent;
      default:
        return Colors.purpleAccent;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'error':
        return Colors.redAccent;
      case 'success':
        return Colors.greenAccent;
      case 'info':
        return Colors.blueAccent;
      default:
        return Colors.white70;
    }
  }

  String _originLabel(String origin) {
    switch (origin) {
      case 'voice':
        return 'Por voz';
      case 'chat':
        return 'Pelo chat';
      case 'app':
        return 'Pela aplicacao';
      default:
        return _safeLabel(origin, fallback: 'Outra origem');
    }
  }

  Color _originColor(String origin) {
    switch (origin) {
      case 'voice':
        return Colors.lightBlueAccent;
      case 'chat':
        return Colors.deepPurpleAccent;
      default:
        return Colors.blueGrey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'success':
        return 'Concluido';
      case 'error':
        return 'Falhou';
      case 'info':
        return 'Informacao';
      default:
        return _safeLabel(status, fallback: 'Outro estado');
    }
  }

  String _safeLabel(String value, {required String fallback}) {
    final cleanValue = value.trim();
    if (cleanValue.isEmpty) {
      return fallback;
    }
    return cleanValue[0].toUpperCase() + cleanValue.substring(1);
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class _HistoryChip extends StatelessWidget {
  const _HistoryChip({
    required this.label,
    required this.color,
    this.compact = false,
  });

  final String label;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
