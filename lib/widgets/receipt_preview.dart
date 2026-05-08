import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/i18n.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

/// Renders a thumbnail / file indicator for a stored receipt reference.
///
/// `stored` is whatever `StorageService.saveReceipt` returned:
/// - `https://...` → Firebase Storage URL → `Image.network`.
/// - relative or absolute filesystem path → resolved through
///   `StorageService.resolveLocal` and rendered with `Image.file` for
///   image extensions, or as a file-icon row for everything else.
///
/// Tapping opens the `ReceiptViewerScreen` full-screen viewer.
class ReceiptPreview extends StatelessWidget {
  final String stored;
  final double size;

  const ReceiptPreview({super.key, required this.stored, this.size = 64});

  bool get _isImage {
    if (StorageService.isRemote(stored) || StorageService.isFirebasePath(stored)) return true;
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
          child: _isImage ? _ImageThumb(stored: stored) : _FileBadge(),
        ),
      ),
    );
  }
}

class _ImageThumb extends StatelessWidget {
  final String stored;
  const _ImageThumb({required this.stored});

  @override
  Widget build(BuildContext context) {
    if (StorageService.isRemote(stored)) {
      return Image.network(
        stored,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _FileBadge(),
      );
    }
    if (StorageService.isFirebasePath(stored)) {
      // Legacy Firebase Storage path — no longer resolvable after migration.
      return _FileBadge(missing: true);
    }
    return FutureBuilder<File?>(
      future: StorageService.resolveLocal(stored),
      builder: (_, snap) {
        final file = snap.data;
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CupertinoActivityIndicator());
        }
        if (file == null) return _FileBadge(missing: true);
        return Image.file(file, fit: BoxFit.cover);
      },
    );
  }
}

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

class _ViewerContent extends StatelessWidget {
  final String stored;
  final Color fallbackColor;
  const _ViewerContent({required this.stored, required this.fallbackColor});

  bool get _isImage {
    if (StorageService.isRemote(stored) || StorageService.isFirebasePath(stored)) return true;
    final lower = stored.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.webp');
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
              stored.split('/').last,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    if (StorageService.isRemote(stored)) {
      return InteractiveViewer(
        child: Image.network(
          stored,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Icon(
            CupertinoIcons.exclamationmark_triangle,
            color: Colors.white70,
            size: 48,
          ),
        ),
      );
    }
    if (StorageService.isFirebasePath(stored)) {
      // Legacy Firebase Storage path — no longer resolvable after migration.
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          context.t('expense.receiptMissing'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }
    return FutureBuilder<File?>(
      future: StorageService.resolveLocal(stored),
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
