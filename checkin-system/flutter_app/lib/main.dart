import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'services/background_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.loadToken();
  await initBackgroundService(); // เริ่มติดตาม GPS ต่อเนื่อง
  runApp(const MardodiApp());
}

class MardodiApp extends StatelessWidget {
  const MardodiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MARDODI เช็คอิน',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3B5BDB),
        useMaterial3: true,
      ),
      home: ApiService.isLoggedIn ? const HomeScreen() : const LoginScreen(),
    );
  }
}
