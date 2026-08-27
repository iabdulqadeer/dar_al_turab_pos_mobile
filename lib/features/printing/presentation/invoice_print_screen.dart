import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_message.dart';
import '../../../data/models/receipt.dart';
import '../../printing/printer_transport.dart';
import '../../printing/providers/printer_providers.dart';
import '../../sales/providers/sales_providers.dart';
import 'invoice_paper.dart';

/// The Customer / Company copies, matching the web invoice's two-copy output.
const _copyLabels = ['CUSTOMER COPY', 'COMPANY COPY'];

/// Width the [InvoicePaper] is laid out at; the printed dots are this × the
/// capture pixel-ratio.
const _designWidth = 384.0;

/// A WYSIWYG invoice preview that reproduces the web invoice exactly and prints
/// it as an ESC/POS raster image (so the paper looks pixel-for-pixel like
/// `invoice.blade.php`). Each copy has a checkbox; only checked copies print.
class InvoicePrintScreen extends ConsumerStatefulWidget {
  const InvoicePrintScreen({required this.saleId, super.key});

  final int saleId;

  @override
  ConsumerState<InvoicePrintScreen> createState() =>
      _InvoicePrintScreenState();
}

class _InvoicePrintScreenState extends ConsumerState<InvoicePrintScreen> {
  // A single off-screen boundary holds the selected copies stacked; capturing
  // one always-painted boundary avoids the unpainted-layer problem of grabbing
  // list items that may be scrolled out of view.
  final _captureKey = GlobalKey();
  final _selected = {0, 1};

  InvoiceDocument? _document;
  Object? _error;
  bool _loading = true;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doc = await ref.read(salesApiProvider).invoice(widget.saleId);
      if (!mounted) return;
      setState(() {
        _document = doc;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _print() async {
    final controller = ref.read(printerControllerProvider);
    if (!controller.hasPrinter) {
      _toast('No printer paired. Set one up in Printer settings first.',
          isError: true);
      return;
    }
    final selected = _selected.toList()..sort();
    if (selected.isEmpty) {
      _toast('Select at least one copy to print.', isError: true);
      return;
    }

    setState(() => _printing = true);
    try {
      // Let the off-screen capture boundary (rebuilt with only the selected
      // copies) paint before we grab it.
      await WidgetsBinding.instance.endOfFrame;

      // Capture at the printer's dot width. The text path uses ~12 dots per
      // character column, so the raster matches that width.
      final dotWidth = controller.saved!.charactersPerLine * 12;
      final pixelRatio = dotWidth / _designWidth;

      final boundary = _captureKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        _toast('Could not render the invoice. Try again.', isError: true);
        return;
      }
      final image = await boundary.toImage(pixelRatio: pixelRatio);

      await ref.read(printerControllerProvider.notifier).reconnect();
      await ref.read(receiptPrinterProvider).printImages([image]);
      if (!mounted) return;
      _toast('Sent ${selected.length} '
          '${selected.length == 1 ? 'copy' : 'copies'} to '
          '${controller.saved!.name}.');
      Navigator.of(context).pop();
    } on PrintException catch (e) {
      if (mounted) _toast('${e.message} ${e.remedy}', isError: true);
    } on ApiException catch (e) {
      if (mounted) _toast(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  void _toast(String message, {bool isError = false}) {
    showAppMessage(
      context,
      message,
      kind: isError ? AppMessageKind.error : AppMessageKind.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      appBar: AppBar(title: const Text('Invoice')),
      body: _buildBody(),
      bottomNavigationBar: _document == null ? null : _controls(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _ErrorView(
        message: _error is ApiException
            ? (_error as ApiException).message
            : 'Could not load the invoice.',
        onRetry: _fetch,
      );
    }
    final doc = _document!;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Visible preview — both copies, dimmed when unchecked. Scaled to fit
        // the screen; the actual print uses the off-screen full-size capture.
        ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            for (var i = 0; i < _copyLabels.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: Opacity(
                  opacity: _selected.contains(i) ? 1 : 0.4,
                  child: Material(
                    elevation: 2,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topCenter,
                      child: InvoicePaper(
                        document: doc,
                        copyLabel: _copyLabels[i],
                        designWidth: _designWidth,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        // Off-screen capture target: only the checked copies, at true size, in
        // one always-painted boundary.
        Positioned(
          left: -100000,
          top: 0,
          child: RepaintBoundary(
            key: _captureKey,
            child: ColoredBox(
              color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _copyLabels.length; i++)
                    if (_selected.contains(i)) ...[
                      InvoicePaper(
                        document: doc,
                        copyLabel: _copyLabels[i],
                        designWidth: _designWidth,
                      ),
                      // Blank feed between copies so they can be torn apart.
                      const SizedBox(width: _designWidth, height: 40),
                    ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _controls() {
    final theme = Theme.of(context);
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                for (var i = 0; i < _copyLabels.length; i++)
                  Expanded(
                    child: CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        _title(_copyLabels[i]),
                        style: theme.textTheme.bodySmall,
                      ),
                      value: _selected.contains(i),
                      onChanged: (v) => setState(() {
                        v == true ? _selected.add(i) : _selected.remove(i);
                      }),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _printing ? null : _print,
                icon: _printing
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.print_outlined),
                label: Text(_printing ? 'Printing…' : 'Print'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _title(String label) => label
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0] + w.substring(1).toLowerCase())
      .join(' ');
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
