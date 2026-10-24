import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionpath/utils/portrait_rgba.dart';

CameraImage yuvFrame({
  required int width,
  required int height,
  required Uint8List y,
  required Uint8List u,
  required Uint8List v,
  int? uStride,
  int? vStride,
  int? uRowStride,
  int? vRowStride,
}) {
  return CameraImage.fromPlatformInterface(
    CameraImageData(
      format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 35),
      planes: <CameraImagePlane>[
        CameraImagePlane(bytes: y, bytesPerRow: width, bytesPerPixel: 1),
        CameraImagePlane(
          bytes: u,
          bytesPerRow: uRowStride ?? (width ~/ 2),
          bytesPerPixel: uStride ?? 1,
        ),
        CameraImagePlane(
          bytes: v,
          bytesPerRow: vRowStride ?? (width ~/ 2),
          bytesPerPixel: vStride ?? 1,
        ),
      ],
      width: width,
      height: height,
    ),
  );
}

({int r, int g, int b, int a}) pixelAt(
  ({Uint8List rgba, int width, int height}) frame,
  int x,
  int y,
) {
  final int i = (y * frame.width + x) * 4;
  return (
    r: frame.rgba[i],
    g: frame.rgba[i + 1],
    b: frame.rgba[i + 2],
    a: frame.rgba[i + 3],
  );
}

void main() {
  test('planar neutral chroma produces opaque grey', () {
    final CameraImage image = yuvFrame(
      width: 4,
      height: 4,
      y: Uint8List(16)..fillRange(0, 16, 128),
      u: Uint8List(4)..fillRange(0, 4, 128),
      v: Uint8List(4)..fillRange(0, 4, 128),
    );

    final frame = convertFrameToPortraitRgba(image, 0)!;
    expect(frame.width, 4);
    expect(frame.height, 4);
    final p = pixelAt(frame, 3, 3);
    expect(p.r, 128);
    expect(p.g, 128);
    expect(p.b, 128);
    expect(p.a, 255);
  });

  test('semi-planar chroma honours bytesPerPixel instead of packing', () {
    final Uint8List u = Uint8List(16);
    final Uint8List v = Uint8List(16);
    for (int i = 0; i < 16; i += 2) {
      u[i] = 128;
      v[i] = 128;
    }
    final CameraImage image = yuvFrame(
      width: 4,
      height: 4,
      y: Uint8List(16)..fillRange(0, 16, 128),
      u: u,
      v: v,
      uStride: 2,
      vStride: 2,
      uRowStride: 8,
      vRowStride: 8,
    );

    final frame = convertFrameToPortraitRgba(image, 0)!;
    for (int y = 0; y < 4; y++) {
      for (int x = 0; x < 4; x++) {
        final p = pixelAt(frame, x, y);
        expect(p.r, 128, reason: 'r at $x,$y');
        expect(p.g, 128, reason: 'g at $x,$y');
        expect(p.b, 128, reason: 'b at $x,$y');
      }
    }
  });

  test('chroma planes map to the expected colour', () {
    final CameraImage withV = yuvFrame(
      width: 4,
      height: 4,
      y: Uint8List(16)..fillRange(0, 16, 100),
      u: Uint8List(4)..fillRange(0, 4, 128),
      v: Uint8List(4)..fillRange(0, 4, 200),
    );
    final pV = pixelAt(convertFrameToPortraitRgba(withV, 0)!, 2, 2);
    expect(pV.r, 199);
    expect(pV.g, 50);
    expect(pV.b, 100);
    expect(pV.a, 255);

    final CameraImage withU = yuvFrame(
      width: 4,
      height: 4,
      y: Uint8List(16)..fillRange(0, 16, 100),
      u: Uint8List(4)..fillRange(0, 4, 200),
      v: Uint8List(4)..fillRange(0, 4, 128),
    );
    final pU = pixelAt(convertFrameToPortraitRgba(withU, 0)!, 0, 0);
    expect(pU.r, 100);
    expect(pU.g, 76);
    expect(pU.b, 225);
  });

  test('quarterTurns rotates clockwise and swaps dimensions', () {
    final Uint8List y = Uint8List.fromList(<int>[10, 20, 30, 40]);
    final CameraImage image = yuvFrame(
      width: 2,
      height: 2,
      y: y,
      u: Uint8List(1)..fillRange(0, 1, 128),
      v: Uint8List(1)..fillRange(0, 1, 128),
    );

    final frame = convertFrameToPortraitRgba(image, 1)!;
    expect(frame.width, 2);
    expect(frame.height, 2);
    expect(pixelAt(frame, 0, 0).r, 30);
    expect(pixelAt(frame, 1, 0).r, 10);
    expect(pixelAt(frame, 0, 1).r, 40);
    expect(pixelAt(frame, 1, 1).r, 20);
  });

  test('a non-YUV frame is rejected', () {
    final CameraImage image = CameraImage.fromPlatformInterface(
      CameraImageData(
        format: const CameraImageFormat(ImageFormatGroup.unknown, raw: 0),
        planes: const <CameraImagePlane>[],
        width: 2,
        height: 2,
      ),
    );
    expect(convertFrameToPortraitRgba(image, 0), isNull);
  });
}
