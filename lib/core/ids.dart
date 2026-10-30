/// CORE — cross-device identity helpers (sync scaffold, S3).
///
/// Local integer PKs stay the local identity (zero disruption to
/// S1/S2); `sync_id` (UUIDv4) is the cross-device identity added by
/// schema v3 (§R6.3 of the research report). Version stamps are
/// hybrid logical clock (HLC) strings with every field zero-padded
/// to a fixed width, so plain lexicographic comparison gives the
/// correct order (an unpadded counter breaks ordering at 10).
library;

import 'dart:math';

final _rng = Random.secure();

/// A random UUIDv4 string.
String newUuid() {
  final b = List<int>.generate(16, (_) => _rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // variant 10xx
  String hex(int i) => b[i].toRadixString(16).padLeft(2, '0');
  return '${hex(0)}${hex(1)}${hex(2)}${hex(3)}-'
      '${hex(4)}${hex(5)}-${hex(6)}${hex(7)}-'
      '${hex(8)}${hex(9)}-'
      '${hex(10)}${hex(11)}${hex(12)}${hex(13)}${hex(14)}${hex(15)}';
}

/// Format an HLC stamp: fixed-width wall ms + counter + device id.
/// Lexicographic order on these strings is the HLC order for the
/// same-width fields (§R6.3). HLC tolerates *small* clock skew only;
/// receivers clamp implausible peer times at sync time (S7/S8).
String formatHlc(int wallMs, int counter, String deviceId) =>
    '${wallMs.toString().padLeft(13, '0')}-'
    '${counter.toString().padLeft(6, '0')}-$deviceId';
