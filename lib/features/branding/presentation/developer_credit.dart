import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_message.dart';

/// The developer's website, opened from the "Developed by" credit.
final Uri _developerSite = Uri.parse('http://kafsols.com');

/// Opens the developer's website in the browser, with a friendly message if no
/// browser can handle it.
Future<void> openDeveloperWebsite(BuildContext context) async {
  try {
    final ok = await launchUrl(
      _developerSite,
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      showAppMessage(
        context,
        'Could not open ${_developerSite.host}.',
        kind: AppMessageKind.error,
      );
    }
  } on Object {
    if (context.mounted) {
      showAppMessage(
        context,
        'Could not open ${_developerSite.host}.',
        kind: AppMessageKind.error,
      );
    }
  }
}

/// "Developed by `name`" where the name is a tappable link to the developer's
/// website. Shared by the login footer and the About screen.
class DeveloperCredit extends StatelessWidget {
  const DeveloperCredit({required this.name, this.centered = true, super.key});

  final String name;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    final row = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Developed by ', style: base),
        InkWell(
          onTap: () => openDeveloperWebsite(context),
          child: Text(
            name,
            style: base?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );

    return centered ? Center(child: row) : row;
  }
}
