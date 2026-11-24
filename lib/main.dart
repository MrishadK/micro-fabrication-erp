import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/legacy.dart';

// NEW: Imports for secure 6-digit PIN app lock
import 'package:shared_preferences/shared_preferences.dart';
import 'services/app_lock_service.dart';
import 'screens/pin_lock_screen.dart';

import 'screens/dashboard_screen.dart';
import 'screens/welcome_restore_screen.dart';
import 'screens/splash/splash_screen.dart';
import 'services/startup/startup_result.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop Window Management: Frameless 900x506 splash window on Windows
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.unmaximize();
    const windowOptions = WindowOptions(
      size: Size(900, 506),
      center: true,
      backgroundColor: Colors.white,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.unmaximize();
      await windowManager.setAsFrameless();
      await windowManager.setResizable(false);
      await windowManager.setSize(const Size(900, 506));
      await windowManager.center();
      await windowManager.show();
      await windowManager.focus();
    });
  }

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

class FabApp extends StatefulWidget {
  const FabApp({super.key});

  @override
  State<FabApp> createState() => _FabAppState();
}

class _FabAppState extends State<FabApp> with WindowListener {
  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowResize() async {
    if (Platform.isWindows) {
      final isMax = await windowManager.isMaximized();
      if (!isMax) {
        final size = await windowManager.getSize();
        if (size.width > 950 && size.height > 550) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setDouble('window_width', size.width);
          await prefs.setDouble('window_height', size.height);
        }
      }
    }
  }

  @override
  void onWindowMaximize() async {
    if (Platform.isWindows) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('window_is_maximized', true);
    }
  }

  @override
  void onWindowUnmaximize() async {
    if (Platform.isWindows) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('window_is_maximized', false);
    }
  }

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
      // On Windows: Start with WindowsSplashScreen. On mobile: AuthWrapper (biometrics).
      home: Platform.isWindows ? const WindowsAppRoot() : const AuthWrapper(),
    );
  }
}

// ========================================================
//   🔥 WINDOWS APPLICATION ROOT (Splash -> PIN -> Workspace) 🔥
// ========================================================
class WindowsAppRoot extends StatefulWidget {
  const WindowsAppRoot({super.key});

  @override
  State<WindowsAppRoot> createState() => _WindowsAppRootState();
}

class _WindowsAppRootState extends State<WindowsAppRoot> {
  bool _isInitializing = true;
  StartupResult? _startupResult;
  bool _showWelcome = false;
  bool _isLocked = false;

  Future<void> _handleStartupComplete(StartupResult result) async {
    final prefs = await SharedPreferences.getInstance();
    final hasCompletedSetup = prefs.getBool('has_completed_setup') ?? false;
    final isLockEnabled = await AppLockService.instance.isLockEnabled();

    // Restore user window preferences or standard desktop workspace defaults
    final bool isMaximized = prefs.getBool('window_is_maximized') ?? false;
    final double savedWidth = prefs.getDouble('window_width') ?? 1280;
    final double savedHeight = prefs.getDouble('window_height') ?? 720;

    // Switch from frameless splash to standard application window
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setResizable(true);
    await windowManager.setSize(Size(savedWidth, savedHeight));
    await windowManager.center();
    if (isMaximized) {
      await windowManager.maximize();
    }

    if (mounted) {
      setState(() {
        _startupResult = result;
        _isInitializing = false;
        _showWelcome = !hasCompletedSetup;
        _isLocked = isLockEnabled;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return WindowsSplashScreen(
        onInitializationComplete: _handleStartupComplete,
      );
    }

    // 🔒 6-Digit App Lock Screen (Secure Desktop Protection)
    if (_isLocked) {
      return PinLockScreen(
        onUnlocked: () => setState(() => _isLocked = false),
      );
    }

    if (_showWelcome) {
      return WelcomeRestoreScreen(
        onComplete: () => setState(() => _showWelcome = false),
      );
    }

    return DashboardScreen(startupResult: _startupResult);
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

  @override
  void initState() {
    super.initState();
    _checkLockStatus();
  }

  Future<void> _checkLockStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final hasCompletedSetup = prefs.getBool('has_completed_setup') ?? false;
    final isLockEnabled = await AppLockService.instance.isLockEnabled();

    if (mounted) {
      setState(() {
        _isChecking = false;
        _showWelcome = !hasCompletedSetup;
        _isLocked = isLockEnabled;
      });
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
              Image.asset('assets/app.png', width: 72, height: 72),
              const SizedBox(height: 24),
              const CircularProgressIndicator(color: Color(0xFFFF6D00), strokeWidth: 2.5),
            ],
          ),
        ),
      );
    }

    // 2. 6-Digit PIN App Lock Screen
    if (_isLocked) {
      return PinLockScreen(
        onUnlocked: () => setState(() => _isLocked = false),
      );
    }

    // 3. First-time setup
    if (_showWelcome) {
      return WelcomeRestoreScreen(
        onComplete: () => setState(() => _showWelcome = false),
      );
    }

    // 4. Load the dashboard
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
