// LINK — link-card rework (S4): creating a card creates its
// topic trigger (card ↔ topic linked both ways, §R6.2), and the
// D-003 thumbnail layers behave: user image wins, auto-fetch is
// best-effort og:image with every failure falling back silently,
// payload stores only the cache file name.
import 'dart:convert';
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/items/link_card/link_card_service.dart';
import 'package:daily_life_app/features/items/link_card/thumbnail_service.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tmp;
  late Store store;
  late LearnStore learn;
  late ThumbnailService thumbs;
  late LinkCardService cards;
  late int projectId;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nimo-link-');
    final db = await AppDatabase.openInMemory();
    store = Store(db);
    learn = LearnStore(db);
    thumbs = ThumbnailService(Directory('${tmp.path}/thumbs'));
    cards = LinkCardService(store, learn, thumbs);
    final ws = await store.createWorkspace('W');
    projectId = (await store.createProject(ws.id, 'P')).id;
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  group('creation = card + topic trigger', () {
    test('payload links to a topic in the same project', () async {
      final item = await cards.createLinkCard(
        projectId: projectId,
        url: 'https://instagram.com/reel/abc',
      );
      expect(item.type, ItemType.linkCard);
      expect(item.title, 'instagram.com'); // derived from host
      final topicId = cards.topicIdOf(item);
      expect(topicId, isNotNull);
      final topic = await learn.topicById(topicId!);
      expect(topic.projectId, projectId);
      expect(topic.triggerUrl, 'https://instagram.com/reel/abc');
      final sources = await learn.sourcesForTopic(topic.id);
      expect(sources.single.kind, SourceKind.link);
      expect(sources.single.url, 'https://instagram.com/reel/abc');
    });

    test('a manual title always wins', () async {
      final item = await cards.createLinkCard(
        projectId: projectId,
        url: 'https://example.com/x',
        title: 'Planes, explained',
      );
      expect(item.title, 'Planes, explained');
      final topic = await learn.topicById(cards.topicIdOf(item)!);
      expect(topic.title, 'Planes, explained');
    });
  });

  group('thumbnail layers (D-003)', () {
    BytesFetcher fetcherFor(Map<String, List<int>> pages,
        {Map<String, String> types = const {}}) {
      return (uri, {required maxBytes}) async {
        final body = pages[uri.toString()];
        if (body == null) {
          return (status: 404, contentType: null, bytes: const <int>[]);
        }
        return (
          status: 200,
          contentType: types[uri.toString()] ?? 'text/html',
          bytes: body.length > maxBytes
              ? body.sublist(0, maxBytes)
              : body,
        );
      };
    }

    test('auto-fetch stores the og:image (relative URL resolved)',
        () async {
      final html = utf8.encode(
          '<html><head><meta property="og:image" content="/img/p.png">'
          '</head></html>');
      final png = [0x89, 0x50, 0x4E, 0x47];
      final svc = ThumbnailService(
        Directory('${tmp.path}/t2'),
        fetcher: fetcherFor(
          {
            'https://example.com/post': html,
            'https://example.com/img/p.png': png,
          },
          types: {'https://example.com/img/p.png': 'image/png'},
        ),
      );
      final name = await svc.fetchForUrl('https://example.com/post');
      expect(name, isNotNull);
      expect(name, endsWith('.png'));
      expect(await svc.fileFor(name)!.readAsBytes(), png);
    });

    test('no og:image → null (fallback card is the answer)',
        () async {
      final svc = ThumbnailService(
        Directory('${tmp.path}/t3'),
        fetcher: fetcherFor({
          'https://example.com/plain':
              utf8.encode('<html><head><title>x</title></head></html>'),
        }),
      );
      expect(await svc.fetchForUrl('https://example.com/plain'), isNull);
    });

    test('HTTP failure and non-image targets → null, never a throw',
        () async {
      final svc = ThumbnailService(
        Directory('${tmp.path}/t4'),
        fetcher: fetcherFor({}),
      );
      expect(await svc.fetchForUrl('https://example.com/gone'), isNull);
      expect(await svc.fetchForUrl('not a url'), isNull);
      expect(await svc.fetchForUrl('ftp://example.com/x'), isNull);
    });

    test('user image attaches and lands in the payload', () async {
      final item = await cards.createLinkCard(
          projectId: projectId, url: 'https://example.com/a');
      final img = File('${tmp.path}/shot.jpg');
      await img.writeAsBytes([1, 2, 3]);
      final updated = await cards.attachUserImage(item, img.path, 'shot.jpg');
      expect(cards.thumbnailNameOf(updated), 'shot.jpg');
      final stored = thumbs.fileFor('shot.jpg');
      expect(await stored!.readAsBytes(), [1, 2, 3]);
    });

    test('service-level fetch updates the payload on success only',
        () async {
      final svc = ThumbnailService(
        Directory('${tmp.path}/t5'),
        fetcher: fetcherFor({
          'https://example.com/p': utf8.encode(
              '<meta content="https://cdn.example.com/i.jpg" '
              'property="og:image">'),
          'https://cdn.example.com/i.jpg': [7, 7],
        }, types: {
          'https://cdn.example.com/i.jpg': 'image/jpeg',
        }),
      );
      final withFetch = LinkCardService(store, learn, svc);
      final item = await withFetch.createLinkCard(
          projectId: projectId, url: 'https://example.com/p');
      final updated = await withFetch.tryFetchThumbnail(item);
      expect(withFetch.thumbnailNameOf(updated), isNotNull);
      expect(withFetch.thumbnailNameOf(updated), endsWith('.jpg'));
      expect(withFetch.thumbnailSourceOf(updated), 'auto');
    });

    test('auto-fetch never replaces a user-attached image (D-003: '
        'layer 1 always wins)', () async {
      final svc = ThumbnailService(
        Directory('${tmp.path}/t6'),
        fetcher: fetcherFor({
          'https://example.com/p': utf8.encode(
              '<meta property="og:image" '
              'content="https://cdn.example.com/i.jpg">'),
          'https://cdn.example.com/i.jpg': [7, 7],
        }, types: {
          'https://cdn.example.com/i.jpg': 'image/jpeg',
        }),
      );
      final withFetch = LinkCardService(store, learn, svc);
      var item = await withFetch.createLinkCard(
          projectId: projectId, url: 'https://example.com/p');
      final img = File('${tmp.path}/mine.png');
      await img.writeAsBytes([9, 9, 9]);
      item = await withFetch.attachUserImage(item, img.path, 'mine.png');
      expect(withFetch.thumbnailSourceOf(item), 'user');
      final after = await withFetch.tryFetchThumbnail(item);
      expect(withFetch.thumbnailNameOf(after), 'mine.png',
          reason: 'the owner-chosen image must survive auto-fetch');
      expect(withFetch.thumbnailSourceOf(after), 'user');
    });

    test('a hostile thumbnail name in a payload cannot escape the '
        'cache directory', () async {
      expect(thumbs.fileFor('../../etc/passwd')!.path,
          '${thumbs.dir.path}/passwd');
      expect(thumbs.fileFor('/etc/passwd')!.path,
          '${thumbs.dir.path}/passwd');
    });
  });
}
