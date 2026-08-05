import 'package:flutter/material.dart';

import '../../../../data/repositories/live_photo_repository.dart';
import '../../../../domain/models/trash_entry.dart';
import '../../../core/formatters.dart';

/// 应用回收站：恢复 / 彻底删除。
class RecycleBinScreen extends StatefulWidget {
  const RecycleBinScreen({super.key, required this.repository});

  final LivePhotoRepository repository;

  @override
  State<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends State<RecycleBinScreen> {
  List<TrashEntry>? _entries;
  String? _error;
  final Set<String> _busy = {};

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

  Future<void> _restore(TrashEntry entry) async {
    setState(() => _busy.add(entry.id));
    final ok = await widget.repository.restoreTrash(entry.id);
    if (!mounted) return;
    setState(() => _busy.remove(entry.id));
    if (ok) {
      _showSnack('已恢复：${entry.originalFileName}');
      _load();
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

    setState(() => _busy.add(entry.id));
    final ok = await widget.repository.permanentDeleteTrash(entry.id);
    if (!mounted) return;
    setState(() => _busy.remove(entry.id));
    if (ok) {
      _showSnack('已彻底删除');
      _load();
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
          final isBusy = _busy.contains(entry.id);
          return ListTile(
            leading: Icon(
              entry.mediaType == 'video'
                  ? Icons.movie_outlined
                  : Icons.photo_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(
              entry.originalFileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${formatDateTime(entry.trashedAt)} · ${formatBytes(entry.size)}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '恢复',
                  onPressed: isBusy ? null : () => _restore(entry),
                  icon: const Icon(Icons.restore, color: Colors.green),
                ),
                IconButton(
                  tooltip: '彻底删除',
                  onPressed: isBusy ? null : () => _confirmPermanentDelete(entry),
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
