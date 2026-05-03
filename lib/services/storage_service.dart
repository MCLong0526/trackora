import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../app_config.dart';

/// Persists receipt files.
///
/// Local mode stores receipts under
/// `{ApplicationDocuments}/receipts/{userId}/{ts}.{ext}` and returns a
/// **relative** path (`receipts/{userId}/{ts}.{ext}`). Earlier builds
/// stored the absolute sandbox path; that broke after every reinstall
/// because iOS rotates the data-container UUID. `resolveLocal()` accepts
/// both forms so old expenses keep showing their receipts.
class StorageService {
  Future<String> saveReceipt(String userId, File file) async {
    if (storageMode == StorageMode.local) {
      return _saveLocalReceipt(userId, file);
    }
    return _uploadFirebaseReceipt(userId, file);
  }

  Future<String> uploadReceipt(String userId, File file) async {
    return _uploadFirebaseReceipt(userId, file);
  }

  Future<String> _uploadFirebaseReceipt(String userId, File file) async {
    final ext = file.path.split('.').last;
    final ref = FirebaseStorage.instance.ref().child(
      'users/$userId/receipts/${DateTime.now().millisecondsSinceEpoch}.$ext',
    );
    await ref.putFile(file);
    return ref.getDownloadURL();
  }

  Future<String> _saveLocalReceipt(String userId, File file) async {
    final ext = file.path.split('.').last;
    final documents = await getApplicationDocumentsDirectory();
    final relDir = 'receipts/$userId';
    final directory = Directory('${documents.path}/$relDir');
    await directory.create(recursive: true);
    final filename = '${DateTime.now().millisecondsSinceEpoch}.$ext';
    final target = File('${directory.path}/$filename');
    await file.copy(target.path);
    return '$relDir/$filename';
  }

  /// Resolve a stored receipt reference to an on-disk [File] for local
  /// mode. Returns null when the file is missing or the value is a
  /// remote URL (Firebase). Accepts both legacy absolute paths and the
  /// new relative form.
  static Future<File?> resolveLocal(String stored) async {
    if (stored.isEmpty) return null;
    if (stored.startsWith('http://') || stored.startsWith('https://')) {
      return null;
    }
    if (stored.startsWith('/')) {
      final f = File(stored);
      return await f.exists() ? f : null;
    }
    final docs = await getApplicationDocumentsDirectory();
    final f = File('${docs.path}/$stored');
    return await f.exists() ? f : null;
  }

  /// True if the stored reference is a remote URL — the UI uses this to
  /// pick between Image.network and Image.file.
  static bool isRemote(String stored) =>
      stored.startsWith('http://') || stored.startsWith('https://');

  Future<void> delete(String url) async {
    if (storageMode == StorageMode.local) {
      final file = await resolveLocal(url);
      if (file != null && await file.exists()) await file.delete();
      return;
    }
    try {
      await FirebaseStorage.instance.refFromURL(url).delete();
    } catch (_) {}
  }
}
