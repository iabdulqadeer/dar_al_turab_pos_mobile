import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The tone of an [showAppMessage] toast, which picks its colour and icon.
enum AppMessageKind { info, success, warning, error }

/// Shows a short message that floats above everything — including modal bottom
/// sheets and dialogs.
///
/// Ordinary `ScaffoldMessenger` snackbars render inside the page's `Scaffold`,
/// which sits *below* an open modal route, so a message shown while a bottom
/// sheet is open is hidden behind it. This instead inserts into the **root**
/// overlay, so the message is always visible.
///
/// Call it while [context] is still mounted — i.e. **before** any
/// `Navigator.pop`. Because the toast lives in the root overlay it stays visible
/// over the sheet and persists through the subsequent pop/navigation.
void showAppMessage(
  BuildContext context,
  String message, {
  AppMessageKind kind = AppMessageKind.info,
  Duration? duration,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  showAppMessageOn(overlay, message, kind: kind, duration: duration);
}

/// Same as [showAppMessage] but takes an already-resolved [OverlayState].
///
/// Use this when the message is shown after an `await`: capture the overlay
/// *before* the async gap (e.g. `Overlay.of(context, rootOverlay: true)`), so no
/// `BuildContext` is used across it. This is what stateless widgets without a
/// `mounted` guard should do.
void showAppMessageOn(
  OverlayState overlay,
  String message, {
  AppMessageKind kind = AppMessageKind.info,
  Duration? duration,
}) {
  // Only one message at a time — a new one replaces the old, mirroring the
  // hideCurrentSnackBar() the call sites used to do.
  _AppMessageController.instance.show(
    overlay: overlay,
    message: message,
    kind: kind,
    duration: duration ??
        (kind == AppMessageKind.error || kind == AppMessageKind.warning
            ? const Duration(seconds: 6)
            : const Duration(seconds: 4)),
  );
}

/// Owns the single active toast and its dismiss timer.
class _AppMessageController {
  _AppMessageController._();
  static final instance = _AppMessageController._();

  OverlayEntry? _entry;
  Timer? _timer;
  final _dismiss = ValueNotifier<bool>(false);

  void show({
    required OverlayState overlay,
    required String message,
    required AppMessageKind kind,
    required Duration duration,
  }) {
    _removeNow();

    _dismiss.value = false;
    final entry = OverlayEntry(
      builder: (context) => _AppMessageToast(
        message: message,
        kind: kind,
        dismiss: _dismiss,
        onDismissed: _removeNow,
      ),
    );
    _entry = entry;
    overlay.insert(entry);

    _timer = Timer(duration, _startDismiss);
  }

  /// Triggers the exit animation; the widget calls [_removeNow] when it ends.
  void _startDismiss() {
    if (_entry != null) _dismiss.value = true;
  }

  void _removeNow() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}

class _AppMessageToast extends StatefulWidget {
  const _AppMessageToast({
    required this.message,
    required this.kind,
    required this.dismiss,
    required this.onDismissed,
  });

  final String message;
  final AppMessageKind kind;

  /// Flips to true when the toast should animate out.
  final ValueNotifier<bool> dismiss;
  final VoidCallback onDismissed;

  @override
  State<_AppMessageToast> createState() => _AppMessageToastState();
}

class _AppMessageToastState extends State<_AppMessageToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
    widget.dismiss.addListener(_onDismissRequested);
  }

  void _onDismissRequested() {
    if (widget.dismiss.value) _reverseOut();
  }

  Future<void> _reverseOut() async {
    if (!mounted) return;
    await _controller.reverse();
    widget.onDismissed();
  }

  @override
  void dispose() {
    widget.dismiss.removeListener(_onDismissRequested);
    _controller.dispose();
    super.dispose();
  }

  ({Color bg, Color fg, IconData icon}) _style(BuildContext context) {
    switch (widget.kind) {
      case AppMessageKind.success:
        return (bg: AppColors.success, fg: Colors.white, icon: Icons.check_circle_outline);
      case AppMessageKind.warning:
        return (bg: AppColors.warning, fg: Colors.white, icon: Icons.warning_amber_outlined);
      case AppMessageKind.error:
        return (bg: AppColors.error, fg: Colors.white, icon: Icons.error_outline);
      case AppMessageKind.info:
        final scheme = Theme.of(context).colorScheme;
        return (bg: scheme.inverseSurface, fg: scheme.onInverseSurface, icon: Icons.info_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final style = _style(context);

    return Positioned(
      left: AppSpacing.md,
      right: AppSpacing.md,
      // Sit above the keyboard when it's open, otherwise above the safe area.
      bottom: AppSpacing.md +
          (media.viewInsets.bottom > 0
              ? media.viewInsets.bottom
              : media.padding.bottom),
      child: FadeTransition(
        opacity: _curve,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.25),
            end: Offset.zero,
          ).animate(_curve),
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _reverseOut,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm + 2,
                ),
                decoration: BoxDecoration(
                  color: style.bg,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(style.icon, size: 20, color: style.fg),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: TextStyle(
                          color: style.fg,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}