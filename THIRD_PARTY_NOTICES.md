# Third-Party Notices

VisionPath bundles the following third-party models and assets. They are used
for fully on-device (offline) processing.

## Face detection — SCRFD

- File: `assets/ml/scrfd_640.tflite`
- Source: InsightFace model zoo / model `scrfd_500m_bnkps`
  (originally from the `ykk648/face_lib` ONNX export, converted to TFLite).
- License: InsightFace model zoo statement — **"ALL models are available for
  non-commercial research purposes only."**

## Face recognition — ArcFace (w600k_mbf)

- File: `assets/ml/arcface_w600k_mbf.tflite`
- Source: InsightFace model zoo / model `w600k_mbf`
  (originally from the `ykk648/face_lib` ONNX export, converted to TFLite).
- License: InsightFace model zoo statement — **"ALL models are available for
  non-commercial research purposes only."**

## Legacy face model — MobileFaceNet

- File: `assets/ml/mobilefacenet.tflite` (no longer bundled or used)
- Retained only for reference/migration.

## Speech recognition — Vosk

- File: `assets/models/vosk-model-small-en-us-0.15.zip`
- License: Apache License 2.0.

> Note: the InsightFace models above are restricted to non-commercial research
> use. Any commercial distribution of this application must obtain an
> appropriate license or replace these models with commercially licensed
> equivalents. Contact the InsightFace project for licensing.