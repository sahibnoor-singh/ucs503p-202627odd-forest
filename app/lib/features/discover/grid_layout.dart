import 'dart:ui';

/// Where tiles go in the Discover grid. Pure arithmetic, so it can be tested without a screen.
///
/// The grid is built from blocks that are 3 cells wide and 3 cells high. Every block is completely filled, and a few of its tiles
/// are bigger than one cell (a feature tile of 2x2, or a tall one of 1x2), which gives the mixed sizes of Instagram's Explore page.
/// The first tile of a block is the biggest slot, so the best-ranked posts get the most room. On a narrow screen one block makes a
/// row band; on a wide one (tablet, foldable) several blocks sit side by side, so the tiles never get huge and a bigger screen shows
/// more of them. Cell size comes from the width, never from fixed pixels, so every phone gets a grid that fits it exactly.

/// A tile's cell and size inside a block (in cells).
class Slot {
  const Slot(this.col, this.row, this.w, this.h);
  final int col;
  final int row;
  final int w;
  final int h;
}

const _featureLeft = [Slot(0, 0, 2, 2), Slot(2, 0, 1, 1), Slot(2, 1, 1, 1), Slot(0, 2, 1, 1), Slot(1, 2, 1, 1), Slot(2, 2, 1, 1)];
const _tallRight = [
  Slot(2, 0, 1, 2), Slot(0, 0, 1, 1), Slot(1, 0, 1, 1), Slot(0, 1, 1, 1), Slot(1, 1, 1, 1),
  Slot(0, 2, 1, 1), Slot(1, 2, 1, 1), Slot(2, 2, 1, 1),
];
const _featureRight = [Slot(1, 0, 2, 2), Slot(0, 0, 1, 1), Slot(0, 1, 1, 1), Slot(0, 2, 1, 1), Slot(1, 2, 1, 1), Slot(2, 2, 1, 1)];

/// The block patterns, used in turn: feature on the left, tall on the right, feature on the right, tall on the right again.
const blockPatterns = [_featureLeft, _tallRight, _featureRight, _tallRight];

/// A tile and the rectangle it fills. [index] is its place in the list of posts being shown.
class PlacedTile {
  const PlacedTile(this.index, this.rect, {required this.big});
  final int index;
  final Rect rect;

  /// Wider or taller than one cell: room to show a title.
  final bool big;
}

/// One horizontal band of the grid: the tiles in it and how tall it is (including the gap below it).
class Band {
  const Band(this.tiles, this.height);
  final List<PlacedTile> tiles;
  final double height;
}

class GridPlan {
  const GridPlan({required this.bands, required this.placed, required this.cell});
  final List<Band> bands;

  /// How many of the posts have a place. The rest wait for more posts to fill their block.
  final int placed;
  final double cell;
}

/// How many 3-cell-wide blocks sit side by side on a screen [width] dp wide.
int blocksAcross(double width) => width < 560 ? 1 : (width / 280).floor().clamp(2, 4);

/// Places [count] posts on a screen [width] dp wide. While more posts can still be loaded ([complete] false) a last block that
/// would not be full is left out, so the grid never ends in a hole; once everything is loaded the leftover posts get plain
/// one-cell tiles in rows.
GridPlan planGrid({required int count, required double width, required bool complete, double gap = 2}) {
  final across = blocksAcross(width);
  final columns = 3 * across;
  final cell = (width - gap * (columns - 1)) / columns;
  final step = cell + gap;
  final bandHeight = 3 * cell + 2 * gap + gap;

  final bands = <Band>[];
  var next = 0;
  var block = 0;
  var tiles = <PlacedTile>[];
  var inBand = 0;

  void closeBand() {
    if (tiles.isNotEmpty) bands.add(Band(tiles, bandHeight));
    tiles = <PlacedTile>[];
    inBand = 0;
  }

  while (true) {
    final pattern = blockPatterns[block % blockPatterns.length];
    if (count - next < pattern.length) break;
    final left = inBand * 3 * step;
    for (final slot in pattern) {
      tiles.add(PlacedTile(
        next++,
        Rect.fromLTWH(left + slot.col * step, slot.row * step, slot.w * cell + (slot.w - 1) * gap, slot.h * cell + (slot.h - 1) * gap),
        big: slot.w > 1 || slot.h > 1,
      ));
    }
    block++;
    if (++inBand == across) closeBand();
  }
  if (!complete && inBand != 0) {
    // a band of side-by-side blocks that is only part full would show a hole until the next posts arrive
    next -= tiles.length;
    tiles = <PlacedTile>[];
    inBand = 0;
  }
  closeBand();

  if (complete) {
    var row = <PlacedTile>[];
    while (next < count) {
      row.add(PlacedTile(next++, Rect.fromLTWH(row.length * step, 0, cell, cell), big: false));
      if (row.length == columns) {
        bands.add(Band(row, step));
        row = <PlacedTile>[];
      }
    }
    if (row.isNotEmpty) bands.add(Band(row, step));
  }
  return GridPlan(bands: bands, placed: next, cell: cell);
}
