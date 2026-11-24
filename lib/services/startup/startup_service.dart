import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../database_helper.dart';
import '../google_drive_service.dart';
import 'startup_step.dart';

/// Service responsible for performing real application initialization,
/// local database verification, Google Drive connectivity diagnostics,
/// and safe data synchronization.
class StartupService {
  static final StartupService instance = StartupService._init();
  StartupService._init();

  /// Stage 1: Starting the application
  /// Verifies Flutter dependencies, app directories, config files and permissions.
  Future<Map<String, dynamic>> initializeApplication() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Ensure FabManager documents directory exists and is writable
      final dbPathStr = await DatabaseHelper.instance.getPublicDataPath();
      final folder = Directory(dbPathStr);
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }

      // Check write accessibility by writing and removing a temporary startup marker
      final testFile = File(p.join(dbPathStr, '.startup_probe'));
      await testFile.writeAsString('probe_${DateTime.now().millisecondsSinceEpoch}', flush: true);
      if (await testFile.exists()) {
        await testFile.delete();
      }

      // Read or initialize launch count
      final launchCount = (prefs.getInt('app_launch_count') ?? 0) + 1;
      await prefs.setInt('app_launch_count', launchCount);

      return {
        'ok': true,
        'message': 'Application initialized',
        'launchCount': launchCount,
      };
    } catch (e) {
      debugPrint("StartupService Stage 1 Error: $e");
      return {
        'ok': false,
        'message': 'Failed to initialize app directory: $e',
      };
    }
  }

  /// Stage 2: Preparing your data
  /// Opens SQLite connection, verifies integrity, checks schema & table accessibility.
  Future<Map<String, dynamic>> prepareData() async {
    try {
      final dbPathStr = await DatabaseHelper.instance.getPublicDataPath();
      final dbFile = File(p.join(dbPathStr, 'fab_shop_pro.db'));
      final bool dbExists = await dbFile.exists();

      // If database does not exist, initializing it creates the workspace tables
      final db = await DatabaseHelper.instance.database;

      if (!dbExists) {
        return {
          'ok': true,
          'isFirstLaunch': true,
          'status': StartupStepStatus.success,
          'message': 'Preparing your first workspace',
        };
      }

      // Check database integrity
      final integrity = await DatabaseHelper.instance.checkIntegrity();
      if (integrity['ok'] != true) {
        return {
          'ok': false,
          'isCorrupt': true,
          'status': StartupStepStatus.failed,
          'message': 'Your saved data needs recovery',
          'error': integrity['message'],
        };
      }

      // Verify required schema and table count
      final schema = await DatabaseHelper.instance.verifySchemaAndTables();
      if (schema['ok'] != true) {
        final List missing = schema['missingTables'] ?? [];
        return {
          'ok': false,
          'status': StartupStepStatus.failed,
          'message': 'Unable to access your saved data',
          'error': 'Missing tables: ${missing.join(', ')}',
        };
      }

      // Query active jobs count to ensure table data accessibility
      final jobsCountResult =
          await db.rawQuery('SELECT COUNT(*) as cnt FROM jobs');
      final jobsCount =
          jobsCountResult.isNotEmpty ? (jobsCountResult.first['cnt'] as int? ?? 0) : 0;

      return {
        'ok': true,
        'isFirstLaunch': false,
        'status': StartupStepStatus.success,
        'message': 'Your data is ready',
        'jobsCount': jobsCount,
        'schemaVersion': schema['version'],
      };
    } catch (e) {
      debugPrint("StartupService Stage 2 Error: $e");
      return {
        'ok': false,
        'status': StartupStepStatus.failed,
        'message': 'Unable to access your saved data',
        'error': e.toString(),
      };
    }
  }

  /// Stage 3: Connecting to Google Drive
  /// Validates internet connection, stored tokens, silent refresh, and Drive API accessibility.
  Future<Map<String, dynamic>> connectGoogleDrive() async {
    try {
      final result =
          await GoogleDriveService.instance.checkDriveConnectivity();
      final bool connected = result['connected'] == true;
      final String? failureReason = result['reason'];
      final String? email = result['email'];
      final bool isOffline = result['isOffline'] == true;

      return {
        'connected': connected,
        'isOffline': isOffline,
        'email': email,
        'status':
            connected ? StartupStepStatus.success : StartupStepStatus.failed,
        'message': connected
            ? (email != null && email.isNotEmpty ? email : 'Connected')
            : (failureReason ?? 'Failed: Unable to connect to Google Drive'),
        'failureReason': connected ? null : failureReason,
      };
    } catch (e) {
      debugPrint("StartupService Stage 3 Error: $e");
      return {
        'connected': false,
        'isOffline': false,
        'status': StartupStepStatus.failed,
        'message': 'Failed: Unable to connect to Google Drive',
        'failureReason': 'Failed: Unable to connect to Google Drive',
      };
    }
  }

  /// Stage 4: Checking for new updates
  /// Compares local modification timestamps & sync state with remote Google Drive backups.
  Future<Map<String, dynamic>> checkForUpdates({
    required bool isDriveConnected,
  }) async {
    if (!isDriveConnected) {
      return {
        'status': StartupStepStatus.skipped,
        'message': 'Skipped: Google Drive offline',
        'hasNewData': false,
        'hasUnsyncedLocal': false,
      };
    }

    try {
      final remoteMetadata =
          await GoogleDriveService.instance.getLatestBackupMetadata();
      if (remoteMetadata == null) {
        return {
          'status': StartupStepStatus.warning,
          'message': 'No previous backup found',
          'hasNewData': false,
          'hasUnsyncedLocal': true, // Local DB exists and should be backed up
        };
      }

      final prefs = await SharedPreferences.getInstance();
      final String? lastSyncStr = prefs.getString('last_backup_time');
      DateTime? lastSync;
      if (lastSyncStr != null && lastSyncStr.isNotEmpty) {
        lastSync = DateTime.tryParse(lastSyncStr);
      }

      final dbPathStr = await DatabaseHelper.instance.getPublicDataPath();
      final dbFile = File(p.join(dbPathStr, 'fab_shop_pro.db'));
      DateTime? localModified;
      if (await dbFile.exists()) {
        localModified = await dbFile.lastModified();
      }

      final DateTime? remoteCreated = remoteMetadata['createdTime'];

      // Compare timestamps with a 2-minute jitter tolerance
      if (remoteCreated != null && localModified != null) {
        final diffSeconds = remoteCreated.difference(localModified).inSeconds;

        if (diffSeconds > 120 && (lastSync == null || remoteCreated.isAfter(lastSync))) {
          // Remote backup is distinctly newer than local file
          return {
            'status': StartupStepStatus.success,
            'message': 'New updates available',
            'hasNewData': true,
            'hasUnsyncedLocal': false,
            'remoteFileId': remoteMetadata['id'],
          };
        } else if (diffSeconds < -120) {
          // Local changes have occurred since the last remote backup
          return {
            'status': StartupStepStatus.success,
            'message': 'Local changes are waiting to sync',
            'hasNewData': false,
            'hasUnsyncedLocal': true,
          };
        }
      }

      return {
        'status': StartupStepStatus.success,
        'message': 'Your data is up to date',
        'hasNewData': false,
        'hasUnsyncedLocal': false,
      };
    } catch (e) {
      debugPrint("StartupService Stage 4 Error: $e");
      return {
        'status': StartupStepStatus.warning,
        'message': 'Could not check updates',
        'hasNewData': false,
        'hasUnsyncedLocal': false,
      };
    }
  }

  /// Stage 5: Synchronizing your data
  /// Safely uploads pending changes or updates local data without destructive overwriting.
  Future<Map<String, dynamic>> synchronizeData({
    required bool isDriveConnected,
    required bool hasNewData,
    required bool hasUnsyncedLocal,
  }) async {
    if (!isDriveConnected) {
      return {
        'status': StartupStepStatus.skipped,
        'message': 'Skipped: Google Drive offline',
        'downloaded': false,
        'uploaded': false,
      };
    }

    final prefs = await SharedPreferences.getInstance();
    final bool autoBackup = prefs.getBool('auto_backup') ?? true;

    if (!autoBackup) {
      return {
        'status': StartupStepStatus.skipped,
        'message': 'No synchronization needed (Auto-backup paused)',
        'downloaded': false,
        'uploaded': false,
      };
    }

    try {
      // If local changes are waiting to be backed up
      if (hasUnsyncedLocal) {
        final uploadedId = await GoogleDriveService.instance.uploadDatabase();
        if (uploadedId != null) {
          return {
            'status': StartupStepStatus.success,
            'message': 'Your data is synchronized',
            'downloaded': false,
            'uploaded': true,
          };
        } else {
          return {
            'status': StartupStepStatus.warning,
            'message': 'Sync unsuccessful — using saved data',
            'downloaded': false,
            'uploaded': false,
          };
        }
      }

      // If newer data exists on Google Drive (e.g. freshly backed up from Android)
      if (hasNewData) {
        // Safe snapshot backup before downloading remote database
        final dbPathStr = await DatabaseHelper.instance.getPublicDataPath();
        final currentDb = File(p.join(dbPathStr, 'fab_shop_pro.db'));
        if (await currentDb.exists()) {
          final backupCopy = File(p.join(dbPathStr, 'fab_shop_pre_sync_backup.db'));
          await currentDb.copy(backupCopy.path);
        }

        final success = await GoogleDriveService.instance.restoreLatestBackup();
        if (success) {
          return {
            'status': StartupStepStatus.success,
            'message': 'Your data is synchronized',
            'downloaded': true,
            'uploaded': false,
          };
        } else {
          return {
            'status': StartupStepStatus.warning,
            'message': 'Sync unsuccessful — using saved data',
            'downloaded': false,
            'uploaded': false,
          };
        }
      }

      return {
        'status': StartupStepStatus.success,
        'message': 'No synchronization needed',
        'downloaded': false,
        'uploaded': false,
      };
    } catch (e) {
      debugPrint("StartupService Stage 5 Error: $e");
      return {
        'status': StartupStepStatus.warning,
        'message': 'Sync unsuccessful — using saved data',
        'downloaded': false,
        'uploaded': false,
      };
    }
  }

  /// Stage 6: Setting up your workspace
  /// Pre-warms business settings, dashboard statistics & prepares final state.
  Future<Map<String, dynamic>> setupWorkspace() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final businessName = prefs.getString('business_name') ?? 'Micro Workshop';

      // Pre-warm active jobs count from database
      final db = await DatabaseHelper.instance.database;
      final activeResult = await db.rawQuery(
        "SELECT COUNT(*) as cnt FROM jobs WHERE status = 'Ongoing'",
      );
      final activeCount =
          activeResult.isNotEmpty ? (activeResult.first['cnt'] as int? ?? 0) : 0;

      return {
        'ok': true,
        'status': StartupStepStatus.success,
        'message': 'Workspace ready',
        'businessName': businessName,
        'activeCount': activeCount,
      };
    } catch (e) {
      debugPrint("StartupService Stage 6 Error: $e");
      return {
        'ok': false,
        'status': StartupStepStatus.failed,
        'message': 'Error setting up workspace',
        'error': e.toString(),
      };
    }
  }
}
