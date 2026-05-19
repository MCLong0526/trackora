import 'dart:developer' as dev;
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_config.dart';
import '../supabase_config.dart';

/// Persists receipt files.
///
/// ## Firebase / Supabase mode
/// Uploads to Supabase Storage at `{userId}/{timestamp}.{ext}` (within the
/// `receipts` bucket) and returns the **storage path** (not a public URL).
/// The path is stored in Firestore. At display time, [createSignedUrl] turns
/// the path into a short-lived (1-hour) HTTPS URL so receipts are never
/// permanently public.
///
/// Backward-compatible: existing Firestore entries that already contain a
/// full `https://` public URL are detected by [isRemote] and displayed
/// directly — no re-upload or migration required.
///
/// ## Local mode
/// Stores receipts under `{ApplicationDocuments}/receipts/{userId}/{ts}.{ext}`
/// and returns a **relative** path. Earlier builds stored the absolute sandbox
/// path; `resolveLocal()` accepts both forms so old expenses keep showing.
///
/// ## Legacy Firebase Storage paths
/// `users/{uid}/receipts/...` paths can no longer be resolved after the
/// migration. [isFirebasePath] detects them so the UI shows a placeholder.
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

  /// Uploads [file] to Supabase and returns the **storage path**
  /// (`{userId}/{timestamp}.{ext}`), not a public URL.
  /// Use [createSignedUrl] to obtain a short-lived display URL.
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

    await Supabase.instance.client.storage.from(supabaseBucket).upload(
      path,
      file,
    );

    dev.log(
      '[RECEIPT_UPLOAD] Upload complete. Returning storage path (no public URL).',
      name: 'StorageService',
    );
    // Return the path, not a public URL.  The caller stores this path in
    // Firestore; [createSignedUrl] generates a time-limited URL at display time.
    return path;
  }

  // ── URL / path classification ───────────────────────────────────────────────

  /// True if [stored] is a Supabase storage path in the new format:
  /// `{uid}/{timestamp}.{ext}` (no scheme, no leading slash, not a local
  /// `receipts/` prefix, not a legacy `users/` Firebase prefix).
  static bool isSupabasePath(String stored) =>
      !stored.startsWith('http://') &&
      !stored.startsWith('https://') &&
      !stored.startsWith('/') &&
      !stored.startsWith('users/') &&
      !stored.startsWith('receipts/') &&
      stored.contains('/');

  /// True if [stored] is a full remote URL (legacy Supabase public URL).
  static bool isRemote(String stored) =>
      stored.startsWith('http://') || stored.startsWith('https://');

  /// True if [stored] is a legacy Firebase Storage object path
  /// (`users/{uid}/receipts/...`). These cannot be resolved after the
  /// migration to Supabase; the UI shows a graceful placeholder.
  static bool isFirebasePath(String stored) =>
      !stored.startsWith('http://') &&
      !stored.startsWith('https://') &&
      !stored.startsWith('/') &&
      stored.startsWith('users/');

  // ── Signed URL generation ───────────────────────────────────────────────────

  /// Generates a signed URL for a Supabase storage [path], valid for
  /// [expiresIn] seconds (default 3600 = 1 hour).
  ///
  /// Works for both private and public buckets.  Call this whenever you need
  /// to display or share a receipt stored in the new path-based format.
  Future<String> createSignedUrl(
    String path, {
    int expiresIn = 3600,
  }) async {
    dev.log(
      '[SUPABASE_STORAGE] Creating signed URL for path: $path',
      name: 'StorageService',
    );
    final url = await Supabase.instance.client.storage
        .from(supabaseBucket)
        .createSignedUrl(path, expiresIn);
    return url;
  }

  // ── Local helpers ───────────────────────────────────────────────────────────

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
  /// Returns null when the file is missing or the value is a remote URL / path.
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
    // Supabase path (new format) — not a local file.
    if (isSupabasePath(stored)) return null;
    final docs = await getApplicationDocumentsDirectory();
    final f = File('${docs.path}/$stored');
    return await f.exists() ? f : null;
  }

  // ── Deletion ────────────────────────────────────────────────────────────────

  Future<void> delete(String stored) async {
    if (storageMode == StorageMode.local) {
      final file = await resolveLocal(stored);
      if (file != null && await file.exists()) await file.delete();
      return;
    }
    if (isFirebasePath(stored)) {
      dev.log(
        '[STORAGE] Skipping delete of legacy Firebase path: $stored',
        name: 'StorageService',
      );
      return;
    }
    // New format: stored IS the path.
    if (isSupabasePath(stored)) {
      try {
        dev.log(
          '[SUPABASE_STORAGE] Deleting receipt at path: $stored',
          name: 'StorageService',
        );
        await Supabase.instance.client.storage
            .from(supabaseBucket)
            .remove([stored]);
        dev.log(
          '[SUPABASE_STORAGE] Receipt deleted successfully.',
          name: 'StorageService',
        );
      } catch (e) {
        dev.log(
          '[SUPABASE_STORAGE] Delete failed (non-fatal): $e',
          name: 'StorageService',
        );
      }
      return;
    }
    // Legacy format: stored is the full public URL — extract path from it.
    if (isRemote(stored)) {
      try {
        final path = _supabasePathFromUrl(stored);
        if (path != null) {
          dev.log(
            '[SUPABASE_STORAGE] Deleting receipt (legacy URL) at path: $path',
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

  /// Extract the storage path from a legacy Supabase public URL.
  /// URL format: {supabaseUrl}/storage/v1/object/public/{bucket}/{path}
  static String? _supabasePathFromUrl(String url) {
    final prefix = '$supabaseUrl/storage/v1/object/public/$supabaseBucket/';
    if (url.startsWith(prefix)) return url.substring(prefix.length);
    return null;
  }
}
