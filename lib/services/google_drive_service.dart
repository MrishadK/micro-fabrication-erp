import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../database_helper.dart';

class GoogleDriveService {
  // Singleton
  static final GoogleDriveService instance = GoogleDriveService._init();
  GoogleDriveService._init();

  // --- CONFIGURATION ---
  static const String _folderName = "MICRO BACKUP";
  static const int _maxBackups = 30; // Maximum number of backups to keep
  static const String _defaultDesktopClientId = String.fromEnvironment(
    'DESKTOP_GOOGLE_CLIENT_ID',
    defaultValue: '540848984717-oc2fa8bvei7jjk55qk3felb5aavflhk2.apps.googleusercontent.com',
  );

  static final List<String> _scopes = [
    drive.DriveApi.driveFileScope,
  ];

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveFileScope],
  );

  GoogleSignInAccount? _mobileUser;
  AutoRefreshingAuthClient? _desktopAuthClient;

  // Cached User Details for Desktop & Mobile
  String? _cachedDisplayName;
  String? _cachedEmail;
  String? _cachedPhotoUrl;

  GoogleSignInAccount? get currentUser => _mobileUser;
  String? get displayName => _mobileUser?.displayName ?? _cachedDisplayName;
  String? get email => _mobileUser?.email ?? _cachedEmail;
  String? get photoUrl => _mobileUser?.photoUrl ?? _cachedPhotoUrl;
  bool get isSignedIn =>
      _mobileUser != null || _desktopAuthClient != null || _cachedEmail != null;

  /// Helper: Check if running on desktop
  bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// 1. Sign In (Cross-Platform)
  Future<bool> signIn() async {
    try {
      if (isDesktop) {
        return await _signInDesktop();
      } else {
        _mobileUser = await _googleSignIn.signInSilently();
        _mobileUser ??= await _googleSignIn.signIn();
        if (_mobileUser != null) {
          await _saveProfileLocally(
            _mobileUser!.displayName,
            _mobileUser!.email,
            _mobileUser!.photoUrl,
          );
          return true;
        }
        return false;
      }
    } catch (e) {
      debugPrint("Sign in error: $e");
      return false;
    }
  }

  /// Load desktop OAuth credentials from SharedPreferences, desktop_oauth.json, or environment
  Future<Map<String, String>> _loadDesktopCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    String? clientId = prefs.getString('custom_desktop_client_id')?.trim();
    String? clientSecret = prefs.getString('custom_desktop_client_secret')?.trim();

    if (clientId != null && clientId.isNotEmpty) {
      return {
        'client_id': clientId,
        'client_secret': clientSecret ?? '',
      };
    }

    // Try reading desktop_oauth.json from local disk if not yet saved in prefs
    try {
      final potentialPaths = [
        'desktop_oauth.json',
        p.join(Directory.current.path, 'desktop_oauth.json'),
        p.join(File(Platform.resolvedExecutable).parent.path, 'desktop_oauth.json'),
      ];

      for (final path in potentialPaths) {
        final file = File(path);
        if (file.existsSync()) {
          final content = await file.readAsString();
          final parsed = jsonDecode(content);
          if (parsed is Map) {
            final Map credMap = (parsed['installed'] is Map)
                ? parsed['installed']
                : parsed;
            final fileClientId = credMap['client_id']?.toString().trim();
            final fileClientSecret = credMap['client_secret']?.toString().trim();
            if (fileClientId != null && fileClientId.isNotEmpty) {
              clientId = fileClientId;
              clientSecret = fileClientSecret;
              // Cache into prefs for subsequent runs
              await prefs.setString('custom_desktop_client_id', clientId);
              if (clientSecret != null && clientSecret.isNotEmpty) {
                await prefs.setString('custom_desktop_client_secret', clientSecret);
              }
              break;
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error reading desktop_oauth.json: $e");
    }

    clientId ??= Platform.environment['DESKTOP_GOOGLE_CLIENT_ID'] ?? _defaultDesktopClientId;
    clientSecret ??= Platform.environment['DESKTOP_GOOGLE_CLIENT_SECRET'];

    return {
      'client_id': clientId,
      'client_secret': clientSecret ?? '',
    };
  }

  /// Helper to get configured ClientId
  Future<ClientId> _getConfiguredClientId() async {
    final creds = await _loadDesktopCredentials();
    final clientId = creds['client_id'] ?? _defaultDesktopClientId;
    final clientSecret = creds['client_secret'];
    return ClientId(
      clientId,
      (clientSecret != null && clientSecret.isNotEmpty) ? clientSecret : null,
    );
  }

  Future<void> setCustomCredentials({required String clientId, String? clientSecret}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_desktop_client_id', clientId.trim());
    if (clientSecret != null && clientSecret.trim().isNotEmpty) {
      await prefs.setString('custom_desktop_client_secret', clientSecret.trim());
    } else {
      await prefs.remove('custom_desktop_client_secret');
    }
  }

  Future<String> getActiveClientId() async {
    final creds = await _loadDesktopCredentials();
    return creds['client_id'] ?? _defaultDesktopClientId;
  }

  Future<String?> getActiveClientSecret() async {
    final creds = await _loadDesktopCredentials();
    final secret = creds['client_secret'];
    return (secret != null && secret.isNotEmpty) ? secret : null;
  }

  /// Desktop Sign In via Loopback OAuth
  Future<bool> _signInDesktop() async {
    try {
      final clientId = await _getConfiguredClientId();
      _desktopAuthClient?.close();
      _desktopAuthClient = null;

      final client = await clientViaUserConsent(
        clientId,
        _scopes,
        (url) async {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
            throw 'Could not launch Google Sign-In URL: $url';
          }
        },
        customPostAuthPage: _buildPostAuthHtml(),
      );

      _desktopAuthClient = client;

      // Save credentials for silent sign-in
      final prefs = await SharedPreferences.getInstance();
      if (client.credentials.refreshToken != null) {
        await prefs.setString(
          'desktop_gdrive_refresh_token',
          client.credentials.refreshToken!,
        );
      }
      await prefs.setString(
        'desktop_gdrive_access_token',
        client.credentials.accessToken.data,
      );
      await prefs.setString(
        'desktop_gdrive_token_expiry',
        client.credentials.accessToken.expiry.toIso8601String(),
      );

      // Fetch user profile from Google Drive endpoint
      await _fetchDesktopUserProfile(client);
      return true;
    } catch (e) {
      debugPrint("Desktop Sign-in failed: $e");
      return false;
    }
  }

  /// Silent Sign In on app startup
  Future<bool> signInSilently() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedDisplayName = prefs.getString('cached_user_name');
      _cachedEmail = prefs.getString('cached_user_email');
      _cachedPhotoUrl = prefs.getString('cached_user_photo');

      if (isDesktop) {
        final refreshToken = prefs.getString('desktop_gdrive_refresh_token');
        final accessTokenData = prefs.getString('desktop_gdrive_access_token');
        final expiryStr = prefs.getString('desktop_gdrive_token_expiry');

        if (refreshToken != null && accessTokenData != null) {
          final expiry = DateTime.tryParse(expiryStr ?? '') ??
              DateTime.now().add(const Duration(hours: 1));
          final credentials = AccessCredentials(
            AccessToken('Bearer', accessTokenData, expiry),
            refreshToken,
            _scopes,
          );

          final clientId = await _getConfiguredClientId();
          _desktopAuthClient = autoRefreshingClient(
            clientId,
            credentials,
            http.Client(),
          );
          return true;
        }
        return false;
      } else {
        _mobileUser = await _googleSignIn.signInSilently();
        return _mobileUser != null;
      }
    } catch (e) {
      debugPrint("Silent sign in error: $e");
      return false;
    }
  }

  Future<void> _fetchDesktopUserProfile(http.Client client) async {
    try {
      final driveApi = drive.DriveApi(client);
      final about = await driveApi.about.get($fields: 'user');
      if (about.user != null) {
        _cachedDisplayName = about.user!.displayName;
        _cachedEmail = about.user!.emailAddress;
        _cachedPhotoUrl = about.user!.photoLink;
        await _saveProfileLocally(
          _cachedDisplayName,
          _cachedEmail,
          _cachedPhotoUrl,
        );
        return;
      }
    } catch (e) {
      debugPrint("Could not fetch user profile via Drive about: $e");
    }

    try {
      final response = await client.get(
        Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _cachedDisplayName = data['name'];
        _cachedEmail = data['email'];
        _cachedPhotoUrl = data['picture'];
        await _saveProfileLocally(
          _cachedDisplayName,
          _cachedEmail,
          _cachedPhotoUrl,
        );
      }
    } catch (e) {
      debugPrint("Could not fetch user profile: $e");
    }
  }

  Future<void> _saveProfileLocally(
    String? name,
    String? email,
    String? photoUrl,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (name != null) await prefs.setString('cached_user_name', name);
    if (email != null) await prefs.setString('cached_user_email', email);
    if (photoUrl != null) await prefs.setString('cached_user_photo', photoUrl);
    _cachedDisplayName = name;
    _cachedEmail = email;
    _cachedPhotoUrl = photoUrl;
  }

  /// 2. Sign Out
  Future<void> signOut() async {
    try {
      if (isDesktop) {
        _desktopAuthClient?.close();
        _desktopAuthClient = null;
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('desktop_gdrive_refresh_token');
        await prefs.remove('desktop_gdrive_access_token');
        await prefs.remove('desktop_gdrive_token_expiry');
        await prefs.remove('cached_user_name');
        await prefs.remove('cached_user_email');
        await prefs.remove('cached_user_photo');
      } else {
        await _googleSignIn.disconnect();
        await _googleSignIn.signOut();
        _mobileUser = null;
      }
      _cachedDisplayName = null;
      _cachedEmail = null;
      _cachedPhotoUrl = null;
    } catch (e) {
      debugPrint("Sign out error: $e");
    }
  }

  /// Helper to get an authenticated HTTP Client for Drive API
  Future<http.Client?> _getAuthenticatedClient() async {
    if (isDesktop) {
      if (_desktopAuthClient == null) {
        final success = await signInSilently();
        if (!success) {
          final loggedIn = await signIn();
          if (!loggedIn) return null;
        }
      }
      return _desktopAuthClient;
    } else {
      if (_mobileUser == null) {
        _mobileUser = await _googleSignIn.signInSilently();
        _mobileUser ??= await _googleSignIn.signIn();
      }
      if (_mobileUser == null) return null;
      return await _googleSignIn.authenticatedClient();
    }
  }

  /// 3. Upload Database (Backup to Google Drive)
  Future<String?> uploadDatabase() async {
    final client = await _getAuthenticatedClient();
    if (client == null) return null;

    final driveApi = drive.DriveApi(client);

    // Get Local DB File
    final dbPathStr = await DatabaseHelper.instance.getPublicDataPath();
    final dbFile = File(p.join(dbPathStr, 'fab_shop_pro.db'));

    if (!dbFile.existsSync()) {
      debugPrint("DB file does not exist at ${dbFile.path}");
      return null;
    }

    // 1. Try to find the folder "MICRO BACKUP"
    String? folderId = await _getFolderId(driveApi, _folderName);

    // 2. If it doesn't exist, create it automatically
    if (folderId == null) {
      folderId = await _createFolder(driveApi, _folderName);
    }

    // Prepare File Metadata
    var driveFile = drive.File();
    driveFile.name =
        "backup_${DateTime.now().toIso8601String().replaceAll(':', '-')}.db";
    driveFile.parents = [folderId!];

    // Upload
    final media = drive.Media(dbFile.openRead(), dbFile.lengthSync());
    final result = await driveApi.files.create(driveFile, uploadMedia: media);

    // Clean up old backups exceeding limit
    await _cleanupOldBackups(driveApi, folderId);

    // Update last backup time
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().toString().split('.')[0];
    await prefs.setString('last_backup_time', now);

    return result.id;
  }

  /// 4. Restore Database from Google Drive (e.g. from Android)
  Future<bool> restoreLatestBackup() async {
    final client = await _getAuthenticatedClient();
    if (client == null) return false;

    final driveApi = drive.DriveApi(client);

    // Find Backup Folder
    final folderId = await _getFolderId(driveApi, _folderName);
    if (folderId == null) return false;

    // Find Latest File inside that folder
    final fileList = await driveApi.files.list(
      q: "'$folderId' in parents and trashed = false",
      orderBy: "createdTime desc",
      pageSize: 1,
    );

    if (fileList.files == null || fileList.files!.isEmpty) return false;

    final backupFile = fileList.files!.first;
    final String fileId = backupFile.id!;

    // Download file
    final drive.Media media =
        await driveApi.files.get(
              fileId,
              downloadOptions: drive.DownloadOptions.fullMedia,
            )
            as drive.Media;

    // Safely close active database connection before replacing
    await DatabaseHelper.instance.close();

    // Save to Local DB Path
    final dbPathStr = await DatabaseHelper.instance.getPublicDataPath();
    final targetDir = Directory(dbPathStr);
    if (!await targetDir.exists()) await targetDir.create(recursive: true);

    final saveFile = File(p.join(dbPathStr, 'fab_shop_pro.db'));

    final List<int> dataStore = [];
    await media.stream.forEach((data) {
      dataStore.addAll(data);
    });

    await saveFile.writeAsBytes(dataStore, flush: true);

    // Reopen database to verify
    await DatabaseHelper.instance.database;
    return true;
  }

  /// 5. List available backups with details
  Future<List<Map<String, dynamic>>> listBackups() async {
    final client = await _getAuthenticatedClient();
    if (client == null) return [];

    try {
      final driveApi = drive.DriveApi(client);
      final folderId = await _getFolderId(driveApi, _folderName);
      if (folderId == null) return [];

      final fileList = await driveApi.files.list(
        q: "'$folderId' in parents and trashed = false",
        orderBy: "createdTime desc",
        pageSize: 10,
        $fields: "files(id, name, createdTime, size)",
      );

      return fileList.files?.map((f) {
            final sizeBytes = int.tryParse(f.size ?? '0') ?? 0;
            final sizeFormatted = sizeBytes > 0
                ? "${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB"
                : "";
            return {
              'id': f.id ?? '',
              'name': f.name ?? 'backup.db',
              'createdTime': f.createdTime?.toLocal().toString().split('.')[0] ?? '',
              'size': sizeFormatted,
            };
          }).toList() ??
          [];
    } catch (e) {
      debugPrint("List backups error: $e");
      return [];
    }
  }

  // --- Helpers ---

  Future<String?> _getFolderId(drive.DriveApi api, String folderName) async {
    final list = await api.files.list(
      q: "mimeType = 'application/vnd.google-apps.folder' and name = '$folderName' and trashed = false",
    );
    if (list.files?.isNotEmpty ?? false) return list.files!.first.id;
    return null;
  }

  Future<String> _createFolder(drive.DriveApi api, String folderName) async {
    var folder = drive.File();
    folder.name = folderName;
    folder.mimeType = "application/vnd.google-apps.folder";
    final result = await api.files.create(folder);
    return result.id!;
  }

  Future<void> _cleanupOldBackups(drive.DriveApi api, String folderId) async {
    try {
      final fileList = await api.files.list(
        q: "'$folderId' in parents and trashed = false",
        orderBy: "createdTime asc",
        pageSize: 100,
      );

      final files = fileList.files;
      if (files != null && files.length > _maxBackups) {
        int excessCount = files.length - _maxBackups;
        for (int i = 0; i < excessCount; i++) {
          final fileId = files[i].id;
          if (fileId != null) {
            await api.files.delete(fileId);
            debugPrint("Deleted old backup: ${files[i].name}");
          }
        }
      }
    } catch (e) {
      debugPrint("Failed to clean up old backups: $e");
    }
  }

  /// Custom high-polish HTML page served to the browser upon successful Google OAuth authorization
  static String _buildPostAuthHtml() {
    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Connected to Google Drive • Micro</title>
  <style>
    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    }
    body {
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      background: linear-gradient(135deg, #0B132B 0%, #1C2541 50%, #1A237E 100%);
      color: #1E293B;
      padding: 24px;
    }
    .card {
      background: #FFFFFF;
      border-radius: 24px;
      padding: 44px 36px;
      max-width: 480px;
      width: 100%;
      box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.35), 0 0 0 1px rgba(255, 255, 255, 0.1);
      text-align: center;
      animation: slideUp 0.5s cubic-bezier(0.16, 1, 0.3, 1) forwards;
    }
    @keyframes slideUp {
      from {
        opacity: 0;
        transform: translateY(24px);
      }
      to {
        opacity: 1;
        transform: translateY(0);
      }
    }
    .brand-row {
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 10px;
      margin-bottom: 24px;
    }
    .brand-badge {
      display: inline-flex;
      align-items: center;
      background: #1A237E;
      color: #FFFFFF;
      font-weight: 800;
      font-size: 13px;
      letter-spacing: 1.2px;
      padding: 6px 12px;
      border-radius: 8px;
    }
    .workstation-badge {
      background: #FFF3E0;
      color: #E65100;
      font-weight: 700;
      font-size: 11px;
      letter-spacing: 0.5px;
      padding: 5px 10px;
      border-radius: 6px;
      border: 1px solid #FFE082;
    }
    .icon-wrapper {
      position: relative;
      width: 76px;
      height: 76px;
      margin: 0 auto 20px;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .icon-glow {
      position: absolute;
      inset: -6px;
      background: rgba(16, 185, 129, 0.18);
      border-radius: 50%;
      animation: pulse 2s infinite ease-in-out;
    }
    @keyframes pulse {
      0%, 100% { transform: scale(0.95); opacity: 0.7; }
      50% { transform: scale(1.08); opacity: 1; }
    }
    .icon-circle {
      position: relative;
      width: 72px;
      height: 72px;
      background: linear-gradient(135deg, #10B981 0%, #059669 100%);
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      box-shadow: 0 10px 20px rgba(16, 185, 129, 0.35);
    }
    .icon-circle svg {
      width: 36px;
      height: 36px;
      fill: none;
      stroke: #FFFFFF;
      stroke-width: 3;
      stroke-linecap: round;
      stroke-linejoin: round;
    }
    h1 {
      font-size: 22px;
      font-weight: 700;
      color: #0F172A;
      margin-bottom: 8px;
      line-height: 1.3;
    }
    .subtitle {
      font-size: 13px;
      color: #64748B;
      line-height: 1.5;
      margin-bottom: 24px;
    }
    .info-box {
      background: #F8FAFC;
      border: 1px solid #E2E8F0;
      border-radius: 14px;
      padding: 16px;
      margin-bottom: 24px;
      text-align: left;
    }
    .info-row {
      display: flex;
      justify-content: space-between;
      align-items: center;
      font-size: 12px;
      padding: 8px 0;
    }
    .info-row:not(:last-child) {
      border-bottom: 1px dashed #E2E8F0;
    }
    .info-label {
      color: #64748B;
      font-weight: 500;
    }
    .info-value {
      color: #0F172A;
      font-weight: 600;
      display: flex;
      align-items: center;
      gap: 6px;
    }
    .status-dot {
      width: 7px;
      height: 7px;
      background: #10B981;
      border-radius: 50%;
      display: inline-block;
    }
    .btn {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 100%;
      padding: 14px 20px;
      background: linear-gradient(135deg, #1A237E 0%, #283593 100%);
      color: #FFFFFF;
      font-size: 14px;
      font-weight: 600;
      border: none;
      border-radius: 12px;
      cursor: pointer;
      text-decoration: none;
      box-shadow: 0 4px 12px rgba(26, 35, 126, 0.25);
      transition: all 0.2s ease;
    }
    .btn:hover {
      transform: translateY(-1px);
      box-shadow: 0 6px 18px rgba(26, 35, 126, 0.35);
      background: linear-gradient(135deg, #0D1757 0%, #1A237E 100%);
    }
    .countdown-text {
      margin-top: 14px;
      font-size: 11px;
      color: #94A3B8;
    }
    .footer-text {
      margin-top: 20px;
      font-size: 11px;
      color: #94A3B8;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="brand-row">
      <span class="brand-badge">MICRO</span>
      <span class="workstation-badge">DESKTOP WORKSTATION</span>
    </div>

    <div class="icon-wrapper">
      <div class="icon-glow"></div>
      <div class="icon-circle">
        <svg viewBox="0 0 24 24">
          <polyline points="20 6 9 17 4 12"></polyline>
        </svg>
      </div>
    </div>

    <h1>Google Drive Connected!</h1>
    <p class="subtitle">Your desktop workstation is now linked to your Google Account. Cloud backup and multi-device sync are ready.</p>

    <div class="info-box">
      <div class="info-row">
        <span class="info-label">Cloud Backup Folder</span>
        <span class="info-value">📁 MICRO BACKUP</span>
      </div>
      <div class="info-row">
        <span class="info-label">Authorization Status</span>
        <span class="info-value"><span class="status-dot"></span> Active & Verified</span>
      </div>
      <div class="info-row">
        <span class="info-label">Cross-Device Sync</span>
        <span class="info-value">Android Phone ⇄ PC</span>
      </div>
    </div>

    <button class="btn" onclick="window.close()">Return to Micro App</button>
    <p class="countdown-text">This browser tab can be closed. Auto-closing in <span id="sec">5</span>s...</p>
    <p class="footer-text">Micro • Industrial Fabrication ERP</p>
  </div>

  <script>
    let remaining = 5;
    const secEl = document.getElementById('sec');
    const interval = setInterval(function() {
      remaining--;
      if (secEl) secEl.textContent = remaining;
      if (remaining <= 0) {
        clearInterval(interval);
        window.close();
      }
    }, 1000);
  </script>
</body>
</html>''';
  }
}
