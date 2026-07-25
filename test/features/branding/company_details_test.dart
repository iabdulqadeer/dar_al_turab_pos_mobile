import 'package:dar_al_turab_pos/data/models/brand_settings.dart';
import 'package:dar_al_turab_pos/features/branding/presentation/company_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpDetails(WidgetTester tester, BrandSettings? brand) {
  return tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: CompanyDetails(brand: brand)),
      ),
    ),
  );
}

void main() {
  const brand = BrandSettings(
    systemTitle: 'DAR AL TURAB',
    companyName: 'DAR AL TURAB FOODSTUFF TRADING LLC',
    vatRegistrationNumber: '104158960500003',
    address: 'WAREHOUSE 1, ALMADAM INDUSTRIAL AREA, SHARJAH, UAE',
    phone: '+97168053256',
    developedBy: 'KAF Sols.',
  );

  testWidgets('renders the company, TRN, phone and developed-by', (
    tester,
  ) async {
    await pumpDetails(tester, brand);

    expect(find.text('DAR AL TURAB FOODSTUFF TRADING LLC'), findsOneWidget);
    expect(find.text('104158960500003'), findsOneWidget);
    expect(find.text('+97168053256'), findsOneWidget);
    expect(find.text('KAF Sols.'), findsOneWidget);
  });

  testWidgets('hides rows the endpoint did not return', (tester) async {
    await pumpDetails(
      tester,
      const BrandSettings(systemTitle: 'DAR AL TURAB'),
    );

    // No phone/address/TRN provided, so their labels are absent...
    expect(find.text('Phone'), findsNothing);
    expect(find.text('TRN'), findsNothing);
    // ...but the guaranteed fallbacks still show.
    expect(find.text('DAR AL TURAB'), findsOneWidget);
    expect(find.text('KAF Sols.'), findsOneWidget);
  });

  testWidgets('falls back fully when branding has not loaded yet', (
    tester,
  ) async {
    await pumpDetails(tester, null);

    expect(find.text('Dar Al Turab'), findsOneWidget);
    expect(find.text('KAF Sols.'), findsOneWidget);
  });
}
