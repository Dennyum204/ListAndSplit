import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/lists/domain/general_note.dart';

void main() {
  const susana = ActiveListNoteMention(
    profileId: '22222222-2222-4222-8222-222222222222',
    username: 'susana_user',
    displayName: 'Susana',
  );

  group('General Note normalization', () {
    test('normalizes line endings, trims only the outside, and counts runes',
        () {
      const raw = ' \r\n  Olá 👋\rworld  \r\n ';

      expect(normalizeGeneralNoteText(raw), 'Olá 👋\nworld');
      expect(normalizedGeneralNoteOrNull(' \r\n '), isNull);
      expect(
        normalizeGeneralNoteText('\u00a0\u3000Shared context\u3000\u00a0'),
        'Shared context',
      );
      expect(generalNoteCodePointLength(' 👨‍👩‍👧‍👦 '), 7);
      expect(
        generalNoteCodePointLength('${List.filled(1999, 'a').join()}😀'),
        generalNoteMaximumCodePoints,
      );
    });

    test('projection enforces text/timestamp and mention invariants', () {
      final updatedAt = DateTime.utc(2026, 7, 25, 10);
      expect(
        ActiveListGeneralNote(
          listVersion: 3,
          text: 'Ask @susana_user',
          version: 2,
          updatedAt: updatedAt,
          mentions: const [susana],
        ).mentions,
        const [susana],
      );
      expect(
        () => ActiveListGeneralNote(
          listVersion: 3,
          text: null,
          version: 2,
          updatedAt: updatedAt,
        ),
        throwsArgumentError,
      );
      expect(
        () => ActiveListGeneralNote(
          listVersion: 3,
          text: 'Text',
          version: 2,
          updatedAt: null,
        ),
        throwsArgumentError,
      );
      expect(
        () => ActiveListGeneralNote(
          listVersion: 3,
          text: 'No matching token',
          version: 2,
          updatedAt: updatedAt,
          mentions: const [susana],
        ),
        throwsArgumentError,
      );
      final malformedMentionSets = <List<ActiveListNoteMention>>[
        const [
          susana,
          ActiveListNoteMention(
            profileId: '33333333-3333-4333-8333-333333333333',
            username: 'susana_user',
            displayName: 'Other Susana',
          ),
        ],
        const [
          ActiveListNoteMention(
            profileId: '22222222-2222-4222-8222-222222222222',
            username: 'susana_user',
            displayName: ' Susana',
          ),
        ],
        [
          ActiveListNoteMention(
            profileId: '22222222-2222-4222-8222-222222222222',
            username: 'susana_user',
            displayName: List.filled(51, 'x').join(),
          ),
        ],
        const [
          susana,
          ActiveListNoteMention(
            profileId: '22222222-2222-4222-8222-222222222222',
            username: 'other_user',
            displayName: 'Other User',
          ),
        ],
        const [
          susana,
          ActiveListNoteMention(
            profileId: '33333333-3333-4333-8333-333333333333',
            username: 'alpha_user',
            displayName: 'Alpha',
          ),
        ],
      ];
      for (final mentions in malformedMentionSets) {
        expect(
          () => ActiveListGeneralNote(
            listVersion: 3,
            text: 'Ask @susana_user and @alpha_user',
            version: 2,
            updatedAt: updatedAt,
            mentions: mentions,
          ),
          throwsArgumentError,
        );
      }
    });
  });

  group('General Note mention boundaries', () {
    test('matches case variants at punctuation and line boundaries', () {
      const text = 'Olá İ 👋 @SUSANA_USER,\n(@susana_user)! @susana_user';
      final occurrences = generalNoteMentionOccurrences(text, const [susana]);

      expect(occurrences, hasLength(3));
      expect(
        occurrences.map((match) => text.substring(match.start, match.end)),
        ['@SUSANA_USER', '@susana_user', '@susana_user'],
      );
      expect(
        occurrences.first.start,
        text.indexOf('@SUSANA_USER'),
        reason: 'Unicode case mapping before a token must not shift offsets.',
      );
    });

    test('rejects email-like, doubled-at, and partial username text', () {
      for (final text in [
        'name@susana_user',
        '@@susana_user',
        '@susana_user@example.test',
        '@susana_user_more',
        'x@susana_user!',
      ]) {
        expect(
          containsGeneralNoteMentionToken(text, susana.username),
          isFalse,
          reason: text,
        );
      }
      expect(
        containsGeneralNoteMentionToken(
          'Ask @susana_user; thanks',
          susana.username,
        ),
        isTrue,
      );
    });
  });

  group('General Note mention insertion', () {
    test('replaces the active fragment and adds space only at the end', () {
      final atEnd = insertGeneralNoteMention(
        text: 'Ask @su',
        selectionStart: 7,
        selectionEnd: 7,
        username: susana.username,
      )!;
      expect(atEnd.text, 'Ask @susana_user ');
      expect(atEnd.caretOffset, atEnd.text.length);

      final beforePunctuation = insertGeneralNoteMention(
        text: 'Olá 👋 @su, please',
        selectionStart: 'Olá 👋 @su'.length,
        selectionEnd: 'Olá 👋 @su'.length,
        username: susana.username,
      )!;
      expect(beforePunctuation.text, 'Olá 👋 @susana_user, please');
      expect(
        beforePunctuation.caretOffset,
        'Olá 👋 @susana_user'.length,
      );

      final beforeAnotherMention = insertGeneralNoteMention(
        text: '@su@other_user',
        selectionStart: 3,
        selectionEnd: 3,
        username: susana.username,
      )!;
      expect(beforeAnotherMention.text, '@susana_user @other_user');
    });

    test('finds fragments case-insensitively but rejects email fragments', () {
      expect(
        generalNoteMentionFragmentAt('Ask @Su', 7)!.query,
        'su',
      );
      expect(generalNoteMentionFragmentAt('mail@example', 12), isNull);
      expect(generalNoteMentionFragmentAt('@@sus', 5), isNull);
    });

    test('inserts at the active caret and rejects expanded selections', () {
      const text = 'First @su, then continue';
      const afterFragment = 9;
      final inserted = insertGeneralNoteMention(
        text: text,
        selectionStart: afterFragment,
        selectionEnd: afterFragment,
        username: susana.username,
      )!;

      expect(inserted.text, 'First @susana_user, then continue');
      expect(inserted.caretOffset, 'First @susana_user'.length);
      expect(
        insertGeneralNoteMention(
          text: text,
          selectionStart: 'First '.length,
          selectionEnd: afterFragment,
          username: susana.username,
        ),
        isNull,
      );
    });
  });
}
