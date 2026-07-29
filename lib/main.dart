import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/landing_screen.dart';
import 'theme/app_colors.dart';
import 'widgets/edge_swipe_back.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  runApp(const RobozzleRebootApp());
}

class RobozzleRebootApp extends StatelessWidget {
  const RobozzleRebootApp({super.key});

  // EdgeSwipeBack sits above the Navigator (it wraps MaterialApp's
  // builder), so it needs this to reach it instead of Navigator.of(context).
  static final navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Robozzle Reboot',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: AppColors.accent,
        scaffoldBackgroundColor: AppColors.background,
        useMaterial3: true,
      ),
      home: const LandingScreen(),
      debugShowCheckedModeBanner: false,
      builder: (context, child) =>
          EdgeSwipeBack(navigatorKey: navigatorKey, child: child!),
    );
  }
}
