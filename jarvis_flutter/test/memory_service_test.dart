import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_flutter/models/memory_entry.dart';
import 'package:jarvis_flutter/services/api_service.dart';
import 'package:jarvis_flutter/services/log_service.dart';
import 'package:jarvis_flutter/services/memory_service.dart';

class _FakeMemoryApiService extends ApiService {
  List<MemoryEntry> fetchResult = <MemoryEntry>[];
  final Map<String, MemoryEntry> updates = <String, MemoryEntry>{};
  final Set<String> deletedKeys = <String>{};
  bool clearCalled = false;

  @override
  Future<List<MemoryEntry>> fetchMemoryEntries() async {
    return fetchResult;
  }

  @override
  Future<MemoryEntry> updateMemoryEntry(String key, String value) async {
    final updated =
        updates[key] ??
        MemoryEntry(key: key, value: value, type: 'fact', label: key);
    return updated;
  }

  @override
  Future<void> deleteMemoryEntry(String key) async {
    deletedKeys.add(key);
  }

  @override
  Future<void> clearMemory() async {
    clearCalled = true;
  }
}

void main() {
  setUp(() {
    LogService().clearLogs();
  });

  test('MemoryService sincroniza memoria a partir da API', () async {
    final api = _FakeMemoryApiService()
      ..fetchResult = <MemoryEntry>[
        const MemoryEntry(
          key: 'reminder_1',
          value: 'reuniao as 15h',
          type: 'reminder',
          label: 'Lembrete 1',
          index: 1,
        ),
      ];
    final service = MemoryService.test(api: api);

    await service.refresh();

    expect(service.entries.length, 1);
    expect(service.entries.single.key, 'reminder_1');
    expect(service.entries.single.value, 'reuniao as 15h');
    expect(service.error, isNull);
  });

  test('MemoryService atualiza registos existentes e adiciona novos', () async {
    final api = _FakeMemoryApiService()
      ..fetchResult = <MemoryEntry>[
        const MemoryEntry(
          key: 'name',
          value: 'Rafael',
          type: 'fact',
          label: 'Nome',
        ),
      ]
      ..updates['name'] = const MemoryEntry(
        key: 'name',
        value: 'Rafael Rodrigues',
        type: 'fact',
        label: 'Nome',
      )
      ..updates['reminder_1'] = const MemoryEntry(
        key: 'reminder_1',
        value: 'comprar cafe',
        type: 'reminder',
        label: 'Lembrete 1',
        index: 1,
      );
    final service = MemoryService.test(api: api);

    await service.refresh();
    await service.updateEntry('name', 'Rafael Rodrigues');
    await service.updateEntry('reminder_1', 'comprar cafe');

    expect(service.entries.first.key, 'reminder_1');
    expect(service.entries.first.value, 'comprar cafe');
    expect(
      service.entries.where((entry) => entry.key == 'name').single.value,
      'Rafael Rodrigues',
    );
  });

  test('MemoryService remove e limpa a memoria local', () async {
    final api = _FakeMemoryApiService()
      ..fetchResult = <MemoryEntry>[
        const MemoryEntry(
          key: 'preference_1',
          value: 'respostas curtas',
          type: 'preference',
          label: 'Preferencia 1',
          index: 1,
        ),
        const MemoryEntry(
          key: 'reminder_1',
          value: 'beber agua',
          type: 'reminder',
          label: 'Lembrete 1',
          index: 1,
        ),
      ];
    final service = MemoryService.test(api: api);

    await service.refresh();
    await service.deleteEntry('preference_1');

    expect(api.deletedKeys, contains('preference_1'));
    expect(service.entries.map((entry) => entry.key), <String>['reminder_1']);

    await service.clearAll();

    expect(api.clearCalled, isTrue);
    expect(service.entries, isEmpty);
  });
}
