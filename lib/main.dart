import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/app_settings.dart';
import 'screens/home_screen.dart';
import 'services/camera_service.dart';
import 'services/depth_analysis_service.dart';
import 'services/familiar_face_service.dart';
import 'services/face_embedding_service.dart';
import 'services/navigation_service.dart';
import 'services/object_detection_service.dart';
import 'services/path_analysis_service.dart';
import 'services/position_detection_service.dart';
import 'services/settings_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Pre-load the face-embedding model so registration/recognition screens
  // do not have to wait for it on first use.
  FaceEmbeddingService.instance.ensureLoaded();
  // Load persisted settings before the first frame so theme/voice behaviour
  // are correct immediately.
  await SettingsService.instance.load();
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
        ChangeNotifierProvider<SettingsService>.value(
          value: SettingsService.instance,
        ),
      ],
      child: const _AppRoot(),
    );
  }
}

class _AppRoot extends StatelessWidget {
  const _AppRoot();

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<SettingsService>(context).theme;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'VisionPath AI',
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: theme == AppThemePreference.dark
          ? ThemeMode.dark
          : theme == AppThemePreference.light
              ? ThemeMode.light
              : ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}

const Color _kInk = Color(0xFF15233D);
const Color _kBlue = Color(0xFF1769E0);
const Color _kBgLight = Color(0xFFF8FAFD);
const Color _kBgDark = Color(0xFF0B1424);

final ThemeData _lightTheme = ThemeData(
  useMaterial3: true,
  fontFamily: 'Roboto',
  scaffoldBackgroundColor: _kBgLight,
  colorScheme: ColorScheme.fromSeed(
    seedColor: _kBlue,
    brightness: Brightness.light,
  ),
  switchTheme: SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? Colors.white
          : _kInk.withValues(alpha: 0.4),
    ),
    trackColor: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.selected) ? _kBlue : const Color(0xFFCBD5E1),
    ),
  ),
);

final ThemeData _darkTheme = ThemeData(
  useMaterial3: true,
  fontFamily: 'Roboto',
  scaffoldBackgroundColor: _kBgDark,
  colorScheme: ColorScheme.fromSeed(
    seedColor: _kBlue,
    brightness: Brightness.dark,
    surface: const Color(0xFF111C30),
  ),
);