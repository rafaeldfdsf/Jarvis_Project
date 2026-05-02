import 'package:flutter/foundation.dart';

import '../models/home_assistant_device.dart';
import 'api_service.dart';
import 'log_service.dart';

class HomeAssistantDevicesService extends ChangeNotifier {
  static final HomeAssistantDevicesService _instance =
      HomeAssistantDevicesService._internal();

  factory HomeAssistantDevicesService() {
    return _instance;
  }

  HomeAssistantDevicesService._internal();

  final ApiService _api = ApiService();
  final LogService _logService = LogService();
  final List<HomeAssistantDevice> _devices = [];

  bool _loading = false;
  bool _loadedOnce = false;
  String? _error;

  List<HomeAssistantDevice> get devices => List.unmodifiable(_devices);
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
      final items = await _api.fetchHomeAssistantDevices();
      _devices
        ..clear()
        ..addAll(items);
      _loadedOnce = true;
      _logService.addLog('INFO', 'Dispositivos Home Assistant carregados: ${items.length}.');
    } catch (error) {
      _error = _normalizeError(error);
      _logService.addLog('ERROR', 'Falha ao carregar dispositivos Home Assistant: $_error');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> sync() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final items = await _api.syncHomeAssistantDevices();
      _devices
        ..clear()
        ..addAll(items);
      _loadedOnce = true;
      _logService.addLog('INFO', 'Dispositivos Home Assistant sincronizados: ${items.length}.');
      return true;
    } catch (error) {
      _error = _normalizeError(error);
      _logService.addLog('ERROR', 'Falha ao sincronizar dispositivos Home Assistant: $_error');
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> updateAlias(String entityId, String alias) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final updated = await _api.updateHomeAssistantDeviceAlias(entityId, alias);
      final index = _devices.indexWhere((item) => item.entityId == entityId);
      if (index >= 0) {
        _devices[index] = updated;
      } else {
        _devices.add(updated);
      }
      _logService.addLog('INFO', 'Alias atualizado para $entityId.');
      return true;
    } catch (error) {
      _error = _normalizeError(error);
      _logService.addLog('ERROR', 'Falha ao atualizar alias Home Assistant: $_error');
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> deleteDevice(String entityId) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      await _api.deleteHomeAssistantDevice(entityId);
      _devices.removeWhere((item) => item.entityId == entityId);
      _logService.addLog('WARN', 'Dispositivo Home Assistant removido: $entityId.');
      return true;
    } catch (error) {
      _error = _normalizeError(error);
      _logService.addLog('ERROR', 'Falha ao remover dispositivo Home Assistant: $_error');
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<int?> clearAll() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final count = await _api.clearHomeAssistantDevices();
      _devices.clear();
      _logService.addLog('WARN', 'Todos os dispositivos Home Assistant foram removidos: $count.');
      return count;
    } catch (error) {
      _error = _normalizeError(error);
      _logService.addLog('ERROR', 'Falha ao limpar dispositivos Home Assistant: $_error');
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
