class MemoryEntry {
  const MemoryEntry({
    required this.key,
    required this.value,
    required this.type,
    required this.label,
    this.index,
  });

  final String key;
  final String value;
  final String type;
  final String label;
  final int? index;

  factory MemoryEntry.fromJson(Map<String, dynamic> json) {
    return MemoryEntry(
      key: json['key'] as String? ?? '',
      value: json['value'] as String? ?? '',
      type: json['type'] as String? ?? 'fact',
      label: json['label'] as String? ?? '',
      index: json['index'] as int?,
    );
  }
}
