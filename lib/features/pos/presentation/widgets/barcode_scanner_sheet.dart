import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/theme/app_colors.dart';

/// Camera barcode scanner.
///
/// Returns the scanned value to the caller, which feeds it into the existing
/// product search — there is no dedicated barcode endpoint, but
/// `/sales/product-search` already matches code and barcode alongside name.
class BarcodeScannerSheet extends StatefulWidget {
  const BarcodeScannerSheet({super.key});

  @override
  State<BarcodeScannerSheet> createState() => _BarcodeScannerSheetState();
}

class _BarcodeScannerSheetState extends State<BarcodeScannerSheet> {
  final _controller = MobileScannerController(
    // A till scans one item at a time; noScan avoids re-firing on the same
    // barcode while it stays in frame.
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  bool _permissionChecked = false;
  bool _permissionGranted = false;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _requestPermission();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Asked at the point of use rather than at launch, so the prompt arrives
  /// with obvious context — same approach as the printer's Bluetooth request.
  Future<void> _requestPermission() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    setState(() {
      _permissionChecked = true;
      _permissionGranted = status.isGranted;
    });
  }

  void _onDetect(BarcodeCapture capture) {
    // The camera fires continuously; take the first good read and close.
    if (_handled) return;

    final code = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.trim().isNotEmpty, orElse: () => null);

    if (code == null) return;

    _handled = true;
    HapticFeedback.mediumImpact();
    Navigator.pop(context, code.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Scan barcode',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (_permissionGranted)
                  IconButton(
                    icon: const Icon(Icons.flash_on_outlined),
                    tooltip: 'Toggle torch',
                    onPressed: () => _controller.toggleTorch(),
                  ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(child: _body(theme)),
        ],
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (!_permissionChecked) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_permissionGranted) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                size: 48,
                color: AppColors.warning,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Camera access is needed to scan',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Allow camera access, or type the code into the search box '
                'instead.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: openAppSettings,
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('Open settings'),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        // Simple reticle so the user knows where to aim.
        IgnorePointer(
          child: Container(
            width: 240,
            height: 140,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
        ),
        Positioned(
          bottom: AppSpacing.lg,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: const Text(
              'Point at a barcode',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
