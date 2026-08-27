import 'dart:typed_data';

import 'package:dar_al_turab_pos/features/printing/raster_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds an RGBA buffer from a per-pixel black/white pattern (true = black).
Uint8List _rgba(List<List<bool>> rows) {
  final height = rows.length;
  final width = rows.first.length;
  final out = Uint8List(width * height * 4);
  var p = 0;
  for (final row in rows) {
    for (final black in row) {
      final v = black ? 0 : 255;
      out[p++] = v; // r
      out[p++] = v; // g
      out[p++] = v; // b
      out[p++] = 255; // a (opaque)
    }
  }
  return out;
}

void main() {
  const encoder = RasterEncoder();

  test('packs an 8×2 image into a single GS v 0 band, MSB-first', () {
    // Row 0 all black → 0xFF; row 1 all white → 0x00.
    final pixels = _rgba([
      List.filled(8, true),
      List.filled(8, false),
    ]);

    final bytes = encoder.encodeRgba(pixels, 8, 2, trailingFeed: 0);

    expect(
      bytes,
      Uint8List.fromList([
        0x1B, 0x40, // ESC @ (init)
        0x1D, 0x76, 0x30, 0x00, // GS v 0 m=0
        0x01, 0x00, // width = 1 byte
        0x02, 0x00, // height = 2 dots
        0xFF, // row 0
        0x00, // row 1
      ]),
    );
  });

  test('pads a sub-byte width and sets the high bits first', () {
    // Width 4 (not a byte multiple): 4 black pixels → 0xF0.
    final pixels = _rgba([
      List.filled(4, true),
    ]);

    final bytes = encoder.encodeRgba(pixels, 4, 1, trailingFeed: 0);

    // last data byte is the packed row.
    expect(bytes.last, 0xF0);
    // width-in-bytes field (GS v 0 xL) = ceil(4/8) = 1, at offset 6.
    expect(bytes[6], 0x01);
  });

  test('appends an ESC d feed when requested', () {
    final pixels = _rgba([
      List.filled(8, false),
    ]);

    final bytes = encoder.encodeRgba(pixels, 8, 1, trailingFeed: 3);

    // ends with ESC d 3.
    expect(bytes.sublist(bytes.length - 3), [0x1B, 0x64, 0x03]);
  });
}
