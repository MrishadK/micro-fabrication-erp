import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/startup/startup_controller.dart';
import '../../services/startup/startup_result.dart';
import '../../services/startup/startup_step.dart';
import 'cloud_sync_header_icon.dart';
import 'fabrication_welding_painter.dart';
import 'google_drive_icon.dart';

/// Production-ready Windows Frameless Startup & Initialization Screen.
/// Dimensions: 900 × 506 logical pixels (16:9 aspect ratio).
class WindowsSplashScreen extends StatefulWidget {
  final void Function(StartupResult result) onInitializationComplete;
  final bool enablePresentationDelay;

  const WindowsSplashScreen({
    super.key,
    required this.onInitializationComplete,
    this.enablePresentationDelay = true,
  });

  @override
  State<WindowsSplashScreen> createState() => _WindowsSplashScreenState();
}

class _WindowsSplashScreenState extends State<WindowsSplashScreen>
    with SingleTickerProviderStateMixin {
  late final StartupController _controller;
  late final AnimationController _weldingAnimController;

  static const Color _accentBlue = Color(0xFF2563EB); // Vibrant Blue 600
  static const Color _cyanSpark = Color(0xFF38BDF8); // Sky 400

  @override
  void initState() {
    super.initState();
    _weldingAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _controller = StartupController(
      enablePresentationDelay: widget.enablePresentationDelay,
    );
    _controller.addListener(_onControllerStateChanged);

    // Begin startup sequence after first frame render
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.startInitialization();
    });
  }

  void _onControllerStateChanged() {
    if (!mounted) return;
    setState(() {});

    final state = _controller.state;
    if (state.isCompleted && state.result != null && !state.isCriticalError) {
      // Small pause on 100% celebration before transitioning
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) {
          widget.onInitializationComplete(state.result!);
        }
      });
    }
  }

  @override
  void dispose() {
    _weldingAnimController.dispose();
    _controller.removeListener(_onControllerStateChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Container(
          width: 900,
          height: 506,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 36,
                spreadRadius: 4,
                offset: const Offset(0, 12),
              ),
            ],
            border: Border.all(
              color: const Color(0xFFE2E8F0),
              width: 1.0,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              // ----------------------------------------------------
              // LEFT PANEL: BRANDING & BLUE-TINTED FABRICATION SCENE
              // ----------------------------------------------------
              _buildLeftBrandingPanel(),

              // SUBTLE VERTICAL DIVIDER
              Container(
                width: 1,
                height: double.infinity,
                color: const Color(0xFFE2E8F0),
              ),

              // ----------------------------------------------------
              // RIGHT PANEL: INITIALIZATION DIAGNOSTICS OR RECOVERY
              // ----------------------------------------------------
              Expanded(
                child: state.isCriticalError
                    ? _buildCriticalRecoveryView(state)
                    : _buildInitializationPanel(state),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Left Column: Brand Logo, Fabrication Workshop Imagery & Curved Accents
  Widget _buildLeftBrandingPanel() {
    return Container(
      width: 330,
      height: 506,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0F172A), // Dark slate navy
            Color(0xFF1E293B),
            Color(0xFF172554), // Deep industrial blue
          ],
        ),
      ),
      child: Stack(
        children: [
          // Top-left curved decorative glow
          Positioned(
            top: -60,
            left: -60,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accentBlue.withValues(alpha: 0.22),
              ),
            ),
          ),

          // Bottom curved decorative wave element
          Positioned(
            bottom: -40,
            right: -30,
            child: Container(
              width: 200,
              height: 120,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(100),
                ),
                gradient: LinearGradient(
                  colors: [
                    _accentBlue.withValues(alpha: 0.2),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Lower Section: Custom Blue-tinted Fabrication & Welding Animation
          Positioned(
            left: 0,
            right: 0,
            bottom: 45,
            height: 220,
            child: AnimatedBuilder(
              animation: _weldingAnimController,
              builder: (context, child) {
                return CustomPaint(
                  painter: FabricationWeldingPainter(
                    animationValue: _weldingAnimController.value,
                  ),
                );
              },
            ),
          ),

          // Branding Content (Logo & Typography)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Clean container holding existing app logo
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: _cyanSpark.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/app.png',
                    width: 44,
                    height: 44,
                    errorBuilder: (_, __, ___) => Image.asset(
                      'assets/Logo.png',
                      width: 44,
                      height: 44,
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Brand Title
                const Text(
                  "MICRO",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),

                // Subtitle
                const Text(
                  "Industrial Fabrication ERP",
                  style: TextStyle(
                    color: Color(0xFF94A3B8), // Slate 400
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),

                const Spacer(),

                // Version & Desktop Platform badge
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF10B981), // Emerald online pulse
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      "v0.2.3 • Windows Desktop Edition",
                      style: TextStyle(
                        color: Color(0xFF64748B), // Slate 500
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Right Column: Dynamic Headers, Checklist Container, Animated Progress Bar
  Widget _buildInitializationPanel(StartupState state) {
    return Container(
      color: const Color(0xFFF8FAFC), // Slate 50
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Center: Animated Blue Cloud Sync Icon & Dynamic Heading
          Center(
            child: Column(
              children: [
                CloudSyncHeaderIcon(
                  size: 46,
                  isSpinning: !state.isCompleted,
                ),
                const SizedBox(height: 10),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    state.heading,
                    key: ValueKey(state.heading),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    state.subheading,
                    key: ValueKey(state.subheading),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64748B),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Rounded Checklist Container
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                for (var step in StartupStep.values) ...[
                  _buildChecklistRow(
                    stepState: state.steps[step]!,
                    isRunning: state.currentRunningStep == step,
                  ),
                  if (step != StartupStep.values.last)
                    const Divider(height: 1, thickness: 0.7, color: Color(0xFFF1F5F9)),
                ],
              ],
            ),
          ),

          const Spacer(),

          // Smooth Animated Progress Bar with Percentage
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                state.isCompleted
                    ? "Workspace ready"
                    : (state.currentRunningStep != null
                        ? state.steps[state.currentRunningStep!]?.title ?? "Initializing..."
                        : "Preparing system..."),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
              Text(
                "${(state.progress * 100).toInt()}%",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2563EB),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: state.progress),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return LinearProgressIndicator(
                  value: value,
                  minHeight: 6,
                  backgroundColor: const Color(0xFFE2E8F0),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Individual checklist row with feature icon on left, title & details in middle,
  /// and dynamic state indicator on the right.
  Widget _buildChecklistRow({
    required StartupStepState stepState,
    required bool isRunning,
  }) {
    final status = stepState.status;

    // Row background highlighting: light-blue when running, light-red when failed
    Color rowBg = Colors.transparent;
    if (isRunning || status == StartupStepStatus.running) {
      rowBg = const Color(0xFFEFF6FF); // Light blue
    } else if (status == StartupStepStatus.failed) {
      rowBg = const Color(0xFFFEF2F2); // Subtle light red
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6.5),
      decoration: BoxDecoration(
        color: rowBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // 1. Feature Icon on Left (Google Drive logo used only on row 3)
          SizedBox(
            width: 22,
            height: 22,
            child: Center(
              child: stepState.step == StartupStep.connectingDrive
                  ? const GoogleDriveIcon(size: 16)
                  : Icon(
                      stepState.customIcon ?? Icons.circle,
                      size: 16,
                      color: isRunning
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF64748B),
                    ),
            ),
          ),
          const SizedBox(width: 10),

          // 2. Title & Dynamic Feedback Reason in Middle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  stepState.title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isRunning ? FontWeight.w700 : FontWeight.w600,
                    color: status == StartupStepStatus.skipped
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF1E293B),
                  ),
                ),
                if (stepState.failureReason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1.5),
                    child: Text(
                      stepState.failureReason!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFDC2626), // Red 600
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else if (stepState.subMessage != null &&
                    stepState.subMessage!.isNotEmpty &&
                    status != StartupStepStatus.pending)
                  Padding(
                    padding: const EdgeInsets.only(top: 1.5),
                    child: Text(
                      stepState.subMessage!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: status == StartupStepStatus.success
                            ? const Color(0xFF16A34A)
                            : const Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // 3. Dynamic Status Indicator on Right
          _buildStatusIcon(status, isRunning),
        ],
      ),
    );
  }

  /// Builds the single dynamic status indicator for the right side of each row
  Widget _buildStatusIcon(StartupStepStatus status, bool isRunning) {
    if (isRunning || status == StartupStepStatus.running) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
        ),
      );
    }

    switch (status) {
      case StartupStepStatus.success:
        return const Icon(
          Icons.check_circle_rounded,
          color: Color(0xFF16A34A), // Emerald 600
          size: 18,
        );
      case StartupStepStatus.failed:
        return const Icon(
          Icons.cancel_rounded,
          color: Color(0xFFDC2626), // Red 600
          size: 18,
        );
      case StartupStepStatus.warning:
        return const Icon(
          Icons.warning_amber_rounded,
          color: Color(0xFFD97706), // Amber 600
          size: 18,
        );
      case StartupStepStatus.skipped:
        return const Icon(
          Icons.remove_circle_outline_rounded,
          color: Color(0xFF94A3B8), // Slate 400
          size: 17,
        );
      case StartupStepStatus.pending:
      default:
        return Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFCBD5E1), width: 1.8),
          ),
        );
    }
  }

  /// Critical Failure View: Allows Retry, Local Restore, Error Inspect or Exit.
  Widget _buildCriticalRecoveryView(StartupState state) {
    return Container(
      color: const Color(0xFFFFF7F7),
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: Color(0xFFDC2626),
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.criticalErrorTitle ?? "Data Recovery Required",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF991B1B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      "A critical problem prevented loading your saved records.",
                      style: TextStyle(fontSize: 12, color: Color(0xFF7F1D1D)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Issue Description:",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF991B1B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  state.criticalErrorDetails ?? "Inaccessible database storage",
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF334155),
                    fontFamily: 'monospace',
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Recovery Actions
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => _controller.retryInitialization(),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text("Retry Verification"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => exit(0),
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text("Exit Application"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF64748B),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
