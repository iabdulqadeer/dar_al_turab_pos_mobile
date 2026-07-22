/// Company branding from `GET /v1/settings/general`.
///
/// Managed entirely in the web admin (Settings → General Settings); the app
/// only ever displays it. Changing branding on the website therefore changes it
/// here too, with no app release.
///
/// Every field except [systemTitle] is nullable server-side, so treat a missing
/// value as "fall back to the bundled default", never as an error.
class BrandSettings {
  const BrandSettings({
    required this.systemTitle,
    this.companyName,
    this.vatRegistrationNumber,
    this.address,
    this.phone,
    this.developedBy,
    this.systemLogo,
  });

  factory BrandSettings.fromJson(Map<String, dynamic> json) {
    String? text(String key) {
      final value = json[key]?.toString().trim();
      return (value == null || value.isEmpty) ? null : value;
    }

    return BrandSettings(
      systemTitle: text('system_title') ?? 'Dar Al Turab',
      companyName: text('company_name'),
      vatRegistrationNumber: text('vat_registration_number'),
      address: text('address'),
      phone: text('phone'),
      developedBy: text('developed_by'),
      systemLogo: text('system_logo'),
    );
  }

  /// Short name, e.g. "DAR AL TURAB". Never null — required in the database.
  final String systemTitle;

  /// Full legal name, e.g. "DAR AL TURAB FOODSTUFF TRADING LLC".
  final String? companyName;

  final String? vatRegistrationNumber;
  final String? address;
  final String? phone;
  final String? developedBy;

  /// Absolute URL to the logo, or null when none has been uploaded. The server
  /// does not verify the file exists, so the image may still 404 — callers must
  /// provide a fallback.
  final String? systemLogo;

  /// Best name to show where space allows.
  String get displayName => companyName ?? systemTitle;

  bool get hasLogo => systemLogo != null;

  Map<String, dynamic> toJson() => {
    'system_title': systemTitle,
    'company_name': companyName,
    'vat_registration_number': vatRegistrationNumber,
    'address': address,
    'phone': phone,
    'developed_by': developedBy,
    'system_logo': systemLogo,
  };
}
