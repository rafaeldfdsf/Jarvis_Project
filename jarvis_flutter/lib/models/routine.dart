class RoutineAction {
  const RoutineAction({
    required this.type,
    this.label,
    this.domain,
    this.service,
    this.entityId,
    this.target,
    this.message,
    this.text,
    this.serviceData,
  });

  final String type;
  final String? label;
  final String? domain;
  final String? service;
  final String? entityId;
  final String? target;
  final String? message;
  final String? text;
  final Map<String, dynamic>? serviceData;

  factory RoutineAction.fromJson(Map<String, dynamic> json) {
    final rawServiceData = json['service_data'];
    return RoutineAction(
      type: json['type']?.toString() ?? '',
      label: json['label']?.toString(),
      domain: json['domain']?.toString(),
      service: json['service']?.toString(),
      entityId: json['entity_id']?.toString(),
      target: json['target']?.toString(),
      message: json['message']?.toString(),
      text: json['text']?.toString(),
      serviceData: rawServiceData is Map<String, dynamic> ? rawServiceData : null,
    );
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{'type': type};
    void setIfNotBlank(String key, String? value) {
      if (value != null && value.trim().isNotEmpty) {
        data[key] = value.trim();
      }
    }

    setIfNotBlank('label', label);
    setIfNotBlank('domain', domain);
    setIfNotBlank('service', service);
    setIfNotBlank('entity_id', entityId);
    setIfNotBlank('target', target);
    setIfNotBlank('message', message);
    setIfNotBlank('text', text);
    if (serviceData != null && serviceData!.isNotEmpty) {
      data['service_data'] = serviceData;
    }
    return data;
  }
}

class Routine {
  const Routine({
    required this.id,
    required this.name,
    required this.description,
    required this.triggerText,
    required this.actions,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String description;
  final String triggerText;
  final List<RoutineAction> actions;
  final bool enabled;
  final String createdAt;
  final String updatedAt;

  factory Routine.fromJson(Map<String, dynamic> json) {
    final rawActions = json['actions'];
    final actions = rawActions is List
        ? rawActions
              .whereType<Map<String, dynamic>>()
              .map(RoutineAction.fromJson)
              .toList()
        : <RoutineAction>[];

    return Routine(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      triggerText: json['trigger_text']?.toString() ?? '',
      actions: actions,
      enabled: json['enabled'] == true,
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
    );
  }
}

class HomeAssistantStatus {
  const HomeAssistantStatus({
    required this.enabled,
    required this.configured,
    required this.connected,
    required this.url,
    required this.locationName,
    required this.entityCount,
    required this.message,
  });

  final bool enabled;
  final bool configured;
  final bool connected;
  final String url;
  final String? locationName;
  final int entityCount;
  final String message;

  factory HomeAssistantStatus.fromJson(Map<String, dynamic> json) {
    return HomeAssistantStatus(
      enabled: json['enabled'] != false,
      configured: json['configured'] == true,
      connected: json['connected'] == true,
      url: json['url']?.toString() ?? '',
      locationName: json['location_name']?.toString(),
      entityCount: (json['entity_count'] as num?)?.toInt() ?? 0,
      message: json['message']?.toString() ?? '',
    );
  }
}
