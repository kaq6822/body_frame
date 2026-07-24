import 'package:body_frame/features/settings/services/pin_hasher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PinHasher', () {
    test('createRecord으로 만든 레코드는 원본 PIN으로 검증에 성공한다', () {
      final record = PinHasher.createRecord('1234');
      expect(PinHasher.verify('1234', record), isTrue);
    });

    test('다른 PIN으로는 검증에 실패한다', () {
      final record = PinHasher.createRecord('1234');
      expect(PinHasher.verify('4321', record), isFalse);
    });

    test('같은 PIN이라도 매번 다른 salt를 사용해 레코드가 달라진다', () {
      final r1 = PinHasher.createRecord('1234');
      final r2 = PinHasher.createRecord('1234');
      expect(r1, isNot(equals(r2)));
      // 그러나 둘 다 원본 PIN으로는 검증에 성공해야 한다.
      expect(PinHasher.verify('1234', r1), isTrue);
      expect(PinHasher.verify('1234', r2), isTrue);
    });

    test('동일 salt/PIN이면 해시가 결정적(deterministic)이다', () {
      const salt = 'fixed-salt';
      final h1 = PinHasher.hash('1234', salt);
      final h2 = PinHasher.hash('1234', salt);
      expect(h1, equals(h2));
    });

    test('형식이 올바르지 않은 레코드는 검증에 실패한다(예외 없이 false)', () {
      expect(PinHasher.verify('1234', 'not-a-valid-record'), isFalse);
      expect(PinHasher.verify('1234', ''), isFalse);
    });

    test('원본 PIN 문자열은 레코드에 그대로 노출되지 않는다', () {
      final record = PinHasher.createRecord('98765');
      expect(record.contains('98765'), isFalse);
    });
  });
}
