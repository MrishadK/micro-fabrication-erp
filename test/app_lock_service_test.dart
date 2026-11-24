import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:micro/services/app_lock_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('AppLockService Tests', () {
    test('Initial state: lock is disabled and no PIN set', () async {
      final isEnabled = await AppLockService.instance.isLockEnabled();
      final hasPin = await AppLockService.instance.hasPinSet();

      expect(isEnabled, isFalse);
      expect(hasPin, isFalse);
    });

    test('Setting valid 6-digit PIN enables lock and saves salted hash', () async {
      final success = await AppLockService.instance.setPin('123456');
      expect(success, isTrue);

      final isEnabled = await AppLockService.instance.isLockEnabled();
      final hasPin = await AppLockService.instance.hasPinSet();
      expect(isEnabled, isTrue);
      expect(hasPin, isTrue);

      final prefs = await SharedPreferences.getInstance();
      final hash = prefs.getString('app_lock_pin_hash');
      final salt = prefs.getString('app_lock_pin_salt');

      expect(hash, isNotNull);
      expect(salt, isNotNull);
      expect(hash, isNot(equals('123456'))); // Must never store plaintext!
    });

    test('Rejects invalid PIN formats (non-6 digits)', () async {
      expect(await AppLockService.instance.setPin('12345'), isFalse);
      expect(await AppLockService.instance.setPin('1234567'), isFalse);
      expect(await AppLockService.instance.setPin('abcdef'), isFalse);
      expect(await AppLockService.instance.setPin('12345a'), isFalse);
    });

    test('PIN Verification returns true for correct PIN, false for incorrect PIN', () async {
      await AppLockService.instance.setPin('789012');

      expect(await AppLockService.instance.verifyPin('789012'), isTrue);
      expect(await AppLockService.instance.verifyPin('000000'), isFalse);
      expect(await AppLockService.instance.verifyPin('123456'), isFalse);
    });

    test('Changing PIN requires valid current PIN', () async {
      await AppLockService.instance.setPin('111222');

      // Wrong current PIN fails
      final fail = await AppLockService.instance.changePin(
        currentPin: '000000',
        newPin: '333444',
      );
      expect(fail, isFalse);
      expect(await AppLockService.instance.verifyPin('111222'), isTrue);

      // Correct current PIN succeeds
      final success = await AppLockService.instance.changePin(
        currentPin: '111222',
        newPin: '333444',
      );
      expect(success, isTrue);
      expect(await AppLockService.instance.verifyPin('111222'), isFalse);
      expect(await AppLockService.instance.verifyPin('333444'), isTrue);
    });

    test('Disabling lock requires valid current PIN', () async {
      await AppLockService.instance.setPin('555666');
      expect(await AppLockService.instance.isLockEnabled(), isTrue);

      // Wrong current PIN fails to disable
      final fail = await AppLockService.instance.disableLock(currentPin: '999999');
      expect(fail, isFalse);
      expect(await AppLockService.instance.isLockEnabled(), isTrue);

      // Correct current PIN disables lock
      final success = await AppLockService.instance.disableLock(currentPin: '555666');
      expect(success, isTrue);
      expect(await AppLockService.instance.isLockEnabled(), isFalse);
    });

    test('Brute force rate limiting locks user out after 5 consecutive failed attempts', () async {
      await AppLockService.instance.setPin('987654');

      for (int i = 0; i < 4; i++) {
        expect(await AppLockService.instance.verifyPin('000000'), isFalse);
        expect(await AppLockService.instance.isLockedOut(), isFalse);
      }

      // 5th failed attempt triggers lockout
      expect(await AppLockService.instance.verifyPin('000000'), isFalse);
      expect(await AppLockService.instance.isLockedOut(), isTrue);
      expect(await AppLockService.instance.getLockoutRemainingSeconds(), greaterThan(0));

      // During lockout, even correct PIN is rejected to throttle attacks
      expect(await AppLockService.instance.verifyPin('987654'), isFalse);
    });
  });
}
