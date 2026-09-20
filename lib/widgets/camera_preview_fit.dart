import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Returns the [Size] of the camera frame as it is DISPLAYED in the current
/// portrait UI.
///
/// On Android rear cameras the sensor/preview buffer arrives in landscape
/// (e.g. 640x480) while the app is portrait. The Flutter camera pipeline
/// (camera_android_camerax RotatedPreviewDelegate / engine SurfaceProducer)
/// delivers the preview already rotated so it is upright on screen, so the
/// displayed frame has the same two sides swapped (e.g. 480x640). Giving the
/// preview widget a box shaped exactly like that stopped rotation from ever
/// being treated as a stretch: the underlying [Texture] fills its parent, so
/// an aspect-matching box keeps the geometry intact.
Size displayPreviewSize(CameraController controller) {
  final Size? preview = controller.value.previewSize;
  if (preview == null || preview.width <= 0 || preview.height <= 0) {
    return Size.zero;
  }
  // Data driven: choose the portrait box for portrait UI instead of assuming
  // the orientation.
  final bool sensorIsLandscape = preview.width > preview.height;
  return sensorIsLandscape
      ? Size(preview.height, preview.width)
      : Size(preview.width, preview.height);
}

/// CameraPreview fit for a portrait, rear-camera full-screen view.
///
/// The camera plugin's preview widget alone stretches when the surrounding
/// layout gives it tight, wrong-shape constraints (the internal AspectRatio is
/// neutralized and the texture stretches to fill the box). This wrapper:
///
/// 1. Sizes [CameraPreview] into a tight box that matches the DISPLAY aspect
///    of the (already upright) camera frame, so the texture is never stretched.
/// 2. Uniformly scales that box onto the available area with `BoxFit.cover`,
///    cropping the overflow. The scale factor is the same for both axes so
///    aspect ratio is preserved and geometry stays natural; nothing is scaled
///    independently per axis.
///
/// All transforms are derived from the actual camera configuration and are
/// logged for on-device verification.
class CameraPreviewFit extends StatelessWidget {
  const CameraPreviewFit({super.key, required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final size = displayPreviewSize(controller);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size area = constraints.biggest;

        print('PREVIEW_AREA_SIZE: $area');
        print('PREVIEW_SENSOR_SIZE: ${controller.value.previewSize}');
        print('PREVIEW_DISPLAY_SIZE: $size');
        print('PREVIEW_SENSOR_ORIENTATION: ${controller.description.sensorOrientation}');
        print('PREVIEW_DEVICE_ORIENTATION: ${controller.value.deviceOrientation}');
        print('PREVIEW_ASPECT_RATIO: ${controller.value.aspectRatio}');

        if (size.width <= 0 ||
            size.height <= 0 ||
            area.width <= 0 ||
            area.height <= 0) {
          return const ColoredBox(color: Color(0xFF05070B));
        }

        // Uniform cover scale: same scale for width and height, crop overflow.
        final double scale = math.max(
          area.width / size.width,
          area.height / size.height,
        );
        print('PREVIEW_FIT_SCALE: $scale');

        return SizedBox.expand(
          child: ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: CameraPreview(controller),
              ),
            ),
          ),
        );
      },
    );
  }
}