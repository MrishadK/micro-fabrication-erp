import 'package:flutter/material.dart';

/// The 6 sequential stages of application startup.
enum StartupStep {
  startingApp,
  preparingData,
  connectingDrive,
  checkingUpdates,
  syncingData,
  settingWorkspace,
}

/// The visual and functional status of an initialization stage.
enum StartupStepStatus {
  pending,
  running,
  success,
  failed,
  skipped,
  warning,
}

/// Represents the runtime state of an individual startup stage.
class StartupStepState {
  final StartupStep step;
  final StartupStepStatus status;
  final String title;
  final String? subMessage;
  final String? failureReason;
  final IconData? customIcon;

  const StartupStepState({
    required this.step,
    required this.status,
    required this.title,
    this.subMessage,
    this.failureReason,
    this.customIcon,
  });

  StartupStepState copyWith({
    StartupStepStatus? status,
    String? title,
    String? subMessage,
    String? failureReason,
    IconData? customIcon,
    bool clearSubMessage = false,
    bool clearFailureReason = false,
  }) {
    return StartupStepState(
      step: step,
      status: status ?? this.status,
      title: title ?? this.title,
      subMessage: clearSubMessage ? null : (subMessage ?? this.subMessage),
      failureReason:
          clearFailureReason ? null : (failureReason ?? this.failureReason),
      customIcon: customIcon ?? this.customIcon,
    );
  }

  /// Initial default state for a given step.
  factory StartupStepState.initial(StartupStep step) {
    switch (step) {
      case StartupStep.startingApp:
        return const StartupStepState(
          step: StartupStep.startingApp,
          status: StartupStepStatus.pending,
          title: "Starting the application",
          customIcon: Icons.rocket_launch_rounded,
        );
      case StartupStep.preparingData:
        return const StartupStepState(
          step: StartupStep.preparingData,
          status: StartupStepStatus.pending,
          title: "Preparing your data",
          customIcon: Icons.storage_rounded,
        );
      case StartupStep.connectingDrive:
        return const StartupStepState(
          step: StartupStep.connectingDrive,
          status: StartupStepStatus.pending,
          title: "Connecting to Google Drive",
          customIcon: Icons.cloud_queue_rounded,
        );
      case StartupStep.checkingUpdates:
        return const StartupStepState(
          step: StartupStep.checkingUpdates,
          status: StartupStepStatus.pending,
          title: "Checking for new updates",
          customIcon: Icons.update_rounded,
        );
      case StartupStep.syncingData:
        return const StartupStepState(
          step: StartupStep.syncingData,
          status: StartupStepStatus.pending,
          title: "Synchronizing your data",
          customIcon: Icons.sync_rounded,
        );
      case StartupStep.settingWorkspace:
        return const StartupStepState(
          step: StartupStep.settingWorkspace,
          status: StartupStepStatus.pending,
          title: "Setting up your workspace",
          customIcon: Icons.desktop_windows_rounded,
        );
    }
  }
}
