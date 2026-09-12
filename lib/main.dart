import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/camera_service.dart';

void main() {
  runApp(const VisionPathApp());
}

class VisionPathApp extends StatelessWidget {
  const VisionPathApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<CameraService>.value(
      value: CameraService(),
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
