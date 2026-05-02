import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/app_setting_entry.dart';
import '../models/memory_entry.dart';
import '../models/routine.dart';
import 'api_service.dart';
import 'memory_service.dart';

class AppSettingsService extends ChangeNotifier {
  static const String defaultAssistantName = 'Jarvis';
  static const String defaultTtsMode = 'local';

  static final AppSettingsService _instance = AppSettingsService._internal();

  factory AppSettingsService() {
    return _instance;
  }

  AppSettingsService._internal();

  final ApiService _api = ApiService();

  bool _loading = false;
  bool _saving = false;
  bool _loadedOnce = false;
  Future<void>? _pendingLoad;
  String? _error;
  String? _warning;

  String _assistantName = defaultAssistantName;
  String _userName = '';
  String _wakeWordPhrase = defaultAssistantName;
  int _wakeWordSensitivity = 40;
  bool _homeAssistantEnabled = false;
  String _homeAssistantUrl = '';
  String _homeAssistantToken = '';
  String _microphoneDeviceId = '';
  String _microphoneDeviceLabel = '';
  String _ttsMode = defaultTtsMode;
  String _ttsVoiceKey = '';
  String _ttsVoiceLabel = '';
  Set<String> _knownKeys = <String>{};

  bool get loading => _loading;
  bool get saving => _saving;
  bool get loadedOnce => _loadedOnce;
  String? get error => _error;
  String? get warning => _warning;

  String get assistantName {
    final clean = _assistantName.trim();
    return clean.isEmpty ? defaultAssistantName : clean;
  }

  String get userName => _userName.trim();
  int get wakeWordSensitivity => _wakeWordSensitivity;
  bool get homeAssistantEnabled => _homeAssistantEnabled;
  String get homeAssistantUrl => _homeAssistantUrl.trim();
  String get homeAssistantToken => _homeAssistantToken.trim();
  String get microphoneDeviceId => _microphoneDeviceId.trim();
  String get microphoneDeviceLabel => _microphoneDeviceLabel.trim();
  String get ttsMode => _normalizeTtsMode(_ttsMode);
  String get ttsVoiceKey => _ttsVoiceKey.trim();
  String get ttsVoiceLabel => _ttsVoiceLabel.trim();

  String get wakeWordPhrase {
    final clean = _wakeWordPhrase.trim();
    if (clean.isNotEmpty) {
      return clean;
    }
    return assistantName;
  }

  Future<void> load({bool force = false}) async {
    if (_pendingLoad != null) {
      await _pendingLoad;
      return;
    }

    if (_loadedOnce && !force) {
      return;
    }

    _pendingLoad = _performLoad();
    try {
      await _pendingLoad;
    } finally {
      _pendingLoad = null;
    }
  }

  Future<void> _performLoad() async {
    _loading = true;
    _error = null;
    _warning = null;
    notifyListeners();

    try {
      final hasLocalSettings = await _loadLocalSettings();

      try {
        final entries = await _api.fetchAppSettings();
        _applySettingsEntries(entries, preserveExistingValues: hasLocalSettings);
        await _persistLocalSettings();
      } catch (error) {
        try {
          final entries = await _api.fetchMemoryEntries();
          _applyEntries(entries, preserveExistingValues: hasLocalSettings);
          await _persistLocalSettings();
          _warning = _normalizeError(error);
        } catch (_) {
          if (hasLocalSettings) {
            _warning = _normalizeError(error);
          } else {
            _error = _normalizeError(error);
          }
        }
      }

      _loadedOnce = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> saveSettings({
    required String assistantName,
    required String userName,
    required String wakeWordPhrase,
    required int wakeWordSensitivity,
    required bool homeAssistantEnabled,
    required String homeAssistantUrl,
    required String homeAssistantToken,
    String? microphoneDeviceId,
    String? microphoneDeviceLabel,
    String? ttsMode,
    String? ttsVoiceKey,
    String? ttsVoiceLabel,
  }) async {
    final cleanAssistantName = assistantName.trim().isEmpty
        ? defaultAssistantName
        : assistantName.trim();
    final cleanUserName = userName.trim();
    final cleanWakeWordPhrase = wakeWordPhrase.trim().isEmpty
        ? cleanAssistantName
        : wakeWordPhrase.trim();
    final cleanWakeWordSensitivity = _clampWakeWordSensitivity(
      wakeWordSensitivity,
    );
    final cleanHomeAssistantEnabled = homeAssistantEnabled;
    final cleanHomeAssistantUrl = homeAssistantUrl.trim();
    final cleanHomeAssistantToken = homeAssistantToken.trim();
    final cleanMicrophoneDeviceId =
        (microphoneDeviceId ?? _microphoneDeviceId).trim();
    final cleanMicrophoneDeviceLabel =
        (microphoneDeviceLabel ?? _microphoneDeviceLabel).trim();
    final cleanTtsMode = _normalizeTtsMode(ttsMode ?? _ttsMode);
    final cleanTtsVoiceKey = (ttsVoiceKey ?? _ttsVoiceKey).trim();
    final cleanTtsVoiceLabel = (ttsVoiceLabel ?? _ttsVoiceLabel).trim();

    _saving = true;
    _error = null;
    _warning = null;
    notifyListeners();

    try {
      _assistantName = cleanAssistantName;
      _userName = cleanUserName;
      _wakeWordPhrase = cleanWakeWordPhrase;
      _wakeWordSensitivity = cleanWakeWordSensitivity;
      _homeAssistantEnabled = cleanHomeAssistantEnabled;
      _homeAssistantUrl = cleanHomeAssistantUrl;
      _homeAssistantToken = cleanHomeAssistantToken;
      _microphoneDeviceId = cleanMicrophoneDeviceId;
      _microphoneDeviceLabel = cleanMicrophoneDeviceLabel;
      _ttsMode = cleanTtsMode;
      _ttsVoiceKey = cleanTtsVoiceKey;
      _ttsVoiceLabel = cleanTtsVoiceLabel;
      _loadedOnce = true;
      await _persistLocalSettings();

      try {
        await _api.updateAppSettings(
          assistantName: cleanAssistantName,
          userName: cleanUserName,
          wakeWordPhrase: cleanWakeWordPhrase,
          wakeWordSensitivity: cleanWakeWordSensitivity,
          homeAssistantEnabled: cleanHomeAssistantEnabled,
          homeAssistantUrl: cleanHomeAssistantUrl,
          homeAssistantToken: cleanHomeAssistantToken,
        );
        await MemoryService().refresh();
      } catch (error) {
        try {
          await _saveField('assistant_name', cleanAssistantName);
          await _saveField('name', cleanUserName);
          await _saveField('wake_word_phrase', cleanWakeWordPhrase);
          await _saveField(
            'wake_word_sensitivity',
            cleanWakeWordSensitivity.toString(),
          );
          await _saveField(
            'home_assistant_enabled',
            cleanHomeAssistantEnabled ? 'true' : 'false',
          );
          await _saveField('home_assistant_url', cleanHomeAssistantUrl);
          await _saveField('home_assistant_token', cleanHomeAssistantToken);
          await MemoryService().refresh();
          _warning = _normalizeError(error);
        } catch (_) {
          _warning = _normalizeError(error);
        }
      }

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

  Future<bool> clearAssistantMemory() async {
    _saving = true;
    _error = null;
    _warning = null;
    notifyListeners();

    try {
      _assistantName = defaultAssistantName;
      _userName = '';
      _wakeWordPhrase = defaultAssistantName;
      _wakeWordSensitivity = 40;
      _homeAssistantEnabled = false;
      _homeAssistantUrl = '';
      _homeAssistantToken = '';
      _microphoneDeviceId = '';
      _microphoneDeviceLabel = '';
      _ttsMode = defaultTtsMode;
      _ttsVoiceKey = '';
      _ttsVoiceLabel = '';
      _knownKeys = <String>{};
      _loadedOnce = true;
      await _persistLocalSettings();

      try {
        await _api.clearAppSettings();
        await _api.clearMemory();
        await MemoryService().refresh();
      } catch (error) {
        _warning = _normalizeError(error);
      }

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

  void _applyEntries(
    List<MemoryEntry> entries, {
    bool preserveExistingValues = false,
  }) {
    _knownKeys = entries.map((entry) => entry.key).toSet();

    final assistantName = _entryValue(entries, 'assistant_name');
    final userName = _entryValue(entries, 'name');
    final wakeWordPhrase = _entryValue(entries, 'wake_word_phrase');
    final wakeWordSensitivity = _entryValue(entries, 'wake_word_sensitivity');
    final homeAssistantEnabled = _entryValue(entries, 'home_assistant_enabled');
    final homeAssistantUrl = _entryValue(entries, 'home_assistant_url');
    final homeAssistantToken = _entryValue(entries, 'home_assistant_token');

    _assistantName = assistantName?.trim().isNotEmpty == true
        ? assistantName!.trim()
        : preserveExistingValues
            ? assistantNameOrDefault()
            : defaultAssistantName;
    _userName = userName?.trim().isNotEmpty == true
        ? userName!.trim()
        : preserveExistingValues
            ? _userName
            : '';
    _wakeWordPhrase = wakeWordPhrase?.trim().isNotEmpty == true
        ? wakeWordPhrase!.trim()
        : preserveExistingValues
            ? wakeWordOrDefault()
            : _assistantName;
    _wakeWordSensitivity = wakeWordSensitivity != null
        ? _clampWakeWordSensitivity(int.tryParse(wakeWordSensitivity) ?? 40)
        : preserveExistingValues
            ? _wakeWordSensitivity
            : 40;
    _homeAssistantEnabled = homeAssistantEnabled != null
        ? _parseBool(homeAssistantEnabled)
        : preserveExistingValues
            ? _homeAssistantEnabled
            : (homeAssistantUrl?.trim().isNotEmpty == true &&
                homeAssistantToken?.trim().isNotEmpty == true);
    _homeAssistantUrl = homeAssistantUrl?.trim().isNotEmpty == true
        ? homeAssistantUrl!.trim()
        : preserveExistingValues
            ? _homeAssistantUrl
            : '';
    _homeAssistantToken = homeAssistantToken?.trim().isNotEmpty == true
        ? homeAssistantToken!.trim()
        : preserveExistingValues
            ? _homeAssistantToken
            : '';
  }

  void _applySettingsEntries(
    List<AppSettingEntry> entries, {
    bool preserveExistingValues = false,
  }) {
    final values = <String, String>{};
    for (final entry in entries) {
      final key = entry.key.trim();
      final value = entry.value;
      if (key.isNotEmpty) {
        values[key] = value;
      }
    }

    final assistantName = values['assistant_name'];
    final userName = values['user_name'];
    final wakeWordPhrase = values['wake_word_phrase'];
    final wakeWordSensitivity = values['wake_word_sensitivity'];
    final homeAssistantEnabled = values['home_assistant_enabled'];
    final homeAssistantUrl = values['home_assistant_url'];
    final homeAssistantToken = values['home_assistant_token'];

    _assistantName = assistantName?.trim().isNotEmpty == true
        ? assistantName!.trim()
        : preserveExistingValues
            ? assistantNameOrDefault()
            : defaultAssistantName;
    _userName = userName?.trim().isNotEmpty == true
        ? userName!.trim()
        : preserveExistingValues
            ? _userName
            : '';
    _wakeWordPhrase = wakeWordPhrase?.trim().isNotEmpty == true
        ? wakeWordPhrase!.trim()
        : preserveExistingValues
            ? wakeWordOrDefault()
            : _assistantName;
    _wakeWordSensitivity = wakeWordSensitivity != null
        ? _clampWakeWordSensitivity(int.tryParse(wakeWordSensitivity) ?? 40)
        : preserveExistingValues
            ? _wakeWordSensitivity
            : 40;
    _homeAssistantEnabled = homeAssistantEnabled != null
        ? _parseBool(homeAssistantEnabled)
        : preserveExistingValues
            ? _homeAssistantEnabled
            : (homeAssistantUrl?.trim().isNotEmpty == true &&
                homeAssistantToken?.trim().isNotEmpty == true);
    _homeAssistantUrl = homeAssistantUrl?.trim().isNotEmpty == true
        ? homeAssistantUrl!.trim()
        : preserveExistingValues
            ? _homeAssistantUrl
            : '';
    _homeAssistantToken = homeAssistantToken?.trim().isNotEmpty == true
        ? homeAssistantToken!.trim()
        : preserveExistingValues
            ? _homeAssistantToken
            : '';
  }

  String assistantNameOrDefault() {
    final clean = _assistantName.trim();
    return clean.isEmpty ? defaultAssistantName : clean;
  }

  String wakeWordOrDefault() {
    final clean = _wakeWordPhrase.trim();
    if (clean.isNotEmpty) {
      return clean;
    }
    return assistantNameOrDefault();
  }

  String? _entryValue(List<MemoryEntry> entries, String key) {
    for (final entry in entries) {
      if (entry.key == key) {
        return entry.value;
      }
    }
    return null;
  }

  Future<void> _saveField(String key, String value) async {
    final cleanValue = value.trim();

    if (cleanValue.isEmpty) {
      if (_knownKeys.contains(key)) {
        await _api.deleteMemoryEntry(key);
        _knownKeys.remove(key);
      }
      return;
    }

    await _api.updateMemoryEntry(key, cleanValue);
    _knownKeys.add(key);
  }

  Future<bool> _loadLocalSettings() async {
    try {
      final file = await _settingsFile();
      if (!await file.exists()) {
        return false;
      }

      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return false;
      }

      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) {
        return false;
      }

      _assistantName = (data['assistant_name']?.toString().trim().isNotEmpty == true)
          ? data['assistant_name'].toString().trim()
          : defaultAssistantName;
      _userName = data['user_name']?.toString().trim() ?? '';
      _wakeWordPhrase = (data['wake_word_phrase']?.toString().trim().isNotEmpty == true)
          ? data['wake_word_phrase'].toString().trim()
          : _assistantName;
      _wakeWordSensitivity = _clampWakeWordSensitivity(
        int.tryParse(data['wake_word_sensitivity']?.toString() ?? '') ?? 40,
      );
      _homeAssistantUrl = data['home_assistant_url']?.toString().trim() ?? '';
      _homeAssistantToken = data['home_assistant_token']?.toString().trim() ?? '';
      _homeAssistantEnabled = data.containsKey('home_assistant_enabled')
          ? _parseBool(data['home_assistant_enabled'])
          : (_homeAssistantUrl.isNotEmpty && _homeAssistantToken.isNotEmpty);
      _microphoneDeviceId = data['microphone_device_id']?.toString().trim() ?? '';
      _microphoneDeviceLabel = data['microphone_device_label']?.toString().trim() ?? '';
      _ttsMode = _normalizeTtsMode(data['tts_mode']?.toString().trim() ?? '');
      _ttsVoiceKey = data['tts_voice_key']?.toString().trim() ?? '';
      _ttsVoiceLabel = data['tts_voice_label']?.toString().trim() ?? '';

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _persistLocalSettings() async {
    final file = await _settingsFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'assistant_name': assistantName,
        'user_name': userName,
        'wake_word_phrase': wakeWordPhrase,
        'wake_word_sensitivity': wakeWordSensitivity,
        'home_assistant_enabled': homeAssistantEnabled,
        'home_assistant_url': homeAssistantUrl,
        'home_assistant_token': homeAssistantToken,
        'microphone_device_id': microphoneDeviceId,
        'microphone_device_label': microphoneDeviceLabel,
        'tts_mode': ttsMode,
        'tts_voice_key': ttsVoiceKey,
        'tts_voice_label': ttsVoiceLabel,
      }),
      flush: true,
    );
  }

  Future<HomeAssistantStatus> testHomeAssistantConnection() {
    return _api.testHomeAssistantConnection();
  }

  Future<File> _settingsFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}${Platform.pathSeparator}jarvis_settings.json');
  }

  String _normalizeError(Object error) {
    final text = error.toString();
    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length);
    }
    return text;
  }

  bool _parseBool(Object? value) {
    final raw = value?.toString().trim().toLowerCase() ?? '';
    return raw == 'true' || raw == '1' || raw == 'yes' || raw == 'on';
  }

  int _clampWakeWordSensitivity(int value) {
    if (value < 0) {
      return 0;
    }
    if (value > 100) {
      return 100;
    }
    return value;
  }

  String _normalizeTtsMode(String value) {
    return value.trim().toLowerCase() == 'backend'
        ? 'backend'
        : defaultTtsMode;
  }
}
