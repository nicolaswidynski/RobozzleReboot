import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/landing_screen.dart';
import 'theme/app_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  runApp(const RobozzleRebootApp());
}

class RobozzleRebootApp extends StatelessWidget {
  const RobozzleRebootApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Robozzle Reboot',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: AppColors.accent,
        scaffoldBackgroundColor: AppColors.background,
        useMaterial3: true,
      ),
      home: const LandingScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
