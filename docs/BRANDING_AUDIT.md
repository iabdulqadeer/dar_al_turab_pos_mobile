# Branding Audit — Dar Al Turab POS (Flutter)

Phase 0 deliverable for `dar-al-turab-flutter-branding-prompt.md`. **No code was changed.**

Date: 2026-07-21 · Repo: `github.com/iabdulqadeer/dar_al_turab_pos_mobile` @ `master`

---

## 0.1 Project inventory

| Item | Value |
|---|---|
| Flutter | 3.41.9 (stable, 2026-04-29) |
| Dart SDK constraint | `^3.11.5` |
| Null safety | Sound, throughout |
| State management | **Riverpod 3.3.2** (`flutter_riverpod`). Hand-written `Notifier`/`AsyncNotifier`; no codegen |
| Routing | **go_router 17.3** — `StatefulShellRoute.indexedStack`, 4 bottom-nav branches, auth redirect guard |
| Networking | `dio` 5.10 behind `ApiClient` + typed `ApiException` |
| Fonts | `google_fonts` 8.2 → **Nunito** (`app_theme.dart:44`), no bundled font files |
| Tests | 135 passing, `flutter analyze` clean |

### Screen inventory

| Route | File | Purpose |
|---|---|---|
| `/` | `features/splash/presentation/splash_screen.dart` | Holds while the stored session is restored |
| `/login` | `features/auth/presentation/login_screen.dart` | Credentials + editable API base URL |
| `/dashboard` | `features/dashboard/presentation/dashboard_screen.dart` | Stat cards from `/sales/statistics` |
| `/sales` | `features/sales/presentation/sales_list_screen.dart` | Paged, filterable sale list |
| `/sales/:id` | `features/sales/presentation/sale_detail_screen.dart` | Lines, totals, payments, print/edit/delete |
| `/sales/:id/edit` | `features/pos/presentation/edit_sale_screen.dart` | Re-opens a sale in the cart UI |
| `/pos` | `features/pos/presentation/pos_screen.dart` | Search → weight-aware cart → payment → submit |
| `/printer` | `features/printing/presentation/printer_settings_screen.dart` | Bluetooth pairing + test print |
| `/profile` | `features/profile/presentation/profile_screen.dart` | User details, sign out |
| `/profile/edit` | `features/profile/presentation/edit_profile_screen.dart` | Name / email / phone |
| `/profile/password` | `features/profile/presentation/change_password_screen.dart` | Password change |

### Reusable widget inventory

**Shared** — `core/widgets/app_form.dart` (`AppTextField`, `AppSubmitButton`, `Validate`), `core/widgets/app_shell.dart` (bottom nav scaffold), `features/dashboard/.../stat_card.dart`, `features/sales/.../status_chip.dart`, `features/pos/.../cart_line_editor.dart`, `customer_picker.dart`, `payment_sheet.dart`, `barcode_scanner_sheet.dart`, `features/sales/.../add_payment_sheet.dart`.

**Duplicated inline** — error+retry blocks (5 screens, each hand-rolled), skeleton loaders (2 screens only), empty states, `SnackBar` construction (42 sites, no shared helper), section headers/cards in `sale_detail_screen.dart`.

---

## 0.2 Current branding footprint

| File | Line | Current value | Category |
|---|---|---|---|
| `pubspec.yaml` | 2 | `"A new Flutter project."` | **Placeholder** |
| `pubspec.yaml` | — | no `flutter.assets` section; no launcher-icon/splash package | Missing |
| `android/app/src/main/AndroidManifest.xml` | 34 | `android:label="Dar Al Turab POS"` | Correct, but long for a launcher |
| `AndroidManifest.xml` | 36 | `android:icon="@mipmap/ic_launcher"`; **no `roundIcon`, no adaptive icon** | Gap |
| `android/app/build.gradle` | 24 | `applicationId = "com.daralturab.dar_al_turab_pos"` | **Real, not `com.example.*` — do not change** |
| `res/mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher.png` | — | **Stock Flutter blue-F icon** | Placeholder |
| `res/drawable/launch_background.xml` | 4 | `@android:color/white`, image item commented out | Placeholder |
| `res/values/styles.xml`, `values-night/styles.xml` | — | Default Flutter launch theme | Placeholder |
| `ios/Runner/Info.plist` | 10 | `CFBundleDisplayName = Dar Al Turab POS` | Correct |
| `ios/Runner/Info.plist` | 37 | `CFBundleName = dar_al_turab_pos` | Should be `DarAlTurab` |
| `ios/.../AppIcon.appiconset/` | — | Stock Flutter icons, all slots | Placeholder |
| `ios/.../LaunchImage.imageset/` | — | Stock Flutter launch image | Placeholder |
| `lib/core/config/app_config.dart` | 31 | `static const appName = 'Dar Al Turab POS'` | Only brand constant that exists |
| `lib/main.dart` | 10, 13 | `DarAlTurabPosApp` | Class name, fine |
| `lib/features/auth/providers/auth_providers.dart` | 168 | `'Dar Al Turab POS mobile'` (device-name fallback) | Hardcoded string |
| `lib/features/printing/.../printer_settings_screen.dart` | 175 | `'DAR AL TURAB POS'` (test-print header) | **Printed output** |
| `lib/core/theme/app_colors.dart` | 3–7 | Comment: palette mirrored from web POS CSS | Provenance note |
| `lib/features/auth/presentation/login_screen.dart` | 212 | URL hint text | Not brand |

**No occurrence anywhere of** the legal name `Dar Al Turab Foodstuff Trading LLC`, the tagline, address, phone, WhatsApp, email, or website. There is no About screen.

### ⚠ Printed output — read this before planning Phase 3

The brief (§3) asks for the receipt header to carry logo, legal name, address, phone, email, website. **The Flutter app cannot do this.** Receipt layout is produced entirely server-side: `SalesApi.receipt` returns a pre-padded `lines[]` array from Laravel's `SaleReceiptFormatter`, and `ReceiptPrinter` (`receipt_printer.dart:20-21`) only *styles, encodes, and transmits* — it never composes content. Changing the receipt header is a **Laravel change**, in a different repository.

The only brand string the Flutter app emits to paper is the **test print** at `printer_settings_screen.dart:175`.

Two further constraints on receipt branding:
- **Logo on thermal paper needs raster mode.** `EscPosEncoder` is text-mode only (plus a QR helper). Printing a bitmap logo means implementing ESC/POS `GS v 0`, which does not exist yet.
- **Arabic is actively refused.** `receipt_printer.dart:66-73` throws when the receipt contains non-Latin glyphs, because text mode cannot shape Arabic. Any Arabic in the brand block would make every receipt unprintable.

---

## 0.3 Theming audit

A centralised `ThemeData` **does exist** and is real — `core/theme/app_theme.dart` builds full light and dark themes and wires `appBarTheme`, `inputDecorationTheme`, `cardTheme`, `chipTheme`, `bottomNavigationBarTheme`, `elevatedButtonTheme` and others. Dark mode works, not broken. `AppSpacing` (8pt) and `AppRadius` token classes already exist in `app_colors.dart`.

So the brief's Phase 2 is **substantially already built**. What it does not have is *semantic* naming or the domain tokens.

### Hardcoded colours — 132 occurrences / 21 files

| Location | Count | Note |
|---|---|---|
| `core/theme/app_theme.dart` | 23 | Legitimate (theme definition) |
| `core/theme/app_colors.dart` | 21 | Legitimate (token definition) |
| **Everything else (19 files)** | **88** | **Phase 2 migration target** |

Worst offenders: `profile_screen.dart` 13, `sale_detail_screen.dart` 8, `status_chip.dart` 8, `dashboard_screen.dart` 8, `pos_screen.dart` 7, `printer_settings_screen.dart` 6.

**Baseline metric for Phase 6: 88 → 0.**

Inline `TextStyle(` — only **6** occurrences across 3 files. Typography is already well disciplined; this is a small job.

**Token naming is by hue, not role.** `AppColors.primary` etc. exist, but there is no `onPrimary`, `surfaceVariant`, `outline`, `info`, no product-category accents, no stock-status tokens. `warning` is `#EB543A` (orange-red) and `error` is `#FF6B6B` — visually close enough to be confusable.

**Font — Nunito has no Arabic coverage.** The brief (§2) requires verifying Arabic glyph support for a UAE business. Nunito is Latin/Cyrillic/Greek only. It is also a soft, rounded humanist face — arguably at odds with the brief's own "no playful rounded styling, slightly formal" direction. IBM Plex Sans (Latin + Arabic siblings) or Noto Sans + Noto Sans Arabic would satisfy both.

---

## 0.4 Iconography audit

**One family in use: Material `Icons.` — 110 references across 18 files.** No `CupertinoIcons`, no SVG assets, no icon package. Consistency of *family* is good; there is no registry.

Concentrations: `pos_screen.dart` 12, `printer_settings_screen.dart` 11, `profile_screen.dart` 11, `sale_detail_screen.dart` 9, `customer_picker.dart` 9, `app_shell.dart` 9.

### Icon deserts
- **Form fields** — `AppTextField` has no `prefixIcon` parameter at all, so *every* form field in the app is icon-less: login, edit profile, change password, payment sheet, add-payment sheet, cart line editor.
- **Buttons** — `AppSubmitButton` takes no icon; primary and destructive actions are text-only.
- **Dialogs** — 5 `showDialog` sites, none with a header icon signalling intent.
- **Empty states** — no shared empty-state widget; existing ones are bare text.
- **Status** — `status_chip.dart` is **colour + text only, no icon** (accessibility gap for colour-blind users, called out explicitly in §4.2).
- **List rows** — sale rows have no leading type indicator.
- **Product categories** — the four categories (Fresh & Chilled Beef, Mutton & Lamb, Frozen Meat, Bulk & Custom Supply) have **no representation in the app at all**; see risk R3.

### Accessibility
`tooltip:` appears 11 times; `Semantics(` **0 times**. Icon-only tappables are under-labelled.

---

## 0.5 UX gap audit

| Screen | Loading | Empty | Error | Success | Refresh | Confirm |
|---|---|---|---|---|---|---|
| Splash | spinner | n/a | ✗ | n/a | n/a | n/a |
| Login | spinner | n/a | ✓ snackbar | ✓ | n/a | n/a |
| Dashboard | **skeleton** | ✗ | ✓ + retry | n/a | ✓ | n/a |
| Sales list | **skeleton** | ✗ | ✓ + retry | n/a | ✓ | n/a |
| Sale detail | spinner | n/a | ✓ + retry | ✓ snackbar | **✗** | ✓ delete |
| POS | spinner | ✗ | ✓ + retry | ✓ snackbar | ✗ | ✓ |
| Edit sale | spinner | n/a | ✓ + retry | ✓ snackbar | ✗ | ✗ |
| Printer settings | spinner | ✗ | weak | ✓ snackbar | ✗ | n/a |
| Profile | spinner | n/a | ✓ | ✗ | ✓ | ✓ sign out |
| Edit profile | ✗ | n/a | ✓ | ✓ snackbar | n/a | n/a |
| Change password | ✗ | n/a | ✓ | ✓ snackbar | n/a | n/a |

**Systemic gaps:** no empty states anywhere; skeletons on 2 of 11 screens (rest are bare spinners); `HapticFeedback` used **twice** in the whole app (both in the barcode scanner) — this is a warehouse/shop-floor tool where the brief rightly flags haptics as high-value; **zero** `AnimatedSwitcher` or `Hero`; sale detail has no pull-to-refresh despite being server-backed and mutable.

---

## 0.6 Proposed plan

### Phase 1 — asset pipeline
Logo URL verified reachable (`HTTP 200`, `image/jpeg`, 85,551 bytes). Python 3.14.6 + Pillow 12.2.0 confirmed present, so colour extraction / background removal / mono variants are all runnable locally. Then `flutter_launcher_icons` + `flutter_native_splash` (two new dev dependencies — needs your nod under the brief's own "ask before adding deps" rule).

### Phase 2 — design system
Rename to semantic roles, add `onPrimary`/`surfaceVariant`/`outline`/`info`, add the domain tokens, split `app_typography.dart` and `app_spacing.dart` out of `app_colors.dart`, swap the font, migrate 88 hardcoded colours.

### Phase 3 — identity
New `brand_constants.dart`; new About section on profile; fix `pubspec.yaml` description and `CFBundleName`. **Receipt branding is out of scope here — see the §0.2 warning.**

### Phase 4 — iconography
New `app_icons.dart`; add `prefixIcon` to `AppTextField` and `icon` to `AppSubmitButton`; icons on status chips, dialogs, empty states, list rows.

### Phase 5 — interaction
`AppEmptyState`, `AppSkeleton`, `AppErrorState`, `AppSnackbar` in `core/widgets/`, then replace the 42 ad-hoc snackbars and 5 duplicated error blocks. Haptics on mutations. Restrained motion.

**Files created:** ~12 (4 theme, 1 constants, 4 shared widgets, brand assets, 2 docs).
**Files modified:** all 11 screens, 9 widgets, `pubspec.yaml`, both manifests, `styles.xml`.

### Risks

- **R1 — `applicationId` is real.** `com.daralturab.dar_al_turab_pos`, not a placeholder, and the app is **already installed on your test device**. Changing it orphans that install. Per the brief: not touching it.
- **R2 — receipt branding is a Laravel job.** The single largest expectation in the brief that this repo cannot satisfy. Needs routing to your backend developer, plus raster-mode ESC/POS work if a logo is genuinely wanted on paper.
- **R3 — the product taxonomy does not exist in the data.** The brief wants accent tokens and icons for four categories. The API returns products with `id`/`name`/`code`/`unit`/`pricing`/`stock` — no category field. These tokens would be defined and unused until the backend exposes a category. Recommend defining the tokens, wiring nothing.
- **R4 — colour direction conflict.** You previously chose "match the existing purple identity" (`#7C5CC4`, from the web POS CSS) so mobile and web read as one product. The brief instead says derive colours from the logo and forbids assuming them. These will very likely disagree. **This is the main decision I need from you** — see below.
- **R5 — Arabic.** Adopting an Arabic-capable font is cheap and worth doing. Actually *rendering* Arabic on receipts is blocked by text-mode ESC/POS (`receipt_printer.dart:66`).
- **R6 — printer calibration still open.** Unrelated to branding but still outstanding: `pm400CharactersPerLine = 64` in the app vs `42` in the server's `printer_settings` row. Needs a physical test print.

---

## ⛔ Phase 0 ends here — awaiting approval

Nothing has been modified. Two answers needed before Phase 1:

1. **R4:** keep the web-matching purple, or re-derive the palette from the logo (and accept mobile diverging from web)?
2. **Phase 1 needs `flutter_launcher_icons` and `flutter_native_splash`** as dev dependencies — approve?
