import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 🔥 REQUIRED FOR CATCHING NATIVE ERRORS
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../services/app_lock_service.dart';
import '../widgets/pin_dialogs.dart';

import '../database_helper.dart';
import '../services/google_drive_service.dart';
import '../services/google_drive_service_desktop.dart';
import '../providers.dart';
import 'summary.dart';
import 'welcome_restore_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  bool _isLoading = false;
  bool _autoBackup = false;
  GoogleSignInAccount? _user;
  String _lastBackupTime = "Never";

  // Cached Profile Data
  String? _cachedName;
  String? _cachedEmail;
  String? _cachedPhotoUrl;

  String _appVersion = "...";

  bool _appLockEnabled = false;

  final Color _primaryColor = const Color(0xFF1A237E);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final lockEnabled = await AppLockService.instance.isLockEnabled();
    PackageInfo packageInfo = await PackageInfo.fromPlatform();

    setState(() {
      _autoBackup = prefs.getBool('auto_backup') ?? false;
      _lastBackupTime = prefs.getString('last_backup_time') ?? "Never";
      _appLockEnabled = lockEnabled;

      _appVersion = packageInfo.version;

      _cachedName = prefs.getString('cached_user_name');
      _cachedEmail = prefs.getString('cached_user_email');
      _cachedPhotoUrl = prefs.getString('cached_user_photo');

      _user = GoogleDriveService.instance.currentUser;
    });
  }

  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    }
  }

  Future<void> _cacheUserProfile(GoogleSignInAccount? user) async {
    final prefs = await SharedPreferences.getInstance();
    final name = user?.displayName ?? GoogleDriveService.instance.displayName;
    final email = user?.email ?? GoogleDriveService.instance.email;
    final photo = user?.photoUrl ?? GoogleDriveService.instance.photoUrl;

    if (name != null || email != null) {
      if (name != null) await prefs.setString('cached_user_name', name);
      if (email != null) await prefs.setString('cached_user_email', email);
      if (photo != null) await prefs.setString('cached_user_photo', photo);
      setState(() {
        _cachedName = name;
        _cachedEmail = email;
        _cachedPhotoUrl = photo;
      });
    } else {
      await prefs.remove('cached_user_name');
      await prefs.remove('cached_user_email');
      await prefs.remove('cached_user_photo');
      setState(() {
        _cachedName = null;
        _cachedEmail = null;
        _cachedPhotoUrl = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 120,
                pinned: true,
                backgroundColor: _primaryColor,
                flexibleSpace: const FlexibleSpaceBar(
                  title: Text(
                    "Settings",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  centerTitle: false,
                  titlePadding: EdgeInsetsDirectional.only(
                    start: 20,
                    bottom: 16,
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 20),

                  _sectionHeader("CLOUD SYNC", Icons.cloud_done_rounded),
                  _buildGoogleCard(),
                  const SizedBox(height: 25),

                  _sectionHeader("BUSINESS INSIGHTS", Icons.analytics_rounded),
                  _buildSummaryCard(),
                  const SizedBox(height: 25),

                  _sectionHeader("SECURITY", Icons.security_rounded),
                  _buildSecurityCard(),
                  const SizedBox(height: 25),

                  _sectionHeader("MIGRATION", Icons.move_to_inbox_rounded),
                  _buildMigrationCard(),
                  const SizedBox(height: 25),

                  _sectionHeader("DATA MANAGEMENT", Icons.storage_rounded),
                  _buildDataCard(),
                  const SizedBox(height: 25),

                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 30.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.asset(
                              'assets/app.png',
                              width: 18,
                              height: 18,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "Developed by Rishad • Version $_appVersion",
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ]),
              ),
            ],
          ),
          if (_isLoading)
            Positioned(
              top: MediaQuery.of(context).padding.top + 56,
              left: 0,
              right: 0,
              child: const LinearProgressIndicator(
                minHeight: 4,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSecurityCard() {
    return _buildCard(
      child: Column(
        children: [
          SwitchListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            title: const Text(
              "6-Digit App Lock",
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: Text(
              _appLockEnabled
                  ? "Workspace is protected with a 6-digit PIN"
                  : "Require a 6-digit PIN to open workspace",
              style: TextStyle(
                fontSize: 12,
                color: _appLockEnabled ? Colors.green[700] : Colors.grey[600],
              ),
            ),
            value: _appLockEnabled,
            onChanged: _isLoading ? null : (v) => _toggleAppLock(v),
            activeColor: _primaryColor,
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (_appLockEnabled ? Colors.green : Colors.orange)
                    .withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _appLockEnabled ? Icons.lock_rounded : Icons.lock_outline_rounded,
                color: _appLockEnabled ? Colors.green[700] : Colors.orange,
                size: 20,
              ),
            ),
          ),
          if (_appLockEnabled) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.password_rounded,
                    color: _primaryColor, size: 20),
              ),
              title: const Text(
                "Change 6-Digit PIN",
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              subtitle: const Text(
                "Update your current security PIN",
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              trailing:
                  const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
              onTap: _handleChangePin,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _toggleAppLock(bool val) async {
    if (val == true) {
      final hasPin = await AppLockService.instance.hasPinSet();
      if (hasPin) {
        await AppLockService.instance.enableLock();
        if (mounted) {
          setState(() => _appLockEnabled = true);
          _msg("6-Digit App Lock Enabled", isError: false);
        }
      } else {
        if (!mounted) return;
        final isSet = await showPinSetupDialog(context);
        if (isSet == true && mounted) {
          setState(() => _appLockEnabled = true);
          _msg("6-Digit PIN Created & App Lock Enabled", isError: false);
        } else if (mounted) {
          setState(() => _appLockEnabled = false);
        }
      }
    } else {
      // Must verify existing PIN before turning off lock!
      final verified = await showPinVerifyDialog(
        context,
        title: "Disable 6-Digit Lock",
        subtitle: "Enter your current 6-digit PIN to turn off lock protection",
      );

      if (verified == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('app_lock_enabled', false);
        if (mounted) {
          setState(() => _appLockEnabled = false);
          _msg("6-Digit App Lock Disabled", isError: false);
        }
      } else if (mounted) {
        setState(() => _appLockEnabled = true);
      }
    }
  }

  Future<void> _handleChangePin() async {
    final updated = await showPinChangeDialog(context);
    if (updated == true && mounted) {
      _msg("6-Digit PIN successfully updated", isError: false);
    }
  }

  Widget _buildGoogleCard() {
    final bool isSignedIn =
        _user != null || _cachedEmail != null || GoogleDriveService.instance.isSignedIn;
    final String displayName =
        _user?.displayName ?? _cachedName ?? GoogleDriveService.instance.displayName ?? "Not Signed In";
    final String displayEmail =
        _user?.email ?? _cachedEmail ?? GoogleDriveService.instance.email ?? "Connect Google Drive to sync with Android";
    final String? photoUrl =
        _user?.photoUrl ?? _cachedPhotoUrl ?? GoogleDriveService.instance.photoUrl;

    return _buildCard(
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: (!isSignedIn || photoUrl == null || photoUrl.isEmpty)
                ? CircleAvatar(
                    backgroundColor: _primaryColor.withOpacity(0.1),
                    child: const Icon(Icons.cloud_sync_rounded, color: Color(0xFF4285F4)),
                  )
                : CircleAvatar(
                    backgroundImage: NetworkImage(photoUrl),
                  ),
            title: Text(
              displayName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              displayEmail,
              style: TextStyle(
                fontSize: 12,
                color: isSignedIn ? Colors.grey[600] : Colors.orange[800],
              ),
            ),
            trailing: !isSignedIn
                ? ElevatedButton.icon(
                    onPressed: _isLoading ? null : _handleSignIn,
                    icon: const Icon(Icons.login, size: 16),
                    label: const Text("SIGN IN"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.logout, color: Colors.redAccent),
                    tooltip: "Sign out",
                    onPressed: _confirmSignOut,
                  ),
          ),
          if (isSignedIn) ...[
            const Divider(height: 1),
            SwitchListTile(
              title: const Text("Auto-Backup"),
              subtitle: const Text("Sync database on app launch"),
              value: _autoBackup,
              onChanged: _isLoading ? null : (v) => _toggleAutoBackup(v),
              activeColor: _primaryColor,
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.folder_special, size: 16, color: Colors.grey[600]),
                          const SizedBox(width: 6),
                          const Text(
                            "Google Drive Folder: MICRO BACKUP",
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                      Text(
                        _lastBackupTime,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _handleBackup,
                          icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                          label: const Text("BACKUP NOW"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryColor,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _handleRestore,
                          icon: const Icon(Icons.cloud_download_rounded, size: 18),
                          label: const Text("RESTORE FROM DRIVE"),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _primaryColor,
                            side: BorderSide(color: _primaryColor.withOpacity(0.5)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          // Offline / Local PC Backup Controls
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _handleDesktopExport,
                      icon: const Icon(Icons.save_rounded, size: 16),
                      label: const Text("Save to PC (.db)", style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _handleDesktopRestore,
                      icon: const Icon(Icons.folder_open_rounded, size: 16),
                      label: const Text("Open Local .db", style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return _buildCard(
      child: _settingsTile(
        icon: Icons.query_stats_rounded,
        color: Colors.purple,
        title: "Business Summary",
        subtitle: "View materials, products & financials by date",
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SummaryView()),
        ),
      ),
    );
  }

  Widget _buildMigrationCard() {
    return _buildCard(
      child: Column(
        children: [
          _settingsTile(
            icon: Icons.cloud_download_rounded,
            color: const Color(0xFF4285F4),
            title: "Android Google Drive Restore Wizard",
            subtitle: "Launch onboarding & restore wizard from Android backup",
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => WelcomeRestoreScreen(
                  onComplete: () {
                    Navigator.pop(context);
                    ref.refresh(activeJobsProvider);
                  },
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          _settingsTile(
            icon: Icons.table_chart_rounded,
            color: Colors.green,
            title: "Migrate from Excel",
            subtitle: "Import previous data via .xlsx file",
            onTap: () => _handleExcelImport(),
          ),
        ],
      ),
    );
  }

  Widget _buildDataCard() {
    return _buildCard(
      child: Column(
        children: [
          _settingsTile(
            icon: Icons.share_rounded,
            color: Colors.blue,
            title: "Export Database",
            subtitle: "Access database file manually",
            onTap: () => _handleExport(context),
          ),
          const Divider(height: 1),
          _settingsTile(
            icon: Icons.delete_forever_rounded,
            color: Colors.red,
            title: "Factory Reset",
            subtitle: "Clear all local data",
            onTap: () => _handleReset(context),
          ),
        ],
      ),
    );
  }

  Future<void> _handleExcelImport() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (result != null) {
        setState(() => _isLoading = true);
        final bytes = await File(result.files.single.path!).readAsBytes();
        int count = await DatabaseHelper.instance.importFromExcel(bytes);
        if (mounted) {
          _msg("Successfully imported $count jobs!", isError: false);
          ref.refresh(activeJobsProvider);
        }
      }
    } catch (e) {
      if (mounted) _msg("Import failed: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleExport(BuildContext context) async {
    setState(() => _isLoading = true);
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final savedPath = await GoogleDriveServiceDesktop.instance.exportDatabase();
        if (mounted) {
          if (savedPath != null) {
            _msg("Backup saved to $savedPath", isError: false);
          }
        }
        return;
      }

      final path = await DatabaseHelper.instance.getPublicDataPath();
      final file = File(p.join(path, 'fab_shop_pro.db'));
      if (await file.exists()) {
        await Share.shareXFiles([XFile(file.path)], text: 'Database Backup');
      } else {
        if (mounted) _msg("Database not found.");
      }
    } catch (e) {
      if (mounted) _msg("Export failed: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSignIn() async {
    if (!await _hasInternet()) {
      _msg("No internet connection to sign in.", isError: true);
      return;
    }

    setState(() => _isLoading = true);
    final success = await GoogleDriveService.instance.signIn();
    if (mounted && success) {
      setState(() {
        _user = GoogleDriveService.instance.currentUser;
        _cachedName = GoogleDriveService.instance.displayName;
        _cachedEmail = GoogleDriveService.instance.email;
        _cachedPhotoUrl = GoogleDriveService.instance.photoUrl;
        _isLoading = false;
      });
      _cacheUserProfile(_user);
      _msg("Signed in successfully to Google Drive!", isError: false);
    } else {
      if (mounted) {
        setState(() => _isLoading = false);
        _msg("Google Sign-In was cancelled or failed.", isError: true);
      }
    }
  }

  Future<void> _confirmSignOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Sign Out?"),
        content: const Text(
          "Are you sure you want to sign out? Automatic backups will stop working.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Sign Out"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _handleSignOut();
    }
  }

  Future<void> _handleSignOut() async {
    if (!await _hasInternet()) {
      _msg("You need internet to fully sign out.", isError: true);
      return;
    }

    setState(() => _isLoading = true);
    await GoogleDriveService.instance.signOut();
    if (mounted) {
      setState(() {
        _user = null;
        _isLoading = false;
      });
      _cacheUserProfile(null);
    }
  }

  Future<void> _handleBackup() async {
    if (!await _hasInternet()) {
      _msg("No internet. Cannot create backup.", isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final id = await GoogleDriveService.instance.uploadDatabase();
      if (id != null) {
        final now = DateFormat('dd MMM, hh:mm a').format(DateTime.now());
        await (await SharedPreferences.getInstance()).setString(
          'last_backup_time',
          now,
        );
        if (mounted) {
          setState(() => _lastBackupTime = now);
          _msg("Backup Successful!", isError: false);
        }
      }
    } catch (e) {
      if (mounted) _msg("Backup failed: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRestore() async {
    if (!await _hasInternet()) {
      _msg("No internet. Cannot restore data.", isError: true);
      return;
    }

    bool? confirm = await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Restore?"),
        content: const Text("This will OVERWRITE your current data."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text("RESTORE"),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      if (await GoogleDriveService.instance.restoreLatestBackup()) {
        if (mounted) _msg("Restored!", isError: false);
      } else {
        if (mounted) _msg("No backup found.");
      }
    } catch (e) {
      if (mounted) _msg("Restore failed: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleAutoBackup(bool val) async {
    await (await SharedPreferences.getInstance()).setBool('auto_backup', val);
    setState(() => _autoBackup = val);
  }

  // --- Desktop Backup/Restore Handlers ---
  Future<void> _handleDesktopExport() async {
    setState(() => _isLoading = true);
    try {
      final path = await GoogleDriveServiceDesktop.instance.exportDatabase();
      if (path != null) {
        final now = DateFormat('dd MMM, hh:mm a').format(DateTime.now());
        await (await SharedPreferences.getInstance()).setString(
          'last_backup_time',
          now,
        );
        if (mounted) {
          setState(() => _lastBackupTime = now);
          _msg("Backup saved to: $path", isError: false);
        }
      }
    } catch (e) {
      if (mounted) _msg("Export failed: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleDesktopRestore() async {
    bool? confirm = await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Restore?"),
        content: const Text("This will OVERWRITE your current data."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text("RESTORE"),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      if (await GoogleDriveServiceDesktop.instance.restoreFromLocalFile()) {
        if (mounted) _msg("Restored!", isError: false);
      } else {
        if (mounted) _msg("No file selected.");
      }
    } catch (e) {
      if (mounted) _msg("Restore failed: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleReset(BuildContext context) =>
      _msg("Reset logic disabled for safety.");

  void _msg(String text, {bool isError = true}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? Colors.redAccent : Colors.green,
        ),
      );

  Widget _sectionHeader(String title, IconData icon) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 0, 20, 10),
    child: Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
            letterSpacing: 1.1,
          ),
        ),
      ],
    ),
  );

  Widget _buildCard({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: _cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.04),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  );

  Widget _settingsTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) => ListTile(
    leading: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 20),
    ),
    title: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
    ),
    subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
    trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
    onTap: onTap,
  );
}
