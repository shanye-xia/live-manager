import 'package:flutter/material.dart';

class ExifClearOption {
  const ExifClearOption({
    required this.key,
    required this.title,
    required this.subtitle,
  });

  final String key;
  final String title;
  final String subtitle;
}

const exifClearOptions = <ExifClearOption>[
  ExifClearOption(key: 'gps', title: '位置信息', subtitle: 'GPS 坐标、海拔、定位时间、定位处理信息'),
  ExifClearOption(key: 'device', title: '设备信息', subtitle: '相机品牌、型号'),
  ExifClearOption(key: 'software', title: '软件信息', subtitle: '拍摄/编辑软件'),
  ExifClearOption(
    key: 'datetime',
    title: '时间信息',
    subtitle: '拍摄时间、数字化时间、时区偏移（默认不选）',
  ),
  ExifClearOption(key: 'description', title: '描述信息', subtitle: '图片描述'),
  ExifClearOption(key: 'comment', title: '备注信息', subtitle: '用户备注'),
];

class ExifClearSelectionMemory {
  static Set<String>? _lastSelection;

  static Set<String> initialSelection() {
    return Set<String>.of(
      _lastSelection ??
          exifClearOptions
              .where((option) => option.key != 'datetime')
              .map((option) => option.key),
    );
  }

  static void remember(Set<String> selection) {
    _lastSelection = Set<String>.of(selection);
  }
}

class ExifClearDialog extends StatefulWidget {
  const ExifClearDialog({
    super.key,
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  State<ExifClearDialog> createState() => _ExifClearDialogState();
}

class _ExifClearDialogState extends State<ExifClearDialog> {
  late final Set<String> _selected =
      ExifClearSelectionMemory.initialSelection();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.description),
            const SizedBox(height: 12),
            for (final option in exifClearOptions)
              CheckboxListTile(
                value: _selected.contains(option.key),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(option.title),
                subtitle: Text(option.subtitle),
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _selected.add(option.key);
                    } else {
                      _selected.remove(option.key);
                    }
                  });
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            setState(() {
              if (_selected.length == exifClearOptions.length) {
                _selected.clear();
              } else {
                _selected
                  ..clear()
                  ..addAll(exifClearOptions.map((option) => option.key));
              }
            });
          },
          child: Text(
            _selected.length == exifClearOptions.length ? '取消全选' : '全选',
          ),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(Set<String>.of(_selected)),
          child: const Text('清除'),
        ),
      ],
    );
  }
}
