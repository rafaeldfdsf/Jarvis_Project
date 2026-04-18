class ActivityHistoryEntry {
  const ActivityHistoryEntry({
    required this.id,
    required this.category,
    required this.status,
    required this.title,
    required this.detail,
    required this.origin,
    required this.timestamp,
    this.target,
    this.source,
  });

  final String id;
  final String category;
  final String status;
  final String title;
  final String detail;
  final String origin;
  final DateTime timestamp;
  final String? target;
  final String? source;

  factory ActivityHistoryEntry.fromJson(Map<String, dynamic> json) {
    return ActivityHistoryEntry(
      id: json['id']?.toString() ?? '',
      category: json['category']?.toString() ?? 'system',
      status: json['status']?.toString() ?? 'info',
      title: json['title']?.toString() ?? '',
      detail: json['detail']?.toString() ?? '',
      origin: json['origin']?.toString() ?? 'app',
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.now(),
      target: json['target']?.toString(),
      source: json['source']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category': category,
      'status': status,
      'title': title,
      'detail': detail,
      'origin': origin,
      'timestamp': timestamp.toIso8601String(),
      'target': target,
      'source': source,
    };
  }
}
