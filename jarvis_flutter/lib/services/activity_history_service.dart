import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/activity_history_entry.dart';
import '../models/chat_response.dart';

class ActivityHistoryService extends ChangeNotifier {
  static const String _storageFileName = 'assistant_activity_history.json';
  static const int _maxEntries = 250;

  static final ActivityHistoryService _instance =
      ActivityHistoryService._internal();

  factory ActivityHistoryService() {
    return _instance;
  }

  ActivityHistoryService._internal();

  final List<ActivityHistoryEntry> _entries = [];

  bool _loading = false;
  bool _loadedOnce = false;
  String? _error;
  Future<void>? _pendingLoad;

  List<ActivityHistoryEntry> get entries => List.unmodifiable(_entries);
  bool get loading => _loading;
  String? get error => _error;

  Future<void> load({bool force = false}) async {
    if (_pendingLoad != null) {
      await _pendingLoad;
      return;
    }

    if (_loadedOnce && !force) {
      return;
    }

    final future = _loadInternal();
    _pendingLoad = future;
    try {
      await future;
    } finally {
      _pendingLoad = null;
    }
  }

  Future<void> _loadInternal() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final file = await _storageFile();
      if (!await file.exists()) {
        _entries.clear();
        _loadedOnce = true;
        return;
      }

      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        _entries.clear();
        _loadedOnce = true;
        return;
      }

      final data = jsonDecode(raw);
      if (data is! List) {
        throw const FormatException('Formato invalido para o historico.');
      }

      _entries
        ..clear()
        ..addAll(
          data
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .map(ActivityHistoryEntry.fromJson),
        );
      _entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _loadedOnce = true;
    } catch (error) {
      _error = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> clear() async {
    await load();
    _entries.clear();
    _error = null;
    await _persist();
    notifyListeners();
  }

  Future<void> recordToolUsage({
    required String origin,
    required ToolCallModel toolCall,
    ToolResultModel? toolResult,
  }) async {
    final toolName = toolCall.toolName.trim();
    if (toolName.isEmpty || _isClientSideActionTool(toolName)) {
      return;
    }

    await load();

    final title = _toolTitle(toolName);
    final target = _toolTarget(toolCall);
    final detail = _toolDetail(toolCall, toolResult);

    await _prependEntry(
      ActivityHistoryEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        category: 'tool',
        status: toolResult?.ok == false ? 'error' : 'success',
        title: title,
        detail: detail,
        origin: origin,
        timestamp: DateTime.now(),
        target: target,
        source: toolName,
      ),
    );
  }

  Future<void> recordClientAction({
    required String origin,
    required ClientAction action,
    required bool success,
    String? detail,
    String? resolvedTarget,
  }) async {
    await load();

    final category = _actionCategory(action);
    final target = resolvedTarget ?? action.url ?? action.appName ?? action.action;
    final title = _actionTitle(action);
    final description = detail?.trim().isNotEmpty == true
        ? detail!.trim()
        : _actionDetail(action, success, target);

    await _prependEntry(
      ActivityHistoryEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        category: category,
        status: success ? 'success' : 'error',
        title: title,
        detail: description,
        origin: origin,
        timestamp: DateTime.now(),
        target: target,
        source: action.type,
      ),
    );
  }

  bool _isClientSideActionTool(String toolName) {
    return toolName == 'open_website' ||
        toolName == 'open_app' ||
        toolName == 'open_youtube';
  }

  String _toolTitle(String toolName) {
    switch (toolName) {
      case 'get_weather':
        return 'Consulta de tempo';
      case 'search_web':
        return 'Pesquisa web';
      default:
        return 'Tool $toolName';
    }
  }

  String? _toolTarget(ToolCallModel toolCall) {
    switch (toolCall.toolName) {
      case 'get_weather':
        return toolCall.arguments['city']?.toString();
      case 'search_web':
        return toolCall.arguments['query']?.toString();
      default:
        return null;
    }
  }

  String _toolDetail(ToolCallModel toolCall, ToolResultModel? toolResult) {
    final resultText = toolResult?.dataAsText() ?? '';

    if (toolCall.toolName == 'get_weather') {
      final city = toolCall.arguments['city']?.toString() ?? 'local desconhecido';
      return 'Tool get_weather usada para $city.';
    }

    if (toolCall.toolName == 'search_web') {
      final query = toolCall.arguments['query']?.toString() ?? 'sem query';
      final source = _extractFirstUrl(resultText);
      if (source != null) {
        return 'Pesquisa web por "$query". Primeira fonte: $source';
      }
      return 'Pesquisa web por "$query".';
    }

    if (resultText.isNotEmpty) {
      return resultText;
    }

    return 'Tool ${toolCall.toolName} executada.';
  }

  String _actionCategory(ClientAction action) {
    switch (action.type) {
      case 'open_url':
        return 'site';
      case 'open_app':
        return 'app';
      default:
        return 'system';
    }
  }

  String _actionTitle(ClientAction action) {
    switch (action.type) {
      case 'open_url':
        return 'Site aberto';
      case 'open_app':
        return 'Aplicacao aberta';
      case 'pc_action':
        return 'Acao do sistema';
      default:
        return 'Acao do assistente';
    }
  }

  String _actionDetail(ClientAction action, bool success, String? target) {
    final status = success ? 'Executado' : 'Falhou';

    if (action.type == 'open_url') {
      return '$status: ${target ?? 'site desconhecido'}';
    }

    if (action.type == 'open_app') {
      return '$status: ${target ?? 'aplicacao desconhecida'}';
    }

    return '$status: ${action.action ?? action.type}';
  }

  String? _extractFirstUrl(String text) {
    final match = RegExp(r'https?://\S+').firstMatch(text);
    return match?.group(0);
  }

  Future<void> _prependEntry(ActivityHistoryEntry entry) async {
    _entries.insert(0, entry);
    if (_entries.length > _maxEntries) {
      _entries.removeRange(_maxEntries, _entries.length);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final file = await _storageFile();
    final payload = jsonEncode(_entries.map((entry) => entry.toJson()).toList());
    await file.writeAsString(payload, flush: true);
  }

  Future<File> _storageFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_storageFileName');
  }
}
