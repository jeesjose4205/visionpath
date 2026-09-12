import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const VisionPathApp());
}

class VisionPathApp extends StatelessWidget {
  const VisionPathApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'VisionPath AI',

      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFFF8FAFD),
      ),

      home: const HomeScreen(),
    );
  }
}
