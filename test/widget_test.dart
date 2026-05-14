import 'package:flutter_test/flutter_test.dart';
import 'package:trackora/app_config.dart';

void main() {
  test('defaults to Firebase storage', () {
    expect(storageMode, StorageMode.firebase);
  });
}
