import 'package:flutter_test/flutter_test.dart';
import 'package:live_manager/data/repositories/live_photo_repository.dart';
import 'package:live_manager/domain/models/photo_item.dart';
import 'package:live_manager/domain/models/trash_entry.dart';
import 'package:live_manager/ui/features/home/view_models/home_view_model.dart';

class _FakeRepository implements LivePhotoRepository {
  _FakeRepository();

  int deleteCalls = 0;
  bool failImageDelete = false;

  final List<PhotoItem> _items = [
    PhotoItem(
      imageId: 1,
      imageUri: 'content://media/external/images/media/1',
      displayName: 'A.jpg',
      createTime: DateTime(2026, 8, 6, 10),
      imageSize: 1000,
      relativePath: 'DCIM/Camera/',
      videoId: 2,
      videoUri: 'content://media/external/video/media/2',
      videoSize: 2000,
      videoDurationMs: 1500,
      isLive: true,
    ),
    PhotoItem(
      imageId: 3,
      imageUri: 'content://media/external/images/media/3',
      displayName: 'B.jpg',
      createTime: DateTime(2026, 8, 5, 9),
      imageSize: 2000,
      relativePath: 'DCIM/Camera/',
      isLive: false,
    ),
    PhotoItem(
      imageId: 5,
      imageUri: 'content://media/external/images/media/5',
      displayName: 'C.jpg',
      createTime: DateTime(2026, 7, 1, 8),
      imageSize: 3000,
      relativePath: 'Pictures/WeiXin/',
      isLive: false,
    ),
  ];

  @override
  Future<List<PhotoItem>> scan() async => _items;

  @override
  Future<String> thumbnailPathFor(PhotoItem item) async =>
      '/fake/${item.imageId}.jpg';

  @override
  Future<String> fullImagePathFor(PhotoItem item) async =>
      '/fake/${item.imageId}_full.jpg';

  @override
  Future<String> videoFilePathFor(PhotoItem item) async =>
      '/fake/${item.videoId}.mp4';

  @override
  Future<Map<String, dynamic>> exifFor(PhotoItem item) async => const {};

  @override
  Future<Map<String, dynamic>> moveToTrash(
    PhotoItem item, {
    required bool deleteVideo,
  }) async {
    deleteCalls++;
    if (!deleteVideo && failImageDelete) {
      return const {'status': 'failed'};
    }
    return const {'status': 'ok'};
  }

  @override
  Future<bool> hasAllFilesAccess() async => true;

  @override
  Future<void> openAllFilesAccessSettings() async {}

  @override
  Future<List<TrashEntry>> trashEntries() async => const [];

  @override
  Future<String> trashPreviewPath(TrashEntry entry, {int size = 512}) async =>
      '/fake/trash.jpg';

  @override
  Future<Map<String, dynamic>?> restoreTrash(String id) async => null;

  @override
  Future<bool> permanentDeleteTrash(String id) async => true;

  @override
  Stream<Map<String, dynamic>> events() => const Stream.empty();
}

void main() {
  group('HomeViewModel 长按多选', () {
    test('长按进入多选并切换选中，退出清空', () async {
      final vm = HomeViewModel(repository: _FakeRepository());
      await vm.load();

      expect(vm.selectionMode, isFalse);
      vm.enterSelectionMode(vm.items.first);
      expect(vm.selectionMode, isTrue);
      expect(vm.selectedCount, 1);
      expect(vm.selectedIds, contains(vm.items.first.imageId));

      vm.toggleSelection(vm.items[1]);
      expect(vm.selectedCount, 2);
      vm.toggleSelection(vm.items.first);
      expect(vm.selectedCount, 1);

      vm.exitSelectionMode();
      expect(vm.selectionMode, isFalse);
      expect(vm.selectedCount, 0);
    });

    test('全选/取消全选作用于全部照片', () async {
      final vm = HomeViewModel(repository: _FakeRepository());
      await vm.load();
      vm.enterSelectionMode(vm.items.first);

      vm.toggleSelectAllVisible(vm.items);
      expect(vm.selectedCount, 3);
      expect(vm.allVisibleSelected(vm.items), isTrue);

      vm.toggleSelectAllVisible(vm.items);
      expect(vm.selectedCount, 0);
    });
  });

  group('HomeViewModel 批量删除', () {
    test('批量删除成功：Live 先视频后图片，条目移除且选择清空', () async {
      final fake = _FakeRepository();
      final vm = HomeViewModel(repository: fake);
      await vm.load();
      vm.enterSelectionMode(vm.items.first);
      vm.toggleSelection(vm.items[1]);

      final result = await vm.deleteSelected();
      expect(result.deleted, 2);
      expect(result.failed, 0);
      expect(fake.deleteCalls, 3); // Live 视频+图片，普通图片
      expect(vm.items, hasLength(1));
      expect(vm.selectionMode, isFalse);
      expect(vm.selectedCount, 0);
    });

    test('图片删除失败：Live 降级为非 Live（仅删动态）', () async {
      final fake = _FakeRepository()..failImageDelete = true;
      final vm = HomeViewModel(repository: fake);
      await vm.load();
      vm.enterSelectionMode(vm.items.first);

      final result = await vm.deleteSelected();
      expect(result.deleted, 0);
      expect(result.videoOnly, 1);
      expect(vm.items, hasLength(3));
      expect(vm.items.first.isLive, isFalse);
      expect(vm.items.first.videoId, isNull);
    });
  });

  group('HomeViewModel 滑动多选与 Live 计数', () {
    test('滑动设置选中/取消并维护 Live 计数', () async {
      final vm = HomeViewModel(repository: _FakeRepository());
      await vm.load();
      vm.enterSelectionMode(vm.items.first); // Live
      expect(vm.selectedLiveCount, 1);

      vm.setSelection(vm.items[1], selected: true); // 普通
      expect(vm.selectedCount, 2);
      expect(vm.selectedLiveCount, 1);

      vm.setSelection(vm.items.first, selected: false);
      expect(vm.selectedCount, 1);
      expect(vm.selectedLiveCount, 0);

      // 无变化调用不影响状态
      vm.setSelection(vm.items[1], selected: true);
      expect(vm.selectedCount, 1);
      expect(vm.selectedLiveCount, 0);
    });

    test('全选时 Live 计数正确，退出清零', () async {
      final vm = HomeViewModel(repository: _FakeRepository());
      await vm.load();
      vm.enterSelectionMode(vm.items.first);
      vm.toggleSelectAllVisible(vm.items);
      expect(vm.selectedLiveCount, 1);
      vm.toggleSelectAllVisible(vm.items);
      expect(vm.selectedLiveCount, 0);
      vm.exitSelectionMode();
      expect(vm.selectedLiveCount, 0);
    });
  });

  group('HomeViewModel 批量仅删 Live 动态', () {
    test('只删选中 Live 的视频，照片降级为非 Live', () async {
      final fake = _FakeRepository();
      final vm = HomeViewModel(repository: fake);
      await vm.load();
      vm.enterSelectionMode(vm.items.first);
      vm.setSelection(vm.items[1], selected: true);

      final result = await vm.deleteLiveParts();
      expect(result.videoOnly, 1);
      expect(result.deleted, 0);
      expect(result.failed, 0);
      expect(fake.deleteCalls, 1);
      expect(vm.items, hasLength(3));
      expect(vm.items.first.isLive, isFalse);
      expect(vm.items.first.videoId, isNull);
      expect(vm.selectionMode, isFalse);
      expect(vm.selectedCount, 0);
      expect(vm.selectedLiveCount, 0);
    });
  });
}
