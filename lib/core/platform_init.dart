/// CORE — platform database factory initialisation (S7, §R8.6).
///
/// sqflite has no Linux/Windows/macOS implementation; on desktop
/// the FFI factory (already a dependency for host tests) is the
/// database factory, and it needs the system SQLite library
/// (Arch: the `sqlite` package — see docs/SYNC_SETUP.md). Android
/// keeps the native sqflite factory untouched.
library;

import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool get isDesktopPlatform =>
    Platform.isLinux || Platform.isWindows || Platform.isMacOS;

/// Install the FFI database factory on desktop platforms. Must
/// run before any database is opened. Safe to call repeatedly
/// (and in tests, which set the factory themselves first — the
/// identical assignment is harmless).
void initDatabaseFactory() {
  if (isDesktopPlatform) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}
