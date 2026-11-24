import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Secure 6-digit application lock service.
/// Uses cryptographically salted SHA-256 hashing, rate limiting, and brute-force protection.
class AppLockService {
  static final AppLockService instance = AppLockService._init();
  AppLockService._init();

  static const String _keyEnabled = 'app_lock_enabled';
  static const String _keyPinHash = 'app_lock_pin_hash';
  static const String _keyPinSalt = 'app_lock_pin_salt';
  static const String _keyFailedAttempts = 'app_lock_failed_attempts';
  static const String _keyLockoutUntil = 'app_lock_lockout_until';

  static const int maxAttemptsBeforeLockout = 5;
  static const int firstLockoutDurationSeconds = 30;
  static const int strictLockoutDurationSeconds = 120;

  /// Check whether the 6-digit lock is currently enabled and configured.
  Future<bool> isLockEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_keyEnabled) ?? false;
    final hash = prefs.getString(_keyPinHash);
    return enabled && hash != null && hash.isNotEmpty;
  }

  /// Check whether a PIN has ever been configured.
  Future<bool> hasPinSet() async {
    final prefs = await SharedPreferences.getInstance();
    final hash = prefs.getString(_keyPinHash);
    return hash != null && hash.isNotEmpty;
  }

  /// Check if the user is currently locked out from entering the PIN.
  Future<bool> isLockedOut() async {
    final remaining = await getLockoutRemainingSeconds();
    return remaining > 0;
  }

  /// Returns remaining lockout time in seconds (0 if not locked out).
  Future<int> getLockoutRemainingSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    final lockoutUntil = prefs.getInt(_keyLockoutUntil) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (lockoutUntil > now) {
      return ((lockoutUntil - now) / 1000).ceil();
    }
    return 0;
  }

  /// Get the current number of consecutive failed attempts.
  Future<int> getFailedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyFailedAttempts) ?? 0;
  }

  /// Verifies the entered 6-digit PIN against the salted hash.
  /// Returns `true` if valid, `false` otherwise.
  Future<bool> verifyPin(String enteredPin) async {
    final lockoutSeconds = await getLockoutRemainingSeconds();
    if (lockoutSeconds > 0) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    final storedHash = prefs.getString(_keyPinHash);
    final salt = prefs.getString(_keyPinSalt);

    if (storedHash == null || salt == null) {
      return false;
    }

    final computedHash = _hashPin(enteredPin, salt);
    final isMatch = _constantTimeEquals(computedHash, storedHash);

    if (isMatch) {
      // Reset failed attempts & lockout
      await prefs.setInt(_keyFailedAttempts, 0);
      await prefs.remove(_keyLockoutUntil);
      return true;
    } else {
      // Increment failed attempts and apply lockout if exceeded
      final attempts = (prefs.getInt(_keyFailedAttempts) ?? 0) + 1;
      await prefs.setInt(_keyFailedAttempts, attempts);

      if (attempts >= maxAttemptsBeforeLockout * 2) {
        // Strict 2-minute lockout
        final lockUntil = DateTime.now()
            .add(const Duration(seconds: strictLockoutDurationSeconds))
            .millisecondsSinceEpoch;
        await prefs.setInt(_keyLockoutUntil, lockUntil);
      } else if (attempts >= maxAttemptsBeforeLockout) {
        // Standard 30-second lockout
        final lockUntil = DateTime.now()
            .add(const Duration(seconds: firstLockoutDurationSeconds))
            .millisecondsSinceEpoch;
        await prefs.setInt(_keyLockoutUntil, lockUntil);
      }
      return false;
    }
  }

  /// Sets or creates a new 6-digit PIN.
  Future<bool> setPin(String newPin) async {
    if (!_isValidPinFormat(newPin)) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    final salt = _generateSalt();
    final hash = _hashPin(newPin, salt);

    await prefs.setString(_keyPinSalt, salt);
    await prefs.setString(_keyPinHash, hash);
    await prefs.setBool(_keyEnabled, true);
    await prefs.setInt(_keyFailedAttempts, 0);
    await prefs.remove(_keyLockoutUntil);

    debugPrint("AppLock: 6-digit PIN successfully configured.");
    return true;
  }

  /// Changes the existing PIN after verifying the current PIN.
  Future<bool> changePin({
    required String currentPin,
    required String newPin,
  }) async {
    final isCurrentValid = await verifyPin(currentPin);
    if (!isCurrentValid) {
      return false;
    }

    return await setPin(newPin);
  }

  /// Disables the app lock after verifying the current PIN.
  Future<bool> disableLock({required String currentPin}) async {
    final isCurrentValid = await verifyPin(currentPin);
    if (!isCurrentValid) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, false);
    await prefs.setInt(_keyFailedAttempts, 0);
    await prefs.remove(_keyLockoutUntil);

    debugPrint("AppLock: App lock disabled.");
    return true;
  }

  /// Enables the lock if a valid PIN hash already exists.
  Future<bool> enableLock() async {
    final hasPin = await hasPinSet();
    if (!hasPin) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, true);
    return true;
  }

  /// Validates format: exactly 6 decimal digits.
  bool _isValidPinFormat(String pin) {
    return RegExp(r'^\d{6}$').hasMatch(pin);
  }

  /// Generates a secure random 16-byte salt as a hex string.
  String _generateSalt() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Hashes the PIN combined with the cryptographic salt using SHA-256.
  String _hashPin(String pin, String salt) {
    final bytes = utf8.encode('$salt:$pin:$salt');
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Constant-time string equality check to mitigate timing attacks.
  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}
