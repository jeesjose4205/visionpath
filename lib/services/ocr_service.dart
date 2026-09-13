import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/ocr_result.dart';

/// OcrService wraps the ML Kit text recognizer and converts camera frames and
/// captured photos into usable [OcrResult]s.
///
/// Orientation pipeline (matches CameraService docs):
/// - Guidance frames arrive as a CameraImage in sensor coordinates (landscape
///   on Android rear cameras). The frame is rotated clockwise by
///   [quarterTurns] to produce an upright portrait RGBA buffer, which is given
///   to ML Kit as an InputImage.fromBitmap. Recognized boxes are therefore
///   already in upright-portrait pixel space and are normalized to 0..1.
/// - Captures are decoded through Flutter's image decoder (which honours EXIF)
///   to a portrait raw-RGBA buffer with a known width/height, so the
///   coordinate space is again portrait and unambiguous.
///
/// IMPORTANT: Logging never includes recognized document contents; only
/// lengths and block counts are logged.
class OcrService {
  TextRecognizer? _recognizer;
  bool _isActive = false;
  bool _closed = false;

  bool get isActive => _isActive;

  Future<TextRecognizer> _ensureRecognizer() async {
    if (_recognizer != null) return _recognizer!;
    if (_closed) {
      final fresh = TextRecognizer(script: TextRecognitionScript.latin);
      _recognizer = fresh;
      _closed = false;
      return fresh;
    }
    print('OCR_INIT_START');
    _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    _isActive = true;
    print('OCR_INIT_DONE');
    return _recognizer!;
  }

  /// Convert a YUV CameraImage frame into an upright portrait RGBA buffer
  /// using the same pixel math as the object detection pipeline.
  ({Uint8List rgba, int width, int height})? convertFrameToPortraitRgba(
    CameraImage image,
    int quarterTurns,
  ) {
    if (image.format.group != ImageFormatGroup.yuv420) {
      print('GUIDANCE_YUV_FORMAT_UNEXPECTED: ${image.format.group}');
      return null;
    }
    if (image.planes.length < 3) {
      print('GUIDANCE_YUV_PLANES_UNEXPECTED: ${image.planes.length}');
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

  /// Run text recognition on an upright portrait RGBA buffer and return the
  /// normalized result, or null if recognition failed.
  Future<OcrResult?> recognizeRgba(
    Uint8List rgba,
    int width,
    int height,
  ) async {
    final TextRecognizer recognizer;
    try {
      recognizer = await _ensureRecognizer();
      final input = InputImage.fromBitmap(
        bitmap: rgba,
        width: width,
        height: height,
      );
      print('GUIDANCE_OCR_START ${width}x$height');
      final result = await recognizer.processImage(input);
      final blocks = _blocksFromRecognized(result, width, height);
      print('GUIDANCE_OCR_BLOCKS: ${blocks.length}');
      print('GUIDANCE_OCR_TEXT_LENGTH: ${result.text.trim().length}');
      return OcrResult(
        text: _clean(result.text),
        blocks: blocks,
        imageWidth: width,
        imageHeight: height,
      );
    } catch (e) {
      print('GUIDANCE_OCR_ERROR: $e');
      return null;
    }
  }

  /// Decode an image file to an upright portrait RGBA buffer (EXIF honoured).
  Future<({Uint8List rgba, int width, int height})?> decodeFileToPortraitRgba(
    String path,
  ) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final ui.Image image = frame.image;
      final ByteData? data =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final w = image.width;
      final h = image.height;
      image.dispose();
      if (data == null) return null;
      return (rgba: data.buffer.asUint8List(), width: w, height: h);
    } catch (e) {
      print('CAPTURE_OCR_DECODE_FAILED: $e');
      return null;
    }
  }

  /// Recognize text in a captured image file.
  Future<OcrResult> recognizePath(String path) async {
    try {
      final recognizer = await _ensureRecognizer();
      final decoded = await decodeFileToPortraitRgba(path);
      if (decoded == null) {
        print('CAPTURE_OCR_DECODE_NULL');
        return const OcrResult.empty();
      }
      print('CAPTURE_OCR_START ${decoded.width}x${decoded.height}');
      final input = InputImage.fromBitmap(
        bitmap: decoded.rgba,
        width: decoded.width,
        height: decoded.height,
      );
      final result = await recognizer.processImage(input);
      final blocks =
          _blocksFromRecognized(result, decoded.width, decoded.height);
      final text = _clean(result.text);
      print('CAPTURE_OCR_BLOCKS: ${blocks.length}');
      print('CAPTURE_OCR_TEXT_LENGTH: ${text.length}');
      return OcrResult(
        text: text,
        blocks: blocks,
        imageWidth: decoded.width,
        imageHeight: decoded.height,
      );
    } catch (e) {
      print('CAPTURE_OCR_ERROR: $e');
      return const OcrResult.empty();
    }
  }

  List<OcrTextBlock> _blocksFromRecognized(
    RecognizedText result,
    int width,
    int height,
  ) {
    final blocks = <OcrTextBlock>[
      for (final b in result.blocks)
        if (b.boundingBox.width > 0 && b.boundingBox.height > 0)
          OcrTextBlock(
            region: Rect.fromLTRB(
              (b.boundingBox.left / width).clamp(0.0, 1.0).toDouble(),
              (b.boundingBox.top / height).clamp(0.0, 1.0).toDouble(),
              (b.boundingBox.right / width).clamp(0.0, 1.0).toDouble(),
              (b.boundingBox.bottom / height).clamp(0.0, 1.0).toDouble(),
            ),
            text: b.text,
          ),
    ];
    // Reading order: top to bottom, then left to right.
    blocks.sort((a, b) {
      final byY = a.region.top.compareTo(b.region.top);
      return byY != 0 ? byY : a.region.left.compareTo(b.region.left);
    });
    return blocks;
  }

  /// Light text cleaning: trims lines, collapses runs of whitespace, keeps
  /// punctuation and paragraph breaks. No aggressive autocorrection.
  String _clean(String raw) {
    if (raw.trim().isEmpty) return '';
    final kept = <String>[];
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        // Preserve a paragraph break only when one already exists.
        if (kept.isNotEmpty && kept.last.isNotEmpty) kept.add('');
        continue;
      }
      kept.add(trimmed.replaceAll(RegExp(r'\s{2,}'), ' '));
    }
    while (kept.isNotEmpty && kept.last.isEmpty) {
      kept.removeLast();
    }
    return kept.join('\n');
  }

  /// Release the recognizer. Safe to call multiple times.
  Future<void> close() async {
    _isActive = false;
    final r = _recognizer;
    _recognizer = null;
    _closed = true;
    if (r == null) return;
    try {
      await r.close();
    } catch (_) {}
  }
}