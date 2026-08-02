import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/branding_providers.dart';
import 'company_details.dart';
import 'developer_credit.dart';

/// Company / contact details from `/v1/settings/general`.
///
/// Reachable from the login footer (signed out — served from cache) and from
/// the profile Company card. The AppBar's automatic leading provides the back
/// arrow.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = ref.watch(brandingProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: CompanyDetails(brand: brand, logoWidth: 200),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          DeveloperCredit(name: brand?.developedBy ?? 'KAF Sols.'),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}
