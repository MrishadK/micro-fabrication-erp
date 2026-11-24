import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

//NEW: Imports for the lock screen
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';

import 'screens/dashboard_screen.dart';
import 'screens/welcome_restore_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  ErrorWidget.builder = (FlutterErrorDetails details) {
    bool isDebug = false;
    assert(() {
      isDebug = true;
      return true;
    }());

    // If in debug mode, show the normal red error screen so you can debug it.
    if (isDebug) {
      return ErrorWidget(details.exception);
    }

    // In Release mode, show a friendly fallback UI to the client.
    return Material(
      color: const Color(0xFFF5F7FA), // Matches your scaffold background
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFFF6D00),
              size: 60,
            ), // Secondary color
            const SizedBox(height: 16),
            const Text(
              "Oops! Something went wrong.",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A237E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "We'll push an update to fix this soon.",
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  };

  // --- STATUS BAR & NAVIGATION BAR CONFIGURATION ---
  // Only set system UI overlays on mobile platforms
  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
  }

  runApp(const ProviderScope(child: FabApp()));
}

class FabApp extends StatelessWidget {
  const FabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Micro',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A237E),
          primary: const Color(0xFF1A237E),
          secondary: const Color(0xFFFF6D00),
        ),
        textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme),

        // 🔥 PREMIUM PAGE TRANSITIONS 🔥
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: _PremiumPageTransitionsBuilder(),
            TargetPlatform.iOS: _PremiumPageTransitionsBuilder(),
            TargetPlatform.windows: _PremiumPageTransitionsBuilder(),
            TargetPlatform.linux: _PremiumPageTransitionsBuilder(),
            TargetPlatform.macOS: _PremiumPageTransitionsBuilder(),
          },
        ),

        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A237E),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
          ),
        ),

        cardTheme: const CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
      // 🔥 FIX: Replaced DashboardScreen with AuthWrapper
      home: const AuthWrapper(),
    );
  }
}

// ==========================================
//      🔥 THE GATEKEEPER LOCK SCREEN 🔥
// ==========================================
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isChecking = true;
  bool _isLocked = false;
  bool _showWelcome = false;
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _checkLockStatus();
  }

  Future<void> _checkLockStatus() async {
    final prefs = await SharedPreferences.getInstance();

    // On desktop: skip biometric, check for first-time setup
    if (Platform.isWindows || Platform.isLinux) {
      final hasCompletedSetup =
          prefs.getBool('has_completed_setup') ?? false;
      setState(() {
        _isChecking = false;
        _isLocked = false;
        _showWelcome = !hasCompletedSetup;
      });
      return;
    }

    // On mobile: original biometric lock logic
    final isLockEnabled = prefs.getBool('app_lock_enabled') ?? false;

    if (isLockEnabled) {
      setState(() => _isLocked = true);
      _authenticate(); // Instantly prompt for fingerprint
    } else {
      // Let them right into the app
      setState(() {
        _isChecking = false;
        _isLocked = false;
      });
    }
  }

  Future<void> _authenticate() async {
    try {
      final authenticated = await _auth.authenticate(
        localizedReason: 'Please authenticate to open the app',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly:
              false, // Allows them to use their PIN if fingerprint fails
        ),
      );

      if (authenticated && mounted) {
        setState(() {
          _isLocked = false;
          _isChecking = false;
        });
      } else if (mounted) {
        // They canceled the prompt
        setState(() => _isChecking = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. Show app logo with loading spinner for the split second it checks SharedPreferences
    if (_isChecking) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/Logo.png', width: 72, height: 72),
              const SizedBox(height: 24),
              const CircularProgressIndicator(color: Color(0xFFFF6D00), strokeWidth: 2.5),
            ],
          ),
        ),
      );
    }

    // 1.5 Desktop first-time: show welcome/restore screen
    if (_showWelcome) {
      return WelcomeRestoreScreen(
        onComplete: () => setState(() => _showWelcome = false),
      );
    }

    // 2. If locked and they canceled the prompt, show a beautiful lock screen
    if (_isLocked) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/Logo.png', width: 88, height: 88),
              const SizedBox(height: 20),
              const Text(
                "Micro Locked",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A237E),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Authenticate to open your workspace",
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _authenticate,
                icon: const Icon(Icons.fingerprint, color: Colors.white),
                label: const Text(
                  "Unlock Workspace",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A237E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const FlutterLogo(size: 14),
                  const SizedBox(width: 6),
                  Text(
                    "Micro Fabrication Suite",
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // 3. If everything is good, load the actual app
    return const DashboardScreen();
  }
}

// ==============================================
//  🔥 PREMIUM PAGE TRANSITION (Slide-up + Fade)
// ==============================================
class _PremiumPageTransitionsBuilder extends PageTransitionsBuilder {
  const _PremiumPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.0, 0.06),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
