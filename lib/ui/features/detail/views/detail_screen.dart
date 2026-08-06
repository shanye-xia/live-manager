import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../data/repositories/live_photo_repository.dart';
import '../../../../domain/models/photo_item.dart';
import '../../../core/formatters.dart';
import '../view_models/detail_view_model.dart';

/// 详情页：相册式分页浏览（左右滑动切换）+ 长按播放 + 单击隐藏 UI。
/// Live 图删除时的两个选项。
enum _LiveDeleteAction { videoOnly, fullDelete }

class DetailScreen extends StatefulWidget {
  const DetailScreen({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.repository,
    required this.thumbnailLoader,
    required this.onDelete,
    this.thumbnailPath,
  });

  final List<PhotoItem> items;
  final int initialIndex;
  final LivePhotoRepository repository;
  final Future<String> Function(PhotoItem item) thumbnailLoader;
  final void Function(int imageId, bool videoOnly) onDelete;
  final String? thumbnailPath;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late final PageController _pageController;
  late List<PhotoItem> _items;
  bool _uiVisible = true;

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.items);
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: _items.length,
            itemBuilder: (context, index) {
              final item = _items[index];
              return _PhotoPage(
                key: ValueKey(item.imageId),
                item: item,
                repository: widget.repository,
                thumbnailPath:
                    index == widget.initialIndex ? widget.thumbnailPath : null,
                thumbnailFuture: widget.thumbnailLoader(item),
                uiVisible: _uiVisible,
                positionText: '${index + 1} / ${_items.length}',
                onToggleUi: () => setState(() => _uiVisible = !_uiVisible),
                onDeleted: (videoOnly) => _handleDeleted(index, videoOnly),
              );
            },
          ),
        ],
      ),
    );
  }

  void _handleDeleted(int index, bool videoOnly) {
    final item = _items[index];
    widget.onDelete(item.imageId, videoOnly);
    setState(() {
      if (videoOnly) {
        _items[index] = item.copyWith(
          isLive: false,
          videoId: null,
          videoUri: null,
          videoSize: null,
          videoDurationMs: null,
        );
      } else {
        _items.removeAt(index);
      }
    });
    if (!videoOnly && _items.isNotEmpty) {
      final target = index.clamp(0, _items.length - 1);
      _pageController.jumpToPage(target);
    }
    if (_items.isEmpty) {
      Navigator.of(context).maybePop();
    }
  }
}

class _PhotoPage extends StatefulWidget {
  const _PhotoPage({
    super.key,
    required this.item,
    required this.repository,
    this.thumbnailPath,
    this.thumbnailFuture,
    required this.uiVisible,
    required this.positionText,
    required this.onToggleUi,
    required this.onDeleted,
  });

  final PhotoItem item;
  final LivePhotoRepository repository;
  final String? thumbnailPath;
  final Future<String>? thumbnailFuture;
  final bool uiVisible;
  final String positionText;
  final VoidCallback onToggleUi;
  final ValueChanged<bool> onDeleted;

  @override
  State<_PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends State<_PhotoPage> {
  late final DetailViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = DetailViewModel(
      item: widget.item,
      repository: widget.repository,
      thumbnailPath: widget.thumbnailPath,
      thumbnailFuture: widget.thumbnailFuture,
    )..init();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            _buildViewer(),
            AnimatedOpacity(
              opacity: widget.uiVisible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !widget.uiVisible,
                child: _buildOverlay(context),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildViewer() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onToggleUi,
      onLongPressStart: widget.item.isLive
          ? (_) => _viewModel.startPlayback()
          : null,
      onLongPressEnd: widget.item.isLive
          ? (_) => _viewModel.stopPlayback()
          : null,
      onLongPressCancel: widget.item.isLive ? _viewModel.stopPlayback : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_viewModel.loading)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          else if (_viewModel.imagePath == null)
            Center(
              child: Text(
                '图片加载失败\n${_viewModel.error ?? ''}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            )
          else
            Center(
              child: Image.file(
                File(_viewModel.imagePath!),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Text(
                  '无法显示图片',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          if (_viewModel.isPlaying && _viewModel.videoReady)
            Center(
              child: AspectRatio(
                aspectRatio: _viewModel.controller!.value.aspectRatio,
                child: VideoPlayer(_viewModel.controller!),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final item = widget.item;
    return Stack(
      children: [
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Column(
              children: [
                _GlassPanel(
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white70),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              widget.positionText,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '详情',
                        onPressed: _showInfoSheet,
                        icon: const Icon(Icons.info_outline_rounded,
                            color: Colors.white70),
                      ),
                      IconButton(
                        tooltip: item.isLive ? '删除' : '删除照片',
                        onPressed: _confirmDelete,
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: Colors.redAccent),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                _GlassPanel(
                  child: Text(
                    '照片 ${formatBytes(item.imageSize)}'
                    '${item.isLive ? ' · 动态 ${formatBytes(item.videoSize ?? 0)}' : ''}'
                    ' · 总计 ${formatBytes(item.totalSize)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (widget.item.isLive) ...[
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: _LiveBadgeSmall(),
                  ),
                ],
                if (!_viewModel.fullImageReady &&
                    _viewModel.fullImageError == null) ...[
                  const SizedBox(height: 6),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: _LoadingOriginalChip(),
                  ),
                ],
                if (_viewModel.fullImageError != null) ...[
                  const SizedBox(height: 6),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: _LoadOriginalFailedChip(),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (item.isLive)
          Positioned(
            bottom: 18,
            left: 0,
            right: 0,
            child: Center(
              child: _GlassPanel(
                child: const Text(
                  '长按图片播放动态效果',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmDelete() async {
    final item = widget.item;
    if (item.isLive) {
      final action = await _showLiveDeleteSheet();
      if (action == null || !mounted) return;
      final videoOnly = action == _LiveDeleteAction.videoOnly;
      final outcome = await _viewModel.startDelete(videoOnly: videoOnly);
      if (!mounted) return;
      switch (outcome) {
        case DeleteOutcome.done:
          _showSnack('已删除');
          widget.onDeleted(videoOnly);
        case DeleteOutcome.videoOnly:
          _showSnack('动态已删除，照片删除失败，已保留为普通照片');
          widget.onDeleted(true);
        case DeleteOutcome.needPermission:
          await _promptAllFilesAccess();
        case DeleteOutcome.failed:
          break;
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除照片？'),
        content: const Text('将把照片移入应用回收站。'),
        actions: [
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final outcome = await _viewModel.startDelete(videoOnly: true);
    if (!mounted) return;
    switch (outcome) {
      case DeleteOutcome.done:
        _showSnack('已删除');
        widget.onDeleted(false);
      case DeleteOutcome.videoOnly:
        _showSnack('已删除');
        widget.onDeleted(false);
      case DeleteOutcome.needPermission:
        await _promptAllFilesAccess();
      case DeleteOutcome.failed:
        break;
    }
  }

  /// Live 图删除底部面板：仅删除动态 / 全部删除。
  Future<_LiveDeleteAction?> _showLiveDeleteSheet() {
    final item = widget.item;
    return showModalBottomSheet<_LiveDeleteAction>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 2),
              child: Text(
                '删除动态视频',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'LIVE · 照片 ${formatBytes(item.imageSize)}'
                ' · 动态 ${formatBytes(item.videoSize ?? 0)}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
            const Divider(height: 1, color: Colors.white12),
            _DeleteOptionTile(
              icon: Icons.movie_outlined,
              title: '仅删除Live动态',
              subtitle: '照片保留，动态视频移入回收站',
              onTap: () =>
                  Navigator.of(context).pop(_LiveDeleteAction.videoOnly),
            ),
            _DeleteOptionTile(
              icon: Icons.delete_outline,
              title: '全部删除',
              subtitle: '照片和动态一起移入回收站',
              destructive: true,
              onTap: () =>
                  Navigator.of(context).pop(_LiveDeleteAction.fullDelete),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  '取消',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _promptAllFilesAccess() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('需要文件访问权限'),
        content: const Text(
          'Android 11+ 删除文件需要“所有文件访问”权限（只需开启一次），'
          '开启后删除将不再弹出系统确认框。',
        ),
        actions: [
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
    if (go == true) {
      await _viewModel.repository.openAllFilesAccessSettings();
    }
  }

  void _showSnack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: messenger.hideCurrentSnackBar,
          child: Text(message),
        ),
      ),
    );
  }

  Future<void> _showInfoSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161616),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _InfoSheet(
        viewModel: _viewModel,
        item: widget.item,
      ),
    );
  }
}

class _LiveBadgeSmall extends StatelessWidget {
  const _LiveBadgeSmall();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'LIVE',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// 半透明灰色圆角面板，保证文字在图片上清晰可读。
class _DeleteOptionTile extends StatelessWidget {
  const _DeleteOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Colors.redAccent : Colors.white;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

/// 详情面板：文件信息 + EXIF（从底部弹出）。
class _InfoSheet extends StatelessWidget {
  const _InfoSheet({required this.viewModel, required this.item});

  final DetailViewModel viewModel;
  final PhotoItem item;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('文件名', item.displayName),
      ('拍摄时间', formatDateTime(item.createTime)),
      ('照片', formatBytes(item.imageSize)),
      if (item.isLive) ('动态', formatBytes(item.videoSize ?? 0)),
      ('总计', formatBytes(item.totalSize)),
    ];
    final exif = viewModel.exif;
    if (exif != null) {
      rows.addAll(formatExif(exif));
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '详情',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final (label, value) in rows)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 76,
                              child: Text(
                                label,
                                style: const TextStyle(color: Colors.white38),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                value,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingOriginalChip extends StatelessWidget {
  const _LoadingOriginalChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white70,
            ),
          ),
          SizedBox(width: 6),
          Text(
            '加载原图…',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _LoadOriginalFailedChip extends StatelessWidget {
  const _LoadOriginalFailedChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Text(
        '原图加载失败',
        style: TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }
}
