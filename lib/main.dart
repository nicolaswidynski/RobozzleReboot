import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/rating_prompt_store.dart';
import 'screens/landing_screen.dart';
import 'theme/app_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  // Once per process start — LandingScreen decides from this whether the
  // (one-time) rate-the-game prompt is due.
  await RatingPromptStore().recordLaunch();
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
