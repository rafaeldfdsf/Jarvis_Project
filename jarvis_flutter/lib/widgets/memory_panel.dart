import 'package:flutter/material.dart';

import '../models/memory_entry.dart';
import '../services/memory_service.dart';

class MemoryPanel extends StatefulWidget {
  const MemoryPanel({
    super.key,
    this.title = 'Memoria do Assistente',
  });

  final String title;

  @override
  State<MemoryPanel> createState() => _MemoryPanelState();
}

class _MemoryPanelState extends State<MemoryPanel> {
  static const String _allTypes = 'all';

  final MemoryService memoryService = MemoryService();
  final TextEditingController _searchController = TextEditingController();

  String _selectedType = _allTypes;

  @override
  void initState() {
    super.initState();
    memoryService.addListener(_onMemoryUpdated);
    _searchController.addListener(_onFiltersChanged);
    memoryService.loadEntries();
  }

  @override
  void dispose() {
    memoryService.removeListener(_onMemoryUpdated);
    _searchController.removeListener(_onFiltersChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onMemoryUpdated() {
    final availableTypes = _availableTypes(memoryService.entries);
    if (_selectedType != _allTypes && !availableTypes.contains(_selectedType)) {
      _selectedType = _allTypes;
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _onFiltersChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _refresh() async {
    await memoryService.refresh();
  }

  Future<void> _editEntry(MemoryEntry entry) async {
    final controller = TextEditingController(text: entry.value);

    final updatedValue = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0B1A2A),
          title: Text('Editar ${entry.label}'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            minLines: 1,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Novo valor',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.55)),
              filled: true,
              fillColor: Colors.black.withOpacity(0.25),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (updatedValue == null) {
      return;
    }

    final cleanValue = updatedValue.trim();
    if (cleanValue.isEmpty || cleanValue == entry.value) {
      return;
    }

    await memoryService.updateEntry(entry.key, cleanValue);
  }

  Future<void> _deleteEntry(MemoryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0B1A2A),
          title: const Text('Remover registo'),
          content: Text(
            'Queres apagar "${entry.label}" da memoria?',
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

    if (confirmed == true) {
      await memoryService.deleteEntry(entry.key);
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0B1A2A),
          title: const Text('Limpar memoria'),
          content: const Text(
            'Isto remove todos os registos guardados. Queres continuar?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('Limpar tudo'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await memoryService.clearAll();
    }
  }

  void _clearFilters() {
    _searchController.clear();
    if (_selectedType != _allTypes) {
      setState(() {
        _selectedType = _allTypes;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = memoryService.entries;
    final filteredEntries = _filteredEntries(entries);
    final availableTypes = _availableTypes(entries);
    final error = memoryService.error;

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
                const Icon(
                  Icons.storage_rounded,
                  color: Colors.cyanAccent,
                  size: 18,
                ),
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
                IconButton(
                  onPressed: memoryService.loading ? null : _refresh,
                  icon: const Icon(Icons.refresh, color: Colors.white70),
                  tooltip: 'Atualizar',
                ),
                TextButton(
                  onPressed: entries.isEmpty || memoryService.loading ? null : _clearAll,
                  child: const Text('Limpar'),
                ),
              ],
            ),
          ),
          if (error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.redAccent.withOpacity(0.12),
              child: Text(
                error,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
          _buildSearchAndFilters(entries, filteredEntries, availableTypes),
          if (memoryService.loading)
            const LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Color(0x1100E5FF),
            ),
          Expanded(
            child: _buildBody(
              entries: entries,
              filteredEntries: filteredEntries,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters(
    List<MemoryEntry> entries,
    List<MemoryEntry> filteredEntries,
    List<String> availableTypes,
  ) {
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
          TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Pesquisar por nome, chave, tipo ou conteudo...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.cyanAccent),
              suffixIcon: _searchController.text.trim().isEmpty
                  ? null
                  : IconButton(
                      onPressed: () => _searchController.clear(),
                      icon: const Icon(Icons.close_rounded),
                      color: Colors.white70,
                      tooltip: 'Limpar pesquisa',
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Todos'),
                selected: _selectedType == _allTypes,
                onSelected: (_) {
                  setState(() {
                    _selectedType = _allTypes;
                  });
                },
                labelStyle: TextStyle(
                  color: _selectedType == _allTypes
                      ? const Color(0xFF05131F)
                      : Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
                selectedColor: Colors.cyanAccent,
                backgroundColor: Colors.white.withOpacity(0.04),
                side: BorderSide(
                  color: _selectedType == _allTypes
                      ? Colors.cyanAccent
                      : Colors.white.withOpacity(0.08),
                ),
              ),
              for (final type in availableTypes)
                ChoiceChip(
                  label: Text(_typeLabel(type)),
                  selected: _selectedType == type,
                  onSelected: (_) {
                    setState(() {
                      _selectedType = type;
                    });
                  },
                  labelStyle: TextStyle(
                    color: _selectedType == type
                        ? const Color(0xFF05131F)
                        : _typeColor(type),
                    fontWeight: FontWeight.w600,
                  ),
                  selectedColor: _typeColor(type),
                  backgroundColor: _typeColor(type).withOpacity(0.12),
                  side: BorderSide(color: _typeColor(type).withOpacity(0.35)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'A mostrar ${filteredEntries.length} de ${entries.length} registos.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.64),
                    fontSize: 12,
                  ),
                ),
              ),
              if (_searchController.text.trim().isNotEmpty || _selectedType != _allTypes)
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

  Widget _buildBody({
    required List<MemoryEntry> entries,
    required List<MemoryEntry> filteredEntries,
  }) {
    if (memoryService.loading && entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (entries.isEmpty) {
      return Center(
        child: Text(
          'Sem registos de memoria ainda.',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
      );
    }

    if (filteredEntries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                color: Colors.white.withOpacity(0.4),
                size: 38,
              ),
              const SizedBox(height: 12),
              const Text(
                'Nenhum registo corresponde aos filtros atuais.',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Ajusta a pesquisa ou muda o filtro de tipo para veres mais resultados.',
                style: TextStyle(color: Colors.white.withOpacity(0.65), height: 1.45),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Repor filtros'),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth < 920 ? 920.0 : constraints.maxWidth;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.015),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(18),
                        ),
                        border: Border(
                          bottom: BorderSide(color: Colors.white.withOpacity(0.08)),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Expanded(flex: 2, child: _MemoryHeaderCell('Tipo')),
                          Expanded(flex: 4, child: _MemoryHeaderCell('Registo')),
                          Expanded(flex: 5, child: _MemoryHeaderCell('Conteudo')),
                          Expanded(flex: 2, child: _MemoryHeaderCell('Acoes')),
                        ],
                      ),
                    ),
                    for (var index = 0; index < filteredEntries.length; index++)
                      _MemoryRow(
                        entry: filteredEntries[index],
                        showDivider: index != filteredEntries.length - 1,
                        loading: memoryService.loading,
                        onEdit: () => _editEntry(filteredEntries[index]),
                        onDelete: () => _deleteEntry(filteredEntries[index]),
                        typeChip: _buildTypeChip(filteredEntries[index].type),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<MemoryEntry> _filteredEntries(List<MemoryEntry> entries) {
    final query = _normalizeText(_searchController.text);

    return entries.where((entry) {
      final matchesType = _selectedType == _allTypes || entry.type == _selectedType;
      if (!matchesType) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      final haystack = _normalizeText(
        '${entry.label} ${entry.key} ${entry.value} ${entry.type} ${_typeLabel(entry.type)}',
      );
      return haystack.contains(query);
    }).toList();
  }

  List<String> _availableTypes(List<MemoryEntry> entries) {
    final types = entries.map((entry) => entry.type).toSet();
    const preferredOrder = ['fact', 'preference', 'reminder'];
    final extraTypes = types.where((type) => !preferredOrder.contains(type)).toList()
      ..sort();

    final orderedTypes = <String>[
      for (final type in preferredOrder)
        if (types.contains(type)) type,
      ...extraTypes,
    ];

    return orderedTypes;
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

  Widget _buildTypeChip(String type) {
    final color = _typeColor(type);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Text(
        _typeLabel(type),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'preference':
        return Colors.orangeAccent;
      case 'reminder':
        return Colors.pinkAccent;
      default:
        return Colors.greenAccent;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'preference':
        return 'Preferencia';
      case 'reminder':
        return 'Lembrete';
      default:
        return 'Facto';
    }
  }
}

class _MemoryHeaderCell extends StatelessWidget {
  const _MemoryHeaderCell(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _MemoryRow extends StatelessWidget {
  const _MemoryRow({
    required this.entry,
    required this.showDivider,
    required this.loading,
    required this.onEdit,
    required this.onDelete,
    required this.typeChip,
  });

  final MemoryEntry entry;
  final bool showDivider;
  final bool loading;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Widget typeChip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(
                bottom: BorderSide(color: Colors.white.withOpacity(0.08)),
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: typeChip,
            ),
          ),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.key,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 5,
            child: Tooltip(
              message: entry.value,
              child: Text(
                entry.value,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  height: 1.45,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                IconButton(
                  tooltip: 'Editar',
                  onPressed: loading ? null : onEdit,
                  icon: const Icon(
                    Icons.edit_outlined,
                    color: Colors.cyanAccent,
                  ),
                ),
                IconButton(
                  tooltip: 'Apagar',
                  onPressed: loading ? null : onDelete,
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
