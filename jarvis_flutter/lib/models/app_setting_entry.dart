class AppSettingEntry {
  const AppSettingEntry({
    required this.key,
    required this.value,
    required this.label,
    this.updatedAt = '',
  });

  final String key;
  final String value;
  final String label;
  final String updatedAt;

  factory AppSettingEntry.fromJson(Map<String, dynamic> json) {
    return AppSettingEntry(
      key: json['key']?.toString() ?? '',
      value: json['value']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
    );
  }
}
