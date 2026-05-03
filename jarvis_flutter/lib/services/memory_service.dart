import 'package:flutter/foundation.dart';

import '../models/memory_entry.dart';
import 'api_service.dart';
import 'log_service.dart';

class MemoryService extends ChangeNotifier {
  static final MemoryService _instance = MemoryService._internal(
    api: ApiService(),
    logService: LogService(),
  );

  factory MemoryService() {
    return _instance;
  }

  MemoryService._internal({
    required ApiService api,
    required LogService logService,
  }) : _api = api,
       _logService = logService;

  @visibleForTesting
  factory MemoryService.test({ApiService? api, LogService? logService}) {
    return MemoryService._internal(
      api: api ?? ApiService(),
      logService: logService ?? LogService(),
    );
  }

  final ApiService _api;
  final LogService _logService;
  final List<MemoryEntry> _entries = [];

  bool _loading = false;
  bool _loadedOnce = false;
  String? _error;

  List<MemoryEntry> get entries => List.unmodifiable(_entries);
  bool get loading => _loading;
  String? get error => _error;

  Future<void> loadEntries({bool force = false}) async {
    if (_loading) return;
    if (_loadedOnce && !force) return;
    await refresh();
  }

  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final items = await _api.fetchMemoryEntries();
      _entries
        ..clear()
        ..addAll(items);
      _loadedOnce = true;
      _logService.addLog(
        'INFO',
        'Memoria sincronizada: ${items.length} registos.',
      );
    } catch (error) {
      _error = _normalizeError(error);
      _logService.addLog('ERROR', 'Falha ao carregar memoria: $_error');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> updateEntry(String key, String value) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final updated = await _api.updateMemoryEntry(key, value);
      final index = _entries.indexWhere((entry) => entry.key == key);

      if (index >= 0) {
        _entries[index] = updated;
      } else {
        _entries.insert(0, updated);
      }

      _logService.addLog('INFO', 'Memoria atualizada: ${updated.label}.');
    } catch (error) {
      _error = _normalizeError(error);
      _logService.addLog('ERROR', 'Falha ao atualizar memoria: $_error');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> deleteEntry(String key) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      await _api.deleteMemoryEntry(key);
      _entries.removeWhere((entry) => entry.key == key);
      _logService.addLog('INFO', 'Memoria removida: $key.');
    } catch (error) {
      _error = _normalizeError(error);
      _logService.addLog('ERROR', 'Falha ao remover memoria: $_error');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> clearAll() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      await _api.clearMemory();
      _entries.clear();
      _logService.addLog('WARN', 'Toda a memoria foi limpa.');
    } catch (error) {
      _error = _normalizeError(error);
      _logService.addLog('ERROR', 'Falha ao limpar memoria: $_error');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void resetForAccountSwitch() {
    _entries.clear();
    _loading = false;
    _loadedOnce = false;
    _error = null;
    notifyListeners();
  }

  String _normalizeError(Object error) {
    final text = error.toString();
    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length);
    }
    return text;
  }
}
