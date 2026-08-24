import 'package:flutter/material.dart';
import 'config.dart';
import 'services/api_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.loadToken();
  runApp(const ThanakonBoxApp());
}

class ThanakonBoxApp extends StatelessWidget {
  const ThanakonBoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'THANAKON-BOX เช็คอิน',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3B5BDB),
        useMaterial3: true,
      ),
      home: ApiService.isLoggedIn
          ? const HomeScreen()
          : LoginScreen(
              notice: ApiService.sessionExpiredOnStart
                  ? Config.sessionExpiredMessage
                  : null,
            ),
    );
  }
}
