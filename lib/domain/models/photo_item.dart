/// 一张照片（可能是 Live Photo：附带可选动态视频）。
class PhotoItem {
  const PhotoItem({
    required this.imageId,
    required this.imageUri,
    required this.displayName,
    required this.createTime,
    required this.imageSize,
    required this.relativePath,
    this.videoId,
    this.videoUri,
    this.videoSize,
    this.videoDurationMs,
    required this.isLive,
  });

  final int imageId;
  final String imageUri;
  final String displayName;
  final DateTime createTime;
  final int imageSize;
  final String relativePath;
  final int? videoId;
  final String? videoUri;
  final int? videoSize;
  final int? videoDurationMs;
  final bool isLive;

  int get totalSize => imageSize + (videoSize ?? 0);

  factory PhotoItem.fromJson(Map<String, dynamic> json) {
    return PhotoItem(
      imageId: json['imageId'] as int,
      imageUri: json['imageUri'] as String,
      displayName: json['displayName'] as String,
      createTime:
          DateTime.fromMillisecondsSinceEpoch(json['createTime'] as int),
      imageSize: json['imageSize'] as int,
      relativePath: json['relativePath'] as String? ?? '',
      videoId: json['videoId'] as int?,
      videoUri: json['videoUri'] as String?,
      videoSize: json['videoSize'] as int?,
      videoDurationMs: json['videoDurationMs'] as int?,
      isLive: json['isLive'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'imageId': imageId,
      'imageUri': imageUri,
      'displayName': displayName,
      'createTime': createTime.millisecondsSinceEpoch,
      'imageSize': imageSize,
      'relativePath': relativePath,
      'videoId': videoId,
      'videoUri': videoUri,
      'videoSize': videoSize,
      'videoDurationMs': videoDurationMs,
      'isLive': isLive,
    };
  }
}
