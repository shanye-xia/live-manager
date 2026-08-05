import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../data/repositories/live_photo_repository.dart';
import '../../../../domain/models/live_photo.dart';
import '../../../core/formatters.dart';
import '../view_models/detail_view_model.dart';

/// 详情页：完整大图 + 长按播放动态效果 + 文件信息与 EXIF。
class DetailScreen extends StatefulWidget {
  const DetailScreen({
    super.key,
    required this.item,
    required this.repository,
    this.thumbnailPath,
    this.thumbnailFuture,
  });

  final LivePhoto item;
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
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.item.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          return Column(
            children: [
              Expanded(child: _buildViewer()),
              _buildInfoPanel(context),
            ],
          );
        },
      ),
    );
  }

  Widget _buildViewer() {
    if (_viewModel.loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
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
      onLongPressStart: (_) => _viewModel.startPlayback(),
      onLongPressEnd: (_) => _viewModel.stopPlayback(),
      onLongPressCancel: _viewModel.stopPlayback,
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
              right: 12,
              child: _LoadingOriginalChip(),
            ),
          if (_viewModel.fullImageError != null)
            const Positioned(
              top: 12,
              right: 12,
              child: _LoadOriginalFailedChip(),
            ),
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.touch_app_outlined,
                        size: 16, color: Colors.white70),
                    SizedBox(width: 6),
                    Text(
                      '长按图片播放动态效果',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPanel(BuildContext context) {
    final item = widget.item;
    final rows = <(String, String)>[
      ('文件名', item.displayName),
      ('拍摄时间', formatDateTime(item.createTime)),
      ('照片', formatBytes(item.imageSize)),
      ('动态', formatBytes(item.videoSize)),
      ('总计', formatBytes(item.totalSize)),
    ];
    if (_viewModel.exif != null) {
      rows.addAll(formatExif(_viewModel.exif!));
    }

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 320),
      color: const Color(0xFF111111),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '信息与 EXIF',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white70,
                  ),
            ),
            const SizedBox(height: 8),
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
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                ),
                onPressed: _viewModel.deleting ? null : _confirmDelete,
                icon: _viewModel.deleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.redAccent,
                        ),
                      )
                    : const Icon(Icons.delete_outline),
                label: Text(_viewModel.deleting ? '删除中…' : '删除动态视频'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除动态视频？'),
        content: const Text(
          '将删除对应的 MP4 动态视频（进入系统回收站，可恢复），'
          'JPG 静态照片会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已删除动态视频（可在系统回收站恢复）')),
      );
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已取消，未删除任何文件')),
      );
    }
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
