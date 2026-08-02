import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/brand_settings.dart';
import 'brand_logo.dart';
import 'developer_credit.dart';

/// The company's branding laid out as a logo plus labelled detail rows.
///
/// Fed by [BrandSettings] from `/v1/settings/general`. Shared by the profile
/// Company card and the About screen so the two never drift. A null [brand]
/// (branding not fetched yet) still renders the bundled logo and the
/// `developed_by` fallback, so it is safe on the signed-out login/About path.
class CompanyDetails extends StatelessWidget {
  const CompanyDetails({required this.brand, this.logoWidth = 160, super.key});

  final BrandSettings? brand;
  final double logoWidth;

  @override
  Widget build(BuildContext context) {
    final onDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: BrandLogo(width: logoWidth, onDark: onDark)),
        const SizedBox(height: AppSpacing.md),
        _Row(
          icon: Icons.business_outlined,
          label: 'Company',
          value: brand?.displayName ?? 'Dar Al Turab',
        ),
        _Row(
          icon: Icons.receipt_long_outlined,
          label: 'TRN',
          value: brand?.vatRegistrationNumber,
        ),
        _Row(
          icon: Icons.location_on_outlined,
          label: 'Address',
          value: brand?.address,
        ),
        _Row(
          icon: Icons.phone_outlined,
          label: 'Phone',
          value: brand?.phone,
        ),
        _Row(
          icon: Icons.code_outlined,
          label: 'Developed by',
          // Always shown — the one field the app guarantees a value for. The
          // name links to the developer's website.
          value: brand?.developedBy ?? 'KAF Sols.',
          link: true,
        ),
      ],
    );
  }
}

/// A labelled detail row. Hidden entirely when [value] is null/blank, so
/// fields the endpoint did not return simply do not appear.
class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    this.link = false,
  });

  final IconData icon;
  final String label;
  final String? value;

  /// When true, the value is rendered as a tappable link to the developer's
  /// website (used by the "Developed by" row).
  final bool link;

  @override
  Widget build(BuildContext context) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    final valueWidget = link
        ? InkWell(
            onTap: () => openDeveloperWebsite(context),
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
              ),
            ),
          )
        : Text(text, style: theme.textTheme.bodyMedium);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: muted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(color: muted),
                ),
                valueWidget,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
