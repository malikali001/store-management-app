import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:store_manager/security/pin.dart';
import 'package:store_manager/security/lock_policy.dart';

void main() {
  group('Pin (PBKDF2-HMAC-SHA256)', () {
    test('matches an RFC-style known vector (P="password", S="salt", c=1)', () {
      // PBKDF2-HMAC-SHA256, 1 iteration, dkLen 32.
      // Expected first bytes: 12 0f b6 cf fc f8 b3 2c ...
      final dk = Pin.pbkdf2(utf8.encode('password'), utf8.encode('salt'), 1, 32);
      final hex = dk.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(hex.startsWith('120fb6cffcf8b32c'), isTrue, reason: hex);
    });

    test('c=2 known vector', () {
      final dk = Pin.pbkdf2(utf8.encode('password'), utf8.encode('salt'), 2, 32);
      final hex = dk.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(hex.startsWith('ae4d0c95af6b46d3'), isTrue, reason: hex);
    });

    test('hash then verify round-trips for the correct PIN', () {
      final stored = Pin.hash('1234');
      expect(Pin.verify('1234', stored), isTrue);
      expect(Pin.verify('4321', stored), isFalse);
      expect(Pin.verify('', stored), isFalse);
    });

    test('two hashes of the same PIN differ (random salt)', () {
      expect(Pin.hash('0000'), isNot(equals(Pin.hash('0000'))));
    });

    test('verify rejects malformed stored strings', () {
      expect(Pin.verify('1234', 'garbage'), isFalse);
      expect(Pin.verify('1234', r'pbkdf2_sha256$0$$'), isFalse);
      expect(Pin.verify('1234', ''), isFalse);
    });
  });

  group('LockPolicy', () {
    test('no cool-down within the free-attempt budget', () {
      for (var i = 0; i <= LockPolicy.freeAttempts; i++) {
        expect(LockPolicy.lockoutFor(i), Duration.zero);
      }
    });

    test('cool-down escalates then caps at one hour', () {
      expect(LockPolicy.lockoutFor(6), const Duration(seconds: 30));
      expect(LockPolicy.lockoutFor(7), const Duration(seconds: 60));
      expect(LockPolicy.lockoutFor(8), const Duration(seconds: 120));
      expect(LockPolicy.lockoutFor(100), LockPolicy.maxLockout);
    });

    test('isLockedOut / remaining track the window', () {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      // 6 failures → 30s cool-down.
      expect(LockPolicy.isLockedOut(6, t0, t0.add(const Duration(seconds: 10))),
          isTrue);
      expect(LockPolicy.remaining(6, t0, t0.add(const Duration(seconds: 10))),
          const Duration(seconds: 20));
      expect(LockPolicy.isLockedOut(6, t0, t0.add(const Duration(seconds: 31))),
          isFalse);
      expect(LockPolicy.isLockedOut(3, t0, t0.add(const Duration(seconds: 1))),
          isFalse);
    });
  });
}
