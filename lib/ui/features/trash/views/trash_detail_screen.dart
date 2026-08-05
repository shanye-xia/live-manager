import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../data/repositories/live_photo_repository.dart';
import '../../../../domain/models/trash_entry.dart';

/// 回收站条目详情：查看大图，可选择恢复或彻底删除。
class TrashDetailScreen extends StatefulWidget {
  const TrashDetailScreen({
    super.key,
    required this.entry,
    required this.repository,
  });

  final TrashEntry entry;
  final LivePhotoRepository repository;

  @override
  State<TrashDetailScreen> createState() => _TrashDetailScreenState();
}

class _TrashDetailScreenState extends State<TrashDetailScreen> {
  bool _busy = false;

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await widget.repository.restoreTrash(widget.entry.id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop('restored');
    } else {
      setState(() => _busy = false);
      _showSnack('恢复失败');
    }
  }

  Future<void> _permanentDelete() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('彻底删除？'),
        content: const Text('此操作不可恢复，文件将从回收站永久删除。'),
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
            child: const Text('彻底删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final ok = await widget.repository.permanentDeleteTrash(widget.entry.id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop('deleted');
    } else {
      setState(() => _busy = false);
      _showSnack('删除失败');
    }
  }

  void _showSnack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(
              child: FutureBuilder<String>(
                future: widget.repository.trashPreviewPath(
                  widget.entry,
                  size: 2048,
                ),
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                    return Center(
                      child: Image.file(
                        File(snapshot.data!),
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Center(
                          child: Text(
                            '无法显示预览',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      ),
                    );
                  }
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                },
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white70),
                    ),
                    Expanded(
                      child: Text(
                        widget.entry.originalFileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 15),
                      ),
                    ),
                    IconButton(
                      tooltip: '恢复',
                      onPressed: _busy ? null : _restore,
                      icon: const Icon(Icons.restore, color: Colors.green),
                    ),
                    IconButton(
                      tooltip: '彻底删除',
                      onPressed: _busy ? null : _permanentDelete,
                      icon: const Icon(Icons.delete_forever_outlined,
                          color: Colors.redAccent),
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
