import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_lock_service.dart';

/// Shows a dialog to set up a new 6-digit PIN.
Future<bool?> showPinSetupDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _PinSetupDialog(),
  );
}

/// Shows a dialog to change the current 6-digit PIN (verifying old PIN first).
Future<bool?> showPinChangeDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _PinChangeDialog(),
  );
}

/// Shows a dialog to verify the current 6-digit PIN before disabling or sensitive actions.
Future<bool?> showPinVerifyDialog(
  BuildContext context, {
  String title = "Verify 6-Digit PIN",
  String subtitle = "Enter your current PIN to continue",
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _PinVerifyDialog(title: title, subtitle: subtitle),
  );
}

// ============================================================================
// 1. PIN SETUP DIALOG
// ============================================================================
class _PinSetupDialog extends StatefulWidget {
  const _PinSetupDialog();

  @override
  State<_PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<_PinSetupDialog> {
  int _step = 1; // 1: Enter new PIN, 2: Confirm new PIN
  String _newPin = "";
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String? _error;
  bool _isLoading = false;

  static const Color _primaryNavy = Color(0xFF1A237E);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onPinSubmitted(String value) {
    if (value.length != 6) return;

    if (_step == 1) {
      setState(() {
        _newPin = value;
        _step = 2;
        _error = null;
        _pinController.clear();
      });
      _focusNode.requestFocus();
    } else {
      if (value != _newPin) {
        setState(() {
          _error = "PINs do not match. Please re-enter.";
          _step = 1;
          _newPin = "";
          _pinController.clear();
        });
        _focusNode.requestFocus();
      } else {
        _savePin(value);
      }
    }
  }

  Future<void> _savePin(String pin) async {
    setState(() => _isLoading = true);
    final success = await AppLockService.instance.setPin(pin);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (success) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = "Failed to save PIN. Please try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header (No white canvas underneath)
                Container(
                  width: double.infinity,
                  color: _primaryNavy,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_rounded, color: Colors.white, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _step == 1 ? "Set 6-Digit PIN" : "Confirm 6-Digit PIN",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                    ],
                  ),
                ),

                // Body
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _step == 1
                            ? "Create a 6-digit PIN to secure your workshop records and payments."
                            : "Re-enter the 6-digit PIN to confirm.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 20),

                      // PIN Input field
                      TextField(
                        controller: _pinController,
                        focusNode: _focusNode,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        obscureText: true,
                        maxLength: 6,
                        style: const TextStyle(
                          fontSize: 28,
                          letterSpacing: 12,
                          fontWeight: FontWeight.bold,
                          color: _primaryNavy,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          counterText: "",
                          hintText: "••••••",
                          hintStyle: TextStyle(
                            color: Colors.grey[400],
                            letterSpacing: 10,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: _primaryNavy, width: 2),
                          ),
                        ),
                        onChanged: (val) {
                          if (val.length == 6) {
                            _onPinSubmitted(val);
                          }
                        },
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],

                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text("Cancel"),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryNavy,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: _isLoading
                                ? null
                                : () => _onPinSubmitted(_pinController.text),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(_step == 1 ? "Next" : "Save PIN"),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 2. PIN CHANGE DIALOG
// ============================================================================
class _PinChangeDialog extends StatefulWidget {
  const _PinChangeDialog();

  @override
  State<_PinChangeDialog> createState() => _PinChangeDialogState();
}

class _PinChangeDialogState extends State<_PinChangeDialog> {
  int _step = 1; // 1: Verify current PIN, 2: Enter new PIN, 3: Confirm new PIN
  String _newPin = "";
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String? _error;
  bool _isLoading = false;

  static const Color _primaryNavy = Color(0xFF1A237E);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _onPinSubmitted(String value) async {
    if (value.length != 6) return;

    if (_step == 1) {
      setState(() => _isLoading = true);
      final isValid = await AppLockService.instance.verifyPin(value);
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (isValid) {
        setState(() {
          _step = 2;
          _error = null;
          _pinController.clear();
        });
        _focusNode.requestFocus();
      } else {
        setState(() {
          _error = "Incorrect current PIN. Please try again.";
          _pinController.clear();
        });
        _focusNode.requestFocus();
      }
    } else if (_step == 2) {
      setState(() {
        _newPin = value;
        _step = 3;
        _error = null;
        _pinController.clear();
      });
      _focusNode.requestFocus();
    } else {
      if (value != _newPin) {
        setState(() {
          _error = "New PINs do not match. Please re-enter new PIN.";
          _step = 2;
          _newPin = "";
          _pinController.clear();
        });
        _focusNode.requestFocus();
      } else {
        setState(() => _isLoading = true);
        final success = await AppLockService.instance.setPin(value);
        if (!mounted) return;
        setState(() => _isLoading = false);
        if (success) {
          Navigator.of(context).pop(true);
        } else {
          setState(() => _error = "Failed to update PIN. Please try again.");
        }
      }
    }
  }

  String _getTitle() {
    switch (_step) {
      case 1:
        return "Verify Current PIN";
      case 2:
        return "Enter New 6-Digit PIN";
      case 3:
        return "Confirm New 6-Digit PIN";
      default:
        return "Change PIN";
    }
  }

  String _getDescription() {
    switch (_step) {
      case 1:
        return "Enter your current 6-digit PIN to authorize changing it.";
      case 2:
        return "Enter your new 6-digit security PIN.";
      case 3:
        return "Re-enter the new 6-digit PIN to confirm.";
      default:
        return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  width: double.infinity,
                  color: _primaryNavy,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_reset_rounded,
                          color: Colors.white, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _getTitle(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                    ],
                  ),
                ),

                // Body
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _getDescription(),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 20),

                      TextField(
                        controller: _pinController,
                        focusNode: _focusNode,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        obscureText: true,
                        maxLength: 6,
                        style: const TextStyle(
                          fontSize: 28,
                          letterSpacing: 12,
                          fontWeight: FontWeight.bold,
                          color: _primaryNavy,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          counterText: "",
                          hintText: "••••••",
                          hintStyle: TextStyle(
                            color: Colors.grey[400],
                            letterSpacing: 10,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: _primaryNavy, width: 2),
                          ),
                        ),
                        onChanged: (val) {
                          if (val.length == 6) {
                            _onPinSubmitted(val);
                          }
                        },
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],

                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text("Cancel"),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryNavy,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: _isLoading
                                ? null
                                : () => _onPinSubmitted(_pinController.text),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(_step == 3 ? "Update PIN" : "Next"),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 3. PIN VERIFY DIALOG (Before disabling or sensitive actions)
// ============================================================================
class _PinVerifyDialog extends StatefulWidget {
  final String title;
  final String subtitle;

  const _PinVerifyDialog({
    required this.title,
    required this.subtitle,
  });

  @override
  State<_PinVerifyDialog> createState() => _PinVerifyDialogState();
}

class _PinVerifyDialogState extends State<_PinVerifyDialog> {
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String? _error;
  bool _isLoading = false;

  static const Color _primaryNavy = Color(0xFF1A237E);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _verify(String pin) async {
    if (pin.length != 6) return;

    setState(() => _isLoading = true);
    final isValid = await AppLockService.instance.verifyPin(pin);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (isValid) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _error = "Incorrect PIN. Please try again.";
        _pinController.clear();
      });
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  width: double.infinity,
                  color: _primaryNavy,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.security_rounded,
                          color: Colors.white, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                    ],
                  ),
                ),

                // Body
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.subtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 20),

                      TextField(
                        controller: _pinController,
                        focusNode: _focusNode,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        obscureText: true,
                        maxLength: 6,
                        style: const TextStyle(
                          fontSize: 28,
                          letterSpacing: 12,
                          fontWeight: FontWeight.bold,
                          color: _primaryNavy,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          counterText: "",
                          hintText: "••••••",
                          hintStyle: TextStyle(
                            color: Colors.grey[400],
                            letterSpacing: 10,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: _primaryNavy, width: 2),
                          ),
                        ),
                        onChanged: (val) {
                          if (val.length == 6) {
                            _verify(val);
                          }
                        },
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],

                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text("Cancel"),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryNavy,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: _isLoading
                                ? null
                                : () => _verify(_pinController.text),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text("Verify"),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
