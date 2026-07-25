import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_overflow_menu.dart';
import '../../../data/models/auth_user.dart';
import '../../auth/providers/auth_providers.dart';
import '../../branding/presentation/brand_logo.dart';
import '../../branding/providers/branding_providers.dart';
import '../../printing/providers/printer_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final printer = ref.watch(printerControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: const [AppOverflowMenu()],
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(authControllerProvider.notifier).refreshUser(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            _IdentityCard(user: user),
            const SizedBox(height: AppSpacing.lg),

            _SectionLabel('Account'),
            _MenuCard(
              children: [
                _MenuTile(
                  icon: Icons.person_outline,
                  title: 'Edit profile',
                  subtitle: 'Name, email, phone, company',
                  onTap: () => context.push(Routes.editProfile),
                ),
                _MenuTile(
                  icon: Icons.lock_outline,
                  title: 'Change password',
                  subtitle: 'Signs out your other devices',
                  onTap: () => context.push(Routes.changePassword),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            _SectionLabel('Hardware'),
            _MenuCard(
              children: [
                _MenuTile(
                  icon: Icons.print_outlined,
                  title: 'Receipt printer',
                  subtitle: printer.hasPrinter
                      ? '${printer.saved!.name}'
                            '${printer.isConnected ? ' · Connected' : ' · Offline'}'
                      : 'No printer paired',
                  trailing: printer.hasPrinter && printer.isConnected
                      ? const Icon(
                          Icons.check_circle,
                          size: 18,
                          color: AppColors.success,
                        )
                      : null,
                  onTap: () => context.push(Routes.printer),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            _SectionLabel('Access'),
            _PermissionsCard(user: user),
            const SizedBox(height: AppSpacing.lg),

            _SectionLabel('Company'),
            const _CompanyCard(),
            const SizedBox(height: AppSpacing.lg),

            OutlinedButton.icon(
              onPressed: () => _confirmSignOut(context, ref),
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Sign out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'This revokes the token for this device only. Your other devices '
          'stay signed in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await ref.read(authControllerProvider.notifier).signOut();
    }
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.user});

  final AuthUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              child: Text(
                user.initials,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              user.name,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if (user.roleName != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  user.roleName!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const Divider(height: AppSpacing.xl),
            _InfoRow(icon: Icons.email_outlined, value: user.email),
            _InfoRow(icon: Icons.phone_outlined, value: user.phone),
            _InfoRow(icon: Icons.business_outlined, value: user.companyName),
            _InfoRow(
              icon: Icons.warehouse_outlined,
              value: user.warehouseName,
              fallback: user.hasWarehouse
                  ? null
                  : 'No warehouse assigned — you will not see any sales',
              isWarning: !user.hasWarehouse,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.value,
    this.label,
    this.fallback,
    this.isWarning = false,
  });

  final IconData icon;
  final String? value;

  /// Optional caption above the value, for rows whose meaning is not obvious
  /// from the icon alone (Company, TRN, Address …).
  final String? label;
  final String? fallback;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = value ?? fallback;
    if (text == null || text.isEmpty) return const SizedBox.shrink();

    final color = isWarning
        ? AppColors.error
        : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label != null)
                  Text(
                    label!,
                    style: theme.textTheme.labelSmall?.copyWith(color: color),
                  ),
                Text(
                  text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isWarning ? AppColors.error : null,
                    fontWeight: isWarning ? FontWeight.w600 : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows what this user is actually allowed to do. Useful in the field: when
/// a button is missing, this explains why without a call to the office.
/// Company branding, live from the web admin (`/v1/settings/general`) and
/// cached on the device. Changing it on the website changes it here — no app
/// release needed. Shows nothing until branding has been fetched at least once.
class _CompanyCard extends ConsumerWidget {
  const _CompanyCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = ref.watch(brandingProvider);

    if (brand == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: _InfoRow(
            icon: Icons.info_outline,
            label: 'Company details',
            value: 'Not loaded yet',
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: BrandLogo(
                width: 160,
                onDark: Theme.of(context).brightness == Brightness.dark,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _InfoRow(
              icon: Icons.business_outlined,
              label: 'Company',
              value: brand.displayName,
            ),
            if (brand.vatRegistrationNumber != null)
              _InfoRow(
                icon: Icons.receipt_long_outlined,
                label: 'TRN',
                value: brand.vatRegistrationNumber!,
              ),
            if (brand.address != null)
              _InfoRow(
                icon: Icons.location_on_outlined,
                label: 'Address',
                value: brand.address!,
              ),
            if (brand.phone != null)
              _InfoRow(
                icon: Icons.phone_outlined,
                label: 'Phone',
                value: brand.phone!,
              ),
            if (brand.developedBy != null)
              _InfoRow(
                icon: Icons.code_outlined,
                label: 'Developed by',
                value: brand.developedBy!,
              ),
          ],
        ),
      ),
    );
  }
}

class _PermissionsCard extends StatelessWidget {
  const _PermissionsCard({required this.user});

  final AuthUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    const labels = {
      Permissions.salesIndex: 'View sales',
      Permissions.salesAdd: 'Create sales',
      Permissions.salesEdit: 'Edit sales',
      Permissions.salesDelete: 'Delete sales',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (user.isAdmin)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  'Administrator — full access to every warehouse.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  'You can only see sales you created in your own warehouse.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final entry in labels.entries)
                  _PermissionChip(
                    label: entry.value,
                    granted: user.can(entry.key),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionChip extends StatelessWidget {
  const _PermissionChip({required this.label, required this.granted});

  final String label;
  final bool granted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = granted
        ? AppColors.success
        : theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            granted ? Icons.check_circle_outline : Icons.remove_circle_outline,
            size: 14,
            color: color,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xs,
        bottom: AppSpacing.sm,
      ),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              const Divider(height: 1, indent: AppSpacing.xxl),
          ],
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      onTap: onTap,
      leading: Icon(icon, size: 22, color: AppColors.primary),
      title: Text(
        title,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: trailing ?? const Icon(Icons.chevron_right, size: 20),
    );
  }
}
