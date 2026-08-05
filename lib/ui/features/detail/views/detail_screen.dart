import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../data/repositories/live_photo_repository.dart';
import '../../../../domain/models/live_photo.dart';
import '../../../core/formatters.dart';
import '../view_models/detail_view_model.dart';

enum _SheetResult { deleted, cancelled }

/// 详情页：相册风全屏大图 + 长按播放 + 角落信息按钮。
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
            tooltip: '删除动态视频',
            onPressed: _viewModel.deleting ? null : _deleteFromPage,
            icon: _viewModel.deleting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white70,
                    ),
                  )
                : const Icon(Icons.delete_outline_rounded,
                    color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFromPage() async {
    final success = await _viewModel.startDelete();
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('已删除动态视频'),
        ),
      );
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('已取消，未删除任何文件'),
        ),
      );
    }
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
              '动态 ${formatBytes(item.videoSize)} · '
              '总计 ${formatBytes(item.totalSize)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 2),
            const Text(
              '长按图片播放动态效果',
              style: TextStyle(color: Colors.white38, fontSize: 10),
            ),
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

  Future<void> _showInfoSheet() async {
    final result = await showModalBottomSheet<_SheetResult>(
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
    if (!mounted) return;

    switch (result) {
      case _SheetResult.deleted:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('已删除动态视频'),
          ),
        );
        Navigator.of(context).pop(true);
      case _SheetResult.cancelled:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('已取消，未删除任何文件'),
          ),
        );
      case null:
        break;
    }
  }
}

/// 详情面板：文件信息 + EXIF + 删除（从底部弹出）。
class _InfoSheet extends StatefulWidget {
  const _InfoSheet({required this.viewModel, required this.item});

  final DetailViewModel viewModel;
  final LivePhoto item;

  @override
  State<_InfoSheet> createState() => _InfoSheetState();
}

class _InfoSheetState extends State<_InfoSheet> {
  bool _deleting = false;

  Future<void> _delete() async {
    if (_deleting) return;
    setState(() => _deleting = true);
    final success = await widget.viewModel.startDelete();
    if (!mounted) return;
    Navigator.of(context).pop(
      success ? _SheetResult.deleted : _SheetResult.cancelled,
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final rows = <(String, String)>[
      ('文件名', item.displayName),
      ('拍摄时间', formatDateTime(item.createTime)),
      ('照片', formatBytes(item.imageSize)),
      ('动态', formatBytes(item.videoSize)),
      ('总计', formatBytes(item.totalSize)),
    ];
    final exif = widget.viewModel.exif;
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
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
              ),
              onPressed: _deleting ? null : _delete,
              icon: _deleting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.redAccent,
                      ),
                    )
                  : const Icon(Icons.delete_outline),
              label: Text(_deleting ? '删除中…' : '删除动态视频'),
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
