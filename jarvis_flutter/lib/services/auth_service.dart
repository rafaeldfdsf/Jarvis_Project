import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../config/app_endpoints.dart';
import '../models/auth_models.dart';
import 'activity_history_service.dart';
import 'api_service.dart';
import 'app_shell_service.dart';
import 'app_settings_service.dart';
import 'assistant_runtime_service.dart';
import 'conversation_service.dart';
import 'home_assistant_devices_service.dart';
import 'memory_service.dart';
import 'routine_service.dart';

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();

  factory AuthService() {
    return _instance;
  }

  AuthService._internal();

  final ApiService _api = ApiService();

  bool _loading = false;
  bool _loadedOnce = false;
  Future<void>? _pendingLoad;
  String? _error;
  String? _notice;
  String _accessToken = '';
  AuthUserModel? _user;

  bool get loading => _loading;
  bool get loadedOnce => _loadedOnce;
  bool get isAuthenticated => _accessToken.trim().isNotEmpty && _user != null;
  String? get error => _error;
  String? get notice => _notice;
  String get accessToken => _accessToken.trim();
  AuthUserModel? get user => _user;

  Future<void> load() async {
    if (_pendingLoad != null) {
      await _pendingLoad;
      return;
    }

    if (_loadedOnce) {
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
    _notice = null;
    notifyListeners();

    try {
      final stored = await _loadStoredSession();
      _accessToken = stored.$1;
      _user = stored.$2;

      if (_accessToken.isNotEmpty) {
        AppEndpoints.setRuntimeApiToken(_accessToken);
        try {
          _user = await _api.fetchCurrentUser();
          await AssistantRuntimeService().setAuthenticated(true);
          await _persistSession();
        } catch (_) {
          await AssistantRuntimeService().setAuthenticated(false);
          await _clearSession(preserveError: false);
        }
      } else {
        await AssistantRuntimeService().setAuthenticated(false);
      }
      _loadedOnce = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> login({required String email, required String password}) async {
    _loading = true;
    _error = null;
    _notice = null;
    notifyListeners();

    try {
      final session = await _api.login(email: email, password: password);
      await _resetAccountScopedState();
      _accessToken = session.accessToken;
      _user = session.user;
      AppEndpoints.setRuntimeApiToken(_accessToken);
      await AssistantRuntimeService().setAuthenticated(true);
      await _persistSession();
      _loadedOnce = true;
      notifyListeners();
      return true;
    } catch (error) {
      _error = _normalizeError(error);
      notifyListeners();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    _loading = true;
    _error = null;
    _notice = null;
    notifyListeners();

    try {
      final status = await _api.register(
        email: email,
        password: password,
        displayName: displayName,
      );
      _notice = status.message;
      _loadedOnce = true;
      notifyListeners();
      return true;
    } catch (error) {
      _error = _normalizeError(error);
      notifyListeners();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _loading = true;
    _error = null;
    _notice = null;
    notifyListeners();

    try {
      await _api.logout();
    } finally {
      await _resetAccountScopedState();
      await AssistantRuntimeService().setAuthenticated(false);
      await _clearSession(preserveError: false);
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> verifyEmail({
    required String email,
    required String code,
  }) async {
    _loading = true;
    _error = null;
    _notice = null;
    notifyListeners();

    try {
      final session = await _api.verifyEmail(email: email, code: code);
      await _resetAccountScopedState();
      _accessToken = session.accessToken;
      _user = session.user;
      AppEndpoints.setRuntimeApiToken(_accessToken);
      await AssistantRuntimeService().setAuthenticated(true);
      await _persistSession();
      _loadedOnce = true;
      _notice = 'Email confirmado com sucesso.';
      notifyListeners();
      return true;
    } catch (error) {
      _error = _normalizeError(error);
      notifyListeners();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> resendVerification({required String email}) async {
    _loading = true;
    _error = null;
    _notice = null;
    notifyListeners();

    try {
      final status = await _api.resendVerification(email: email);
      _notice = status.message;
      notifyListeners();
      return true;
    } catch (error) {
      _error = _normalizeError(error);
      notifyListeners();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> requestPasswordReset({required String email}) async {
    _loading = true;
    _error = null;
    _notice = null;
    notifyListeners();

    try {
      final status = await _api.requestPasswordReset(email: email);
      _notice = status.message;
      notifyListeners();
      return true;
    } catch (error) {
      _error = _normalizeError(error);
      notifyListeners();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    _loading = true;
    _error = null;
    _notice = null;
    notifyListeners();

    try {
      final status = await _api.resetPassword(
        email: email,
        code: code,
        newPassword: newPassword,
      );
      _notice = status.message;
      notifyListeners();
      return true;
    } catch (error) {
      _error = _normalizeError(error);
      notifyListeners();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<(String, AuthUserModel?)> _loadStoredSession() async {
    try {
      final file = await _sessionFile();
      if (!await file.exists()) {
        return ('', null);
      }

      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return ('', null);
      }

      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) {
        return ('', null);
      }

      final token = data['access_token']?.toString().trim() ?? '';
      final userJson = data['user'];
      final user = userJson is Map<String, dynamic>
          ? AuthUserModel.fromJson(userJson)
          : null;
      return (token, user);
    } catch (_) {
      return ('', null);
    }
  }

  Future<void> _persistSession() async {
    final file = await _sessionFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({'access_token': _accessToken, 'user': _user?.toJson()}),
      flush: true,
    );
  }

  Future<void> _clearSession({required bool preserveError}) async {
    _accessToken = '';
    _user = null;
    AppEndpoints.clearRuntimeApiToken();

    try {
      final file = await _sessionFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      if (!preserveError) {
        _error = null;
      }
    }
  }

  Future<void> _resetAccountScopedState() async {
    await AppSettingsService().resetForAccountSwitch();
    MemoryService().resetForAccountSwitch();
    RoutineService().resetForAccountSwitch();
    HomeAssistantDevicesService().resetForAccountSwitch();
    await ActivityHistoryService().resetForAccountSwitch();
    ConversationService().resetForAccountSwitch();
    AppShellService().resetForAccountSwitch();
  }

  Future<File> _sessionFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}${Platform.pathSeparator}jarvis_auth.json');
  }

  String _normalizeError(Object error) {
    final text = error.toString();
    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length);
    }
    return text;
  }
}
