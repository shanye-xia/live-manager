import 'package:flutter_test/flutter_test.dart';
import 'package:live_manager/ui/core/formatters.dart';

void main() {
  group('formatExif GPS', () {
    test('地址为空时仍显示经纬度', () {
      final rows = formatExif({
        'latitude': 31.2304,
        'longitude': 121.4737,
        'gpsAddress': '',
      });

      expect(rows, contains(('GPS', '31.2304, 121.4737')));
    });

    test('地址存在时优先显示地址', () {
      final rows = formatExif({
        'latitude': 31.2304,
        'longitude': 121.4737,
        'gpsAddress': '上海市 黄浦区',
      });

      expect(rows, contains(('GPS', '上海市 黄浦区')));
    });

    test('补充展示常见 GPS 与拍摄字段', () {
      final rows = formatExif({
        'gpsAltitude': '120/1',
        'gpsDateStamp': '2026:08:13',
        'gpsTimeStamp': '04:30:00',
        'gpsProcessingMethod': 'GPS',
        'lightSource': '0',
        'sceneCaptureType': '0',
      });

      expect(rows, contains(('GPS 海拔', '120')));
      expect(rows, contains(('GPS 时间', '2026:08:13 04:30:00')));
      expect(rows, contains(('GPS 定位方式', 'GPS')));
    });
  });
}
