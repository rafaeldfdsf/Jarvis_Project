import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;

import 'package:jarvis_flutter/config/app_endpoints.dart';
import 'package:jarvis_flutter/services/log_service.dart';

import 'app_settings_service.dart';

class TtsVoiceOption {
  const TtsVoiceOption({
    required this.key,
    required this.label,
    required this.voiceData,
  });

  final String key;
  final String label;
  final Map<String, String> voiceData;
}

class TtsService {
  static const String modeLocal = 'local';
  static const String modeBackend = 'backend';

  final AudioPlayer _player = AudioPlayer();
  final FlutterTts _flutterTts = FlutterTts();
  final String baseUrl = AppEndpoints.apiBaseUrl;
  final LogService _logService = LogService();
  final AppSettingsService _settings = AppSettingsService();

  bool _initialized = false;
  bool _preferLocalTts = true;
  String? _lastWindowsTempAudioPath;
  void Function()? _completionHandler;

  Future<void> init() async {
    if (_initialized) {
      return;
    }

    _initialized = true;
    if (Platform.isWindows) {
      _logService.addLog(
        'INFO',
        'TtsService inicializado com motor local WinRT para Windows.',
      );
      return;
    }

    try {
      await _flutterTts.setLanguage('pt-PT');
      await _flutterTts.setSpeechRate(0.47);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.awaitSpeakCompletion(true);
      _flutterTts.setCompletionHandler(() {
        _logService.addLog('INFO', 'Reproducao TTS local terminada.');
        _completionHandler?.call();
      });
      _flutterTts.setErrorHandler((message) {
        _logService.addLog('ERROR', 'Erro no TTS local: $message');
      });
      _logService.addLog('INFO', 'TtsService inicializado com flutter_tts.');
    } catch (error) {
      _preferLocalTts = false;
      _logService.addLog(
        'WARN',
        'Nao consegui inicializar TTS local. Vou usar o backend como fallback. Erro: $error',
      );
    }
  }

  void setOnComplete(void Function() handler) {
    _completionHandler = handler;
  }

  Future<void> speak(String text) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      _logService.addLog('WARN', 'TTS ignorado porque o texto veio vazio.');
      return;
    }

    await init();

    final selectedMode = _normalizeMode(_settings.ttsMode);
    if (selectedMode == modeBackend) {
      await _speakViaBackend(cleanText);
      return;
    }

    if (_preferLocalTts) {
      final spokenLocally = await _speakLocally(cleanText);
      if (spokenLocally) {
        return;
      }
    }

    await _speakViaBackend(cleanText);
  }

  Future<bool> _speakLocally(String cleanText) async {
    if (Platform.isWindows) {
      return _speakViaWindowsLocal(cleanText);
    }

    try {
      await _player.stop();
      await _flutterTts.stop();
      await _applyConfiguredVoice();
      _logService.addLog('INFO', 'A reproduzir resposta com TTS local.');
      final result = await _flutterTts.speak(cleanText);
      if (result == 1 || result == null) {
        return true;
      }
      _logService.addLog(
        'WARN',
        'flutter_tts devolveu codigo inesperado ($result). Vou usar fallback.',
      );
    } catch (error) {
      _logService.addLog('WARN', 'Falha no TTS local. Vou usar fallback: $error');
    }

    return false;
  }

  Future<List<TtsVoiceOption>> listAvailableVoices() async {
    await init();

    if (Platform.isWindows) {
      final windowsVoices = await _listWindowsVoices();
      if (windowsVoices.isNotEmpty) {
        return windowsVoices;
      }
    }

    try {
      final rawVoices = await _flutterTts.getVoices;
      if (rawVoices is! List) {
        return const <TtsVoiceOption>[];
      }

      final voices = <TtsVoiceOption>[];
      for (final item in rawVoices) {
        if (item is! Map) {
          continue;
        }
        final voiceData = <String, String>{};
        for (final entry in item.entries) {
          final key = entry.key?.toString().trim() ?? '';
          final value = entry.value?.toString().trim() ?? '';
          if (key.isEmpty || value.isEmpty) {
            continue;
          }
          voiceData[key] = value;
        }
        final key = _voiceKeyFromData(voiceData);
        if (key.isEmpty) {
          continue;
        }
        voices.add(
          TtsVoiceOption(
            key: key,
            label: _voiceLabelFromData(voiceData),
            voiceData: voiceData,
          ),
        );
      }

      voices.sort((a, b) {
        final localeCompare = _localePriority(a.voiceData).compareTo(
          _localePriority(b.voiceData),
        );
        if (localeCompare != 0) {
          return localeCompare;
        }

        final localeLabelCompare = _voiceLocaleLabel(
          a.voiceData,
        ).compareTo(_voiceLocaleLabel(b.voiceData));
        if (localeLabelCompare != 0) {
          return localeLabelCompare;
        }

        return _voiceName(a.voiceData).toLowerCase().compareTo(
          _voiceName(b.voiceData).toLowerCase(),
        );
      });
      return voices;
    } catch (error) {
      _logService.addLog('WARN', 'Falha ao listar vozes locais: $error');
      return const <TtsVoiceOption>[];
    }
  }

  Future<bool> previewVoice(
    String text, {
    String? voiceKey,
    String? mode,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      return false;
    }

    await init();
    final selectedMode = _normalizeMode(mode ?? _settings.ttsMode);

    if (selectedMode == modeBackend) {
      return _speakViaBackend(cleanText);
    }

    if (Platform.isWindows) {
      return _speakViaWindowsLocal(cleanText, overrideVoiceKey: voiceKey);
    }

    try {
      await _player.stop();
      await _flutterTts.stop();
      await _applyConfiguredVoice(overrideVoiceKey: voiceKey);
      final result = await _flutterTts.speak(cleanText);
      return result == 1 || result == null;
    } catch (error) {
      _logService.addLog('WARN', 'Falha ao testar voz local: $error');
      return false;
    }
  }

  Future<void> _applyConfiguredVoice({String? overrideVoiceKey}) async {
    if (Platform.isWindows) {
      return;
    }

    final selectedVoiceKey = (overrideVoiceKey ?? _settings.ttsVoiceKey).trim();
    if (selectedVoiceKey.isEmpty) {
      return;
    }

    final voices = await listAvailableVoices();
    for (final voice in voices) {
      if (voice.key != selectedVoiceKey) {
        continue;
      }

      try {
        await _flutterTts.setVoice(voice.voiceData);
        _logService.addLog('INFO', 'Voz local configurada: ${voice.label}.');
      } catch (error) {
        _logService.addLog('WARN', 'Nao consegui aplicar a voz local "${voice.label}": $error');
      }
      return;
    }
  }

  String _voiceKeyFromData(Map<String, String> voiceData) {
    final identifier = voiceData['identifier']?.toString().trim() ?? '';
    if (identifier.isNotEmpty) {
      return identifier;
    }

    final name = voiceData['name']?.toString().trim() ?? '';
    final locale = voiceData['locale']?.toString().trim() ?? '';
    if (name.isEmpty && locale.isEmpty) {
      return '';
    }
    return '$name|$locale';
  }

  String _voiceLabelFromData(Map<String, String> voiceData) {
    final parts = <String>[_voiceName(voiceData)];
    final localeLabel = _voiceLocaleLabel(voiceData);
    final genderLabel = _voiceGenderLabel(voiceData);
    if (localeLabel.isNotEmpty) {
      parts.add(localeLabel);
    }
    if (genderLabel.isNotEmpty) {
      parts.add(genderLabel);
    }
    return parts.join(' | ');
  }

  int _localePriority(Map<String, String> voiceData) {
    final locale = _voiceLocale(voiceData);
    if (locale == 'pt-pt') {
      return 0;
    }
    if (locale.startsWith('pt-')) {
      return 1;
    }
    return 2;
  }

  String _voiceName(Map<String, String> voiceData) {
    final name = voiceData['name']?.toString().trim() ?? '';
    return name.isEmpty ? 'Voz sem nome' : name;
  }

  String _voiceLocale(Map<String, String> voiceData) {
    return voiceData['locale']?.toString().trim().toLowerCase() ?? '';
  }

  String _voiceLocaleLabel(Map<String, String> voiceData) {
    final locale = _voiceLocale(voiceData);
    switch (locale) {
      case 'pt-pt':
        return 'Portugues (Portugal)';
      case 'pt-br':
        return 'Portugues (Brasil)';
      case 'en-us':
        return 'English (US)';
      case 'en-gb':
        return 'English (UK)';
      case '':
        return '';
      default:
        return locale.replaceAll('_', '-').toUpperCase();
    }
  }

  String _voiceGenderLabel(Map<String, String> voiceData) {
    final raw = voiceData['gender']?.toString().trim().toLowerCase() ?? '';
    if (raw.contains('female')) {
      return 'Feminina';
    }
    if (raw.contains('male')) {
      return 'Masculina';
    }
    if (raw.isEmpty) {
      return '';
    }
    return raw[0].toUpperCase() + raw.substring(1);
  }

  String _normalizeMode(String value) {
    return value.trim().toLowerCase() == modeBackend ? modeBackend : modeLocal;
  }

  Future<List<TtsVoiceOption>> _listWindowsVoices() async {
    try {
      final result = await Process.run(
        'powershell',
        <String>[
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          _windowsVoiceListScript,
        ],
      ).timeout(const Duration(seconds: 15));

      if (result.exitCode != 0) {
        _logService.addLog(
          'WARN',
          'Falha ao listar vozes WinRT: ${result.stderr}',
        );
        return const <TtsVoiceOption>[];
      }

      final output = result.stdout.toString().trim();
      if (output.isEmpty) {
        return const <TtsVoiceOption>[];
      }

      final decoded = jsonDecode(output);
      final rawItems = decoded is List
          ? decoded
          : decoded is Map<String, dynamic>
              ? <dynamic>[decoded]
              : const <dynamic>[];
      final voices = <TtsVoiceOption>[];
      for (final item in rawItems) {
        if (item is! Map) {
          continue;
        }
        final voiceData = <String, String>{};
        for (final entry in item.entries) {
          final key = entry.key.toString().trim();
          final value = entry.value?.toString().trim() ?? '';
          if (key.isEmpty || value.isEmpty) {
            continue;
          }
          voiceData[key] = value;
        }
        final key = _voiceKeyFromData(voiceData);
        if (key.isEmpty) {
          continue;
        }
        voices.add(
          TtsVoiceOption(
            key: key,
            label: _voiceLabelFromData(voiceData),
            voiceData: voiceData,
          ),
        );
      }

      voices.sort((a, b) {
        final localeCompare = _localePriority(a.voiceData).compareTo(
          _localePriority(b.voiceData),
        );
        if (localeCompare != 0) {
          return localeCompare;
        }

        final localeLabelCompare = _voiceLocaleLabel(
          a.voiceData,
        ).compareTo(_voiceLocaleLabel(b.voiceData));
        if (localeLabelCompare != 0) {
          return localeLabelCompare;
        }

        return _voiceName(a.voiceData).toLowerCase().compareTo(
          _voiceName(b.voiceData).toLowerCase(),
        );
      });
      return voices;
    } catch (error) {
      _logService.addLog('WARN', 'Falha ao listar vozes OneCore: $error');
      return const <TtsVoiceOption>[];
    }
  }

  Future<bool> _speakViaWindowsLocal(
    String cleanText, {
    String? overrideVoiceKey,
  }) async {
    final requestedVoiceKey = (overrideVoiceKey ?? _settings.ttsVoiceKey).trim();
    final availableVoices = await _listWindowsVoices();
    final selectedVoiceKey = requestedVoiceKey.isNotEmpty
        ? requestedVoiceKey
        : _pickPreferredWindowsVoice(availableVoices);
    final outputPath = _nextWindowsTempAudioPath();

    try {
      await _player.stop();
      await _deleteLastWindowsTempAudio();
      final result = await Process.run(
        'powershell',
        <String>[
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          _windowsVoiceSynthesisScript,
        ],
        environment: <String, String>{
          'JARVIS_TTS_TEXT': cleanText,
          'JARVIS_TTS_VOICE': selectedVoiceKey,
          'JARVIS_TTS_OUTPUT': outputPath,
        },
      ).timeout(const Duration(seconds: 25));

      if (result.exitCode != 0) {
        _logService.addLog(
          'WARN',
          'Falha ao sintetizar voz OneCore: ${result.stderr}',
        );
        return false;
      }

      final audioFile = File(outputPath);
      if (!await audioFile.exists()) {
        _logService.addLog(
          'WARN',
          'A sintese WinRT terminou sem gerar o ficheiro de audio esperado.',
        );
        return false;
      }

      _lastWindowsTempAudioPath = outputPath;
      final playbackCompleted = Completer<void>();
      StreamSubscription<void>? completionSubscription;
      try {
        completionSubscription = _player.onPlayerComplete.listen((event) {
          if (!playbackCompleted.isCompleted) {
            _logService.addLog('INFO', 'Reproducao TTS WinRT terminada.');
            _completionHandler?.call();
            playbackCompleted.complete();
          }
        });

        await _player.play(DeviceFileSource(outputPath));
        await playbackCompleted.future.timeout(
          const Duration(minutes: 2),
          onTimeout: () {
            _logService.addLog(
              'WARN',
              'Tempo limite atingido a aguardar pelo fim do TTS local WinRT.',
            );
          },
        );
      } finally {
        await completionSubscription?.cancel();
      }

      return true;
    } catch (error) {
      _logService.addLog('WARN', 'Falha no TTS local WinRT: $error');
      return false;
    }
  }

  String _pickPreferredWindowsVoice(List<TtsVoiceOption> voices) {
    for (final voice in voices) {
      if (_voiceLocale(voice.voiceData) == 'pt-pt') {
        return voice.key;
      }
    }
    for (final voice in voices) {
      if (_voiceLocale(voice.voiceData).startsWith('pt-')) {
        return voice.key;
      }
    }
    return voices.isNotEmpty ? voices.first.key : '';
  }

  String _nextWindowsTempAudioPath() {
    return '${Directory.systemTemp.path}${Platform.pathSeparator}jarvis_tts_${DateTime.now().microsecondsSinceEpoch}.wav';
  }

  Future<void> _deleteLastWindowsTempAudio() async {
    final path = _lastWindowsTempAudioPath;
    _lastWindowsTempAudioPath = null;
    if (path == null || path.isEmpty) {
      return;
    }

    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignore temp cleanup failures.
    }
  }

  Future<bool> _speakViaBackend(String cleanText) async {
    StreamSubscription<void>? completionSubscription;

    try {
      _logService.addLog('INFO', 'A enviar texto para /tts.');

      final response = await http
          .post(
            Uri.parse('$baseUrl/tts'),
            headers: AppEndpoints.apiHeaders(includeJsonContentType: true),
            body: jsonEncode({'text': cleanText}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        _logService.addLog('ERROR', 'Erro HTTP no /tts: ${response.body}');
        return false;
      }

      final data = jsonDecode(response.body);
      final audioBase64 = data['audio'];

      if (audioBase64 is! String || audioBase64.isEmpty) {
        _logService.addLog('ERROR', 'O backend respondeu sem audio valido.');
        return false;
      }

      final bytes = base64Decode(audioBase64);
      final playbackCompleted = Completer<void>();

      await _player.stop();
      completionSubscription = _player.onPlayerComplete.listen((event) {
        if (!playbackCompleted.isCompleted) {
          _logService.addLog('INFO', 'Reproducao TTS backend terminada.');
          _completionHandler?.call();
          playbackCompleted.complete();
        }
      });

      await _player.play(BytesSource(bytes));
      await playbackCompleted.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () {
          _logService.addLog(
            'WARN',
            'Tempo limite atingido a aguardar pelo fim do TTS.',
          );
        },
      );
      return true;
    } on TimeoutException {
      _logService.addLog('ERROR', AppEndpoints.apiUnavailableMessage());
    } catch (error) {
      _logService.addLog('ERROR', 'Falha no TTS via backend: $error');
    } finally {
      await completionSubscription?.cancel();
    }

    return false;
  }

  Future<void> stop() async {
    if (!Platform.isWindows) {
      await _flutterTts.stop();
    }
    await _player.stop();
    await _deleteLastWindowsTempAudio();
    _logService.addLog('WARN', 'Reproducao de audio interrompida.');
  }

  static const String _windowsVoiceListScript = r'''
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Media.SpeechSynthesis.SpeechSynthesizer, Windows.Media.SpeechSynthesis, ContentType=WindowsRuntime]
[Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices |
  ForEach-Object {
    [PSCustomObject]@{
      identifier = $_.Id
      name = $_.DisplayName
      locale = $_.Language
      gender = $_.Gender.ToString()
    }
  } |
  ConvertTo-Json -Compress
''';

  static const String _windowsVoiceSynthesisScript = r'''
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Media.SpeechSynthesis.SpeechSynthesizer, Windows.Media.SpeechSynthesis, ContentType=WindowsRuntime]

$text = [Environment]::GetEnvironmentVariable('JARVIS_TTS_TEXT')
$voiceId = [Environment]::GetEnvironmentVariable('JARVIS_TTS_VOICE')
$output = [Environment]::GetEnvironmentVariable('JARVIS_TTS_OUTPUT')

if ([string]::IsNullOrWhiteSpace($text)) {
  throw 'Texto TTS vazio.'
}

if ([string]::IsNullOrWhiteSpace($output)) {
  throw 'Caminho de output TTS vazio.'
}

$voices = [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices
$voice = $null
if (-not [string]::IsNullOrWhiteSpace($voiceId)) {
  $voice = $voices | Where-Object { $_.Id -eq $voiceId } | Select-Object -First 1
}
if ($null -eq $voice) {
  $voice = $voices | Where-Object { $_.Language -eq 'pt-PT' } | Select-Object -First 1
}
if ($null -eq $voice) {
  $voice = $voices | Where-Object { $_.Language -like 'pt-*' } | Select-Object -First 1
}
if ($null -eq $voice) {
  $voice = $voices | Select-Object -First 1
}
if ($null -eq $voice) {
  throw 'Nenhuma voz local disponivel no Windows.'
}

$synth = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer
$synth.Voice = $voice
$operation = $synth.SynthesizeTextToStreamAsync($text)
$method = [System.WindowsRuntimeSystemExtensions].GetMethods() |
  Where-Object {
    $_.Name -eq 'AsTask' -and
    $_.IsGenericMethod -and
    $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -like 'IAsyncOperation*'
  } |
  Select-Object -First 1
$generic = $method.MakeGenericMethod([Windows.Media.SpeechSynthesis.SpeechSynthesisStream])
$task = $generic.Invoke($null, @($operation))
$stream = $task.GetAwaiter().GetResult()
$directory = Split-Path -Parent $output
if (-not [string]::IsNullOrWhiteSpace($directory)) {
  New-Item -ItemType Directory -Path $directory -Force | Out-Null
}
$readStream = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($stream)
$file = [System.IO.File]::Create($output)
try {
  $readStream.CopyTo($file)
} finally {
  $file.Dispose()
  $readStream.Dispose()
  $stream.Dispose()
  $synth.Dispose()
}
Write-Output $output
''';
}
