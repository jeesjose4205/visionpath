import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/camera_service.dart';
import 'services/depth_analysis_service.dart';
import 'services/navigation_service.dart';
import 'services/object_detection_service.dart';
import 'services/path_analysis_service.dart';
import 'services/position_detection_service.dart';

void main() {
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