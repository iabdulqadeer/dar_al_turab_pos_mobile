import 'sale.dart';

/// Horizontal alignment for a receipt line, mapped to `ESC a n`.
enum ReceiptAlign {
  left,
  center,
  right;

  static ReceiptAlign fromName(String? value) => switch (value) {
    'center' => ReceiptAlign.center,
    'right' => ReceiptAlign.right,
    _ => ReceiptAlign.left,
  };
}

/// Character size for a receipt line, mapped to `GS ! n`.
enum ReceiptSize {
  normal,
  large;

  static ReceiptSize fromName(String? value) =>
      value == 'large' ? ReceiptSize.large : ReceiptSize.normal;
}

/// One pre-laid-out line from `GET /v1/sales/{id}/receipt`.
///
/// The server (`SaleReceiptFormatter`) has already done column padding and
/// wrapping to the requested characters-per-line, so the client must only
/// style and encode these — never re-layout, or columns will drift out of
/// agreement with the web receipt.
class ReceiptLine {
  const ReceiptLine({
    required this.text,
    this.align = ReceiptAlign.left,
    this.bold = false,
    this.size = ReceiptSize.normal,
  });

  factory ReceiptLine.fromJson(Map<String, dynamic> json) {
    return ReceiptLine(
      text: json['text']?.toString() ?? '',
      align: ReceiptAlign.fromName(json['align']?.toString()),
      bold: json['bold'] == true,
      size: ReceiptSize.fromName(json['size']?.toString()),
    );
  }

  final String text;
  final ReceiptAlign align;
  final bool bold;
  final ReceiptSize size;
}

/// Printer configuration the server holds for this warehouse
/// (`printer_settings`), returned as `default_printer` on the invoice.
class PrinterConfig {
  const PrinterConfig({
    this.id,
    this.printerName,
    this.connectionType,
    this.paperWidth,
    this.charactersPerLine,
  });

  static PrinterConfig? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return PrinterConfig(
      id: (json['id'] as num?)?.toInt(),
      printerName: json['printer_name']?.toString(),
      connectionType: json['connection_type']?.toString(),
      paperWidth: json['paper_width']?.toString(),
      charactersPerLine: (json['characters_per_line'] as num?)?.toInt(),
    );
  }

  final int? id;
  final String? printerName;
  final String? connectionType;

  /// e.g. "110 mm". The web template supports 80/100/110mm.
  final String? paperWidth;
  final int? charactersPerLine;
}

/// Seller identity printed at the top of the invoice.
class CompanyInfo {
  const CompanyInfo({
    this.name,
    this.vatRegistrationNumber,
    this.address,
    this.phone,
  });

  static CompanyInfo fromJson(Map<String, dynamic>? json) {
    return CompanyInfo(
      name: json?['name']?.toString(),
      vatRegistrationNumber: json?['vat_registration_number']?.toString(),
      address: json?['address']?.toString(),
      phone: json?['phone']?.toString(),
    );
  }

  final String? name;
  final String? vatRegistrationNumber;
  final String? address;
  final String? phone;
}

/// `GET /v1/sales/{id}/invoice` — the sale plus everything needed to render a
/// tax invoice. `GET .../receipt` returns this same shape plus [lines].
class InvoiceDocument {
  const InvoiceDocument({
    required this.sale,
    required this.company,
    required this.lines,
    this.currencyCode = 'AED',
    this.amountInWords,
    this.qrCode,
    this.invoiceLayout,
    this.defaultPrinter,
  });

  factory InvoiceDocument.fromJson(Map<String, dynamic> json) {
    return InvoiceDocument(
      sale: SaleDetail.fromJson(json),
      company: CompanyInfo.fromJson(
        json['company'] is Map
            ? Map<String, dynamic>.from(json['company'] as Map)
            : null,
      ),
      currencyCode: json['currency_code']?.toString() ?? 'AED',
      amountInWords: json['amount_in_words']?.toString(),
      qrCode: json['qr_code']?.toString(),
      invoiceLayout: json['invoice_layout']?.toString(),
      defaultPrinter: PrinterConfig.fromJson(
        json['default_printer'] is Map
            ? Map<String, dynamic>.from(json['default_printer'] as Map)
            : null,
      ),
      lines: (json['lines'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => ReceiptLine.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
    );
  }

  final SaleDetail sale;
  final CompanyInfo company;
  final String currencyCode;
  final String? amountInWords;

  /// Base64 ZATCA TLV payload, present only when the server has ZATCA
  /// enabled. The web template generates this but hides it with
  /// `display:none`; on mobile it should be printed.
  final String? qrCode;

  final String? invoiceLayout;
  final PrinterConfig? defaultPrinter;

  /// Populated only by the `/receipt` endpoint, empty for `/invoice`.
  final List<ReceiptLine> lines;

  bool get hasPrintableLines => lines.isNotEmpty;
  bool get hasQrCode => qrCode != null && qrCode!.isNotEmpty;
}
