import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_lock_service.dart';

/// Production-ready 6-digit PIN Lock Screen.
/// Works smoothly on Windows desktop (with physical keyboard & numpad support)
/// and on mobile (with on-screen keypad and haptics).
class PinLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  final String title;
  final String subtitle;

  const PinLockScreen({
    super.key,
    required this.onUnlocked,
    this.title = "MICRO Manager",
    this.subtitle = "Enter 6-digit PIN to access workspace",
  });

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen>
    with SingleTickerProviderStateMixin {
  final List<String> _enteredDigits = [];
  bool _isVerifying = false;
  String? _errorMessage;
  int _lockoutSeconds = 0;
  Timer? _lockoutTimer;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;
  final FocusNode _focusNode = FocusNode();

  static const Color _primaryNavy = Color(0xFF1A237E);
  static const Color _accentOrange = Color(0xFFFF6D00);
  static const Color _bgSoft = Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -14.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -14.0, end: 14.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 14.0, end: -10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut));

    _checkLockout();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _shakeController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _checkLockout() async {
    final remaining = await AppLockService.instance.getLockoutRemainingSeconds();
    if (!mounted) return;
    if (remaining > 0) {
      setState(() {
        _lockoutSeconds = remaining;
        _errorMessage = "Too many attempts. Locked for ${_lockoutSeconds}s";
      });
      _startLockoutCountdown();
    }
  }

  void _startLockoutCountdown() {
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_lockoutSeconds <= 1) {
        timer.cancel();
        setState(() {
          _lockoutSeconds = 0;
          _errorMessage = null;
        });
      } else {
        setState(() {
          _lockoutSeconds--;
          _errorMessage = "Too many attempts. Locked for ${_lockoutSeconds}s";
        });
      }
    });
  }

  void _handleKeyPress(String digit) {
    if (_isVerifying || _lockoutSeconds > 0) return;
    if (_enteredDigits.length < 6) {
      setState(() {
        _enteredDigits.add(digit);
        _errorMessage = null;
      });

      if (_enteredDigits.length == 6) {
        _submitPin();
      }
    }
  }

  void _handleBackspace() {
    if (_isVerifying || _lockoutSeconds > 0) return;
    if (_enteredDigits.isNotEmpty) {
      setState(() {
        _enteredDigits.removeLast();
        _errorMessage = null;
      });
    }
  }

  void _handleClear() {
    if (_isVerifying || _lockoutSeconds > 0) return;
    if (_enteredDigits.isNotEmpty) {
      setState(() {
        _enteredDigits.clear();
        _errorMessage = null;
      });
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.backspace) {
        _handleBackspace();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        _handleClear();
        return KeyEventResult.handled;
      }
      // Digits 0-9 from main keyboard and numpad
      final char = event.character;
      if (char != null && RegExp(r'^\d$').hasMatch(char)) {
        _handleKeyPress(char);
        return KeyEventResult.handled;
      }
      if (key.keyId >= LogicalKeyboardKey.digit0.keyId &&
          key.keyId <= LogicalKeyboardKey.digit9.keyId) {
        final d = (key.keyId - LogicalKeyboardKey.digit0.keyId).toString();
        _handleKeyPress(d);
        return KeyEventResult.handled;
      }
      if (key.keyId >= LogicalKeyboardKey.numpad0.keyId &&
          key.keyId <= LogicalKeyboardKey.numpad9.keyId) {
        final d = (key.keyId - LogicalKeyboardKey.numpad0.keyId).toString();
        _handleKeyPress(d);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Future<void> _submitPin() async {
    final pin = _enteredDigits.join();
    setState(() => _isVerifying = true);

    final isValid = await AppLockService.instance.verifyPin(pin);

    if (!mounted) return;

    if (isValid) {
      widget.onUnlocked();
    } else {
      _shakeController.forward(from: 0.0);
      final remainingLockout =
          await AppLockService.instance.getLockoutRemainingSeconds();
      final failedAttempts =
          await AppLockService.instance.getFailedAttempts();

      setState(() {
        _isVerifying = false;
        _enteredDigits.clear();
        if (remainingLockout > 0) {
          _lockoutSeconds = remainingLockout;
          _errorMessage = "Too many failed attempts. Locked for ${_lockoutSeconds}s";
          _startLockoutCountdown();
        } else {
          final remaining = 5 - (failedAttempts % 5);
          _errorMessage = "Incorrect PIN. $remaining attempts before temporary lockout.";
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: _bgSoft,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Header Logo & Branding
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _primaryNavy.withOpacity(0.08),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/app.png',
                        width: 56,
                        height: 56,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.lock_rounded,
                          size: 48,
                          color: _primaryNavy,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: _primaryNavy,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blueGrey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // 6-Digit PIN Indicators with Shake Animation
                    AnimatedBuilder(
                      animation: _shakeAnimation,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(_shakeAnimation.value, 0),
                          child: child,
                        );
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(6, (index) {
                          final isFilled = index < _enteredDigits.length;
                          final isCurrent = index == _enteredDigits.length;
                          final hasError = _errorMessage != null;

                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isFilled
                                  ? (hasError ? Colors.red.shade600 : _primaryNavy)
                                  : Colors.transparent,
                              border: Border.all(
                                color: hasError
                                    ? Colors.red.shade400
                                    : (isFilled
                                        ? _primaryNavy
                                        : (isCurrent
                                            ? _accentOrange
                                            : Colors.blueGrey.shade300)),
                                width: isCurrent ? 2.5 : 2.0,
                              ),
                              boxShadow: isFilled
                                  ? [
                                      BoxShadow(
                                        color: (hasError ? Colors.red : _primaryNavy)
                                            .withOpacity(0.25),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Error or Lockout Feedback
                    SizedBox(
                      height: 24,
                      child: _errorMessage != null
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _lockoutSeconds > 0
                                      ? Icons.timer_outlined
                                      : Icons.error_outline_rounded,
                                  size: 15,
                                  color: Colors.red.shade600,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    _errorMessage!,
                                    style: TextStyle(
                                      color: Colors.red.shade600,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            )
                          : (_isVerifying
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: _primaryNavy,
                                  ),
                                )
                              : const SizedBox.shrink()),
                    ),
                    const SizedBox(height: 24),

                    // On-Screen Keypad (0-9, Clear, Backspace)
                    _buildKeypad(),
                    const SizedBox(height: 20),

                    // Security Label
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shield_outlined,
                            size: 14, color: Colors.blueGrey[400]),
                        const SizedBox(width: 6),
                        Text(
                          "Encrypted Offline Security • MICRO Fabrication Suite",
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blueGrey[400],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeypad() {
    final bool disabled = _isVerifying || _lockoutSeconds > 0;

    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildKeyButton("1", disabled: disabled),
              _buildKeyButton("2", disabled: disabled),
              _buildKeyButton("3", disabled: disabled),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildKeyButton("4", disabled: disabled),
              _buildKeyButton("5", disabled: disabled),
              _buildKeyButton("6", disabled: disabled),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildKeyButton("7", disabled: disabled),
              _buildKeyButton("8", disabled: disabled),
              _buildKeyButton("9", disabled: disabled),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionButton(
                icon: Icons.refresh_rounded,
                tooltip: "Clear",
                onPressed: disabled ? null : _handleClear,
              ),
              _buildKeyButton("0", disabled: disabled),
              _buildActionButton(
                icon: Icons.backspace_outlined,
                tooltip: "Delete",
                onPressed: disabled ? null : _handleBackspace,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKeyButton(String text, {required bool disabled}) {
    return Material(
      color: Colors.white,
      elevation: disabled ? 0 : 1,
      shadowColor: Colors.black.withOpacity(0.06),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        splashColor: _accentOrange.withOpacity(0.12),
        highlightColor: _primaryNavy.withOpacity(0.04),
        onTap: disabled ? null : () => _handleKeyPress(text),
        child: Container(
          width: 72,
          height: 62,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.blueGrey.withOpacity(0.12),
              width: 1,
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: disabled ? Colors.blueGrey.shade300 : _primaryNavy,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    final bool disabled = onPressed == null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Container(
          width: 72,
          height: 62,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 22,
            color: disabled ? Colors.blueGrey.shade300 : Colors.blueGrey.shade600,
          ),
        ),
      ),
    );
  }
}
