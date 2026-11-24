import 'package:flutter_test/flutter_test.dart';
import 'package:micro/services/startup/startup_step.dart';
import 'package:micro/services/startup/startup_result.dart';
import 'package:micro/services/startup/startup_controller.dart';

void main() {
  group('StartupStep Tests', () {
    test('StartupStep definitions contain all 6 stages', () {
      final steps = StartupStep.values;
      expect(steps.length, equals(6));
      expect(steps[0], equals(StartupStep.startingApp));
      expect(steps[1], equals(StartupStep.preparingData));
      expect(steps[2], equals(StartupStep.connectingDrive));
      expect(steps[3], equals(StartupStep.checkingUpdates));
      expect(steps[4], equals(StartupStep.syncingData));
      expect(steps[5], equals(StartupStep.settingWorkspace));
    });

    test('StartupStepState initial state is pending', () {
      final state = StartupStepState.initial(StartupStep.startingApp);
      expect(state.status, equals(StartupStepStatus.pending));
      expect(state.subMessage, isNull);
      expect(state.failureReason, isNull);
    });

    test('StartupStepState running and success transitions', () {
      final state = StartupStepState.initial(StartupStep.preparingData)
          .copyWith(
            status: StartupStepStatus.running,
            subMessage: 'Checking database tables',
          );
      expect(state.status, equals(StartupStepStatus.running));
      expect(state.subMessage, equals('Checking database tables'));

      final doneState = state.copyWith(
        status: StartupStepStatus.success,
        subMessage: 'Your data is ready',
      );
      expect(doneState.status, equals(StartupStepStatus.success));
      expect(doneState.subMessage, equals('Your data is ready'));
    });

    test('StartupStepState failure handles failureReason and status', () {
      final state = StartupStepState.initial(StartupStep.connectingDrive)
          .copyWith(
            status: StartupStepStatus.failed,
            failureReason: 'Failed: Google not logged in',
          );
      expect(state.status, equals(StartupStepStatus.failed));
      expect(state.failureReason, equals('Failed: Google not logged in'));
    });

    test('StartupStepState skipped transition', () {
      final state = StartupStepState.initial(StartupStep.syncingData)
          .copyWith(
            status: StartupStepStatus.skipped,
            subMessage: 'Offline — local data preserved',
          );
      expect(state.status, equals(StartupStepStatus.skipped));
      expect(state.subMessage, equals('Offline — local data preserved'));
    });
  });

  group('StartupResult Tests', () {
    test('StartupResult reports success when overallStatus is success', () {
      final steps = {
        for (var step in StartupStep.values)
          step: StartupStepState.initial(step).copyWith(
            status: StartupStepStatus.success,
            subMessage: 'OK',
          ),
      };
      final result = StartupResult(
        overallStatus: StartupOverallStatus.success,
        stepStates: steps,
        isGoogleDriveConnected: true,
        googleEmail: 'user@example.com',
        isOffline: false,
        syncStatusMessage: 'Data synchronized',
        hasDownloadedNewData: false,
        hasUploadedLocalChanges: false,
        failureReasons: const [],
        totalDuration: const Duration(seconds: 2),
      );

      expect(result.overallStatus, equals(StartupOverallStatus.success));
      expect(result.isCritical, isFalse);
      expect(result.isGoogleDriveConnected, isTrue);
      expect(result.isOffline, isFalse);
    });

    test('StartupResult reports offlineReady when Drive is not signed in', () {
      final steps = {
        StartupStep.startingApp: StartupStepState.initial(StartupStep.startingApp)
            .copyWith(status: StartupStepStatus.success),
        StartupStep.preparingData: StartupStepState.initial(StartupStep.preparingData)
            .copyWith(status: StartupStepStatus.success),
        StartupStep.connectingDrive: StartupStepState.initial(StartupStep.connectingDrive)
            .copyWith(
              status: StartupStepStatus.failed,
              failureReason: 'Failed: Google not logged in',
            ),
        StartupStep.checkingUpdates: StartupStepState.initial(StartupStep.checkingUpdates)
            .copyWith(status: StartupStepStatus.skipped),
        StartupStep.syncingData: StartupStepState.initial(StartupStep.syncingData)
            .copyWith(status: StartupStepStatus.skipped),
        StartupStep.settingWorkspace: StartupStepState.initial(StartupStep.settingWorkspace)
            .copyWith(status: StartupStepStatus.success),
      };
      final result = StartupResult(
        overallStatus: StartupOverallStatus.offlineReady,
        stepStates: steps,
        isGoogleDriveConnected: false,
        isOffline: false,
        syncStatusMessage: 'Google Drive offline — continuing with local database',
        hasDownloadedNewData: false,
        hasUploadedLocalChanges: false,
        failureReasons: const ['Failed: Google not logged in'],
        totalDuration: const Duration(seconds: 2),
        inAppNotificationMessage: 'Google Drive is disconnected. Your work is saved locally.',
        inAppNotificationType: 'info',
      );

      expect(result.overallStatus, equals(StartupOverallStatus.offlineReady));
      expect(result.isCritical, isFalse);
      expect(result.hasInAppNotification, isTrue);
      expect(result.failureReasons, contains('Failed: Google not logged in'));
    });

    test('StartupResult reports criticalError when database check fails', () {
      final steps = {
        StartupStep.startingApp: StartupStepState.initial(StartupStep.startingApp)
            .copyWith(status: StartupStepStatus.success),
        StartupStep.preparingData: StartupStepState.initial(StartupStep.preparingData)
            .copyWith(
              status: StartupStepStatus.failed,
              failureReason: 'PRAGMA integrity check returned corrupt',
            ),
        StartupStep.connectingDrive: StartupStepState.initial(StartupStep.connectingDrive),
        StartupStep.checkingUpdates: StartupStepState.initial(StartupStep.checkingUpdates),
        StartupStep.syncingData: StartupStepState.initial(StartupStep.syncingData),
        StartupStep.settingWorkspace: StartupStepState.initial(StartupStep.settingWorkspace),
      };
      final result = StartupResult(
        overallStatus: StartupOverallStatus.criticalError,
        stepStates: steps,
        isGoogleDriveConnected: false,
        isOffline: true,
        syncStatusMessage: 'Database integrity verification failed',
        hasDownloadedNewData: false,
        hasUploadedLocalChanges: false,
        failureReasons: const ['PRAGMA integrity check returned corrupt'],
        totalDuration: const Duration(seconds: 1),
        criticalErrorDetails: 'PRAGMA integrity check returned corrupt',
      );

      expect(result.isCritical, isTrue);
      expect(result.overallStatus, equals(StartupOverallStatus.criticalError));
      expect(result.criticalErrorDetails, contains('corrupt'));
    });
  });

  group('StartupController Tests', () {
    test('StartupController initializes with pending steps and 0 progress', () {
      final controller = StartupController(enablePresentationDelay: false);
      expect(controller.state.progress, equals(0.0));
      expect(controller.state.isCompleted, isFalse);
      expect(controller.state.heading, equals('Getting things ready for you...'));
      expect(controller.state.steps.length, equals(6));
    });

    test('StartupState copyWith correctly updates progress and completion', () {
      var state = StartupState.initial();
      expect(state.progress, equals(0.0));

      state = state.copyWith(progress: 0.5, heading: 'Checking remote updates');
      expect(state.progress, equals(0.5));
      expect(state.heading, equals('Checking remote updates'));
      expect(state.isCompleted, isFalse);

      state = state.copyWith(progress: 1.0, isCompleted: true);
      expect(state.progress, equals(1.0));
      expect(state.isCompleted, isTrue);
    });
  });
}
