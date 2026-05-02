import 'package:flutter/foundation.dart';

import '../models/registered_device.dart';
import 'api_service.dart';

class DeviceRegistryService extends ChangeNotifier {
  final ApiService _api = ApiService();

  bool _loading = false;
  bool _saving = false;
  String? _error;
  List<RegisteredDevice> _devices = const <RegisteredDevice>[];

  bool get loading => _loading;
  bool get saving => _saving;
  String? get error => _error;
  List<RegisteredDevice> get devices => List<RegisteredDevice>.unmodifiable(_devices);

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _devices = await _api.fetchRegisteredDevices();
    } catch (error) {
      _error = _normalizeError(error);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> updateDevice(
    String deviceId, {
    String? name,
    String? location,
    String? platform,
    bool? isActive,
    bool? preferredForWakeWord,
    bool? preferredForTts,
    bool? preferredForDesktopControl,
  }) async {
    _saving = true;
    _error = null;
    notifyListeners();

    try {
      final updated = await _api.updateRegisteredDevice(
        deviceId,
        name: name,
        location: location,
        platform: platform,
        isActive: isActive,
        preferredForWakeWord: preferredForWakeWord,
        preferredForTts: preferredForTts,
        preferredForDesktopControl: preferredForDesktopControl,
      );

      _devices = _devices
          .map((device) => device.deviceId == updated.deviceId ? updated : device)
          .toList();
      notifyListeners();
      return true;
    } catch (error) {
      _error = _normalizeError(error);
      notifyListeners();
      return false;
    } finally {
      _saving = false;
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
