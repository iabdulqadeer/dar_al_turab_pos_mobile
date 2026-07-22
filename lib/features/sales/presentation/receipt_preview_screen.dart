import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/receipt.dart';
import '../../printing/escpos_encoder.dart';
import '../../printing/printer_transport.dart';
import '../../printing/providers/printer_providers.dart';
import '../providers/sales_providers.dart';

/// WYSIWYG print preview: renders each receipt copy exactly as it will print
/// (centred block, same [EscPosEncoder.layoutLine] the printer uses), and lets
/// the cashier choose which copies and how many to print, and nudge the
/// side-margin until it sits centred on the paper.
class ReceiptPreviewScreen extends ConsumerStatefulWidget {
  const ReceiptPreviewScreen({required this.saleId, super.key});

  final int saleId;

  @override
  ConsumerState<ReceiptPreviewScreen> createState() =>
      _ReceiptPreviewScreenState();
}

class _ReceiptPreviewScreenState extends ConsumerState<ReceiptPreviewScreen> {
  InvoiceDocument? _document;
  Object? _error;
  bool _loading = true;
  bool _printing = false;

  int _copies = 1;
  final Set<int> _selected = {};

  /// The content width the current document was fetched at. The server lays
  /// columns out to this, so a margin change (which changes it) requires a
  /// re-fetch to keep columns aligned.
  int _fetchedWidth = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  Future<void> _fetch() async {
    final saved = ref.read(printerControllerProvider).saved;
    final width = saved?.contentWidth ?? 64;

    setState(() {
      _loading = true;
      _error = null;
      _fetchedWidth = width;
    });

    try {
      final document = await ref
          .read(salesApiProvider)
          .receipt(widget.saleId, charactersPerLine: width);
      if (!mounted) return;
      setState(() {
        _document = document;
        // Select every page the first time; keep the user's choice after that.
        if (_selected.isEmpty) {
          _selected.addAll(
            List.generate(document.pages.length, (i) => i),
          );
        }
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

  Future<void> _changeMargin(int delta) async {
    final saved = ref.read(printerControllerProvider).saved;
    if (saved == null) return;
    await ref
        .read(printerControllerProvider.notifier)
        .setLeftMargin(saved.leftMargin + delta);
    // contentWidth moved, so the server layout must be refreshed.
    final newWidth = ref.read(printerControllerProvider).saved?.contentWidth;
    if (newWidth != _fetchedWidth) await _fetch();
  }

  Future<void> _print() async {
    final saved = ref.read(printerControllerProvider).saved;
    final document = _document;
    if (saved == null || document == null) return;

    if (!ref.read(printerControllerProvider).hasPrinter) {
      _toast('No printer paired. Set one up in Printer settings first.',
          isError: true);
      return;
    }

    final pages = [
      for (var i = 0; i < document.pages.length; i++)
        if (_selected.contains(i)) document.pages[i],
    ];
    if (pages.isEmpty) {
      _toast('Select at least one copy to print.', isError: true);
      return;
    }

    setState(() => _printing = true);
    try {
      await ref.read(printerControllerProvider.notifier).reconnect();
      await ref.read(receiptPrinterProvider).printPages(
            pages,
            copies: _copies,
            contentWidth: saved.contentWidth,
            leftMargin: saved.leftMargin,
            qrCode: document.qrCode,
          );
      if (!mounted) return;
      _toast('Sent ${pages.length * _copies} '
          '${pages.length * _copies == 1 ? 'copy' : 'copies'} to ${saved.name}.');
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? AppColors.error : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(printerControllerProvider).saved;

    return Scaffold(
      appBar: AppBar(title: const Text('Print preview')),
      body: _buildBody(saved),
      bottomNavigationBar: _document == null
          ? null
          : _Controls(
              pages: _document!.pages,
              selected: _selected,
              copies: _copies,
              leftMargin: saved?.leftMargin ?? 0,
              printing: _printing,
              onTogglePage: (i) => setState(() {
                _selected.contains(i)
                    ? _selected.remove(i)
                    : _selected.add(i);
              }),
              onCopies: (v) => setState(() => _copies = v),
              onMargin: _changeMargin,
              onPrint: _printing ? null : _print,
            ),
    );
  }

  Widget _buildBody(SavedPrinter? saved) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _PreviewError(
        message: _error is ApiException
            ? (_error as ApiException).message
            : 'Could not load the receipt.',
        onRetry: _fetch,
      );
    }
    final document = _document;
    if (document == null || document.pages.isEmpty) {
      return const Center(child: Text('This receipt has no printable pages.'));
    }

    final contentWidth = saved?.contentWidth ?? 64;
    final leftMargin = saved?.leftMargin ?? 0;
    final capacity = saved?.charactersPerLine ?? (contentWidth + 2 * leftMargin);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        for (var i = 0; i < document.pages.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Opacity(
              opacity: _selected.contains(i) ? 1 : 0.4,
              child: _PaperPreview(
                page: document.pages[i],
                contentWidth: contentWidth,
                leftMargin: leftMargin,
                capacity: capacity,
              ),
            ),
          ),
      ],
    );
  }
}

/// A single copy rendered on paper-coloured card, monospaced, at the true
/// centred layout. The whole page scales down to the card width so the
/// character grid — and therefore the column alignment — is preserved.
class _PaperPreview extends StatelessWidget {
  const _PaperPreview({
    required this.page,
    required this.contentWidth,
    required this.leftMargin,
    required this.capacity,
  });

  final ReceiptPage page;
  final int contentWidth;
  final int leftMargin;
  final int capacity;

  @override
  Widget build(BuildContext context) {
    // Right-pad to the paper capacity so the right-hand margin is visible too,
    // not just the left — the point of the centring.
    String render(ReceiptLine line) {
      final laid = EscPosEncoder.layoutLine(
        line.text,
        line.align,
        contentWidth,
        leftMargin,
      );
      return laid.length >= capacity
          ? laid
          : laid.padRight(capacity);
    }

    const mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      height: 1.25,
      color: Color(0xFF111111),
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.md,
        horizontal: AppSpacing.sm,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final line in page.lines)
              Text(
                render(line).isEmpty ? ' ' : render(line),
                maxLines: 1,
                softWrap: false,
                style: line.bold
                    ? mono.copyWith(fontWeight: FontWeight.w700)
                    : mono,
              ),
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.pages,
    required this.selected,
    required this.copies,
    required this.leftMargin,
    required this.printing,
    required this.onTogglePage,
    required this.onCopies,
    required this.onMargin,
    required this.onPrint,
  });

  final List<ReceiptPage> pages;
  final Set<int> selected;
  final int copies;
  final int leftMargin;
  final bool printing;
  final ValueChanged<int> onTogglePage;
  final ValueChanged<int> onCopies;
  final ValueChanged<int> onMargin;
  final VoidCallback? onPrint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.dividerColor),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (var i = 0; i < pages.length; i++)
                  FilterChip(
                    label: Text(
                      pages[i].label.isEmpty ? 'Receipt' : _title(pages[i].label),
                    ),
                    selected: selected.contains(i),
                    onSelected: (_) => onTogglePage(i),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                _Stepper(
                  label: 'Copies',
                  value: copies,
                  min: 1,
                  max: 9,
                  onChanged: onCopies,
                ),
                const SizedBox(width: AppSpacing.lg),
                _Stepper(
                  label: 'Margin',
                  value: leftMargin,
                  min: 0,
                  max: 12,
                  onChanged: (v) => onMargin(v - leftMargin),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onPrint,
                icon: printing
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.print_outlined),
                label: Text(printing ? 'Printing…' : 'Print'),
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

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        const SizedBox(width: AppSpacing.xs),
        IconButton(
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
          visualDensity: VisualDensity.compact,
        ),
        SizedBox(
          width: 20,
          child: Text('$value', textAlign: TextAlign.center),
        ),
        IconButton(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class _PreviewError extends StatelessWidget {
  const _PreviewError({required this.message, required this.onRetry});

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
