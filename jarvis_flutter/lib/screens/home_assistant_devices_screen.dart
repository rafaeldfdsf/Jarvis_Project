import 'package:flutter/material.dart';

import '../models/home_assistant_device.dart';
import '../services/home_assistant_devices_service.dart';

class HomeAssistantDevicesScreen extends StatefulWidget {
  const HomeAssistantDevicesScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<HomeAssistantDevicesScreen> createState() =>
      _HomeAssistantDevicesScreenState();
}

class _HomeAssistantDevicesScreenState
    extends State<HomeAssistantDevicesScreen> {
  final HomeAssistantDevicesService _devicesService =
      HomeAssistantDevicesService();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_refreshView);
    _devicesService.load();
  }

  @override
  void dispose() {
    _searchController.removeListener(_refreshView);
    _searchController.dispose();
    super.dispose();
  }

  void _refreshView() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _syncDevices() async {
    final success = await _devicesService.sync();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Dispositivos sincronizados.'
              : (_devicesService.error ??
                  'Nao foi possivel sincronizar dispositivos.'),
        ),
      ),
    );
  }

  Future<void> _clearAllDevices() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0B1A2A),
          title: const Text('Limpar dispositivos'),
          content: const Text(
            'Isto remove todos os dispositivos sincronizados e aliases guardados. Queres continuar?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('Limpar tudo'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final deletedCount = await _devicesService.clearAll();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deletedCount != null
              ? 'Foram removidos $deletedCount dispositivo(s).'
              : (_devicesService.error ??
                  'Nao foi possivel limpar os dispositivos.'),
        ),
      ),
    );
  }

  Future<void> _editAlias(HomeAssistantDevice device) async {
    final controller = TextEditingController(text: device.alias);
    final alias = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0B1A2A),
          title: Text('Alias para ${device.friendlyName}'),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Ex.: luz da sala',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              filled: true,
              fillColor: Colors.white.withOpacity(0.04),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (alias == null) {
      return;
    }

    final success = await _devicesService.updateAlias(device.entityId, alias);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Alias atualizado.'
              : (_devicesService.error ??
                  'Nao foi possivel atualizar o alias.'),
        ),
      ),
    );
  }

  Future<void> _deleteDevice(HomeAssistantDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0B1A2A),
          title: const Text('Remover dispositivo'),
          content: Text(
            'Queres remover "${device.entityId}" da lista sincronizada?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('Remover'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final success = await _devicesService.deleteDevice(device.entityId);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Dispositivo removido.'
              : (_devicesService.error ??
                  'Nao foi possivel remover o dispositivo.'),
        ),
      ),
    );
  }

  List<HomeAssistantDevice> _filteredDevices(List<HomeAssistantDevice> devices) {
    final query = _normalize(_searchController.text);
    if (query.isEmpty) {
      return devices;
    }

    final filtered = devices.where((device) {
      final haystack = _normalize(
        '${device.entityId} ${device.domain} ${device.friendlyName} ${device.alias} ${device.state}',
      );
      return haystack.contains(query);
    }).toList();

    filtered.sort((a, b) {
      final aliasA = a.alias.trim().isEmpty ? 1 : 0;
      final aliasB = b.alias.trim().isEmpty ? 1 : 0;
      if (aliasA != aliasB) {
        return aliasA.compareTo(aliasB);
      }
      final duplicateA = _duplicateGroupSize(devices, a) > 1 ? 1 : 0;
      final duplicateB = _duplicateGroupSize(devices, b) > 1 ? 1 : 0;
      if (duplicateA != duplicateB) {
        return duplicateA.compareTo(duplicateB);
      }
      return a.friendlyName.toLowerCase().compareTo(b.friendlyName.toLowerCase());
    });

    return filtered;
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll('\u00E1', 'a')
        .replaceAll('\u00E0', 'a')
        .replaceAll('\u00E2', 'a')
        .replaceAll('\u00E3', 'a')
        .replaceAll('\u00E9', 'e')
        .replaceAll('\u00EA', 'e')
        .replaceAll('\u00ED', 'i')
        .replaceAll('\u00F3', 'o')
        .replaceAll('\u00F4', 'o')
        .replaceAll('\u00F5', 'o')
        .replaceAll('\u00FA', 'u')
        .replaceAll('\u00E7', 'c')
        .trim();
  }

  int _duplicateGroupSize(
    List<HomeAssistantDevice> devices,
    HomeAssistantDevice device,
  ) {
    final key = _normalize('${device.domain} ${device.friendlyName}');
    return devices
        .where((item) => _normalize('${item.domain} ${item.friendlyName}') == key)
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 980;
    final topPadding = widget.embedded && isCompact ? 78.0 : 18.0;

    return AnimatedBuilder(
      animation: _devicesService,
      builder: (context, _) {
        final devices = _filteredDevices(_devicesService.devices);
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF08111B), Color(0xFF03070D)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            top: widget.embedded,
            bottom: true,
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, topPadding, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0C2236), Color(0xFF091521)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: const Color(0xFF17324C)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Dispositivos',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.92),
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Sincroniza os dispositivos do Home Assistant e define aliases para o assistente os reconhecer por nomes naturais.',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.72),
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        FilledButton.icon(
                          onPressed: _devicesService.loading ? null : _syncDevices,
                          icon: const Icon(Icons.sync_rounded),
                          label: const Text('Sincronizar'),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.tonalIcon(
                          onPressed: _devicesService.loading ? null : _clearAllDevices,
                          icon: const Icon(Icons.delete_sweep_outlined),
                          label: const Text('Limpar lista'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Pesquisar por alias, nome, entidade ou dominio...',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: Colors.cyanAccent,
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.04),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_devicesService.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _devicesService.error!,
                        style: const TextStyle(color: Color(0xFFFF8A80)),
                      ),
                    ),
                  Expanded(
                    child: devices.isEmpty && !_devicesService.loading
                        ? const _EmptyDevicesState()
                        : ListView.separated(
                            itemCount: devices.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final device = devices[index];
                              return _DeviceCard(
                                device: device,
                                duplicateCount: _duplicateGroupSize(
                                  _devicesService.devices,
                                  device,
                                ),
                                loading: _devicesService.loading,
                                onEditAlias: () => _editAlias(device),
                                onDelete: () => _deleteDevice(device),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.duplicateCount,
    required this.loading,
    required this.onEditAlias,
    required this.onDelete,
  });

  final HomeAssistantDevice device;
  final int duplicateCount;
  final bool loading;
  final VoidCallback onEditAlias;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xAA07111B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF17324C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  device.alias.trim().isNotEmpty
                      ? device.alias
                      : device.friendlyName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _DeviceBadge(
                label: device.domain,
                color: const Color(0xFF42D9FF),
              ),
              if (duplicateCount > 1) ...[
                const SizedBox(width: 8),
                _DeviceBadge(
                  label: 'Possivel duplicado ($duplicateCount)',
                  color: const Color(0xFFFFCC80),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Nome original: ${device.friendlyName}',
            style: TextStyle(color: Colors.white.withOpacity(0.7)),
          ),
          const SizedBox(height: 4),
          Text(
            'Entity ID: ${device.entityId}',
            style: TextStyle(color: Colors.white.withOpacity(0.6)),
          ),
          const SizedBox(height: 4),
          Text(
            'Estado atual: ${device.state}',
            style: TextStyle(color: Colors.white.withOpacity(0.6)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DeviceBadge(
                label: device.alias.trim().isNotEmpty
                    ? 'Alias: ${device.alias}'
                    : 'Sem alias',
                color: device.alias.trim().isNotEmpty
                    ? const Color(0xFF4CE7A7)
                    : const Color(0xFFFFCC80),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: loading ? null : onEditAlias,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar alias'),
          ),
          TextButton.icon(
            onPressed: loading ? null : onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Remover'),
          ),
        ],
      ),
    );
  }
}

class _DeviceBadge extends StatelessWidget {
  const _DeviceBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _EmptyDevicesState extends StatelessWidget {
  const _EmptyDevicesState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(
                Icons.devices_other_rounded,
                size: 46,
                color: Colors.white.withOpacity(0.36),
              ),
              const SizedBox(height: 14),
              const Text(
                'Ainda nao existem dispositivos sincronizados.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sincroniza os dispositivos do Home Assistant para poderes gerir aliases e ensinar o assistente a reconhece-los.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.66),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
