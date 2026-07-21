import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bluetooth_classic_transport.dart';
import '../printer_transport.dart';
import '../receipt_printer.dart';

/// Platform-appropriate transport.
///
/// Android uses Bluetooth Classic (SPP). iOS cannot — Classic accessories
/// require MFi certification the PM400 does not carry — so it needs a BLE
/// transport, which is not implemented yet.
final printerTransportProvider = Provider<PrinterTransport>((ref) {
  return BluetoothClassicTransport();
});

final receiptPrinterProvider = Provider<ReceiptPrinter>((ref) {
  return ReceiptPrinter(transport: ref.watch(printerTransportProvider));
});

/// The printer the user selected, persisted between launches.
class SavedPrinter {
  const SavedPrinter({
    required this.name,
    required this.address,
    required this.charactersPerLine,
  });

  factory SavedPrinter.fromJson(Map<String, dynamic> json) {
    return SavedPrinter(
      name: json['name'] as String? ?? 'Printer',
      address: json['address'] as String? ?? '',
      charactersPerLine:
          (json['characters_per_line'] as num?)?.toInt() ??
          ReceiptPrinter.pm400CharactersPerLine,
    );
  }

  final String name;
  final String address;

  /// Physical width of this printer in characters. Defaults to the PM400's
  /// 64 at Font A across its 104mm print width.
  final int charactersPerLine;

  Map<String, dynamic> toJson() => {
    'name': name,
    'address': address,
    'characters_per_line': charactersPerLine,
  };

  DiscoveredPrinter toDiscovered(PrinterTransportKind kind) =>
      DiscoveredPrinter(name: name, address: address, transport: kind);
}

/// Connection state for the paired printer.
class PrinterState {
  const PrinterState({
    this.saved,
    this.isConnected = false,
    this.isBusy = false,
    this.error,
  });

  final SavedPrinter? saved;
  final bool isConnected;
  final bool isBusy;
  final PrintException? error;

  bool get hasPrinter => saved != null;

  PrinterState copyWith({
    SavedPrinter? saved,
    bool? isConnected,
    bool? isBusy,
    PrintException? error,
    bool clearError = false,
    bool clearSaved = false,
  }) {
    return PrinterState(
      saved: clearSaved ? null : (saved ?? this.saved),
      isConnected: isConnected ?? this.isConnected,
      isBusy: isBusy ?? this.isBusy,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class PrinterController extends Notifier<PrinterState> {
  static const _prefsKey = 'saved_printer';

  @override
  PrinterState build() {
    Future.microtask(_restore);
    return const PrinterState();
  }

  PrinterTransport get _transport => ref.read(printerTransportProvider);

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;

    try {
      final saved = SavedPrinter.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      state = state.copyWith(
        saved: saved,
        isConnected: await _transport.isConnected,
      );
    } on Object {
      // A corrupt entry should not block printing setup; drop it.
      await prefs.remove(_prefsKey);
    }
  }

  Future<List<DiscoveredPrinter>> discover() async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      return await _transport.discover();
    } on PrintException catch (e) {
      state = state.copyWith(error: e);
      rethrow;
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  Future<void> select(
    DiscoveredPrinter printer, {
    int charactersPerLine = ReceiptPrinter.pm400CharactersPerLine,
  }) async {
    state = state.copyWith(isBusy: true, clearError: true);

    try {
      await _transport.connect(printer);

      final saved = SavedPrinter(
        name: printer.name,
        address: printer.address,
        charactersPerLine: charactersPerLine,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(saved.toJson()));

      state = state.copyWith(saved: saved, isConnected: true, isBusy: false);
    } on PrintException catch (e) {
      state = state.copyWith(isBusy: false, isConnected: false, error: e);
      rethrow;
    }
  }

  /// Reconnects to the saved printer, e.g. before printing after the link
  /// dropped on sleep.
  Future<void> reconnect() async {
    final saved = state.saved;
    if (saved == null) {
      throw const PrintException(
        PrintFailure.notConnected,
        'No printer has been paired yet.',
      );
    }

    if (await _transport.isConnected) {
      state = state.copyWith(isConnected: true);
      return;
    }

    await select(
      saved.toDiscovered(_transport.kind),
      charactersPerLine: saved.charactersPerLine,
    );
  }

  Future<void> disconnect() async {
    await _transport.disconnect();
    state = state.copyWith(isConnected: false);
  }

  Future<void> forget() async {
    await disconnect();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    state = const PrinterState();
  }

  Future<void> refreshConnection() async {
    state = state.copyWith(isConnected: await _transport.isConnected);
  }
}

final printerControllerProvider =
    NotifierProvider<PrinterController, PrinterState>(PrinterController.new);

/// Whether printing is available at all on this platform.
///
/// iOS returns false until a BLE transport exists, so the UI can explain the
/// limitation instead of offering a control that always fails.
final printingSupportedProvider = Provider<bool>((ref) {
  return ref.watch(printerTransportProvider).isSupported;
});

final printingUnsupportedReasonProvider = Provider<String?>((ref) {
  if (ref.watch(printingSupportedProvider)) return null;
  if (kIsWeb) {
    return 'Receipt printing is not available in the browser. Use the '
        'Android app to print to the PM400.';
  }
  return defaultTargetPlatform == TargetPlatform.iOS
      ? 'Bluetooth printing on iOS needs the BLE transport, which is not '
            'implemented yet. The PM400 cannot use Bluetooth Classic on iOS.'
      : 'Bluetooth printing is not available on this platform.';
});
