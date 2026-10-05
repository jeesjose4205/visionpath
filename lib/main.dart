import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'l10n/app_localizations.dart';
import 'models/app_settings.dart';
import 'screens/navigate_screen.dart';
import 'services/camera_service.dart';
import 'services/depth_analysis_service.dart';
import 'services/emergency_contact_service.dart';
import 'services/familiar_face_service.dart';
import 'services/face_embedding_service.dart';
import 'services/navigation_service.dart';
import 'services/object_detection_service.dart';
import 'services/path_analysis_service.dart';
import 'services/position_detection_service.dart';
import 'services/settings_service.dart';
import 'services/sos_service.dart';
import 'services/voice_service.dart';
import 'widgets/settings_scope.dart';
import 'widgets/sos_gesture.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Pre-load the face-embedding model so registration/recognition screens
  // do not have to wait for it on first use.
  FaceEmbeddingService.instance.ensureLoaded();
  // Load persisted settings before the first frame so theme/voice behaviour
  // are correct immediately.
  await SettingsService.instance.load();
  // Point the single shared TTS engine at the loaded voice settings and keep it
  // there. Screens no longer configure rate/volume/language themselves, so this
  // is what makes Speech Rate / Volume / Language apply app-wide.
  VoiceService.bindToSettings();
  // Emergency contacts must already be in memory: SOS has to be able to call
  // the primary contact the instant it activates, with no async gap.
  await EmergencyContactService.instance.load();
  runApp(const VisionPathApp());
}

class VisionPathApp extends StatelessWidget {
  const VisionPathApp({super.key});

  @override
  Widget build(BuildContext context) {
    // SOS needs to mute navigation guidance for the whole app, so it is given
    // the app-wide navigation service rather than a copy.
    SosService.instance.attachNavigation(NavigationService.instance);

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
          value: NavigationService.instance,
        ),
        ChangeNotifierProvider<FamiliarFaceService>(
          create: (_) => FamiliarFaceService()..load(),
        ),
        ChangeNotifierProvider<SettingsService>.value(
          value: SettingsService.instance,
        ),
        // The emergency procedure is app-scoped: its alert must survive
        // navigating away from the SOS screen, so it is a shared instance
        // rather than something created per route.
        ChangeNotifierProvider<SosService>.value(value: SosService.instance),
      ],
      child: const _AppRoot(),
    );
  }
}

class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final SosRouteObserver _sosObserver = SosRouteObserver();

  @override
  Widget build(BuildContext context) {
    // Read both theme values together: High Contrast composes with whichever base
    // theme is active, so System / Light / Dark keep working independently.
final settings = Provider.of<SettingsService>(context);
    final theme = settings.theme;
    final bool highContrast = settings.highContrast;
    // Text Size, High Contrast and Large Buttons all resolve here, once, above
    // the navigator. Text scaling is applied inside SettingsScope (it is a
    // MediaQuery concern); theme-level changes belong on ThemeData.
    final double controlScale = settings.controlScaleFactor;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'VisionPath AI',
      navigatorKey: _navigatorKey,
      navigatorObservers: [_sosObserver],
      // Global gesture layer above every routed screen: a deliberate
      // three-finger swipe from the top of the screen downwards opens the
      // existing emergency SOS screen.
      //
      // SettingsScope sits above it so text scaling, high contrast, large
      // controls, reduced motion and voice-first mode are installed once, for
      // every route, instead of each screen reading SettingsService itself.
      builder: (context, child) => SettingsScope(
        child: SosGestureOverlay(
          navigatorKey: _navigatorKey,
          observer: _sosObserver,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      theme: _resolveTheme(_lightTheme, highContrast, controlScale),
      darkTheme: _resolveTheme(_darkTheme, highContrast, controlScale),
      // App Language resolves through AppLocalizations, which only accepts
      // languages the app actually ships reviewed strings for. Anything else
      // falls back to English rather than rendering a half-translated UI.
      locale: settings.appLocale,
      supportedLocales: AppLocalizations.supportedLanguages
          .map((String tag) => Locale(tag))
          .toList(growable: false),
      themeMode: theme == AppThemePreference.dark
          ? ThemeMode.dark
          : theme == AppThemePreference.light
              ? ThemeMode.light
              : ThemeMode.system,
      // Fallback for any named/unknown route lookups (the launch stack and all
      // screen pushes use explicit routes, so this only fires defensively).
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const NavigateScreen(),
      ),
      // The app opens straight into the Navigate (camera guidance) screen.
      onGenerateInitialRoutes: (initialRouteName) => <Route<dynamic>>[
        MaterialPageRoute<void>(
          settings: RouteSettings(name: initialRouteName),
          builder: (_) => const NavigateScreen(),
        ),
      ],
    );
  }
}

/// Composes the three display settings onto a base theme.
///
/// High Contrast and Large Buttons are independent, so they are applied in a
/// fixed order (contrast first, then control scale) rather than by enumerating
/// every theme/contrast/scale combination. System / Light / Dark keep working
/// unchanged because each base theme is resolved on its own.
ThemeData _resolveTheme(ThemeData base, bool highContrast, double controlScale) {
  final ThemeData base2 = highContrast ? applyHighContrast(base) : base;
  return applyControlScale(base2, controlScale);
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