import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/camera_service.dart';
import 'services/depth_analysis_service.dart';
import 'services/familiar_face_service.dart';
import 'services/face_embedding_service.dart';
import 'services/navigation_service.dart';
import 'services/object_detection_service.dart';
import 'services/path_analysis_service.dart';
import 'services/position_detection_service.dart';

void main() {
  // Pre-load the face-embedding model so registration/recognition screens
  // do not have to wait for it on first use.
  FaceEmbeddingService.instance.ensureLoaded();
  runApp(const VisionPathApp());
}

class VisionPathApp extends StatelessWidget {
  const VisionPathApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CameraService>.value(value: CameraService()),
        ChangeNotifierProvider<ObjectDetectionService>.value(
          value: ObjectDetectionService(),
        ),
        Provider<PositionDetectionService>.value(
          value: PositionDetectionService(),
        ),
        Provider<DepthAnalysisService>.value(value: DepthAnalysisService()),
        Provider<PathAnalysisService>.value(value: PathAnalysisService()),
        ChangeNotifierProvider<NavigationService>.value(
          value: NavigationService(),
        ),
        ChangeNotifierProvider<FamiliarFaceService>(
          create: (_) => FamiliarFaceService()..load(),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'VisionPath AI',

        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Roboto',
          scaffoldBackgroundColor: const Color(0xFFF8FAFD),
        ),

        home: const HomeScreen(),
      ),
    );
  }
}