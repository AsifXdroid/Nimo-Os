// HTML quiz — navigation policy (S5 legacy player): only the
// quiz file itself and files inside its own html_quizzes
// directory may load; everything else is blocked.
import 'package:daily_life_app/features/items/html_quiz/html_quiz_policy.dart';
import 'package:daily_life_app/features/items/item_registry.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const quizPath = '/data/Library/html_quizzes/quiz.html';
  const quizUrl = 'file:///data/Library/html_quizzes/quiz.html';

  group('quizNavigationAllowed — allow', () {
    test('the quiz file itself', () {
      expect(quizNavigationAllowed(quizUrl, quizFilePath: quizPath), isTrue);
    });

    test('the quiz file itself with an uppercase FILE scheme', () {
      expect(
        quizNavigationAllowed('FILE:///data/Library/html_quizzes/quiz.html',
            quizFilePath: quizPath),
        isTrue,
      );
    });

    test('a sibling file inside the same html_quizzes directory', () {
      expect(
        quizNavigationAllowed('file:///data/Library/html_quizzes/style.css',
            quizFilePath: quizPath),
        isTrue,
      );
    });

    test('an asset in a subfolder of html_quizzes (quiz_files/app.js style)',
        () {
      expect(
        quizNavigationAllowed(
            'file:///data/Library/html_quizzes/quiz_files/app.js',
            quizFilePath: quizPath),
        isTrue,
      );
    });

    test('the quiz file passed as a file:// URL', () {
      expect(quizNavigationAllowed(quizUrl, quizFilePath: quizUrl), isTrue);
    });
  });

  group('quizNavigationAllowed — block', () {
    test('https', () {
      expect(
        quizNavigationAllowed('https://example.com/evil.html',
            quizFilePath: quizPath),
        isFalse,
      );
    });

    test('http', () {
      expect(
        quizNavigationAllowed('http://example.com/evil.html',
            quizFilePath: quizPath),
        isFalse,
      );
    });

    test('file:// outside the Library (/etc/passwd)', () {
      expect(
        quizNavigationAllowed('file:///etc/passwd', quizFilePath: quizPath),
        isFalse,
      );
    });

    test('file:// in a different directory', () {
      expect(
        quizNavigationAllowed('file:///data/Library/sources/secret.html',
            quizFilePath: quizPath),
        isFalse,
      );
    });

    test('javascript:', () {
      expect(
        quizNavigationAllowed('javascript:alert(1)', quizFilePath: quizPath),
        isFalse,
      );
    });

    test('data:', () {
      expect(
        quizNavigationAllowed('data:text/html,<h1>hi</h1>',
            quizFilePath: quizPath),
        isFalse,
      );
    });

    test('about:', () {
      expect(
        quizNavigationAllowed('about:blank', quizFilePath: quizPath),
        isFalse,
      );
    });

    test('URL-encoded traversal %2e%2e%2f escapes the quiz directory', () {
      expect(
        quizNavigationAllowed(
            'file:///data/Library/html_quizzes/%2e%2e%2fsources/secret.html',
            quizFilePath: quizPath),
        isFalse,
      );
      expect(
        quizNavigationAllowed(
            'file:///data/Library/html_quizzes/%2e%2e%2f%2e%2e%2fetc/passwd',
            quizFilePath: quizPath),
        isFalse,
      );
    });

    test('plain .. traversal escapes the quiz directory', () {
      expect(
        quizNavigationAllowed(
            'file:///data/Library/html_quizzes/../sources/secret.html',
            quizFilePath: quizPath),
        isFalse,
      );
    });

    test('empty and malformed URLs', () {
      expect(quizNavigationAllowed('', quizFilePath: quizPath), isFalse);
      expect(quizNavigationAllowed('not a url', quizFilePath: quizPath),
          isFalse);
    });
  });

  group('item registry — html_quiz', () {
    test('itemTypeDef(html_quiz) resolves to label HTML quiz', () {
      final def = itemTypeDef(ItemType.htmlQuiz);
      expect(def.key, 'html_quiz');
      expect(def.label, 'HTML quiz');
      expect(itemTypeDef('html_quiz').label, 'HTML quiz');
    });
  });
}
