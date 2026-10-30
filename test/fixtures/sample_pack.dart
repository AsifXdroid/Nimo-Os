/// Acceptance fixture for the S5 pack importer (§R10.2): an
/// Arabic greetings pack with one of every question type,
/// including an image-point on a real (tiny) PNG and a branching
/// scenario, with RTL Arabic strings (§R9.4).
///
/// Single source of truth: [samplePackJsonTemplate] is the
/// pack.json text. Its one placeholder, `__SHA256__`, is filled
/// by [buildSamplePackJson] with the digest of [samplePngBytes]
/// (computed by the builder, so the fixture can never drift from
/// the media it ships).
library;

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

/// A valid 1×1 transparent PNG.
const String samplePngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8Xw8AAwMCAO+ip1sAAAAASUVORK5CYII=';

List<int> get samplePngBytes => base64Decode(samplePngBase64);

/// Zip entry name of the pack's one media file.
const String sampleMediaEntryName = 'media/greeting-card.png';

const String samplePackJsonTemplate = r'''
{
  "schema": "nimo.quizpack",
  "schemaVersion": 1,
  "pack": {
    "id": "arabic-greetings-01",
    "title": "Arabic Greetings",
    "version": "1.0.0",
    "language": "ar",
    "author": "ai-assistant",
    "tags": ["arabic", "conversation"],
    "sourceRef": "greetings-notes.pdf"
  },
  "media": [
    {
      "id": "m1",
      "file": "media/greeting-card.png",
      "mime": "image/png",
      "sha256": "__SHA256__",
      "alt": "A greeting card"
    }
  ],
  "arc": {
    "id": "arabic-city-01",
    "title": "City Errands",
    "episode": 1,
    "episodeTitle": "Greetings",
    "teaser": "Tomorrow: the café owner argues about the bill"
  },
  "questions": [
    {
      "id": "q1", "type": "mcq", "difficulty": 1,
      "prompt": "How do you say \"Peace be upon you\"?",
      "choices": [
        {"id": "a", "text": "السلام عليكم"},
        {"id": "b", "text": "شكراً"},
        {"id": "c", "text": "مع السلامة"},
        {"id": "d", "text": "صباح الخير"}
      ],
      "correctChoiceIds": ["a"], "shuffle": true,
      "explanation": "السلام عليكم (as-salāmu ʿalaykum) is the standard greeting: peace be upon you."
    },
    {
      "id": "q2", "type": "mcq", "difficulty": 2,
      "prompt": "Someone says السلام عليكم to you. What is the reply?",
      "choices": [
        {"id": "a", "text": "أهلاً وسهلاً"},
        {"id": "b", "text": "وعليكم السلام"},
        {"id": "c", "text": "إلى اللقاء"},
        {"id": "d", "text": "عفواً"}
      ],
      "correctChoiceIds": ["b"], "shuffle": true,
      "explanation": "The reply mirrors the greeting: وعليكم السلام (wa-ʿalaykumu s-salām) — and upon you be peace."
    },
    {
      "id": "q3", "type": "mcq", "difficulty": 2,
      "prompt": "How do you say \"Thank you\" in Arabic?",
      "choices": [
        {"id": "a", "text": "من فضلك"},
        {"id": "b", "text": "آسف"},
        {"id": "c", "text": "شكراً"},
        {"id": "d", "text": "نعم"}
      ],
      "correctChoiceIds": ["c"], "shuffle": true,
      "explanation": "شكراً (shukran) means thank you; من فضلك is please and آسف is sorry."
    },
    {
      "id": "q4", "type": "mcq", "difficulty": 3,
      "prompt": "Which phrase is the morning greeting, and which is its traditional reply?",
      "choices": [
        {"id": "a", "text": "مساء الخير ← مساء النور"},
        {"id": "b", "text": "صباح الخير ← صباح النور"},
        {"id": "c", "text": "ليلة سعيدة ← شكراً"},
        {"id": "d", "text": "أهلاً ← مع السلامة"}
      ],
      "correctChoiceIds": ["b"], "shuffle": false,
      "explanation": "صباح الخير (ṣabāḥ al-khayr, morning of goodness) is answered with صباح النور (ṣabāḥ an-nūr, morning of light). The مساء pair is for the evening."
    },
    {
      "id": "q5", "type": "flashcard", "difficulty": 1,
      "front": "السلام عليكم",
      "back": "Peace be upon you — the standard greeting at any time of day.",
      "explanation": "Literally: the peace be upon you (plural/respectful form)."
    },
    {
      "id": "q6", "type": "flashcard", "difficulty": 2,
      "front": "مع السلامة",
      "back": "Goodbye — literally, go with safety/peace.",
      "explanation": "Used when someone is leaving; the reply can be الله يسلمك (may God keep you safe)."
    },
    {
      "id": "q7", "type": "flashcard", "difficulty": 3,
      "front": "أهلاً وسهلاً",
      "back": "Welcome — literally, you have come to family and to ease.",
      "explanation": "A warm welcome formula: أهلاً (family/people) وسهلاً (ease, level ground)."
    },
    {
      "id": "q8", "type": "cloze", "difficulty": 2,
      "text": "The standard greeting at any time of day is {{السلام عليكم}}.",
      "explanation": "السلام عليكم works morning, afternoon and evening — it is not time-specific."
    },
    {
      "id": "q9", "type": "cloze", "difficulty": 3,
      "text": "The reply to صباح الخير (good morning) is {{صباح النور}} (morning of light).",
      "explanation": "Greeting replies often swap الخير (goodness) for النور (light)."
    },
    {
      "id": "q10", "type": "mythfact", "difficulty": 3,
      "statement": "شكراً (shukran) means goodbye in Arabic.",
      "isFact": false,
      "explanation": "False friend: شكراً means thank you. Goodbye is مع السلامة or إلى اللقاء."
    },
    {
      "id": "q11", "type": "ordering", "difficulty": 3,
      "prompt": "Put this greeting exchange in order",
      "items": [
        {"id": "i1", "text": "السلام عليكم"},
        {"id": "i2", "text": "وعليكم السلام"},
        {"id": "i3", "text": "كيف حالك؟"},
        {"id": "i4", "text": "بخير، الحمد لله"}
      ],
      "correctOrder": ["i1", "i2", "i3", "i4"],
      "explanation": "Greeting first, its reply second, then the how-are-you question and its answer: بخير، الحمد لله (fine, praise be to God)."
    },
    {
      "id": "q12", "type": "image_point", "difficulty": 2,
      "prompt": "Tap the greeting card",
      "image": "m1",
      "target": {"cx": 0.5, "cy": 0.5, "r": 0.2},
      "explanation": "The card in the middle carries the greeting السلام عليكم."
    },
    {
      "id": "q13", "type": "scenario", "difficulty": 4,
      "startNode": "n1",
      "nodes": {
        "n1": {
          "text": "You push open the café door in the morning. The owner looks up and smiles. How do you greet him?",
          "choices": [
            {"text": "صباح الخير، كيف حالك؟", "next": "n2", "feedback": "A warm morning greeting — he beams back صباح النور."},
            {"text": "مع السلامة!", "next": "n3", "feedback": "That means goodbye — he looks puzzled, since you just arrived."}
          ]
        },
        "n2": {
          "text": "He replies صباح النور and asks what you would like. You order tea and thank him as he sets it down.",
          "choices": [
            {"text": "شكراً جزيلاً", "next": "n4", "feedback": "شكراً جزيلاً — thank you very much. Perfect."}
          ]
        },
        "n3": {
          "text": "You catch yourself, laugh, and correct the greeting: صباح الخير! He laughs too and waves you to a table.",
          "choices": [
            {"text": "آسف! صباح الخير، من فضلك شاي", "next": "n4", "feedback": "Recovered gracefully: sorry, good morning, tea please."}
          ]
        },
        "n4": {
          "end": true,
          "text": "You sip your tea as the café fills up.",
          "summary": "Morning greetings: صباح الخير answered by صباح النور; save مع السلامة for when you leave, and شكراً makes every order warmer."
        }
      },
      "explanation": "Branch-and-bottleneck: the farewell slip costs one beat, then both paths rejoin at the thank-you."
    }
  ]
}
''';

/// The pack.json text with the media digest filled in.
String buildSamplePackJson() => samplePackJsonTemplate.replaceAll(
      '__SHA256__',
      sha256.convert(samplePngBytes).toString(),
    );

/// The complete .quizpack zip bytes: pack.json at the root plus
/// the one declared media file.
List<int> buildSamplePackBytes() {
  final archive = Archive();
  final jsonBytes = utf8.encode(buildSamplePackJson());
  archive.addFile(ArchiveFile('pack.json', jsonBytes.length, jsonBytes));
  final png = samplePngBytes;
  archive.addFile(ArchiveFile(sampleMediaEntryName, png.length, png));
  return ZipEncoder().encode(archive);
}
