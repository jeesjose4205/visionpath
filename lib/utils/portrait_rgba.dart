import 'dart:typed_data';

import 'package:camera/camera.dart';

/// Converts a YUV420 [CameraImage] into an upright portrait RGBA buffer using
/// identical pixel math across every consumer (object detection, OCR, face
/// detection).
///
/// Orientation: frames arrive in sensor coordinates (landscape on Android
/// rear cameras) and are rotated clockwise by [quarterTurns] so the result is
/// an upright portrait buffer with a known width/height. Normalized coordinates
/// derived from [width]/[height] are therefore always portrait and unambiguous.
({Uint8List rgba, int width, int height})? convertFrameToPortraitRgba(
  CameraImage image,
  int quarterTurns,
) {
  if (image.format.group != ImageFormatGroup.yuv420) {
    print('FRAME_YUV_FORMAT_UNEXPECTED: ${image.format.group}');
    return null;
  }
  if (image.planes.length < 3) {
    print('FRAME_YUV_PLANES_UNEXPECTED: ${image.planes.length}');
    return null;
  }

  final yPlane = image.planes[0];
  final uPlane = image.planes[1];
  final vPlane = image.planes[2];
  final width = image.width;
  final height = image.height;

  // YUV -> RGB, row-major in sensor orientation.
  final rgb = Uint8List(width * height * 3);
  int out = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final yv = yPlane.bytes[y * yPlane.bytesPerRow + x];
      final u = uPlane.bytes[(y ~/ 2) * uPlane.bytesPerRow + (x ~/ 2)] - 128;
      final v = vPlane.bytes[(y ~/ 2) * vPlane.bytesPerRow + (x ~/ 2)] - 128;

      rgb[out++] = (yv + 1.370705 * v).round().clamp(0, 255);
      rgb[out++] = (yv - 0.337633 * u - 0.698001 * v).round().clamp(0, 255);
      rgb[out++] = (yv + 1.732446 * u).round().clamp(0, 255);
    }
  }

  // Rotate clockwise into upright portrait. A 90-degree CW rotation maps
  // input (x, y) -> (height - 1 - y, x) and swaps the buffer dimensions.
  var w = width;
  var h = height;
  var pixels = rgb;
  for (var turn = 0; turn < (quarterTurns % 4); turn++) {
    final inW = w;
    final inH = h;
    final rotated = Uint8List(inW * inH * 3);
    for (var y = 0; y < inH; y++) {
      for (var x = 0; x < inW; x++) {
        final src = (y * inW + x) * 3;
        final dx = inH - 1 - y;
        final dy = x;
        final dst = (dy * inH + dx) * 3;
        rotated[dst] = pixels[src];
        rotated[dst + 1] = pixels[src + 1];
        rotated[dst + 2] = pixels[src + 2];
      }
    }
    w = inH;
    h = inW;
    pixels = rotated;
  }

  // RGB -> RGBA (alpha 255) for InputImage.fromBitmap.
  final rgba = Uint8List(w * h * 4);
  for (var i = 0, j = 0; i < pixels.length; i += 3, j += 4) {
    rgba[j] = pixels[i];
    rgba[j + 1] = pixels[i + 1];
    rgba[j + 2] = pixels[i + 2];
    rgba[j + 3] = 255;
  }

  return (rgba: rgba, width: w, height: h);
}