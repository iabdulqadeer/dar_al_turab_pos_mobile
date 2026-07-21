import 'package:dar_al_turab_pos/core/widgets/app_form.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Validate.name', () {
    test('requires a value', () {
      expect(Validate.name(null), isNotNull);
      expect(Validate.name(''), isNotNull);
      expect(Validate.name('   '), isNotNull);
    });

    test('accepts a normal name', () {
      expect(Validate.name('Ahmed Al Mansouri'), isNull);
    });

    test('enforces the server\'s 255 character limit', () {
      expect(Validate.name('a' * 255), isNull);
      expect(Validate.name('a' * 256), isNotNull);
    });
  });

  group('Validate.optionalEmail', () {
    test('treats blank as valid, since the column is nullable', () {
      expect(Validate.optionalEmail(null), isNull);
      expect(Validate.optionalEmail(''), isNull);
      expect(Validate.optionalEmail('   '), isNull);
    });

    test('accepts ordinary addresses', () {
      expect(Validate.optionalEmail('user@example.com'), isNull);
      expect(Validate.optionalEmail('first.last@sub.example.co.uk'), isNull);
      expect(Validate.optionalEmail('user+tag@example.com'), isNull);
    });

    test('rejects clearly malformed addresses', () {
      expect(Validate.optionalEmail('not-an-email'), isNotNull);
      expect(Validate.optionalEmail('missing@domain'), isNotNull);
      expect(Validate.optionalEmail('@example.com'), isNotNull);
      expect(Validate.optionalEmail('spaces in@example.com'), isNotNull);
    });
  });

  group('Validate.optionalPhone', () {
    test('treats blank as valid', () {
      expect(Validate.optionalPhone(''), isNull);
    });

    test('accepts varied international formats', () {
      // No format is enforced deliberately: the server only caps length, and
      // Gulf numbers arrive in several shapes.
      expect(Validate.optionalPhone('+971 50 123 4567'), isNull);
      expect(Validate.optionalPhone('0501234567'), isNull);
      expect(Validate.optionalPhone('(050) 123-4567'), isNull);
    });

    test('enforces the server\'s 50 character limit', () {
      expect(Validate.optionalPhone('1' * 50), isNull);
      expect(Validate.optionalPhone('1' * 51), isNotNull);
    });
  });

  group('Validate.newPassword', () {
    test('requires at least 8 characters, matching the server rule', () {
      expect(Validate.newPassword(''), isNotNull);
      expect(Validate.newPassword('short'), isNotNull);
      expect(Validate.newPassword('1234567'), isNotNull);
      expect(Validate.newPassword('12345678'), isNull);
    });
  });

  group('Validate.notEmpty', () {
    test('names the field in its message', () {
      expect(Validate.notEmpty('', 'Current password'), contains('Current password'));
      expect(Validate.notEmpty('x', 'Current password'), isNull);
    });
  });

  group('Validate.maxLength', () {
    test('allows blank and enforces the cap', () {
      expect(Validate.maxLength('', 10, 'Company'), isNull);
      expect(Validate.maxLength('a' * 10, 10, 'Company'), isNull);
      expect(Validate.maxLength('a' * 11, 10, 'Company'), isNotNull);
    });
  });
}
