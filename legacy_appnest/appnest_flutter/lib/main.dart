import 'package:flutter/material.dart';

import 'client.dart';
import 'screens/sign_in_screen.dart';
import 'features/home/home_screen.dart';
import 'navigation/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeClient();
  runApp(const MyApp());
}

/// Builds a theme for the given [brightness].
ThemeData _buildTheme(Brightness brightness) {
  const ink = Color(0xff25332e),
      teal = Color(0xff276c61),
      paper = Color(0xfff7f6f2);
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: teal,
      surface: Colors.white,
      primary: teal,
      onSurface: ink,
    ),
    scaffoldBackgroundColor: paper,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: paper,
      surfaceTintColor: Colors.transparent,
    ),
    textTheme: base.textTheme.copyWith(
      displaySmall: const TextStyle(
        fontFamily: 'Lora',
        fontSize: 42,
        height: 1.15,
        color: ink,
        fontWeight: FontWeight.w600,
      ),
      headlineSmall: const TextStyle(
        fontFamily: 'Lora',
        fontSize: 28,
        color: ink,
      ),
      bodyMedium: const TextStyle(
        fontSize: 15,
        height: 1.5,
        color: Color(0xff617069),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xffe2e5df)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xffd7ddd7)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final router = AppNestRouterDelegate();
  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'AppNest',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      themeMode: ThemeMode.light,
      routerDelegate: router,
      routeInformationParser: const AppNestRouteParser(),
    );
  }
}

class MyHomePage extends StatelessWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const SignInScreen(child: HomeScreen()),
      // To test authentication in this example app, uncomment the line below
      // and comment out the line above. This wraps the GreetingsScreen with a
      // SignInScreen, which automatically shows a sign-in UI when the user is
      // not authenticated and displays the GreetingsScreen once they sign in.
      //
      // body: SignInScreen(
      //   child: GreetingsScreen(
      //     onSignOut: () async {
      //       await client.auth.signOutDevice();
      //     },
      //   ),
      // ),
    );
  }
}
