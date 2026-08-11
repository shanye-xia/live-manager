/// 字节大小格式化。
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

String _two(int n) => n.toString().padLeft(2, '0');

/// 时间格式化：yyyy-MM-dd HH:mm。
String formatDateTime(DateTime dt) {
  return '${dt.year}-${_two(dt.month)}-${_two(dt.day)} '
      '${_two(dt.hour)}:${_two(dt.minute)}';
}

/// 把 EXIF 原始值整理成可展示的键值对（空值跳过）。
List<(String, String)> formatExif(Map<String, dynamic> exif) {
  final result = <(String, String)>[];

  void add(String label, Object? value) {
    if (value == null) return;
    final text = value.toString().trim();
    if (text.isEmpty || text == '0') return;
    result.add((label, text));
  }

  final make = (exif['make'] as String?)?.trim() ?? '';
  final model = (exif['model'] as String?)?.trim() ?? '';
  final camera = model.startsWith(make) && make.isNotEmpty
      ? model
      : [make, model].where((e) => e.isNotEmpty).join(' ');
  add('相机', camera);
  add('焦距', _formatRational(exif['focalLength'], unit: 'mm'));
  add('ISO', exif['iso']);
  add('快门', _formatShutter(exif['exposureTime']));
  add('光圈', 'f/${_formatDouble(exif['aperture'])}');
  add('曝光补偿', _formatRational(exif['exposureBias'], unit: ' EV'));
  add('分辨率', '${exif['width']} × ${exif['height']}');

  final address = (exif['gpsAddress'] as String?)?.trim();
  final lat = exif['latitude'];
  final lng = exif['longitude'];
  if (address != null && address.isNotEmpty) {
    add('GPS', address);
  } else if (lat is num && lng is num) {
    add('GPS', '$lat, $lng');
  }
  return result;
}

/// 把 "6540/1000" 或 "6.54" 这类 EXIF 有理数解析成易读数字。
String? _formatRational(Object? raw, {String unit = ''}) {
  if (raw == null) return null;
  final text = raw.toString().trim();
  if (text.isEmpty) return null;

  double? value;
  final parts = text.split('/');
  if (parts.length == 2) {
    final n = double.tryParse(parts[0]);
    final d = double.tryParse(parts[1]);
    if (n == null || d == null || d == 0) return null;
    value = n / d;
  } else {
    value = double.tryParse(text);
  }
  if (value == null || value == 0) return null;
  return '${_formatDouble(value)}$unit';
}

/// 快门时间：0.01 → 1/100，0.5 → 1/2。
String? _formatShutter(Object? raw) {
  if (raw == null) return null;
  final text = raw.toString().trim();
  if (text.isEmpty) return null;

  double? value;
  final parts = text.split('/');
  if (parts.length == 2) {
    final n = double.tryParse(parts[0]);
    final d = double.tryParse(parts[1]);
    if (n == null || d == null || d == 0) return null;
    value = n / d;
  } else {
    value = double.tryParse(text);
  }
  if (value == null || value <= 0) return null;
  if (value < 1) return '1/${(1 / value).round()}';
  return _formatDouble(value);
}

String _formatDouble(Object? raw) {
  if (raw is num) return raw.toStringAsFixed(raw.truncateToDouble() == raw ? 0 : 1);
  final text = raw?.toString().trim() ?? '';
  final value = double.tryParse(text);
  if (value == null) return text;
  return value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1);
}
