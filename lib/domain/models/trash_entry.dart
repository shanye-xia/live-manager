/// 应用回收站条目。
class TrashEntry {
  const TrashEntry({
    required this.id,
    required this.originalFileName,
    required this.originalRelativePath,
    required this.mediaType,
    required this.size,
    required this.dateTaken,
    required this.trashedAt,
  });

  final String id;
  final String originalFileName;
  final String originalRelativePath;
  final String mediaType;
  final int size;
  final DateTime dateTaken;
  final DateTime trashedAt;

  factory TrashEntry.fromJson(Map<String, dynamic> json) {
    return TrashEntry(
      id: json['id'] as String,
      originalFileName: json['originalFileName'] as String,
      originalRelativePath: json['originalRelativePath'] as String? ?? '',
      mediaType: json['mediaType'] as String? ?? 'video',
      size: json['size'] as int? ?? 0,
      dateTaken: DateTime.fromMillisecondsSinceEpoch(
          json['dateTaken'] as int? ?? 0),
      trashedAt: DateTime.fromMillisecondsSinceEpoch(
          json['trashedAt'] as int? ?? 0),
    );
  }
}
