import 'startup_step.dart';

enum StartupOverallStatus {
  success,
  offlineReady,
  syncConflict,
  criticalError,
}

/// Comprehensive startup outcome passed from the splash screen into the main app.
class StartupResult {
  final StartupOverallStatus overallStatus;
  final Map<StartupStep, StartupStepState> stepStates;
  final bool isGoogleDriveConnected;
  final String? googleEmail;
  final bool isOffline;
  final String syncStatusMessage;
  final bool hasDownloadedNewData;
  final bool hasUploadedLocalChanges;
  final DateTime? lastSyncTime;
  final List<String> failureReasons;
  final Duration totalDuration;
  final String? criticalErrorDetails;
  final String? inAppNotificationMessage;
  final String inAppNotificationType; // 'none', 'info', 'warning', 'success'

  const StartupResult({
    required this.overallStatus,
    required this.stepStates,
    required this.isGoogleDriveConnected,
    this.googleEmail,
    required this.isOffline,
    required this.syncStatusMessage,
    required this.hasDownloadedNewData,
    required this.hasUploadedLocalChanges,
    this.lastSyncTime,
    required this.failureReasons,
    required this.totalDuration,
    this.criticalErrorDetails,
    this.inAppNotificationMessage,
    this.inAppNotificationType = 'none',
  });

  bool get isCritical => overallStatus == StartupOverallStatus.criticalError;
  bool get hasInAppNotification =>
      inAppNotificationMessage != null && inAppNotificationMessage!.isNotEmpty;
}
