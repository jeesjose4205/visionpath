/// Coarse depth map over a normalized [0, 1] x [0, 1] grid.
///
/// Cell values are RELATIVE nearness in [0, 1]:
///   1.0 = closest to the camera, 0.0 = far away (or unknown).
/// This is NOT metric distance and must never be spoken or drawn as meters.
class DepthMap {
  final int cols;

  final int rows;

  final List<double> _cells;

  DepthMap({
    required this.cols,
    required this.rows,
    required List<double> cells,
  })  : assert(cols > 0 && rows > 0),
        assert(cells.length == cols * rows),
        _cells = cells;

  /// Number of cells (cols * rows).
  int get length => cols * rows;

  /// Raw cells, row-major (row = index ~/ cols, col = index % cols).
  List<double> get cells => _cells;

  /// Value of the cell at integer grid coordinates.
  double cellAt(int col, int row) => _cells[row * cols + col];

  /// Nearest-neighbour sample at normalized coordinates (clamped to grid).
  double valueAt(double nx, double ny) {
    final double x = nx.clamp(0.0, 1.0);
    final double y = ny.clamp(0.0, 1.0);
    final int col = (x * (cols - 1)).round().clamp(0, cols - 1);
    final int row = (y * (rows - 1)).round().clamp(0, rows - 1);
    return cellAt(col, row);
  }

  /// Bilinear sample at normalized coordinates (clamped to grid).
  double sampleBilinear(double nx, double ny) {
    final double x = nx.clamp(0.0, 1.0);
    final double y = ny.clamp(0.0, 1.0);
    final double fx = x * (cols - 1);
    final double fy = y * (rows - 1);
    final int x0 = fx.floor().clamp(0, cols - 1);
    final int y0 = fy.floor().clamp(0, rows - 1);
    final int x1 = (x0 + 1).clamp(0, cols - 1);
    final int y1 = (y0 + 1).clamp(0, rows - 1);

    final double tx = fx - x0;
    final double ty = fy - y0;

    final double v00 = cellAt(x0, y0);
    final double v10 = cellAt(x1, y0);
    final double v01 = cellAt(x0, y1);
    final double v11 = cellAt(x1, y1);

    final double top = v00 + (v10 - v00) * tx;
    final double bottom = v01 + (v11 - v01) * tx;
    return top + (bottom - top) * ty;
  }
}