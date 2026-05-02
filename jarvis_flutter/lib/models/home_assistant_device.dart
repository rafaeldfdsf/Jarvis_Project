class HomeAssistantDevice {
  const HomeAssistantDevice({
    required this.entityId,
    required this.domain,
    required this.friendlyName,
    required this.alias,
    required this.state,
    required this.attributes,
    required this.lastSeenAt,
    required this.updatedAt,
  });

  final String entityId;
  final String domain;
  final String friendlyName;
  final String alias;
  final String state;
  final Map<String, dynamic> attributes;
  final String lastSeenAt;
  final String updatedAt;

  factory HomeAssistantDevice.fromJson(Map<String, dynamic> json) {
    final rawAttributes = json['attributes'];
    return HomeAssistantDevice(
      entityId: json['entity_id']?.toString() ?? '',
      domain: json['domain']?.toString() ?? '',
      friendlyName: json['friendly_name']?.toString() ?? '',
      alias: json['alias']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      attributes: rawAttributes is Map<String, dynamic>
          ? rawAttributes
          : const <String, dynamic>{},
      lastSeenAt: json['last_seen_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
    );
  }
}
