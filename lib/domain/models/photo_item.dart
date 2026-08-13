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
    this.liveProtocol = 'NONE',
    bool? canPlayLiveVideo,
    bool? canDeleteLivePart,
  }) : canPlayLiveVideo =
           canPlayLiveVideo ??
           ((liveProtocol == 'GOOGLE_MOTION_PHOTO' && isLive) ||
               videoUri != null),
       canDeleteLivePart = canDeleteLivePart ?? videoUri != null;

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
  final String liveProtocol;
  final bool canPlayLiveVideo;
  final bool canDeleteLivePart;

  bool get isGoogleMotionPhoto => liveProtocol == 'GOOGLE_MOTION_PHOTO';

  int get totalSize => imageSize + (videoSize ?? 0);

  PhotoItem copyWith({
    int? imageId,
    String? imageUri,
    String? displayName,
    DateTime? createTime,
    int? imageSize,
    String? relativePath,
    int? videoId,
    String? videoUri,
    int? videoSize,
    int? videoDurationMs,
    bool? isLive,
    String? liveProtocol,
    bool? canPlayLiveVideo,
    bool? canDeleteLivePart,
  }) {
    return PhotoItem(
      imageId: imageId ?? this.imageId,
      imageUri: imageUri ?? this.imageUri,
      displayName: displayName ?? this.displayName,
      createTime: createTime ?? this.createTime,
      imageSize: imageSize ?? this.imageSize,
      relativePath: relativePath ?? this.relativePath,
      videoId: videoId ?? this.videoId,
      videoUri: videoUri ?? this.videoUri,
      videoSize: videoSize ?? this.videoSize,
      videoDurationMs: videoDurationMs ?? this.videoDurationMs,
      isLive: isLive ?? this.isLive,
      liveProtocol: liveProtocol ?? this.liveProtocol,
      canPlayLiveVideo: canPlayLiveVideo ?? this.canPlayLiveVideo,
      canDeleteLivePart: canDeleteLivePart ?? this.canDeleteLivePart,
    );
  }

  factory PhotoItem.fromJson(Map<String, dynamic> json) {
    final isLive = json['isLive'] as bool? ?? false;
    final liveProtocol = json['liveProtocol'] as String? ?? 'NONE';
    return PhotoItem(
      imageId: json['imageId'] as int,
      imageUri: json['imageUri'] as String,
      displayName: json['displayName'] as String,
      createTime: DateTime.fromMillisecondsSinceEpoch(
        json['createTime'] as int,
      ),
      imageSize: json['imageSize'] as int,
      relativePath: json['relativePath'] as String? ?? '',
      videoId: json['videoId'] as int?,
      videoUri: json['videoUri'] as String?,
      videoSize: json['videoSize'] as int?,
      videoDurationMs: json['videoDurationMs'] as int?,
      isLive: isLive,
      liveProtocol: liveProtocol,
      canPlayLiveVideo:
          (json['canPlayLiveVideo'] as bool?) ??
          (((liveProtocol == 'GOOGLE_MOTION_PHOTO' ||
                      (json['displayName'] as String).toLowerCase().contains(
                        '.mp.',
                      )) &&
                  isLive) ||
              json['videoUri'] != null),
      canDeleteLivePart:
          (json['canDeleteLivePart'] as bool?) ?? (json['videoUri'] != null),
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
      'liveProtocol': liveProtocol,
      'canPlayLiveVideo': canPlayLiveVideo,
      'canDeleteLivePart': canDeleteLivePart,
    };
  }
}
