import 'dart:math' as math;
import 'dart:ui';

/// DetectionCoordinateTransformer maps a normalized YOLO detection box (in
/// rotated model-input space) to pixel coordinates in the preview overlay's
/// canvas.
///
/// The model input is the CameraImage AFTER applying the camera rotation
/// (portrait-up for this app), so normalized boxes already share the
/// orientation of the visible preview. This transformer only handles the
/// scale + letterbox mapping from that input frame onto the widget canvas,
/// which is the same contain behavior CameraPreview's AspectRatio uses:
/// the preview frame is centered and scaled to fit the available area, leaving
/// uniform bands on the sides when the canvas aspect differs.
class DetectionCoordinateTransformer {
  const DetectionCoordinateTransformer();

  /// Projects a normalized [box] (0..1 coordinates in the rotated model-input
  /// frame of size [inputSize]) onto a [widgetSize] canvas.
  ///
  /// The input frame is center-fitted into the canvas (contain), so the
  /// returned rectangle accounts for the letterbox offset as well as scale.
  static Rect project(Rect box, Size inputSize, Size widgetSize) {
    if (inputSize.width <= 0 ||
        inputSize.height <= 0 ||
        widgetSize.width <= 0 ||
        widgetSize.height <= 0) {
      return Rect.zero;
    }

    final double scale = math.min(
      widgetSize.width / inputSize.width,
      widgetSize.height / inputSize.height,
    );

    final double fittedWidth = inputSize.width * scale;
    final double fittedHeight = inputSize.height * scale;

    final double offsetX = (widgetSize.width - fittedWidth) / 2;
    final double offsetY = (widgetSize.height - fittedHeight) / 2;

    return Rect.fromLTRB(
      offsetX + box.left * fittedWidth,
      offsetY + box.top * fittedHeight,
      offsetX + box.right * fittedWidth,
      offsetY + box.bottom * fittedHeight,
    );
  }
}