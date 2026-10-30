// LEARN-data — LibraryStore (S4): the §R6.4 layout, relative
// paths only, untrusted-filename sanitising, traversal refusal,
// collision suffixes, the size cap, and the red-team #8 rule —
// every write is temp-then-rename, so a torn write can never
// damage the previous good file.
import 'dart:convert';
import 'dart:io';

import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late LibraryStore library;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nimo-lib-');
    library = LibraryStore(Directory('${tmp.path}/Library'));
    await library.ensureLayout();
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('ensureLayout creates the §R6.4 subfolders + library.json',
      () async {
    for (final sub in LibraryStore.subdirs) {
      expect(await Directory('${library.rootPath}/$sub').exists(),
          isTrue,
          reason: sub);
    }
    final meta = jsonDecode(
        await File('${library.rootPath}/.nimo/library.json')
            .readAsString()) as Map<String, Object?>;
    expect(meta['format_version'], 1);
    expect(meta['library_id'], isNotNull);
    // Idempotent: a second pass keeps the same library id.
    final firstId = meta['library_id'];
    await library.ensureLayout();
    final again = jsonDecode(
        await File('${library.rootPath}/.nimo/library.json')
            .readAsString()) as Map<String, Object?>;
    expect(again['library_id'], firstId);
  });

  test('writeAtomic round-trips and replaces cleanly', () async {
    await library.writeAtomic('sources/a.txt', utf8.encode('one'));
    expect(await library.readText('sources/a.txt'), 'one');
    await library.writeAtomic('sources/a.txt', utf8.encode('two'));
    expect(await library.readText('sources/a.txt'), 'two');
    // No temp litter remains after successful writes.
    final leftovers = await Directory('${library.rootPath}/sources')
        .list()
        .where((e) => e.path.contains('.tmp-'))
        .length;
    expect(leftovers, 0);
  });

  test('concurrent readers never see a torn file during writeAtomic '
      '(§10.2 mutation guard: an in-place writer fails this)',
      () async {
    // 2 MB uniform payloads: a reader must always observe one
    // complete payload or the other — never empty, never mixed.
    // rename() gives that; truncate-and-write-in-place does not.
    final payloadA = List<int>.filled(2 * 1024 * 1024, 65);
    final payloadB = List<int>.filled(2 * 1024 * 1024, 66);
    await library.writeAtomic('sources/big.bin', payloadA);
    var stop = false;
    var torn = 0;
    var reads = 0;
    Future<void> reader() async {
      final file = library.resolve('sources/big.bin');
      while (!stop) {
        try {
          final bytes = await file.readAsBytes();
          reads++;
          if (bytes.length != payloadA.length) {
            torn++;
          } else {
            final firstByte = bytes.first;
            for (final b in bytes) {
              if (b != firstByte) {
                torn++;
                break;
              }
            }
          }
        } on FileSystemException {
          torn++; // path must never vanish under rename semantics
        }
      }
    }

    final readerFuture = reader();
    for (var i = 0; i < 60; i++) {
      await library.writeAtomic(
          'sources/big.bin', i.isEven ? payloadB : payloadA);
    }
    stop = true;
    await readerFuture;
    expect(reads, greaterThan(0));
    expect(torn, 0, reason: 'readers observed a half-written file');
  });

  test('a torn write (temp file left by a crashed writer) leaves '
      'the good file intact', () async {
    await library.writeAtomic('sources/doc.pdf', [1, 2, 3]);
    // Simulate the crash: a half-written temp sibling appears.
    await File('${library.rootPath}/sources/doc.pdf.tmp-deadbeef')
        .writeAsBytes([9, 9]);
    expect(await library.readBytes('sources/doc.pdf'), [1, 2, 3]);
  });

  test('resolve refuses traversal and absolute paths', () async {
    expect(() => library.resolve('../outside.txt'),
        throwsA(isA<LibraryException>()));
    expect(() => library.resolve('sources/../../outside.txt'),
        throwsA(isA<LibraryException>()));
    expect(() => library.resolve('/etc/passwd'),
        throwsA(isA<LibraryException>()));
  });

  group('sanitizeFileName (untrusted share/picker names)', () {
    final cases = <String, String>{
      '../../etc/passwd': 'passwd',
      r'..\..\evil.pdf': 'evil.pdf',
      'normal name.pdf': 'normal_name.pdf',
      '...hidden.txt': 'hidden.txt',
      '': 'file',
      '..': 'file',
      'résumé 📄.pdf': 'r_sum_.pdf',
      'a/b/c.txt': 'c.txt',
    };
    for (final entry in cases.entries) {
      test('${entry.key} → ${entry.value}', () {
        expect(LibraryStore.sanitizeFileName(entry.key), entry.value);
      });
    }

    test('very long names are capped at 100 chars, extension kept',
        () {
      final out =
          LibraryStore.sanitizeFileName('${'x' * 150}.pdf');
      expect(out.length, 100);
      expect(out.endsWith('.pdf'), isTrue);
    });
  });

  test('importFile copies under a sanitised name; collisions get '
      'a hash suffix', () async {
    final src = File('${tmp.path}/in.pdf');
    await src.writeAsBytes([5, 5, 5]);
    final rel1 = await library.importFile('sources', src.path, 'doc.pdf');
    expect(rel1, 'sources/doc.pdf');
    final rel2 = await library.importFile('sources', src.path, 'doc.pdf');
    expect(rel2, startsWith('sources/doc-'));
    expect(rel2, endsWith('.pdf'));
    expect(rel2, isNot(rel1));
    expect(await library.readBytes(rel2), [5, 5, 5]);
  });

  test('importFile with a traversal name cannot escape sources/',
      () async {
    final src = File('${tmp.path}/incoming.bin');
    await src.writeAsBytes([1]);
    final rel =
        await library.importFile('sources', src.path, '../../../evil.bin');
    expect(rel, 'sources/evil.bin');
    expect(await File('${tmp.path}/evil.bin').exists(), isFalse);
  });

  test('oversized imports are refused cleanly', () async {
    final big = List<int>.filled(LibraryStore.maxImportBytes + 1, 0);
    await expectLater(
      library.importBytes('sources', big, 'big.pdf'),
      throwsA(isA<LibraryException>()),
    );
  });

  test('stats count content but not the backups folder', () async {
    await library.writeAtomic('sources/a.txt', [1, 2]);
    await library.writeAtomic('backups/b.zip', [1, 2, 3, 4]);
    final stats = await library.stats();
    expect(stats.files, 2); // a.txt + .nimo/library.json
    expect(stats.bytes, greaterThan(2));
  });
}
