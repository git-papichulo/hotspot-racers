import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const RacersApp());
}

class RacersApp extends StatelessWidget {
  const RacersApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hotspot Racers',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF00BCD4),
        scaffoldBackgroundColor: const Color(0xFF1B2430),
        useMaterial3: true,
      ),
      home: const MenuScreen(),
    );
  }
}
