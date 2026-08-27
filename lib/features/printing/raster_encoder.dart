import 'dart:typed_data';
import 'dart:ui' as ui;

import 'escpos_encoder.dart';

/// Encodes a rendered [ui.Image] (a rasterised invoice) into ESC/POS
/// `GS v 0` bit-image commands, so the printed receipt is a pixel-faithful
/// bitmap of the invoice rather than a monospace text approximation.
///
/// The image is thresholded to 1-bit (black on white) and sent in horizontal
/// bands so it never exceeds a printer's line buffer.
class RasterEncoder {
  const RasterEncoder({this.threshold = 160, this.bandHeight = 128});

  /// Luminance (0–255) at/below which a pixel prints as black.
  final int threshold;

  /// Rows per `GS v 0` command; printers buffer a band at a time.
  final int bandHeight;

  Future<Uint8List> encode(ui.Image image, {int trailingFeed = 3}) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      throw StateError('Could not read pixels from the rendered invoice.');
    }
    return encodeRgba(
      data.buffer.asUint8List(),
      image.width,
      image.height,
      trailingFeed: trailingFeed,
    );
  }

  /// Pure core: packs raw RGBA [pixels] (`width * height * 4` bytes) into the
  /// ESC/POS `GS v 0` banded raster stream. Separated out so it is unit-testable
  /// without an engine-backed [ui.Image].
  Uint8List encodeRgba(
    Uint8List pixels,
    int width,
    int height, {
    int trailingFeed = 3,
  }) {
    final bytesPerRow = (width + 7) >> 3; // ceil(width / 8)

    final out = BytesBuilder();
    out.add(EscPos.init);

    for (var top = 0; top < height; top += bandHeight) {
      final rows = (top + bandHeight <= height) ? bandHeight : height - top;

      // GS v 0 m xL xH yL yH  — m=0, x in bytes, y in dots (little-endian).
      out.add([
        0x1D, 0x76, 0x30, 0x00,
        bytesPerRow & 0xFF, (bytesPerRow >> 8) & 0xFF,
        rows & 0xFF, (rows >> 8) & 0xFF,
      ]);

      final band = Uint8List(bytesPerRow * rows);
      for (var y = 0; y < rows; y++) {
        final srcRow = (top + y) * width;
        final dstRow = y * bytesPerRow;
        for (var x = 0; x < width; x++) {
          final p = (srcRow + x) << 2; // *4 (RGBA)
          final a = pixels[p + 3];
          // Transparent → treated as white (paper). Otherwise luminance.
          final lum = a < 128
              ? 255
              : (pixels[p] * 30 + pixels[p + 1] * 59 + pixels[p + 2] * 11) ~/
                  100;
          if (lum <= threshold) {
            band[dstRow + (x >> 3)] |= 0x80 >> (x & 7); // MSB-first, 1 = black
          }
        }
      }
      out.add(band);
    }

    if (trailingFeed > 0) {
      out.add([0x1B, 0x64, trailingFeed]); // ESC d n — feed n lines
    }
    return out.toBytes();
  }
}
