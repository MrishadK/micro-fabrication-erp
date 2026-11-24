import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'startup_result.dart';
import 'startup_service.dart';
import 'startup_step.dart';

/// State object emitted by [StartupController].
class StartupState {
  final Map<StartupStep, StartupStepState> steps;
  final StartupStep? currentRunningStep;
  final double progress; // 0.0 to 1.0
  final String heading;
  final String subheading;
  final bool isCompleted;
  final bool isCriticalError;
  final String? criticalErrorTitle;
  final String? criticalErrorDetails;
  final StartupResult? result;

  const StartupState({
    required this.steps,
    this.currentRunningStep,
    required this.progress,
    required this.heading,
    required this.subheading,
    this.isCompleted = false,
    this.isCriticalError = false,
    this.criticalErrorTitle,
    this.criticalErrorDetails,
    this.result,
  });

  StartupState copyWith({
    Map<StartupStep, StartupStepState>? steps,
    StartupStep? currentRunningStep,
    bool clearCurrentRunning = false,
    double? progress,
    String? heading,
    String? subheading,
    bool? isCompleted,
    bool? isCriticalError,
    String? criticalErrorTitle,
    String? criticalErrorDetails,
    StartupResult? result,
  }) {
    return StartupState(
      steps: steps ?? this.steps,
      currentRunningStep: clearCurrentRunning
          ? null
          : (currentRunningStep ?? this.currentRunningStep),
      progress: progress ?? this.progress,
      heading: heading ?? this.heading,
      subheading: subheading ?? this.subheading,
      isCompleted: isCompleted ?? this.isCompleted,
      isCriticalError: isCriticalError ?? this.isCriticalError,
      criticalErrorTitle: criticalErrorTitle ?? this.criticalErrorTitle,
      criticalErrorDetails: criticalErrorDetails ?? this.criticalErrorDetails,
      result: result ?? this.result,
    );
  }

  factory StartupState.initial() {
    final Map<StartupStep, StartupStepState> initialSteps = {
      for (var s in StartupStep.values) s: StartupStepState.initial(s),
    };
    return StartupState(
      steps: initialSteps,
      currentRunningStep: null,
      progress: 0.0,
      heading: "Getting things ready for you...",
      subheading: "Initializing Micro Fabrication ERP",
    );
  }
}

/// Controller coordinating the sequential startup stages, dynamic headings,
/// asynchronous operations, presentation delays, and error states.
class StartupController extends ChangeNotifier {
  final StartupService _service;
  final bool enablePresentationDelay;
  final Random _random = Random();

  StartupState _state = StartupState.initial();
  StartupState get state => _state;

  bool _isDisposed = false;
  bool _hasStarted = false;

  StartupController({
    StartupService? service,
    this.enablePresentationDelay = true,
  }) : _service = service ?? StartupService.instance;

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  void _updateState(StartupState newState) {
    if (_isDisposed) return;
    _state = newState;
    notifyListeners();
  }

  /// Initiates the sequential startup procedure.
  Future<StartupResult> startInitialization() async {
    if (_hasStarted) {
      if (_state.result != null) return _state.result!;
    }
    _hasStarted = true;

    final stopwatch = Stopwatch()..start();
    final List<String> failureReasons = [];
    bool isGoogleDriveConnected = false;
    String? googleEmail;
    bool isOffline = false;
    bool hasNewData = false;
    bool hasUnsyncedLocal = false;
    bool downloadedNewData = false;
    bool uploadedLocalChanges = false;
    String syncStatusMessage = "No synchronization needed";

    try {
      // =========================================================
      // STAGE 1: Starting the application
      // =========================================================
      await _runStep(
        step: StartupStep.startingApp,
        targetProgress: 0.16,
        heading: "Starting the application...",
        subheading: "Verifying system components and permissions",
        operation: () => _service.initializeApplication(),
        onSuccess: (data) {},
        onFailure: (data) {
          failureReasons.add(data['message']?.toString() ?? 'App startup error');
        },
      );

      // =========================================================
      // STAGE 2: Preparing your data
      // =========================================================
      Map<String, dynamic> dbResult = {};
      await _runStep(
        step: StartupStep.preparingData,
        targetProgress: 0.33,
        heading: "Preparing your saved data...",
        subheading: "Checking SQLite database integrity & schema",
        operation: () async {
          dbResult = await _service.prepareData();
          return dbResult;
        },
        onSuccess: (data) {},
        onFailure: (data) {
          final err = data['error']?.toString() ?? data['message']?.toString();
          if (err != null) failureReasons.add(err);
        },
      );

      // If database is corrupt or inaccessible, halt for critical recovery
      if (dbResult['ok'] != true) {
        stopwatch.stop();
        final criticalResult = StartupResult(
          overallStatus: StartupOverallStatus.criticalError,
          stepStates: _state.steps,
          isGoogleDriveConnected: false,
          isOffline: false,
          syncStatusMessage: "Database unavailable",
          hasDownloadedNewData: false,
          hasUploadedLocalChanges: false,
          failureReasons: failureReasons,
          totalDuration: stopwatch.elapsed,
          criticalErrorDetails: dbResult['error'] ?? dbResult['message'],
        );

        _updateState(
          _state.copyWith(
            isCriticalError: true,
            criticalErrorTitle: dbResult['message'] ?? "Database Error",
            criticalErrorDetails: dbResult['error'] ?? "Unknown database fault",
            result: criticalResult,
          ),
        );
        return criticalResult;
      }

      // =========================================================
      // STAGE 3: Connecting to Google Drive
      // =========================================================
      Map<String, dynamic> driveResult = {};
      await _runStep(
        step: StartupStep.connectingDrive,
        targetProgress: 0.50,
        heading: "Connecting to Google Drive...",
        subheading: "Checking cloud backup & sync credentials",
        operation: () async {
          driveResult = await _service.connectGoogleDrive();
          return driveResult;
        },
        onSuccess: (data) {
          isGoogleDriveConnected = true;
          googleEmail = data['email'];
        },
        onFailure: (data) {
          isGoogleDriveConnected = false;
          isOffline = data['isOffline'] == true;
          final reason = data['failureReason']?.toString() ??
              data['message']?.toString();
          if (reason != null) failureReasons.add(reason);
        },
      );

      // =========================================================
      // STAGE 4: Checking for new updates
      // =========================================================
      Map<String, dynamic> updateCheckResult = {};
      if (isGoogleDriveConnected) {
        await _runStep(
          step: StartupStep.checkingUpdates,
          targetProgress: 0.67,
          heading: "Checking for your latest updates...",
          subheading: "Scanning cloud backup files in MICRO BACKUP",
          operation: () async {
            updateCheckResult = await _service.checkForUpdates(
              isDriveConnected: isGoogleDriveConnected,
            );
            return updateCheckResult;
          },
          onSuccess: (data) {
            hasNewData = data['hasNewData'] == true;
            hasUnsyncedLocal = data['hasUnsyncedLocal'] == true;
          },
          onFailure: (data) {},
        );
      } else {
        // Skip stage cleanly without delay
        _markStepSkipped(
          StartupStep.checkingUpdates,
          "Skipped: Google Drive offline",
        );
      }

      // =========================================================
      // STAGE 5: Synchronizing your data
      // =========================================================
      if (isGoogleDriveConnected) {
        await _runStep(
          step: StartupStep.syncingData,
          targetProgress: 0.84,
          heading: "Keeping your data in sync...",
          subheading: hasUnsyncedLocal
              ? "Uploading pending local records to cloud"
              : (hasNewData ? "Applying newer cloud updates" : "Verifying synchronization"),
          operation: () async {
            final syncRes = await _service.synchronizeData(
              isDriveConnected: isGoogleDriveConnected,
              hasNewData: hasNewData,
              hasUnsyncedLocal: hasUnsyncedLocal,
            );
            downloadedNewData = syncRes['downloaded'] == true;
            uploadedLocalChanges = syncRes['uploaded'] == true;
            syncStatusMessage = syncRes['message'] ?? syncStatusMessage;
            return syncRes;
          },
          onSuccess: (data) {},
          onFailure: (data) {
            final msg = data['message']?.toString();
            if (msg != null) failureReasons.add(msg);
          },
        );
      } else {
        // Skip stage cleanly without delay
        _markStepSkipped(
          StartupStep.syncingData,
          "Skipped: Google Drive offline",
        );
      }

      // =========================================================
      // STAGE 6: Setting up your workspace
      // =========================================================
      await _runStep(
        step: StartupStep.settingWorkspace,
        targetProgress: 1.0,
        heading: "Setting up your workspace...",
        subheading: "Preparing billing, jobs & financial ledger",
        operation: () => _service.setupWorkspace(),
        onSuccess: (data) {},
        onFailure: (data) {},
      );

      stopwatch.stop();

      // Determine overall status & dynamic in-app notification
      StartupOverallStatus overallStatus;
      String inAppNotification = "";
      String notifType = 'none';

      if (!isGoogleDriveConnected) {
        overallStatus = StartupOverallStatus.offlineReady;
        if (isOffline) {
          inAppNotification = "You're offline. You can continue using your saved data.";
          notifType = 'info';
        } else {
          inAppNotification =
              "Google Drive is not connected. Sign in from Settings to enable backups.";
          notifType = 'warning';
        }
      } else if (downloadedNewData) {
        overallStatus = StartupOverallStatus.success;
        inAppNotification = "Your latest business records have been synchronized.";
        notifType = 'success';
      } else if (uploadedLocalChanges) {
        overallStatus = StartupOverallStatus.success;
        inAppNotification = "Your data is up to date and backed up to Google Drive.";
        notifType = 'success';
      } else {
        overallStatus = StartupOverallStatus.success;
        notifType = 'none';
      }

      final finalResult = StartupResult(
        overallStatus: overallStatus,
        stepStates: _state.steps,
        isGoogleDriveConnected: isGoogleDriveConnected,
        googleEmail: googleEmail,
        isOffline: isOffline,
        syncStatusMessage: syncStatusMessage,
        hasDownloadedNewData: downloadedNewData,
        hasUploadedLocalChanges: uploadedLocalChanges,
        failureReasons: failureReasons,
        totalDuration: stopwatch.elapsed,
        inAppNotificationMessage: inAppNotification.isNotEmpty ? inAppNotification : null,
        inAppNotificationType: notifType,
      );

      // Final celebration heading
      String finalHeading = "You're all set!";
      String finalSubheading = "Opening your workspace...";
      if (!isGoogleDriveConnected) {
        finalHeading = "Your workspace is ready";
        finalSubheading = "You're working offline. Your saved data is available.";
      }

      _updateState(
        _state.copyWith(
          progress: 1.0,
          heading: finalHeading,
          subheading: finalSubheading,
          isCompleted: true,
          clearCurrentRunning: true,
          result: finalResult,
        ),
      );

      return finalResult;
    } catch (e) {
      stopwatch.stop();
      debugPrint("StartupController uncaught error: $e");
      final errorResult = StartupResult(
        overallStatus: StartupOverallStatus.criticalError,
        stepStates: _state.steps,
        isGoogleDriveConnected: isGoogleDriveConnected,
        isOffline: isOffline,
        syncStatusMessage: "Startup failure",
        hasDownloadedNewData: false,
        hasUploadedLocalChanges: false,
        failureReasons: [...failureReasons, e.toString()],
        totalDuration: stopwatch.elapsed,
        criticalErrorDetails: e.toString(),
      );
      _updateState(
        _state.copyWith(
          isCriticalError: true,
          criticalErrorTitle: "Startup Error",
          criticalErrorDetails: e.toString(),
          result: errorResult,
        ),
      );
      return errorResult;
    }
  }

  /// Retries initialization after resolving a critical issue.
  Future<StartupResult> retryInitialization() async {
    _hasStarted = false;
    _state = StartupState.initial();
    notifyListeners();
    return startInitialization();
  }

  /// Executes an individual stage concurrently with its presentation delay.
  Future<void> _runStep({
    required StartupStep step,
    required double targetProgress,
    required String heading,
    required String subheading,
    required Future<Map<String, dynamic>> Function() operation,
    required void Function(Map<String, dynamic> data) onSuccess,
    required void Function(Map<String, dynamic> data) onFailure,
  }) async {
    final currentStepState = _state.steps[step]!;

    // Set step to Running
    final updatedSteps = Map<StartupStep, StartupStepState>.from(_state.steps);
    updatedSteps[step] = currentStepState.copyWith(
      status: StartupStepStatus.running,
      clearSubMessage: true,
      clearFailureReason: true,
    );

    _updateState(
      _state.copyWith(
        steps: updatedSteps,
        currentRunningStep: step,
        heading: heading,
        subheading: subheading,
      ),
    );

    // Presentation duration: randomized between 1000 and 2000 milliseconds
    final int delayMs = enablePresentationDelay ? (1000 + _random.nextInt(1000)) : 0;
    final delayFuture = delayMs > 0
        ? Future.delayed(Duration(milliseconds: delayMs))
        : Future.value();

    // Run the actual operation asynchronously
    Map<String, dynamic> opResult = {};
    try {
      opResult = await operation();
    } catch (e) {
      opResult = {'ok': false, 'status': StartupStepStatus.failed, 'message': e.toString()};
    }

    // Wait for the minimum presentation duration so the user can easily follow along
    await delayFuture;

    // Determine final status of this step
    final StartupStepStatus finalStatus = (opResult['status'] is StartupStepStatus)
        ? opResult['status']
        : (opResult['ok'] == true
            ? StartupStepStatus.success
            : (opResult['connected'] == true
                ? StartupStepStatus.success
                : StartupStepStatus.failed));

    final String? message = opResult['message']?.toString();
    final String? failureReason = opResult['failureReason']?.toString() ??
        (finalStatus == StartupStepStatus.failed ? message : null);

    updatedSteps[step] = currentStepState.copyWith(
      status: finalStatus,
      subMessage: message,
      failureReason: failureReason,
    );

    if (finalStatus == StartupStepStatus.success) {
      onSuccess(opResult);
    } else {
      onFailure(opResult);
    }

    _updateState(
      _state.copyWith(
        steps: updatedSteps,
        progress: targetProgress,
        clearCurrentRunning: true,
      ),
    );
  }

  void _markStepSkipped(StartupStep step, String reason) {
    final updatedSteps = Map<StartupStep, StartupStepState>.from(_state.steps);
    final current = updatedSteps[step]!;
    updatedSteps[step] = current.copyWith(
      status: StartupStepStatus.skipped,
      subMessage: reason,
      clearFailureReason: true,
    );
    _updateState(_state.copyWith(steps: updatedSteps));
  }
}
