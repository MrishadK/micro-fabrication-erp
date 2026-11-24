import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../database_helper.dart';

/// Desktop-compatible backup/restore service.
/// Uses local file system instead of Google Drive OAuth
/// (which isn't supported on Windows desktop).
class GoogleDriveServiceDesktop {
  static final GoogleDriveServiceDesktop instance =
      GoogleDriveServiceDesktop._init();
  GoogleDriveServiceDesktop._init();

  /// Restore from a local .db file (user picks from file system)
  Future<bool> restoreFromLocalFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db'],
        dialogTitle: 'Select your Micro backup file',
      );

      if (result == null || result.files.single.path == null) return false;

      final sourceFile = File(result.files.single.path!);
      if (!await sourceFile.exists()) return false;

      // Get the target database path
      final dbPathStr = await DatabaseHelper.instance.getPublicDataPath();
      final targetDir = Directory(dbPathStr);
      if (!await targetDir.exists()) await targetDir.create(recursive: true);

      final targetFile = File(p.join(dbPathStr, 'fab_shop_pro.db'));

      // Close the existing database connection before overwriting
      await DatabaseHelper.instance.close();

      // Copy the backup over the current database
      await sourceFile.copy(targetFile.path);

      // Re-initialize database connection
      await DatabaseHelper.instance.database;

      return true;
    } catch (e) {
      debugPrint("Desktop restore error: $e");
      return false;
    }
  }

  /// Export/backup database to a user-chosen location
  Future<String?> exportDatabase() async {
    try {
      final dbPathStr = await DatabaseHelper.instance.getPublicDataPath();
      final dbFile = File(p.join(dbPathStr, 'fab_shop_pro.db'));

      if (!await dbFile.exists()) return null;

      String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Micro Backup',
        fileName:
            'micro_backup_${DateTime.now().toIso8601String().replaceAll(':', '-')}.db',
        type: FileType.custom,
        allowedExtensions: ['db'],
      );

      if (outputPath == null) return null;

      await dbFile.copy(outputPath);
      return outputPath;
    } catch (e) {
      debugPrint("Desktop export error: $e");
      return null;
    }
  }
}
