import 'dart:developer' as dev;
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_config.dart';
import '../supabase_config.dart';

/// Persists receipt files.
///
/// Firebase mode uploads to Supabase Storage at
/// `{userId}/{timestamp}.{ext}` (within the `receipts` bucket) and returns the public HTTPS URL,
/// which is stored directly in the Firestore entry.
///
/// Local mode stores receipts under
/// `{ApplicationDocuments}/receipts/{userId}/{ts}.{ext}` and returns a
/// **relative** path. Earlier builds stored the absolute sandbox path; that
/// broke after every reinstall because iOS rotates the data-container UUID.
/// `resolveLocal()` accepts both forms so old expenses keep showing receipts.
///
/// Legacy receipts that carry a Firebase Storage path
/// (`users/{uid}/receipts/...`) can no longer be resolved after the migration.
/// `isFirebasePath()` detects them so the UI can show a graceful placeholder.
class StorageService {
  Future<String> saveReceipt(String userId, File file) async {
    if (storageMode == StorageMode.local) {
      return _saveLocalReceipt(userId, file);
    }
    return _uploadSupabaseReceipt(userId, file);
  }

  /// Saves a receipt to local app documents regardless of storage mode.
  /// Used when offline in Firebase mode — the returned relative path is stored
  /// in the expense and later uploaded to Supabase during sync.
  Future<String> saveReceiptLocally(String userId, File file) =>
      _saveLocalReceipt(userId, file);

  Future<String> _uploadSupabaseReceipt(String userId, File file) async {
    final filename = file.path.split('/').last;
    final dotIndex = filename.lastIndexOf('.');
    final ext =
        (dotIndex != -1 && dotIndex < filename.length - 1)
            ? filename.substring(dotIndex + 1).toLowerCase()
            : 'jpg';

    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    dev.log(
      '[RECEIPT_UPLOAD] Uploading to Supabase — path: $path',
      name: 'StorageService',
    );
    dev.log(
      '[SUPABASE_STORAGE] Local file: ${file.path} | exists: ${file.existsSync()}',
      name: 'StorageService',
    );

    final supabase = Supabase.instance.client;
    await supabase.storage.from(supabaseBucket).upload(path, file);

    final publicUrl = supabase.storage.from(supabaseBucket).getPublicUrl(path);
    dev.log(
      '[RECEIPT_UPLOAD] Upload complete. Public URL obtained.',
      name: 'StorageService',
    );
    return publicUrl;
  }

  /// Returns true if the stored receipt value is a **legacy** Firebase Storage
  /// object path (`users/{uid}/receipts/{ts}.ext`). These can no longer be
  /// resolved after the migration to Supabase; the UI shows a placeholder.
  static bool isFirebasePath(String stored) =>
      !stored.startsWith('http://') &&
      !stored.startsWith('https://') &&
      !stored.startsWith('/') &&
      stored.startsWith('users/');

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

  /// Resolve a stored receipt reference to an on-disk [File] for local mode.
  /// Returns null when the file is missing or the value is a remote URL.
  /// Accepts both legacy absolute paths and the new relative form.
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

  /// True if the stored reference is a remote URL (Supabase public URL).
  static bool isRemote(String stored) =>
      stored.startsWith('http://') || stored.startsWith('https://');

  Future<void> delete(String stored) async {
    if (storageMode == StorageMode.local) {
      final file = await resolveLocal(stored);
      if (file != null && await file.exists()) await file.delete();
      return;
    }
    if (isFirebasePath(stored)) {
      // Legacy Firebase Storage path — firebase_storage SDK removed; skip.
      dev.log(
        '[STORAGE] Skipping delete of legacy Firebase path: $stored',
        name: 'StorageService',
      );
      return;
    }
    if (isRemote(stored)) {
      try {
        final path = _supabasePathFromUrl(stored);
        if (path != null) {
          dev.log(
            '[SUPABASE_STORAGE] Deleting receipt: $path',
            name: 'StorageService',
          );
          await Supabase.instance.client.storage
              .from(supabaseBucket)
              .remove([path]);
          dev.log(
            '[SUPABASE_STORAGE] Receipt deleted successfully.',
            name: 'StorageService',
          );
        }
      } catch (e) {
        dev.log(
          '[SUPABASE_STORAGE] Delete failed (non-fatal): $e',
          name: 'StorageService',
        );
      }
    }
  }

  /// Extract the storage path from a Supabase public URL.
  /// URL format: {supabaseUrl}/storage/v1/object/public/{bucket}/{path}
  static String? _supabasePathFromUrl(String url) {
    final prefix = '$supabaseUrl/storage/v1/object/public/$supabaseBucket/';
    if (url.startsWith(prefix)) return url.substring(prefix.length);
    return null;
  }
}
