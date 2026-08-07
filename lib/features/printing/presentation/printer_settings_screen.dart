import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_overflow_menu.dart';
import '../../../core/widgets/home_back_button.dart';
import '../../../data/models/receipt.dart';
import '../escpos_encoder.dart';
import '../printer_transport.dart';
import '../providers/printer_providers.dart';
import '../receipt_printer.dart';

class PrinterSettingsScreen extends ConsumerStatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  ConsumerState<PrinterSettingsScreen> createState() =>
      _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState
    extends ConsumerState<PrinterSettingsScreen> {
  List<DiscoveredPrinter> _discovered = const [];
  bool _scanning = false;
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(printerControllerProvider.notifier).refreshConnection();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(printerControllerProvider);
    final unsupportedReason = ref.watch(printingUnsupportedReasonProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const HomeBackButton(),
        title: const Text('Printer'),
        actions: const [AppOverflowMenu()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          if (unsupportedReason != null)
            _Notice(
              icon: Icons.info_outline,
              color: AppColors.warning,
              message: unsupportedReason,
            )
          else ...[
            _ConnectedCard(state: state, onTestPrint: _testPrint),
            const SizedBox(height: AppSpacing.lg),

            Row(
              children: [
                Expanded(
                  child: Text(
                    'Paired devices',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _scanning ? null : _scan,
                  icon: _scanning
                      ? const SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  label: Text(_scanning ? 'Scanning' : 'Refresh'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),

            // SPP has no discovery step: the PM400 is paired once in the
            // system Bluetooth settings and then appears here.
            _Notice(
              icon: Icons.lightbulb_outline,
              color: AppColors.primary,
              message:
                  'Pair the PM400 in your phone\'s Bluetooth settings first, '
                  'then refresh this list.',
            ),

            // Printers are shown by default; other paired devices (earbuds,
            // phones) are hidden unless the user asks for them.
            SwitchListTile(
              value: _showAll,
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.devices_other_outlined),
              title: const Text('Show all paired devices'),
              subtitle: const Text('Include non-printer Bluetooth devices'),
              onChanged: (value) {
                setState(() => _showAll = value);
                _scan();
              },
            ),
            const SizedBox(height: AppSpacing.sm),

            if (_discovered.isEmpty && !_scanning)
              _Notice(
                icon: Icons.bluetooth_disabled,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                message: _showAll
                    ? 'No paired devices found.'
                    : 'No paired printers found. Turn on "Show all paired '
                          'devices" if your printer is missing.',
              )
            else
              for (final printer in _discovered)
                _PrinterTile(
                  printer: printer,
                  isSelected: state.saved?.address == printer.address,
                  onTap: () => _select(printer),
                ),
          ],
        ],
      ),
    );
  }

  Future<bool> _ensurePermissions() async {
    // Android 12+ requires the granular Bluetooth permissions at runtime.
    // Requesting them lazily here (rather than at launch) means the prompt
    // arrives with obvious context.
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    final denied = statuses.values.any((s) => !s.isGranted);
    if (denied && mounted) {
      final permanentlyDenied = statuses.values.any(
        (s) => s.isPermanentlyDenied,
      );
      _showMessage(
        permanentlyDenied
            ? 'Bluetooth permission is blocked. Enable it in Settings to print.'
            : 'Bluetooth permission is needed to find the printer.',
        isError: true,
      );
    }
    return !denied;
  }

  Future<void> _scan() async {
    if (!await _ensurePermissions()) return;

    setState(() => _scanning = true);
    try {
      final printers = await ref
          .read(printerControllerProvider.notifier)
          .discover(includeAll: _showAll);
      if (mounted) setState(() => _discovered = printers);
    } on PrintException catch (e) {
      if (mounted) _showMessage('${e.message} ${e.remedy}', isError: true);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _select(DiscoveredPrinter printer) async {
    if (!await _ensurePermissions()) return;

    try {
      await ref.read(printerControllerProvider.notifier).select(printer);
      if (mounted) _showMessage('Connected to ${printer.name}.');
    } on PrintException catch (e) {
      if (mounted) _showMessage('${e.message} ${e.remedy}', isError: true);
    }
  }

  /// Prints a short fixed receipt so the user can confirm the paper width and
  /// column alignment before relying on it for a real sale.
  Future<void> _testPrint() async {
    final state = ref.read(printerControllerProvider);
    final cpl = state.saved?.charactersPerLine ??
        ReceiptPrinter.pm400CharactersPerLine;

    try {
      await ref.read(printerControllerProvider.notifier).reconnect();

      final transport = ref.read(printerTransportProvider);
      const encoder = EscPosEncoder();

      await transport.write(
        encoder.encode([
          const ReceiptLine(
            text: 'DAR AL TURAB POS',
            align: ReceiptAlign.center,
            bold: true,
          ),
          const ReceiptLine(text: 'Test Print', align: ReceiptAlign.center),
          ReceiptLine(text: '-' * cpl),
          // A full-width ruler makes a width mismatch immediately visible:
          // if this wraps, the printer is narrower than configured.
          ReceiptLine(text: _ruler(cpl)),
          ReceiptLine(text: '-' * cpl),
          ReceiptLine(text: 'Width: $cpl characters'),
          const ReceiptLine(text: 'If the ruler above wraps onto a second'),
          const ReceiptLine(text: 'line, reduce the character width.'),
        ]),
      );

      if (mounted) _showMessage('Test receipt sent.');
    } on PrintException catch (e) {
      if (mounted) _showMessage('${e.message} ${e.remedy}', isError: true);
    }
  }

  /// `1234567890` repeated and trimmed, so each column is countable.
  String _ruler(int width) {
    final buffer = StringBuffer();
    for (var i = 1; i <= width; i++) {
      buffer.write(i % 10);
    }
    return buffer.toString();
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError
              ? Theme.of(context).colorScheme.error
              : null,
        ),
      );
  }
}

class _ConnectedCard extends ConsumerWidget {
  const _ConnectedCard({required this.state, required this.onTestPrint});

  final PrinterState state;
  final VoidCallback onTestPrint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final saved = state.saved;

    if (saved == null) {
      return const _Notice(
        icon: Icons.print_disabled_outlined,
        color: AppColors.warning,
        message: 'No printer paired yet. Choose one below to print receipts.',
      );
    }

    final statusColor = state.isConnected
        ? AppColors.success
        : theme.colorScheme.onSurfaceVariant;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.print_outlined, color: statusColor),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        saved.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${saved.address}  ·  ${saved.charactersPerLine} chars',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    state.isConnected ? 'Connected' : 'Offline',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onTestPrint,
                    icon: const Icon(Icons.receipt_outlined, size: 18),
                    label: const Text('Test print'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  onPressed: () =>
                      ref.read(printerControllerProvider.notifier).forget(),
                  icon: const Icon(Icons.link_off),
                  tooltip: 'Forget printer',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PrinterTile extends StatelessWidget {
  const _PrinterTile({
    required this.printer,
    required this.isSelected,
    required this.onTap,
  });

  final DiscoveredPrinter printer;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Card(
        child: ListTile(
          leading: Icon(
            Icons.bluetooth,
            color: isSelected
                ? AppColors.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          title: Text(printer.name),
          subtitle: Text(printer.address),
          trailing: isSelected
              ? const Icon(Icons.check_circle, color: AppColors.success)
              : const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
