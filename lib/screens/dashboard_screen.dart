import 'dart:io'; // 🔥 NEW: Required for internet check
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
// 🔥 EXTERNAL PACKAGES 🔥 (mobile-only, guarded by platform checks)
import 'package:shorebird_code_push/shorebird_code_push.dart'
    if (dart.library.io) 'package:shorebird_code_push/shorebird_code_push.dart';
import 'package:restart_app/restart_app.dart'
    if (dart.library.io) 'package:restart_app/restart_app.dart';

// 🔥 PROJECT IMPORTS 🔥
import '../services/google_drive_service.dart';
import '../services/startup/startup_result.dart';
import '../widgets/receipt_form.dart';
import '../widgets/nav_bar.dart';
import '../providers.dart';
import 'active_jobs_view.dart';
import 'client_history_view.dart';
import 'history_view.dart';
import 'settings_view.dart';
import 'wages_view.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  final StartupResult? startupResult;
  const DashboardScreen({super.key, this.startupResult});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final Color _primaryColor = const Color(0xFF1A237E);
  bool _showStartupBanner = false;
  // Only create ShorebirdUpdater on mobile platforms
  late final ShorebirdUpdater? _updater = (Platform.isAndroid || Platform.isIOS)
      ? ShorebirdUpdater()
      : null;

  bool _showUpdateWindow = false;
  String _updateStatusText = "Checking for updates...";
  bool _isChecking = false;
  bool _isConnectingDrive = false;

  Future<void> _handleConnectDrive() async {
    setState(() => _isConnectingDrive = true);
    try {
      final success = await GoogleDriveService.instance.signIn();
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "Connected to Google Drive: ${GoogleDriveService.instance.email ?? 'Success'}",
              ),
              backgroundColor: Colors.green[700],
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Google Sign-In was cancelled or could not be completed.",
              ),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Connection error: $e"),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isConnectingDrive = false);
      }
    }
  }

  void _showQuickCloudDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.cloud_sync_rounded, color: Color(0xFF1A237E)),
            SizedBox(width: 10),
            Text(
              "Google Drive Sync",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Account: ${GoogleDriveService.instance.email ?? 'Connected'}",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 12),
            const Text(
              "Sync your jobs, billing and worker records with Google Drive:",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  _triggerDriveBackup();
                },
                icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                label: const Text("BACKUP DATABASE TO DRIVE"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  _triggerDriveRestore();
                },
                icon: const Icon(Icons.cloud_download_rounded, size: 18),
                label: const Text("RESTORE FROM ANDROID CLOUD"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primaryColor,
                  side: BorderSide(color: _primaryColor.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(navIndexProvider.notifier).state = 4;
            },
            child: const Text("Open Full Settings"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  Future<void> _triggerDriveBackup() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Uploading backup to Google Drive..."),
        duration: Duration(seconds: 1),
      ),
    );
    final id = await GoogleDriveService.instance.uploadDatabase();
    if (mounted) {
      if (id != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Backup uploaded successfully!"),
            backgroundColor: Colors.green[700],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Backup failed. Check internet."),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _triggerDriveRestore() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.phone_android_rounded, color: Color(0xFF1A237E)),
            SizedBox(width: 10),
            Text("Restore from Android Backup?"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              "Please ensure you tapped 'BACKUP NOW' on your Android phone (Settings → Cloud Sync) first so your latest records are in Google Drive.",
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            SizedBox(height: 12),
            Text(
              "Restoring will update your PC workstation with that cloud backup.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A237E),
              foregroundColor: Colors.white,
            ),
            child: const Text("Yes, Restore Now"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Restoring database from Google Drive..."),
        duration: Duration(seconds: 2),
      ),
    );
    final success = await GoogleDriveService.instance.restoreLatestBackup();
    if (mounted) {
      if (success) {
        ref.invalidate(activeJobsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Data restored successfully!"),
            backgroundColor: Colors.green[700],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Restore failed or no backup found in 'MICRO BACKUP'.",
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.startupResult != null &&
        widget.startupResult!.hasInAppNotification) {
      _showStartupBanner = true;
    }
    _initDashboard();
  }

  Widget _buildStartupBanner() {
    if (!_showStartupBanner || widget.startupResult == null) {
      return const SizedBox.shrink();
    }
    final notif = widget.startupResult!.inAppNotificationMessage!;
    final type = widget.startupResult!.inAppNotificationType;

    Color bg;
    Color border;
    Color text;
    IconData icon;

    if (type == 'warning') {
      bg = const Color(0xFFFFFBEB); // Amber 50
      border = const Color(0xFFFDE68A);
      text = const Color(0xFF92400E);
      icon = Icons.cloud_off_rounded;
    } else if (type == 'info') {
      bg = const Color(0xFFEFF6FF); // Blue 50
      border = const Color(0xFFBFDBFE);
      text = const Color(0xFF1E40AF);
      icon = Icons.wifi_off_rounded;
    } else {
      bg = const Color(0xFFF0FDF4); // Green 50
      border = const Color(0xFFBBF7D0);
      text = const Color(0xFF166534);
      icon = Icons.cloud_done_rounded;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: text),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              notif,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: text,
              ),
            ),
          ),
          if (type == 'warning') ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                setState(() => _showStartupBanner = false);
                ref.read(navIndexProvider.notifier).state = 4; // Settings view
              },
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: text,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: BorderSide(color: border),
                ),
              ),
              child: const Text(
                "Open Settings",
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
              ),
            ),
          ],
          const SizedBox(width: 6),
          IconButton(
            onPressed: () => setState(() => _showStartupBanner = false),
            icon: Icon(Icons.close_rounded, size: 16, color: text),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: "Dismiss",
          ),
        ],
      ),
    );
  }

  Future<void> _initDashboard() async {
    await _checkAutoBackup();
    // Only check for updates on mobile (Shorebird is Android/iOS only)
    if (!_isChecking && (Platform.isAndroid || Platform.isIOS)) {
      _checkForUpdates();
    }
  }

  Future<void> _checkForUpdates() async {
    final updater = _updater;
    if (updater == null) return;

    setState(() {
      _isChecking = true;
      _showUpdateWindow = true;
      _updateStatusText = "Checking for updates...";
    });

    try {
      await Future.delayed(const Duration(seconds: 1));
      final status = await updater.checkForUpdate();

      if (status == UpdateStatus.outdated) {
        setState(() => _updateStatusText = "Downloading new patch...");
        try {
          await updater.update();
          if (mounted) {
            setState(() {
              // Leave the window open with restart instructions
              _updateStatusText =
                  "Update downloaded. Please restart the app completely to apply.";
            });
            _showUpdateDialog();
          }
        } catch (e) {
          debugPrint("Shorebird Update Download Error: $e");
          if (mounted) {
            setState(
              () => _updateStatusText = "Download failed. Check your internet.",
            );
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "Failed to download update. Please try again later.",
                ),
                backgroundColor: Colors.red,
              ),
            );
            await Future.delayed(const Duration(seconds: 3));
            if (mounted) setState(() => _showUpdateWindow = false);
          }
        }
      } else {
        setState(() => _updateStatusText = "App is up to date!");
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) setState(() => _showUpdateWindow = false);
      }
    } catch (e) {
      debugPrint("Shorebird Error: $e");
      if (mounted) {
        setState(() => _updateStatusText = "Update check failed");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Could not check for updates. Please check your internet connection.",
            ),
            backgroundColor: Colors.orange,
          ),
        );
        await Future.delayed(const Duration(seconds: 3));
        if (mounted) setState(() => _showUpdateWindow = false);
      }
    } finally {
      if (mounted) _isChecking = false;
    }
  }

  void _showUpdateDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(
                Icons.system_update_rounded,
                color: Colors.green[600],
                size: 28,
              ),
              const SizedBox(width: 10),
              const Text(
                "Update Ready",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: const Text(
            "A new system update was just downloaded in the background!\n\nDo you want to restart the app now to apply the new features?",
            style: TextStyle(fontSize: 14, height: 1.5, color: Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "Later",
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Restart.restartApp(),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                "Restart Now",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  // ==========================================
  //               BACKUP LOGIC (UPDATED)
  // ==========================================
  Future<void> _checkAutoBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final bool autoBackup = prefs.getBool('auto_backup') ?? false;

    if (autoBackup) {
      // 1. Ping Google to check if internet is actually working
      bool hasInternet = false;
      try {
        final result = await InternetAddress.lookup('google.com');
        if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
          hasInternet = true;
        }
      } on SocketException catch (_) {
        hasInternet = false;
      }

      // 2. If no internet, show orange warning and cancel backup
      if (!hasInternet) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("No internet connection. Auto-backup paused."),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // 3. Proceed with upload on both mobile and desktop
      debugPrint("Auto-Backup: Starting background upload...");
      GoogleDriveService.instance.uploadDatabase().then((id) {
        if (id != null) {
          debugPrint("Auto-Backup: Success (File ID: $id)");
          final now = DateTime.now().toString().split('.')[0];
          prefs.setString('last_backup_time', now);
        }
      });
    }
  }

  Widget _buildUpdateStatusOverlay() {
    if (!_showUpdateWindow) return const SizedBox.shrink();
    final double topPadding = MediaQuery.of(context).padding.top + 10;

    return Positioned(
      top: topPadding,
      left: 16,
      right: 16,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutBack,
        builder: (context, value, child) {
          return Opacity(
            opacity: value.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, (1 - value) * -20),
              child: child,
            ),
          );
        },
        child: Material(
          elevation: 8,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.blue.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                (_updateStatusText.contains("up to date") ||
                        _updateStatusText.contains("restart"))
                    ? const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 20,
                      )
                    : const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    _updateStatusText,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: _primaryColor,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() => _showUpdateWindow = false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final navIndex = ref.watch(navIndexProvider);
    final List<Widget> pages = [
      const ActiveJobsView(),
      const ClientHistoryView(),
      const HistoryView(),
      const WagesView(),
      const SettingsView(),
    ];

    final bool isDesktop = MediaQuery.of(context).size.width >= 800;

    if (isDesktop) {
      return Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        body: Stack(
          children: [
            Row(
              children: [
                // 1. Desktop Sidebar Navigation Rail
                _buildDesktopSidebar(navIndex),
                // 2. Main Desktop Workstation Content
                Expanded(
                  child: Column(
                    children: [
                      // Desktop Top Header Bar
                      _buildDesktopHeader(navIndex),
                      // Non-intrusive startup notification banner
                      _buildStartupBanner(),
                      // Active View Canvas
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: _buildPageTransition,
                          child: KeyedSubtree(
                            key: ValueKey<int>(navIndex),
                            child: pages[navIndex],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            _buildUpdateStatusOverlay(),
          ],
        ),
      );
    }

    // Mobile Layout (Phones / narrow screens)
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              _buildStartupBanner(),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: _buildPageTransition,
                  child: KeyedSubtree(
                    key: ValueKey<int>(navIndex),
                    child: pages[navIndex],
                  ),
                ),
              ),
            ],
          ),
          _buildUpdateStatusOverlay(),
        ],
      ),
      floatingActionButton: AnimatedScale(
        scale: navIndex == 0 ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        child: FloatingActionButton.extended(
          onPressed: () => ReceiptForm.show(context),
          backgroundColor: const Color(0xFFFF6D00),
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text(
            "NEW JOB",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ),
      bottomNavigationBar: CustomNavBar(
        selectedIndex: navIndex,
        onDestinationSelected: (i) =>
            ref.read(navIndexProvider.notifier).state = i,
      ),
    );
  }

  /// Modern Desktop Left Sidebar (Fixed 250px)
  Widget _buildDesktopSidebar(int selectedIndex) {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_primaryColor, const Color(0xFF0C133B)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(4, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // 1. Sidebar Brand Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/app.png',
                      width: 50,
                      height: 50,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "MICRO",
                      style: GoogleFonts.orbitron(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                      ),
                    ),
                    Text(
                      "FABRICATION SUITE",
                      style: GoogleFonts.montserrat(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. Primary Desktop CTA: "+ NEW JOB ORDER"
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: () => ReceiptForm.show(context),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text(
                  "NEW JOB ORDER",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    fontSize: 13,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6D00),
                  foregroundColor: Colors.white,
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 3. Navigation Menu Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _buildSidebarNavItem(
                  index: 0,
                  selectedIndex: selectedIndex,
                  icon: Icons.dashboard_rounded,
                  label: "Active Jobs",
                ),
                _buildSidebarNavItem(
                  index: 1,
                  selectedIndex: selectedIndex,
                  icon: Icons.people_alt_rounded,
                  label: "Clients Directory",
                ),
                _buildSidebarNavItem(
                  index: 2,
                  selectedIndex: selectedIndex,
                  icon: Icons.inventory_2_rounded,
                  label: "Job Archive",
                ),
                _buildSidebarNavItem(
                  index: 3,
                  selectedIndex: selectedIndex,
                  icon: Icons.engineering_rounded,
                  label: "Wages & Attendance",
                ),
                _buildSidebarNavItem(
                  index: 4,
                  selectedIndex: selectedIndex,
                  icon: Icons.settings_rounded,
                  label: "Settings & Sync",
                ),
              ],
            ),
          ),

          // 4. Bottom Google Drive Cloud Sync Status Widget
          _buildSidebarCloudWidget(),
        ],
      ),
    );
  }

  Widget _buildSidebarNavItem({
    required int index,
    required int selectedIndex,
    required IconData icon,
    required String label,
  }) {
    final bool isSelected = index == selectedIndex;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: isSelected ? Colors.white.withOpacity(0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => ref.read(navIndexProvider.notifier).state = index,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected
                      ? const Color(0xFFFF6D00)
                      : Colors.white.withOpacity(0.7),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : Colors.white.withOpacity(0.7),
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6D00),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Cloud status tile at bottom of sidebar
  Widget _buildSidebarCloudWidget() {
    final bool isSignedIn = GoogleDriveService.instance.isSignedIn;
    final String email =
        GoogleDriveService.instance.email ?? "Drive Not Connected";

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.cloud_sync_rounded,
                size: 18,
                color: isSignedIn ? Colors.greenAccent : Colors.orangeAccent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isSignedIn ? "Google Drive Connected" : "Cloud Sync Offline",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            email,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 10,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 30,
            child: _isConnectingDrive
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        "Connecting...",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  )
                : OutlinedButton.icon(
                    onPressed: () {
                      if (!isSignedIn) {
                        _handleConnectDrive();
                      } else {
                        _showQuickCloudDialog();
                      }
                    },
                    icon: Icon(
                      isSignedIn
                          ? Icons.cloud_sync_rounded
                          : Icons.login_rounded,
                      size: 14,
                    ),
                    label: Text(
                      isSignedIn ? "Backup & Restore" : "Connect Drive",
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: isSignedIn
                          ? Colors.white.withOpacity(0.08)
                          : const Color(0xFFFF6D00),
                      side: BorderSide(
                        color: isSignedIn
                            ? Colors.white.withOpacity(0.3)
                            : const Color(0xFFFF6D00),
                      ),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageTransition(Widget child, Animation<double> animation) {
    final offsetAnim = Tween<Offset>(
      begin: const Offset(0.02, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
    final fadeAnim = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: fadeAnim,
      child: SlideTransition(position: offsetAnim, child: child),
    );
  }

  /// Modern Desktop Top Header Bar
  Widget _buildDesktopHeader(int selectedIndex) {
    final titles = [
      "Active Jobs & Work Orders",
      "Clients Directory",
      "Job Archive & Records",
      "Wages & Worker Attendance",
      "Workstation Settings & Cloud Sync",
    ];

    final subtitles = [
      "Real-time overview of current fabrication projects and billing status",
      "Manage customer contact profiles, history and account ledgers",
      "Search and review archived or delivered work orders",
      "Daily worker attendance, overtime rates and payroll records",
      "Cloud backup, database restore and system preferences",
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isCompact = constraints.maxWidth < 700;
        final bool isVeryCompact = constraints.maxWidth < 560;

        return Container(
          height: 68,
          padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 28),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Colors.grey.withOpacity(0.2)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // View Title & Subtitle
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titles[selectedIndex],
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1E293B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitles[selectedIndex],
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Header Right Status & Actions
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Google Drive Cloud Sync quick pill
                  InkWell(
                    onTap: () {
                      if (GoogleDriveService.instance.isSignedIn) {
                        _showQuickCloudDialog();
                      } else {
                        _handleConnectDrive();
                      }
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: GoogleDriveService.instance.isSignedIn
                            ? Colors.green[50]
                            : Colors.orange[50],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: GoogleDriveService.instance.isSignedIn
                              ? Colors.green[200]!
                              : Colors.orange[200]!,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cloud_done_rounded,
                            size: 16,
                            color: GoogleDriveService.instance.isSignedIn
                                ? Colors.green[700]
                                : Colors.orange[700],
                          ),
                          if (!isVeryCompact) ...[
                            const SizedBox(width: 6),
                            Text(
                              GoogleDriveService.instance.isSignedIn
                                  ? "Drive Synced"
                                  : "Drive Offline",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: GoogleDriveService.instance.isSignedIn
                                    ? Colors.green[800]
                                    : Colors.orange[800],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // Date Badge (hidden on compact widths to prevent any right overflow)
                  if (!isCompact) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 13,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 6),
                          Text(
                            DateTime.now().toString().split(' ')[0],
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(width: 10),

                  // + New Job Quick CTA
                  ElevatedButton.icon(
                    onPressed: () => ReceiptForm.show(context),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text(
                      "New Job",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6D00),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
