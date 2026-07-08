import 'package:flutter_test/flutter_test.dart';
import 'package:store_manager/security/lock_service.dart';

import '../app/lock_test_support.dart';

void main() {
  group('recovery code generation', () {
    final svc = LockService(store: FakeSecureStore());

    test('is formatted in three groups and uses an unambiguous alphabet', () {
      final code = svc.generateRecoveryCode();
      expect(code.length, 14); // 12 chars + 2 hyphens
      expect(code[4], '-');
      expect(code[9], '-');
      final bare = code.replaceAll('-', '');
      expect(bare.length, 12);
      // No ambiguous characters (I, L, O, 0, 1).
      expect(RegExp('[ILO01]').hasMatch(bare), isFalse);
    });

    test('normalises case and separators', () {
      expect(LockService.normaliseRecoveryCode('a7km-3qrt-9xyz'),
          'A7KM3QRT9XYZ');
      expect(LockService.normaliseRecoveryCode(' A7 KM3Q '), 'A7KM3Q');
    });

    test('two generated codes differ', () {
      expect(svc.generateRecoveryCode(), isNot(svc.generateRecoveryCode()));
    });
  });

  group('resetPinWithRecovery', () {
    late LockService svc;
    late String code;

    setUp(() async {
      svc = LockService(store: FakeSecureStore());
      await svc.setPin('1111');
      code = svc.generateRecoveryCode();
      await svc.setRecoveryCode(code);
    });

    test('correct code resets the PIN', () async {
      expect(await svc.hasRecoveryCode(), isTrue);
      expect(await svc.resetPinWithRecovery(code, '2222'), PinResult.ok);
      expect(await svc.verifyPin('2222'), PinResult.ok);
      expect(await svc.verifyPin('1111'), PinResult.wrong);
    });

    test('accepts the code typed without hyphens / lowercase', () async {
      final messy = code.replaceAll('-', '').toLowerCase();
      expect(await svc.resetPinWithRecovery(messy, '3333'), PinResult.ok);
      expect(await svc.verifyPin('3333'), PinResult.ok);
    });

    test('wrong code is rejected and the old PIN still works', () async {
      expect(await svc.resetPinWithRecovery('WRNG-CODE-AAAA', '2222'),
          PinResult.wrong);
      expect(await svc.verifyPin('1111'), PinResult.ok);
    });

    test('throttles repeated wrong codes', () async {
      final t0 = DateTime(2026, 1, 1, 12);
      for (var i = 0; i < 6; i++) {
        await svc.resetPinWithRecovery('WRNG-CODE-AAAA', '2222', now: t0);
      }
      // Even the correct code is refused while locked out.
      expect(await svc.resetPinWithRecovery(code, '2222', now: t0),
          PinResult.lockedOut);
    });

    test('disable() forgets the recovery code', () async {
      await svc.disable();
      expect(await svc.hasRecoveryCode(), isFalse);
    });
  });
}
