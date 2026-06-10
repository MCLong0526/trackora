import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Builds the visual content for the tile at visual position [index].
typedef ReorderableTileBuilder = Widget Function(BuildContext context, int index);

/// A fixed-height tile grid with flexible, iOS-home-screen-style long-press
/// drag-and-drop reordering.
///
/// Unlike a plain "drop onto a target cell" approach, the surrounding tiles
/// **reflow live** to open a gap under the finger, so a tile can be carried to
/// *any* position in a single gesture instead of being nudged one slot at a
/// time.
///
/// Tiles are laid out in the order supplied by [itemBuilder]. The first
/// [reorderableCount] tiles can be picked up; any remaining tiles are pinned at
/// the tail and stay put (e.g. an always-on tool). On drop the grid calls
/// [onReorder] with remove-at-`oldIndex` / insert-at-`newIndex` semantics over
/// the reorderable range, so the caller applies the same change to its own
/// backing order.
///
/// [itemKeys] must hold a stable identity per visual position (same length as
/// [itemCount]); it lets the grid animate each tile smoothly to its new slot
/// once the caller commits the reorder.
class ReorderableTileGrid extends StatefulWidget {
  const ReorderableTileGrid({
    super.key,
    required this.itemCount,
    required this.itemKeys,
    required this.itemBuilder,
    required this.onReorder,
    this.feedbackBuilder,
    this.onDragStart,
    this.reorderableCount = -1,
    this.columns = 3,
    this.spacing = 10,
    this.runSpacing = 10,
    this.tileHeight = 82,
    this.enabled = true,
    this.dragScale = 1.06,
  });

  final int itemCount;

  /// Stable identity per visual position; length must equal [itemCount].
  final List<Object> itemKeys;

  final ReorderableTileBuilder itemBuilder;

  /// Floating widget shown under the finger while dragging; falls back to the
  /// tile content when null.
  final ReorderableTileBuilder? feedbackBuilder;

  /// Remove-at-`oldIndex` / insert-at-`newIndex` over the reorderable range.
  final void Function(int oldIndex, int newIndex) onReorder;

  /// Called the moment a drag begins (e.g. enter edit mode + haptic).
  final VoidCallback? onDragStart;

  /// Number of leading tiles that can be reordered; `-1` means all of them.
  final int reorderableCount;

  final int columns;
  final double spacing;
  final double runSpacing;
  final double tileHeight;
  final bool enabled;
  final double dragScale;

  @override
  State<ReorderableTileGrid> createState() => _ReorderableTileGridState();
}

class _ReorderableTileGridState extends State<ReorderableTileGrid> {
  final GlobalKey _gridKey = GlobalKey();
  int? _dragIndex;
  int _targetIndex = 0;
  double _cellW = 0;

  int get _reorderableCount =>
      widget.reorderableCount < 0 ? widget.itemCount : widget.reorderableCount;

  int get _rows => ((widget.itemCount - 1) ~/ widget.columns) + 1;

  /// Maps each visual index to the slot it should occupy right now, accounting
  /// for any in-progress drag (this is what produces the live reflow).
  List<int> _displayPositions() {
    final n = widget.itemCount;
    final positions = List<int>.generate(n, (i) => i);
    final drag = _dragIndex;
    if (drag == null) return positions;

    final rc = _reorderableCount;
    final seq = <int>[for (var i = 0; i < rc; i++) i];
    seq.removeAt(drag);
    seq.insert(_targetIndex.clamp(0, seq.length), drag);
    for (var pos = 0; pos < seq.length; pos++) {
      positions[seq[pos]] = pos;
    }
    return positions;
  }

  Offset _offsetFor(int position, double cellW) {
    final row = position ~/ widget.columns;
    final col = position % widget.columns;
    return Offset(
      col * (cellW + widget.spacing),
      row * (widget.tileHeight + widget.runSpacing),
    );
  }

  void _updateTarget(Offset globalPos) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || _cellW <= 0) return;
    final local = box.globalToLocal(globalPos);
    final colSpan = _cellW + widget.spacing;
    final rowSpan = widget.tileHeight + widget.runSpacing;
    final col = (local.dx / colSpan).floor().clamp(0, widget.columns - 1);
    final row = (local.dy / rowSpan).floor().clamp(0, _rows - 1);
    final linear = row * widget.columns + col;
    final target = linear.clamp(0, _reorderableCount - 1);
    if (target != _targetIndex) {
      setState(() => _targetIndex = target);
      HapticFeedback.selectionClick();
    }
  }

  void _commit() {
    final from = _dragIndex;
    final to = _targetIndex;
    if (from == null) return;
    setState(() {
      _dragIndex = null;
      _targetIndex = 0;
    });
    if (from != to) widget.onReorder(from, to);
  }

  Widget _buildFeedback(int index, double cellW) {
    final child = (widget.feedbackBuilder ?? widget.itemBuilder)(context, index);
    return Material(
      color: Colors.transparent,
      child: Transform.scale(
        scale: widget.dragScale,
        child: SizedBox(width: cellW, height: widget.tileHeight, child: child),
      ),
    );
  }

  Widget _buildTile(int index, int position, double cellW) {
    final offset = _offsetFor(position, cellW);
    final reorderable =
        widget.enabled && index < _reorderableCount && _reorderableCount > 1;
    final content = SizedBox(
      width: cellW,
      height: widget.tileHeight,
      child: widget.itemBuilder(context, index),
    );

    Widget tile = content;
    if (reorderable) {
      tile = LongPressDraggable<int>(
        data: index,
        dragAnchorStrategy: childDragAnchorStrategy,
        onDragStarted: () {
          widget.onDragStart?.call();
          setState(() {
            _dragIndex = index;
            _targetIndex = index;
          });
        },
        onDragUpdate: (d) => _updateTarget(d.globalPosition),
        onDragEnd: (_) => _commit(),
        onDraggableCanceled: (_, _) => _commit(),
        feedback: _buildFeedback(index, cellW),
        childWhenDragging: Opacity(opacity: 0.15, child: content),
        child: content,
      );
    }

    return AnimatedPositioned(
      key: ValueKey(widget.itemKeys[index]),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      left: offset.dx,
      top: offset.dy,
      width: cellW,
      height: widget.tileHeight,
      child: tile,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellW =
            (constraints.maxWidth - (widget.columns - 1) * widget.spacing) /
                widget.columns;
        _cellW = cellW;
        final positions = _displayPositions();
        final totalHeight =
            _rows * widget.tileHeight + (_rows - 1) * widget.runSpacing;
        return SizedBox(
          key: _gridKey,
          width: constraints.maxWidth,
          height: totalHeight,
          child: Stack(
            children: [
              for (var i = 0; i < widget.itemCount; i++)
                _buildTile(i, positions[i], cellW),
            ],
          ),
        );
      },
    );
  }
}
