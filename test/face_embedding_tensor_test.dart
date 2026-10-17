import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:visionpath/services/face_embedding_service.dart';

void main() {
  group('TensorFlow Lite buffer contract (ArcFace)', () {
    test('model-shaped float32 input is packed as raw little-endian bytes', () {
      final values = Float32List.fromList([0.0, -0.5, 1.25, 127.5]);
      final bytes = FaceEmbeddingService.float32AsBytes(values);
      expect(bytes, isA<Uint8List>());
      expect(bytes.length, values.length * 4);
      final decoded =
          bytes.buffer.asFloat32List(bytes.offsetInBytes, values.length);
      for (var i = 0; i < values.length; i++) {
        expect(decoded[i], values[i]);
      }
    });

    test('input byte length matches the 112x112x3 float32 tensor', () {
      final input = Float32List(112 * 112 * 3);
      expect(
        FaceEmbeddingService.float32AsBytes(input).length,
        112 * 112 * 3 * 4,
      );
    });

    test('the interpreter input is a Uint8List (not a flat numeric List)', () {
      final input = Float32List(112 * 112 * 3);
      final bytes = FaceEmbeddingService.float32AsBytes(input);
      expect(bytes, isA<Uint8List>());
      expect(bytes, isNot(isA<Float32List>()));
    });

    test('output byte buffer decodes to a 512-d float32 vector', () {
      const embeddingDim = 512;
      final outputBytes = Uint8List(embeddingDim * 4);
      expect(outputBytes.length, 2048);
      final out = outputBytes.buffer
          .asFloat32List(outputBytes.offsetInBytes, embeddingDim);
      expect(out, hasLength(embeddingDim));
      expect(out[0], 0.0);
    });
  });
}
