import 'package:dar_al_turab_pos/core/widgets/app_form.dart';
import 'package:flutter_test/flutter_test.dart';

// The reset/forgot screens reuse the shared Validate rules; these lock in the
// client-side guards so a user is not bounced by a 422 for something catchable
// locally (matching the server: required email, min-8 password).
void main() {
  group('Validate.email path used by the forgot/reset screens', () {
    String? emailField(String? value) =>
        Validate.notEmpty(value, 'Email') ?? Validate.optionalEmail(value);

    test('rejects a blank email', () {
      expect(emailField(''), isNotNull);
      expect(emailField('   '), isNotNull);
    });

    test('rejects a malformed email', () {
      expect(emailField('not-an-email'), isNotNull);
    });

    test('accepts a well-formed email', () {
      expect(emailField('cashier@example.com'), isNull);
    });
  });

  group('Validate.newPassword used by the reset screen', () {
    test('requires at least 8 characters', () {
      expect(Validate.newPassword(''), isNotNull);
      expect(Validate.newPassword('short'), isNotNull);
    });

    test('accepts an 8+ character password', () {
      expect(Validate.newPassword('longenough'), isNull);
    });
  });
}
