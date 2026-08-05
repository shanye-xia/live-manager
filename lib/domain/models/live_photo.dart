/// 一条配对的 Live Photo（JPG 静态图 + MP4 动态视频）。
class LivePhoto {
  const LivePhoto({
    required this.imageId,
    required this.videoId,
    required this.imageUri,
    required this.videoUri,
    required this.displayName,
    required this.createTime,
    required this.imageSize,
    required this.videoSize,
    required this.videoDurationMs,
  });

  final int imageId;
  final int videoId;
  final String imageUri;
  final String videoUri;
  final String displayName;
  final DateTime createTime;
  final int imageSize;
  final int videoSize;
  final int videoDurationMs;

  int get totalSize => imageSize + videoSize;

  factory LivePhoto.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'imageId': int imageId,
        'videoId': int videoId,
        'imageUri': String imageUri,
        'videoUri': String videoUri,
        'displayName': String displayName,
        'createTime': int createTime,
        'imageSize': int imageSize,
        'videoSize': int videoSize,
        'videoDurationMs': int videoDurationMs,
      } =>
        LivePhoto(
          imageId: imageId,
          videoId: videoId,
          imageUri: imageUri,
          videoUri: videoUri,
          displayName: displayName,
          createTime: DateTime.fromMillisecondsSinceEpoch(createTime),
          imageSize: imageSize,
          videoSize: videoSize,
          videoDurationMs: videoDurationMs,
        ),
      _ => throw const FormatException('LivePhoto JSON 字段缺失或类型不匹配'),
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'imageId': imageId,
      'videoId': videoId,
      'imageUri': imageUri,
      'videoUri': videoUri,
      'displayName': displayName,
      'createTime': createTime.millisecondsSinceEpoch,
      'imageSize': imageSize,
      'videoSize': videoSize,
      'videoDurationMs': videoDurationMs,
    };
  }
}
