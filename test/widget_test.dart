import 'package:flutter_test/flutter_test.dart';
import 'package:live_manager/data/repositories/live_photo_repository.dart';
import 'package:live_manager/domain/models/live_photo.dart';
import 'package:live_manager/main.dart';

class _FakeRepository implements LivePhotoRepository {
  @override
  Future<List<LivePhoto>> scan() async {
    return [
      LivePhoto(
        imageId: 1,
        videoId: 2,
        imageUri: 'content://media/external/images/media/1',
        videoUri: 'content://media/external/video/media/2',
        displayName: 'IMG_TEST_0001',
        createTime: DateTime(2026, 8, 1),
        imageSize: 1000,
        videoSize: 2000,
        videoDurationMs: 1500,
      ),
      LivePhoto(
        imageId: 3,
        videoId: 4,
        imageUri: 'content://media/external/images/media/3',
        videoUri: 'content://media/external/video/media/4',
        displayName: 'IMG_TEST_0002',
        createTime: DateTime(2026, 8, 2),
        imageSize: 2000,
        videoSize: 3000,
        videoDurationMs: 1800,
      ),
    ];
  }

  @override
  Future<String> thumbnailPathFor(LivePhoto item) async {
    return '/nonexistent/${item.imageId}.jpg';
  }
}

void main() {
  testWidgets('首页展示 Live 图片数量与网格', (WidgetTester tester) async {
    await tester.pumpWidget(LiveManagerApp(repository: _FakeRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Live Manager'), findsOneWidget);
    expect(find.text('共 2 张 Live 图片'), findsOneWidget);
    expect(find.text('LIVE'), findsNWidgets(2));
  });
}
