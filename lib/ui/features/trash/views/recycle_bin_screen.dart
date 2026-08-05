import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../data/repositories/live_photo_repository.dart';
import '../../../../domain/models/trash_entry.dart';
import '../../../core/formatters.dart';
import 'trash_detail_screen.dart';

/// 应用回收站：缩略图列表，点击查看大图并可恢复/彻底删除。
class RecycleBinScreen extends StatefulWidget {
  const RecycleBinScreen({
    super.key,
    required this.repository,
    this.onRestored,
  });

  final LivePhotoRepository repository;
  final void Function(Map<String, dynamic> info)? onRestored;

  @override
  State<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends State<RecycleBinScreen> {
  List<TrashEntry>? _entries;
  String? _error;
  final Map<String, Future<String>> _previews = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _entries = null;
      _error = null;
    });
    try {
      final entries = await widget.repository.trashEntries();
      if (!mounted) return;
      setState(() => _entries = entries);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  /// 原地更新：从列表移除该条目（不重新加载、不重置滚动）。
  void _removeEntry(String id) {
    final entries = _entries;
    if (entries == null) return;
    setState(() {
      _entries = entries.where((e) => e.id != id).toList();
    });
  }

  Future<String> _previewPath(TrashEntry entry) {
    return _previews.putIfAbsent(
      entry.id,
      () => widget.repository.trashPreviewPath(entry, size: 256),
    );
  }

  Future<void> _openDetail(TrashEntry entry) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => TrashDetailScreen(
          entry: entry,
          repository: widget.repository,
          onRestored: widget.onRestored,
        ),
      ),
    );
    if (!mounted || result == null) return;
    if (result == 'restored') {
      _removeEntry(entry.id);
      _showSnack('已恢复：${entry.originalFileName}');
    } else if (result == 'deleted') {
      _removeEntry(entry.id);
      _showSnack('已彻底删除');
    }
  }

  Future<void> _restore(TrashEntry entry) async {
    final info = await widget.repository.restoreTrash(entry.id);
    if (!mounted) return;
    if (info != null) {
      widget.onRestored?.call(info);
      _removeEntry(entry.id);
      _showSnack('已恢复：${entry.originalFileName}');
    } else {
      _showSnack('恢复失败');
    }
  }

  Future<void> _confirmPermanentDelete(TrashEntry entry) async {
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

    final ok = await widget.repository.permanentDeleteTrash(entry.id);
    if (!mounted) return;
    if (ok) {
      _removeEntry(entry.id);
      _showSnack('已彻底删除');
    } else {
      _showSnack('删除失败');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站'),
        centerTitle: false,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Text('加载失败\n$_error', textAlign: TextAlign.center),
      );
    }
    final entries = _entries;
    if (entries == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (entries.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, size: 56, color: Colors.grey),
            SizedBox(height: 16),
            Text('回收站为空'),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          return ListTile(
            leading: _TrashThumbnail(
              future: _previewPath(entry),
              mediaType: entry.mediaType,
            ),
            title: Text(
              entry.originalFileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${formatDateTime(entry.trashedAt)} · ${formatBytes(entry.size)}',
            ),
            onTap: () => _openDetail(entry),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '恢复',
                  onPressed: () => _restore(entry),
                  icon: const Icon(Icons.restore, color: Colors.green),
                ),
                IconButton(
                  tooltip: '彻底删除',
                  onPressed: () => _confirmPermanentDelete(entry),
                  icon: const Icon(Icons.delete_forever_outlined,
                      color: Colors.redAccent),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TrashThumbnail extends StatelessWidget {
  const _TrashThumbnail({required this.future, required this.mediaType});

  final Future<String> future;
  final String mediaType;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 56,
        height: 56,
        child: FutureBuilder<String>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data!.isNotEmpty) {
              return Image.file(
                File(snapshot.data!),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _icon(context),
              );
            }
            return _icon(context);
          },
        ),
      ),
    );
  }

  Widget _icon(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        mediaType == 'video' ? Icons.movie_outlined : Icons.photo_outlined,
      ),
    );
  }
}
