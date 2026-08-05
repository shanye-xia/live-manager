import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../data/repositories/live_photo_repository.dart';
import '../../../../domain/models/photo_item.dart';
import '../../../core/formatters.dart';
import '../view_models/detail_view_model.dart';

/// 详情页：相册风全屏大图 + 长按播放 + 信息/删除。
class DetailScreen extends StatefulWidget {
  const DetailScreen({
    super.key,
    required this.item,
    required this.repository,
    this.thumbnailPath,
    this.thumbnailFuture,
  });

  final PhotoItem item;
  final LivePhotoRepository repository;
  final String? thumbnailPath;
  final Future<String>? thumbnailFuture;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          return SizedBox.expand(
            child: Stack(
              children: [
                Positioned.fill(child: _buildViewer()),
                SafeArea(child: _buildTopBar()),
                Positioned(
                  bottom: 18,
                  left: 0,
                  right: 0,
                  child: _buildBottomStrip(context),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white70),
          ),
          Expanded(
            child: Text(
              widget.item.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ),
          IconButton(
            tooltip: '详情',
            onPressed: _showInfoSheet,
            icon: const Icon(
              Icons.info_outline_rounded,
              color: Colors.white70,
            ),
          ),
          IconButton(
            tooltip: widget.item.isLive ? '删除动态视频' : '删除照片',
            onPressed: _confirmDelete,
            icon: Icon(
              Icons.delete_outline_rounded,
              color: Colors.redAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomStrip(BuildContext context) {
    final item = widget.item;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '照片 ${formatBytes(item.imageSize)} · '
              '${item.isLive ? '动态 ${formatBytes(item.videoSize ?? 0)} · ' : ''}'
              '总计 ${formatBytes(item.totalSize)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            if (item.isLive) ...[
              const SizedBox(height: 2),
              const Text(
                '长按图片播放动态效果',
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildViewer() {
    if (_viewModel.loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    final path = _viewModel.imagePath;
    if (path == null || path.isEmpty) {
      return Center(
        child: Text(
          '图片加载失败\n${_viewModel.error ?? ''}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
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
          Center(
            child: Image.file(
              File(path),
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
          if (!_viewModel.fullImageReady &&
              _viewModel.fullImageError == null)
            const Positioned(
              top: 12,
              left: 12,
              child: _LoadingOriginalChip(),
            ),
          if (_viewModel.fullImageError != null)
            const Positioned(
              top: 12,
              left: 12,
              child: _LoadOriginalFailedChip(),
            ),
        ],
      ),
    );
  }

  /// 自定义确认弹窗：删除（红底）/ 取消（灰底），返回/点外部等同取消。
  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.item.isLive ? '删除动态视频？' : '删除照片？'),
        content: Text(
          widget.item.isLive
              ? '将把 MP4 动态视频移入应用回收站，JPG 照片保留。'
              : '将把照片移入应用回收站。',
        ),
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

    final success = await _viewModel.startDelete();
    if (!mounted) return;
    if (success) {
      _showDeletedSnackBar();
      Navigator.of(context).pop(true);
    }
    // 取消/失败不弹任何提示
  }

  /// “已删除”提示：点击即消失，多次删除快速覆盖。
  void _showDeletedSnackBar() {
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: messenger.hideCurrentSnackBar,
          child: const Text('已删除'),
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

/// 详情面板：文件信息 + EXIF + 删除（从底部弹出）。
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
