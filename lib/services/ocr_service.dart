import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/ocr_result.dart';
import '../utils/portrait_rgba.dart' as portrait_rgba;

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

  /// Convert a YUV CameraImage frame into an upright portrait RGBA buffer.
  /// Delegates to the shared [convertFrameToPortraitRgba] utility so every
  /// consumer of the live stream uses identical pixel math.
  ({Uint8List rgba, int width, int height})? convertFrameToPortraitRgba(
    CameraImage image,
    int quarterTurns,
  ) {
    return portrait_rgba.convertFrameToPortraitRgba(
      image,
      quarterTurns,
    );
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