class RegisteredDevice {
  const RegisteredDevice({
    required this.deviceId,
    required this.name,
    required this.deviceType,
    required this.platform,
    required this.location,
    required this.isActive,
    required this.preferredForWakeWord,
    required this.preferredForTts,
    required this.preferredForDesktopControl,
    required this.connected,
    required this.lastSeenAt,
    required this.lastError,
    required this.capabilities,
  });

  final String deviceId;
  final String name;
  final String deviceType;
  final String platform;
  final String location;
  final bool isActive;
  final bool preferredForWakeWord;
  final bool preferredForTts;
  final bool preferredForDesktopControl;
  final bool connected;
  final String lastSeenAt;
  final String lastError;
  final List<String> capabilities;

  factory RegisteredDevice.fromJson(Map<String, dynamic> json) {
    final rawCapabilities = json['capabilities'];
    return RegisteredDevice(
      deviceId: json['device_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      deviceType: json['device_type']?.toString() ?? '',
      platform: json['platform']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      isActive: json['is_active'] == true,
      preferredForWakeWord: json['preferred_for_wake_word'] == true,
      preferredForTts: json['preferred_for_tts'] == true,
      preferredForDesktopControl: json['preferred_for_desktop_control'] == true,
      connected: json['connected'] == true,
      lastSeenAt: json['last_seen_at']?.toString() ?? '',
      lastError: json['last_error']?.toString() ?? '',
      capabilities: rawCapabilities is List
          ? rawCapabilities.map((item) => item.toString()).toList()
          : const <String>[],
    );
  }
}
