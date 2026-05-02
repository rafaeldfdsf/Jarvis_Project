import 'package:flutter/foundation.dart';

import '../models/routine.dart';
import 'api_service.dart';
import 'log_service.dart';

class RoutineService extends ChangeNotifier {
  static final RoutineService _instance = RoutineService._internal();

  factory RoutineService() {
    return _instance;
  }

  RoutineService._internal();

  final ApiService _api = ApiService();
  final LogService _logService = LogService();
  final List<Routine> _routines = [];

  bool _loading = false;
  bool _loadedOnce = false;
  String? _error;

  List<Routine> get routines => List.unmodifiable(_routines);
  bool get loading => _loading;
  String? get error => _error;

  Future<void> load({bool force = false}) async {
    if (_loading) return;
    if (_loadedOnce && !force) return;
    await refresh();
  }

  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final items = await _api.fetchRoutines();
      _routines
        ..clear()
        ..addAll(items);
      _loadedOnce = true;
      _logService.addLog('INFO', 'Rotinas sincronizadas: ${items.length}.');
    } catch (error) {
      _error = _normalizeError(error);
      _logService.addLog('ERROR', 'Falha ao carregar rotinas: $_error');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> saveRoutine({
    String? routineId,
    required String name,
    required String description,
    required String triggerText,
    required List<RoutineAction> actions,
    required bool enabled,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final routine = routineId == null || routineId.trim().isEmpty
          ? await _api.createRoutine(
              name: name,
              description: description,
              triggerText: triggerText,
              actions: actions,
              enabled: enabled,
            )
          : await _api.updateRoutine(
              routineId,
              name: name,
              description: description,
              triggerText: triggerText,
              actions: actions,
              enabled: enabled,
            );

      final index = _routines.indexWhere((item) => item.id == routine.id);
      if (index >= 0) {
        _routines[index] = routine;
      } else {
        _routines.insert(0, routine);
      }
      _logService.addLog('INFO', 'Rotina guardada: ${routine.name}.');
      return true;
    } catch (error) {
      _error = _normalizeError(error);
      _logService.addLog('ERROR', 'Falha ao guardar rotina: $_error');
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> deleteRoutine(String routineId) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      await _api.deleteRoutine(routineId);
      _routines.removeWhere((item) => item.id == routineId);
      _logService.addLog('WARN', 'Rotina removida: $routineId.');
      return true;
    } catch (error) {
      _error = _normalizeError(error);
      _logService.addLog('ERROR', 'Falha ao remover rotina: $_error');
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<String?> runRoutine(String routineId) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _api.runRoutine(routineId);
      final steps = result['results'];
      final total = steps is List ? steps.length : 0;
      _logService.addLog('INFO', 'Rotina executada: $routineId ($total passos).');
      return total == 0
          ? 'Rotina executada sem passos.'
          : 'Rotina executada com $total passo${total == 1 ? '' : 's'}.';
    } catch (error) {
      _error = _normalizeError(error);
      _logService.addLog('ERROR', 'Falha ao executar rotina: $_error');
      return null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  String _normalizeError(Object error) {
    final text = error.toString();
    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length);
    }
    return text;
  }
}
