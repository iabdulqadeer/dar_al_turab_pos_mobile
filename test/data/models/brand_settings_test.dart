import 'package:dar_al_turab_pos/data/models/brand_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The live shape from docs/api/general-settings.md.
  Map<String, dynamic> json() => {
    'system_title': 'DAR AL TURAB',
    'company_name': 'DAR AL TURAB FOODSTUFF TRADING LLC',
    'vat_registration_number': '104158960500003',
    'address': 'WAREHOUSE 1, ALMADAM INDUSTRIAL AREA, SHARJAH, UAE',
    'phone': '+97168053256',
    'developed_by': 'KAF Sols.',
    'system_logo': 'https://example.com/public/logo/20260518065424.jpeg',
  };

  test('parses the documented response', () {
    final brand = BrandSettings.fromJson(json());

    expect(brand.systemTitle, 'DAR AL TURAB');
    expect(brand.companyName, 'DAR AL TURAB FOODSTUFF TRADING LLC');
    expect(brand.vatRegistrationNumber, '104158960500003');
    expect(brand.phone, '+97168053256');
    expect(brand.hasLogo, isTrue);
  });

  test('prefers the legal company name for display', () {
    expect(
      BrandSettings.fromJson(json()).displayName,
      'DAR AL TURAB FOODSTUFF TRADING LLC',
    );
  });

  test('falls back to the system title when no company name is set', () {
    final brand = BrandSettings.fromJson(json()..['company_name'] = null);

    expect(brand.displayName, 'DAR AL TURAB');
  });

  test('treats a null logo as "no logo", not an error', () {
    // The server returns null when nothing has been uploaded; the UI must fall
    // back to the bundled asset rather than showing a broken image.
    final brand = BrandSettings.fromJson(json()..['system_logo'] = null);

    expect(brand.hasLogo, isFalse);
    expect(brand.systemLogo, isNull);
  });

  test('normalises blank strings to null so the UI can fall back', () {
    final brand = BrandSettings.fromJson(
      json()
        ..['phone'] = '   '
        ..['address'] = '',
    );

    expect(brand.phone, isNull);
    expect(brand.address, isNull);
  });

  test('survives a round trip through the cache', () {
    final original = BrandSettings.fromJson(json());
    final restored = BrandSettings.fromJson(original.toJson());

    expect(restored.displayName, original.displayName);
    expect(restored.systemLogo, original.systemLogo);
    expect(restored.vatRegistrationNumber, original.vatRegistrationNumber);
  });
}
