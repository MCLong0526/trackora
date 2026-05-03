import 'package:flutter_test/flutter_test.dart';
import 'package:trackora/app_config.dart';

void main() {
  test('defaults to offline local storage', () {
    expect(storageMode, StorageMode.local);
  });
}
