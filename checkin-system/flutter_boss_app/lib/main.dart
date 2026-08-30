import 'package:flutter/material.dart';
import 'config.dart';
import 'services/api_service.dart';
import 'screens/login_screen.dart';
import 'screens/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.loadToken();
  runApp(const ThanakonBoxBossApp());
}

class ThanakonBoxBossApp extends StatelessWidget {
  const ThanakonBoxBossApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'THANAKON-BOX หัวหน้า',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3B5BDB),
        useMaterial3: true,
      ),
      home: ApiService.isLoggedIn
          ? const AppShell()
          : LoginScreen(
              notice: ApiService.sessionExpiredOnStart
                  ? Config.sessionExpiredMessage
                  : null,
            ),
    );
  }
}
