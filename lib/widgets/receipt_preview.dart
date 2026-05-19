import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/i18n.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

/// Renders a thumbnail / file indicator for a stored receipt reference.
///
/// `stored` is whatever `StorageService.saveReceipt` returned:
/// - `https://...`      → legacy Supabase public URL → `Image.network` directly.
/// - `{uid}/{ts}.ext`   → new Supabase path → [StorageService.createSignedUrl]
///                        produces a 1-hour signed URL, then `Image.network`.
/// - relative / absolute filesystem path → resolved through
///   [StorageService.resolveLocal] and rendered with `Image.file` for image
///   extensions, or as a file-icon row for everything else.
/// - `users/{uid}/...`  → legacy Firebase Storage path → shows placeholder.
///
/// Tapping opens the [ReceiptViewerScreen] full-screen viewer.
class ReceiptPreview extends StatelessWidget {
  final String stored;
  final double size;

  const ReceiptPreview({super.key, required this.stored, this.size = 64});

  bool get _isImage {
    if (StorageService.isRemote(stored) ||
        StorageService.isSupabasePath(stored) ||
        StorageService.isFirebasePath(stored)) {
      return true;
    }
    final lower = stored.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.webp');
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        CupertinoPageRoute(
          builder: (_) => ReceiptViewerScreen(stored: stored),
          fullscreenDialog: true,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: size,
          height: size,
          color: brand.background,
          child: _isImage ? _ImageThumb(stored: stored) : const _FileBadge(),
        ),
      ),
    );
  }
}

// ── Thumbnail ──────────────────────────────────────────────────────────────────

class _ImageThumb extends StatefulWidget {
  final String stored;
  const _ImageThumb({required this.stored});

  @override
  State<_ImageThumb> createState() => _ImageThumbState();
}

class _ImageThumbState extends State<_ImageThumb> {
  /// Cached future so signed-URL generation isn't repeated on every rebuild.
  Future<String>? _signedUrlFuture;

  @override
  void initState() {
    super.initState();
    if (StorageService.isSupabasePath(widget.stored)) {
      _signedUrlFuture = StorageService().createSignedUrl(widget.stored);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Legacy: full public URL stored directly.
    if (StorageService.isRemote(widget.stored)) {
      return Image.network(
        widget.stored,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const _FileBadge(),
      );
    }

    // New: Supabase storage path — display via short-lived signed URL.
    if (StorageService.isSupabasePath(widget.stored)) {
      return FutureBuilder<String>(
        future: _signedUrlFuture,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CupertinoActivityIndicator());
          }
          if (snap.hasError || snap.data == null) {
            return const _FileBadge(missing: true);
          }
          return Image.network(
            snap.data!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const _FileBadge(missing: true),
          );
        },
      );
    }

    // Legacy Firebase Storage path — no longer resolvable after migration.
    if (StorageService.isFirebasePath(widget.stored)) {
      return const _FileBadge(missing: true);
    }

    // Local file (offline mode or pending sync).
    return FutureBuilder<File?>(
      future: StorageService.resolveLocal(widget.stored),
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CupertinoActivityIndicator());
        }
        final file = snap.data;
        if (file == null) return const _FileBadge(missing: true);
        return Image.file(file, fit: BoxFit.cover);
      },
    );
  }
}

// ── File badge ─────────────────────────────────────────────────────────────────

class _FileBadge extends StatelessWidget {
  final bool missing;
  const _FileBadge({this.missing = false});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      color: brand.surface,
      alignment: Alignment.center,
      child: Icon(
        missing
            ? CupertinoIcons.exclamationmark_triangle
            : CupertinoIcons.doc_text,
        color: missing ? AppColors.expense : brand.inkSoft,
      ),
    );
  }
}

// ── Full-screen viewer ─────────────────────────────────────────────────────────

/// Full-screen receipt viewer. Used by [ReceiptPreview] on tap and by
/// the expense edit screen's "View" action.
class ReceiptViewerScreen extends StatelessWidget {
  final String stored;
  const ReceiptViewerScreen({super.key, required this.stored});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.xmark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(context.t('expense.receipt')),
      ),
      body: Center(
        child: _ViewerContent(stored: stored, fallbackColor: brand.background),
      ),
    );
  }
}

class _ViewerContent extends StatefulWidget {
  final String stored;
  final Color fallbackColor;
  const _ViewerContent({required this.stored, required this.fallbackColor});

  @override
  State<_ViewerContent> createState() => _ViewerContentState();
}

class _ViewerContentState extends State<_ViewerContent> {
  Future<String>? _signedUrlFuture;

  bool get _isImage {
    if (StorageService.isRemote(widget.stored) ||
        StorageService.isSupabasePath(widget.stored) ||
        StorageService.isFirebasePath(widget.stored)) {
      return true;
    }
    final lower = widget.stored.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.webp');
  }

  @override
  void initState() {
    super.initState();
    if (StorageService.isSupabasePath(widget.stored)) {
      // Request a slightly longer expiry for the viewer (read time).
      _signedUrlFuture = StorageService().createSignedUrl(
        widget.stored,
        expiresIn: 3600,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isImage) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.doc_text, color: Colors.white70, size: 64),
            const SizedBox(height: 12),
            Text(
              widget.stored.split('/').last,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Legacy: full public URL.
    if (StorageService.isRemote(widget.stored)) {
      return InteractiveViewer(
        child: Image.network(
          widget.stored,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Icon(
            CupertinoIcons.exclamationmark_triangle,
            color: Colors.white70,
            size: 48,
          ),
        ),
      );
    }

    // New: Supabase path → signed URL.
    if (StorageService.isSupabasePath(widget.stored)) {
      return FutureBuilder<String>(
        future: _signedUrlFuture,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const CupertinoActivityIndicator(color: Colors.white);
          }
          if (snap.hasError || snap.data == null) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                context.t('expense.receiptMissing'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            );
          }
          return InteractiveViewer(
            child: Image.network(
              snap.data!,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(
                CupertinoIcons.exclamationmark_triangle,
                color: Colors.white70,
                size: 48,
              ),
            ),
          );
        },
      );
    }

    // Legacy Firebase Storage path — no longer resolvable.
    if (StorageService.isFirebasePath(widget.stored)) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          context.t('expense.receiptMissing'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }

    // Local file.
    return FutureBuilder<File?>(
      future: StorageService.resolveLocal(widget.stored),
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const CupertinoActivityIndicator(color: Colors.white);
        }
        final file = snap.data;
        if (file == null) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              context.t('expense.receiptMissing'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          );
        }
        return InteractiveViewer(child: Image.file(file, fit: BoxFit.contain));
      },
    );
  }
}
