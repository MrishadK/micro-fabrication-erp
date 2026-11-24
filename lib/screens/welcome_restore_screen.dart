import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/google_drive_service.dart';
import '../services/google_drive_service_desktop.dart';

/// Modern Desktop Opening & Onboarding Screen.
/// Designed specifically for PC/Desktop workstations with rich dual-column layout,
/// prominent theme colors, and seamless 1-click Google Drive restore from Android.
class WelcomeRestoreScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const WelcomeRestoreScreen({super.key, required this.onComplete});

  @override
  State<WelcomeRestoreScreen> createState() => _WelcomeRestoreScreenState();
}

class _WelcomeRestoreScreenState extends State<WelcomeRestoreScreen>
    with SingleTickerProviderStateMixin {
  bool _isRestoring = false;
  String _statusText = '';
  bool _restoreSuccess = false;
  bool _showError = false;
  String _errorText = '';
  List<Map<String, dynamic>> _cloudBackups = [];

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  static const Color _primary = Color(0xFF1A237E); // Theme Primary Deep Navy
  static const Color _accent = Color(0xFFFF6D00); // Theme Accent Orange
  static const Color _bg = Color(0xFFF0F4F8); // Clean Slate Background

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _completeSetup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_completed_setup', true);
    widget.onComplete();
  }

  /// 1. Prompt Confirmation: Ensure Android Backup is Done
  Future<void> _promptEnsureAndroidBackup() async {
    final bool? proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF4285F4).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.phone_android_rounded, color: Color(0xFF4285F4), size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Ensure Android Backup is Done',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Before restoring on PC, please verify that you tapped "BACKUP NOW" on your Android phone so Google Drive has your latest data:',
              style: TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF334155)),
            ),
            const SizedBox(height: 14),
            _buildDialogStep(
              number: '1',
              title: 'Open Micro on Android phone',
              subtitle: 'Ensure you are signed in with the same Google Account.',
            ),
            const SizedBox(height: 8),
            _buildDialogStep(
              number: '2',
              title: 'Go to Settings → Cloud Sync',
              subtitle: 'Locate the Google Drive Cloud Sync section.',
            ),
            const SizedBox(height: 8),
            _buildDialogStep(
              number: '3',
              title: 'Tap "BACKUP NOW"',
              subtitle: 'Wait for the green confirmation notification.',
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.wifi_off_rounded, size: 16, color: Colors.blueGrey),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No internet? You can transfer fab_shop_pro.db via USB cable or Pendrive and click "Import Local Backup File" instead.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF475569)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: const Text('Yes, I Backed Up! Continue'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4285F4),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );

    if (proceed == true) {
      _handleGoogleDriveRestore();
    }
  }

  Widget _buildDialogStep({
    required String number,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 11,
          backgroundColor: const Color(0xFF4285F4),
          child: Text(
            number,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 2. Handle Google Drive Restore (Direct from Android phone backup)
  Future<void> _handleGoogleDriveRestore() async {
    setState(() {
      _isRestoring = true;
      _showError = false;
      _statusText = 'Connecting to Google Drive...';
    });

    try {
      // Sign in (opens browser on Windows desktop)
      final signedIn = await GoogleDriveService.instance.signIn();
      if (!signedIn) {
        setState(() {
          _isRestoring = false;
          _showError = true;
          _errorText =
              'Google Sign-In was cancelled or could not be completed.';
          _statusText = '';
        });
        return;
      }

      setState(() => _statusText = 'Scanning Google Drive for "MICRO BACKUP"...');

      // Attempt to restore latest backup
      final success = await GoogleDriveService.instance.restoreLatestBackup();

      if (success) {
        setState(() {
          _restoreSuccess = true;
          _statusText = 'Android backup restored successfully!';
        });
        await Future.delayed(const Duration(milliseconds: 1500));
        await _completeSetup();
      } else {
        // Try listing backups to see if any exist
        final backups = await GoogleDriveService.instance.listBackups();
        setState(() {
          _isRestoring = false;
          _cloudBackups = backups;
          _showError = true;
          _errorText = backups.isEmpty
              ? 'No backups found in "MICRO BACKUP" on Google Drive. Make sure you tapped "BACKUP NOW" on your Android phone.'
              : 'Could not restore backup. Please try selecting a file below.';
          _statusText = '';
        });
      }
    } catch (e) {
      final isOffline = e.toString().toLowerCase().contains('socketexception') ||
          e.toString().toLowerCase().contains('failed host lookup') ||
          e.toString().toLowerCase().contains('network is unreachable') ||
          e.toString().toLowerCase().contains('clientexception') ||
          e.toString().toLowerCase().contains('no address associated with hostname') ||
          e.toString().toLowerCase().contains('os error');
      setState(() {
        _isRestoring = false;
        _showError = true;
        _errorText = isOffline
            ? 'No internet connection detected. Please connect to Wi-Fi/Ethernet, or click "Import Local Backup File (.db)" below to restore offline without internet!'
            : 'Google Drive Restore failed: $e';
        _statusText = '';
      });
    }
  }

  /// 2. Handle Local File Restore
  Future<void> _handleLocalFileRestore() async {
    setState(() {
      _isRestoring = true;
      _showError = false;
      _statusText = 'Select your .db backup file...';
    });

    try {
      final success =
          await GoogleDriveServiceDesktop.instance.restoreFromLocalFile();

      if (success) {
        setState(() {
          _restoreSuccess = true;
          _statusText = 'Database imported successfully!';
        });
        await Future.delayed(const Duration(milliseconds: 1500));
        await _completeSetup();
      } else {
        setState(() {
          _isRestoring = false;
          _statusText = '';
        });
      }
    } catch (e) {
      setState(() {
        _isRestoring = false;
        _showError = true;
        _errorText = 'File restore failed: $e';
        _statusText = '';
      });
    }
  }

  void _showSyncHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.help_outline, color: _primary),
            ),
            const SizedBox(width: 12),
            const Text(
              'How to Restore from Android',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHelpStep(
              '1',
              'Open Micro on Android',
              'Go to Settings → Cloud Sync and make sure you are signed into Google Drive.',
            ),
            const SizedBox(height: 12),
            _buildHelpStep(
              '2',
              'Tap "BACKUP NOW"',
              'This uploads your latest jobs, billing, and wages to the "MICRO BACKUP" folder on your Google Drive.',
            ),
            const SizedBox(height: 12),
            _buildHelpStep(
              '3',
              'Click "Restore from Google Drive" here on PC',
              'Sign in with the SAME Google account. Micro on PC will automatically download and restore your data!',
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpStep(String number, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: _primary,
          child: Text(
            number,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isWideScreen = size.width >= 900;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Center(
              child: isWideScreen
                  ? _buildWideScreenLayout()
                  : _buildNarrowScreenLayout(),
            ),
          ),
        ),
      ),
    );
  }

  /// Widescreen Desktop Layout (Dual-Column Professional Workstation)
  Widget _buildWideScreenLayout() {
    return Container(
      margin: const EdgeInsets.all(32),
      constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 720),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _primary.withOpacity(0.08),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          // Left Hero Panel
          Expanded(
            flex: 5,
            child: _buildLeftHeroPanel(),
          ),
          // Vertical Divider
          Container(width: 1, color: Colors.grey.withOpacity(0.15)),
          // Right Interactive Onboarding Panel
          Expanded(
            flex: 6,
            child: _buildRightActionsPanel(),
          ),
        ],
      ),
    );
  }

  /// Responsive Fallback Layout for smaller windows
  Widget _buildNarrowScreenLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Column(
            children: [
              _buildBrandHeader(),
              const SizedBox(height: 28),
              _buildRightActionsPanel(),
            ],
          ),
        ),
      ),
    );
  }

  /// Left Hero Panel: Micro Brand, Capabilities & Android-to-PC info
  Widget _buildLeftHeroPanel() {
    return Container(
      padding: const EdgeInsets.all(44),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _primary,
            const Color(0xFF0D144A),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo & Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/Logo.png',
                    width: 44,
                    height: 44,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MICRO',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _accent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'DESKTOP WORKSTATION',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 36),

          // Main Tagline
          const Text(
            'Industrial Workshop &\nFabrication Management',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Welcome to the desktop edition. Jump right into your PC by restoring your Android Google Drive backup or start a clean workstation.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.75),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),

          // Feature Grid Highlights
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildLeftFeatureTile(
                  Icons.cloud_sync_rounded,
                  'Android Cloud Sync',
                  'Restore from Google Drive seamlessly',
                ),
                _buildLeftFeatureTile(
                  Icons.assignment_turned_in_rounded,
                  'Job & Work Order Tracking',
                  'Live orders, target quantity & delivery milestones',
                ),
                _buildLeftFeatureTile(
                  Icons.receipt_long_rounded,
                  'Smart Invoicing & Billing',
                  'Professional PDF bills, scrap deduction & receipts',
                ),
                _buildLeftFeatureTile(
                  Icons.people_alt_rounded,
                  'Wages & Attendance System',
                  'Track worker attendance, overtime & piece rates',
                ),
              ],
            ),
          ),

          // Footer
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'v0.2.3 • Developed by Rishad',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.65),
                  fontSize: 12,
                ),
              ),
              InkWell(
                onTap: _showSyncHelpDialog,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.help_outline,
                        size: 16,
                        color: Colors.white.withOpacity(0.8),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Sync Guide',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLeftFeatureTile(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _accent, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Compact header for narrow windows
  Widget _buildBrandHeader() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _primary.withOpacity(0.12),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/Logo.png',
              width: 64,
              height: 64,
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Micro Workstation',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: _primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Desktop Edition • Seamless Android Sync',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  /// Right Actions Panel: Restore options & fresh start
  Widget _buildRightActionsPanel() {
    if (_restoreSuccess) {
      return _buildSuccessCard();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 36),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Get Started',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Restore from your Android phone or begin fresh',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              IconButton(
                tooltip: 'How to restore from Android',
                icon: const Icon(Icons.info_outline, color: _primary),
                onPressed: _showSyncHelpDialog,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Error Display
          if (_showError) ...[
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline, color: Colors.red[700], size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorText,
                          style: TextStyle(color: Colors.red[900], fontSize: 13, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                  if (_errorText.contains('Import Local Backup File') || _errorText.contains('offline') || _errorText.contains('internet')) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _handleLocalFileRestore,
                        icon: const Icon(Icons.folder_open, size: 16),
                        label: const Text('Pick Local .db File Instead'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red[900],
                          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          // Loading Progress Bar
          if (_isRestoring) ...[
            Container(
              padding: const EdgeInsets.all(20),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: _primary.withOpacity(0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _primary.withOpacity(0.1)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: _accent,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          _statusText,
                          style: const TextStyle(
                            color: _primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // Main Action Cards
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // CARD 1: GOOGLE DRIVE RESTORE (HERO ACTION)
                _buildGoogleDriveActionCard(),
                const SizedBox(height: 16),

                // CARD 2: LOCAL FILE RESTORE
                _buildLocalFileActionCard(),
                const SizedBox(height: 20),

                // Divider OR
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'OR',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 16),

                // CARD 3: START FRESH
                _buildStartFreshActionCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Primary Action: Restore from Google Drive
  Widget _buildGoogleDriveActionCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _primary.withOpacity(0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _primary.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _isRestoring ? null : _promptEnsureAndroidBackup,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4285F4).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.cloud_download_rounded,
                    size: 32,
                    color: Color(0xFF4285F4),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Restore from Google Drive',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.green[200]!),
                            ),
                            child: Text(
                              'RECOMMENDED',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[800],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Restores your Android phone backup from the "MICRO BACKUP" folder automatically.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: Colors.grey,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Secondary Action: Local File Restore
  Widget _buildLocalFileActionCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _isRestoring ? null : _handleLocalFileRestore,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.folder_open_rounded,
                    size: 26,
                    color: _accent,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Import Local Backup File (.db)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Pick a fab_shop_pro.db or backup_*.db file from PC or USB',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Tertiary Action: Start Fresh
  Widget _buildStartFreshActionCard() {
    return Center(
      child: TextButton.icon(
        onPressed: _isRestoring ? null : _completeSetup,
        icon: Icon(
          Icons.add_task_rounded,
          size: 18,
          color: Colors.grey[700],
        ),
        label: Text(
          'Start Fresh — Set up new database',
          style: TextStyle(
            color: Colors.grey[800],
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  /// Success Card when database is successfully restored
  Widget _buildSuccessCard() {
    return Container(
      padding: const EdgeInsets.all(44),
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green[50],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_rounded,
                size: 64,
                color: Colors.green[600],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Database Ready!',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: Colors.green[900],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your Android backup has been restored successfully.\nLaunching your Micro desktop workstation...',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.green[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
