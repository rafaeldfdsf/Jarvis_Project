import 'package:flutter/material.dart';

import '../models/log_entry.dart';
import '../services/log_service.dart';

class LogPanel extends StatefulWidget {
  const LogPanel({
    super.key,
    this.title = 'Logs do Sistema',
  });

  final String title;

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  static const String _allTypes = 'ALL';

  final LogService logService = LogService();
  final TextEditingController _searchController = TextEditingController();

  String _selectedType = _allTypes;

  @override
  void initState() {
    super.initState();
    logService.addListener(_onLogsUpdated);
    _searchController.addListener(_onFiltersChanged);
  }

  @override
  void dispose() {
    logService.removeListener(_onLogsUpdated);
    _searchController.removeListener(_onFiltersChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onLogsUpdated() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onFiltersChanged() {
    if (mounted) {
      setState(() {});
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
    final logs = logService.logs;
    final filteredLogs = _filteredLogs(logs);
    final availableTypes = _availableTypes(logs);

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
                const Icon(Icons.terminal, color: Colors.cyanAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.title} (${filteredLogs.length}/${logs.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    logService.clearLogs();
                  },
                  child: const Text('Limpar'),
                ),
              ],
            ),
          ),
          _buildFilters(logs, filteredLogs, availableTypes),
          Expanded(child: _buildBody(logs, filteredLogs)),
        ],
      ),
    );
  }

  Widget _buildFilters(
    List<LogEntry> logs,
    List<LogEntry> filteredLogs,
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
              hintText: 'Pesquisar mensagens de log...',
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
                  label: Text(type),
                  selected: _selectedType == type,
                  onSelected: (_) {
                    setState(() {
                      _selectedType = type;
                    });
                  },
                  labelStyle: TextStyle(
                    color: _selectedType == type
                        ? const Color(0xFF05131F)
                        : _getLogColor(type),
                    fontWeight: FontWeight.w600,
                  ),
                  selectedColor: _getLogColor(type),
                  backgroundColor: _getLogColor(type).withOpacity(0.12),
                  side: BorderSide(color: _getLogColor(type).withOpacity(0.35)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'A mostrar ${filteredLogs.length} de ${logs.length} logs.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.64),
                    fontSize: 12,
                  ),
                ),
              ),
              if (_searchController.text.trim().isNotEmpty ||
                  _selectedType != _allTypes)
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

  Widget _buildBody(List<LogEntry> logs, List<LogEntry> filteredLogs) {
    if (logs.isEmpty) {
      return const Center(
        child: Text(
          'Sem logs ainda.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    if (filteredLogs.isEmpty) {
      return Center(
        child: Text(
          'Nenhum log corresponde aos filtros atuais.',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(10),
      itemCount: filteredLogs.length,
      separatorBuilder: (_, __) => Divider(
        color: Colors.white.withOpacity(0.08),
        height: 10,
      ),
      itemBuilder: (context, index) {
        final log = filteredLogs[index];

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getLogColor(log.type).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _getLogColor(log.type).withOpacity(0.45),
                ),
              ),
              child: Text(
                log.type,
                style: TextStyle(
                  color: _getLogColor(log.type),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    log.message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(log.timestamp),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  List<LogEntry> _filteredLogs(List<LogEntry> logs) {
    final query = _searchController.text.trim().toLowerCase();

    return logs.where((log) {
      final matchesType =
          _selectedType == _allTypes || log.type.toUpperCase() == _selectedType;
      if (!matchesType) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      return log.message.toLowerCase().contains(query) ||
          log.type.toLowerCase().contains(query);
    }).toList();
  }

  List<String> _availableTypes(List<LogEntry> logs) {
    final types = logs.map((log) => log.type.toUpperCase()).toSet();
    const preferredOrder = ['ERROR', 'WARN', 'DEBUG', 'INFO'];
    final extra = types.where((type) => !preferredOrder.contains(type)).toList()
      ..sort();

    return <String>[
      for (final type in preferredOrder)
        if (types.contains(type)) type,
      ...extra,
    ];
  }

  Color _getLogColor(String type) {
    switch (type.toUpperCase()) {
      case 'ERROR':
        return Colors.redAccent;
      case 'WARN':
        return Colors.orangeAccent;
      case 'DEBUG':
        return Colors.purpleAccent;
      case 'INFO':
      default:
        return Colors.greenAccent;
    }
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
