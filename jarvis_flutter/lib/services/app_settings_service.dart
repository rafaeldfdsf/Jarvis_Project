import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/memory_entry.dart';
import '../models/routine.dart';
import 'api_service.dart';
import 'memory_service.dart';

class AppSettingsService extends ChangeNotifier {
  static const String defaultAssistantName = 'Jarvis';

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
  String _homeAssistantUrl = '';
  String _homeAssistantToken = '';
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
  String get homeAssistantUrl => _homeAssistantUrl.trim();
  String get homeAssistantToken => _homeAssistantToken.trim();

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
        final entries = await _api.fetchMemoryEntries();
        _applyEntries(entries, preserveExistingValues: hasLocalSettings);
        await _persistLocalSettings();
      } catch (error) {
        if (hasLocalSettings) {
          _warning = _normalizeError(error);
        } else {
          _error = _normalizeError(error);
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
    required String homeAssistantUrl,
    required String homeAssistantToken,
  }) async {
    final cleanAssistantName = assistantName.trim().isEmpty
        ? defaultAssistantName
        : assistantName.trim();
    final cleanUserName = userName.trim();
    final cleanWakeWordPhrase = wakeWordPhrase.trim().isEmpty
        ? cleanAssistantName
        : wakeWordPhrase.trim();
    final cleanHomeAssistantUrl = homeAssistantUrl.trim();
    final cleanHomeAssistantToken = homeAssistantToken.trim();

    _saving = true;
    _error = null;
    _warning = null;
    notifyListeners();

    try {
      _assistantName = cleanAssistantName;
      _userName = cleanUserName;
      _wakeWordPhrase = cleanWakeWordPhrase;
      _homeAssistantUrl = cleanHomeAssistantUrl;
      _homeAssistantToken = cleanHomeAssistantToken;
      _loadedOnce = true;
      await _persistLocalSettings();

      try {
        await _saveField('assistant_name', cleanAssistantName);
        await _saveField('name', cleanUserName);
        await _saveField('wake_word_phrase', cleanWakeWordPhrase);
        await _saveField('home_assistant_url', cleanHomeAssistantUrl);
        await _saveField('home_assistant_token', cleanHomeAssistantToken);
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

  Future<bool> clearAssistantMemory() async {
    _saving = true;
    _error = null;
    _warning = null;
    notifyListeners();

    try {
      _assistantName = defaultAssistantName;
      _userName = '';
      _wakeWordPhrase = defaultAssistantName;
      _homeAssistantUrl = '';
      _homeAssistantToken = '';
      _knownKeys = <String>{};
      _loadedOnce = true;
      await _persistLocalSettings();

      try {
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
      _homeAssistantUrl = data['home_assistant_url']?.toString().trim() ?? '';
      _homeAssistantToken = data['home_assistant_token']?.toString().trim() ?? '';

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
        'home_assistant_url': homeAssistantUrl,
        'home_assistant_token': homeAssistantToken,
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
}
