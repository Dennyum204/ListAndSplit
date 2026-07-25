const generalNoteMaximumCodePoints = 2000;

final _generalNoteUsernamePattern = RegExp(r'^[a-z][a-z0-9_]{2,23}$');

String normalizeGeneralNoteText(String value) {
  return value.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
}

String? normalizedGeneralNoteOrNull(String value) {
  final normalized = normalizeGeneralNoteText(value);
  return normalized.isEmpty ? null : normalized;
}

int generalNoteCodePointLength(String value) {
  return normalizeGeneralNoteText(value).runes.length;
}

class ActiveListNoteMention {
  const ActiveListNoteMention({
    required this.profileId,
    required this.username,
    required this.displayName,
  });

  final String profileId;
  final String username;
  final String displayName;
}

class ActiveListGeneralNote {
  ActiveListGeneralNote({
    required this.listVersion,
    required this.text,
    required this.version,
    required this.updatedAt,
    List<ActiveListNoteMention> mentions = const [],
  }) : mentions = List.unmodifiable(mentions) {
    final profileIds = mentions.map((mention) => mention.profileId).toSet();
    final usernames = mentions.map((mention) => mention.username).toSet();
    if (listVersion < 1 ||
        version < 1 ||
        (text == null && mentions.isNotEmpty) ||
        ((text == null) != (updatedAt == null)) ||
        (text != null &&
            (text != normalizeGeneralNoteText(text!) ||
                text!.runes.length > generalNoteMaximumCodePoints)) ||
        profileIds.length != mentions.length ||
        usernames.length != mentions.length ||
        mentions.length > 20 ||
        mentions.any(
          (mention) =>
              !_generalNoteUsernamePattern.hasMatch(mention.username) ||
              mention.displayName.trim() != mention.displayName ||
              mention.displayName.runes.isEmpty ||
              mention.displayName.runes.length > 50 ||
              !containsGeneralNoteMentionToken(text ?? '', mention.username),
        ) ||
        !_areGeneralNoteMentionsOrdered(mentions)) {
      throw ArgumentError('invalid General Note projection');
    }
  }

  const ActiveListGeneralNote.empty()
      : listVersion = 1,
        text = null,
        version = 1,
        updatedAt = null,
        mentions = const [];

  final int listVersion;
  final String? text;
  final int version;
  final DateTime? updatedAt;
  final List<ActiveListNoteMention> mentions;

  Set<String> get mentionedProfileIds =>
      mentions.map((mention) => mention.profileId).toSet();
}

class GeneralNoteMentionFragment {
  const GeneralNoteMentionFragment({
    required this.start,
    required this.end,
    required this.query,
  });

  final int start;
  final int end;
  final String query;
}

class GeneralNoteMentionInsertion {
  const GeneralNoteMentionInsertion({
    required this.text,
    required this.caretOffset,
  });

  final String text;
  final int caretOffset;
}

class GeneralNoteMentionOccurrence {
  const GeneralNoteMentionOccurrence({
    required this.start,
    required this.end,
    required this.mention,
  });

  final int start;
  final int end;
  final ActiveListNoteMention mention;
}

GeneralNoteMentionFragment? generalNoteMentionFragmentAt(
  String text,
  int caretOffset,
) {
  if (caretOffset < 0 || caretOffset > text.length) return null;
  var at = caretOffset - 1;
  while (at >= 0 && _isUsernameCodeUnit(text.codeUnitAt(at))) {
    at -= 1;
  }
  if (at < 0 || text.codeUnitAt(at) != 0x40) return null;
  if (at > 0 && !_isMentionBoundary(text.codeUnitAt(at - 1))) return null;
  final query = text.substring(at + 1, caretOffset);
  if (query.length > 24 ||
      query.codeUnits.any((unit) => !_isUsernameCodeUnit(unit))) {
    return null;
  }
  return GeneralNoteMentionFragment(
    start: at,
    end: caretOffset,
    query: query.toLowerCase(),
  );
}

GeneralNoteMentionInsertion? insertGeneralNoteMention({
  required String text,
  required int selectionStart,
  required int selectionEnd,
  required String username,
}) {
  if (!_generalNoteUsernamePattern.hasMatch(username) ||
      selectionStart < 0 ||
      selectionEnd < selectionStart ||
      selectionEnd > text.length) {
    return null;
  }
  final fragment = generalNoteMentionFragmentAt(text, selectionStart);
  if (fragment == null || selectionStart != selectionEnd) return null;
  var replacementEnd = fragment.end;
  while (replacementEnd < text.length &&
      _isUsernameCodeUnit(text.codeUnitAt(replacementEnd))) {
    replacementEnd += 1;
  }
  final needsSpace =
      replacementEnd == text.length || text.codeUnitAt(replacementEnd) == 0x40;
  final replacement = '@$username${needsSpace ? ' ' : ''}';
  return GeneralNoteMentionInsertion(
    text: text.replaceRange(fragment.start, replacementEnd, replacement),
    caretOffset: fragment.start + replacement.length,
  );
}

bool containsGeneralNoteMentionToken(String text, String username) {
  return generalNoteMentionOccurrences(
    text,
    [
      ActiveListNoteMention(
        profileId: '00000000-0000-4000-8000-000000000000',
        username: username,
        displayName: username,
      ),
    ],
  ).isNotEmpty;
}

List<GeneralNoteMentionOccurrence> generalNoteMentionOccurrences(
  String text,
  Iterable<ActiveListNoteMention> mentions,
) {
  final matches = <GeneralNoteMentionOccurrence>[];
  for (final mention in mentions) {
    if (!_generalNoteUsernamePattern.hasMatch(mention.username)) continue;
    final token = '@${mention.username}';
    var start = 0;
    while (start <= text.length - token.length) {
      var found = -1;
      for (var candidate = start;
          candidate <= text.length - token.length;
          candidate += 1) {
        if (_matchesAsciiCaseInsensitiveAt(text, token, candidate)) {
          found = candidate;
          break;
        }
      }
      if (found < 0) break;
      final end = found + token.length;
      final beforeIsBoundary =
          found == 0 || _isMentionBoundary(text.codeUnitAt(found - 1));
      final afterIsBoundary =
          end == text.length || _isMentionBoundary(text.codeUnitAt(end));
      if (beforeIsBoundary && afterIsBoundary) {
        matches.add(
          GeneralNoteMentionOccurrence(
            start: found,
            end: end,
            mention: mention,
          ),
        );
      }
      start = found + token.length;
    }
  }
  matches.sort((left, right) {
    final startOrder = left.start.compareTo(right.start);
    return startOrder != 0 ? startOrder : left.end.compareTo(right.end);
  });
  return List.unmodifiable(matches);
}

bool _isMentionBoundary(int codeUnit) {
  return codeUnit != 0x40 && !_isUsernameCodeUnit(codeUnit);
}

bool _isUsernameCodeUnit(int codeUnit) {
  return (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
      (codeUnit >= 0x61 && codeUnit <= 0x7a) ||
      (codeUnit >= 0x30 && codeUnit <= 0x39) ||
      codeUnit == 0x5f;
}

bool _matchesAsciiCaseInsensitiveAt(
  String text,
  String lowercaseToken,
  int offset,
) {
  for (var index = 0; index < lowercaseToken.length; index += 1) {
    final actual = text.codeUnitAt(offset + index);
    final expected = lowercaseToken.codeUnitAt(index);
    final folded = actual >= 0x41 && actual <= 0x5a ? actual + 0x20 : actual;
    if (folded != expected) return false;
  }
  return true;
}

bool _areGeneralNoteMentionsOrdered(List<ActiveListNoteMention> mentions) {
  for (var index = 1; index < mentions.length; index += 1) {
    final previous = mentions[index - 1];
    final current = mentions[index];
    final usernameOrder = previous.username.compareTo(current.username);
    if (usernameOrder > 0 ||
        (usernameOrder == 0 &&
            previous.profileId.compareTo(current.profileId) >= 0)) {
      return false;
    }
  }
  return true;
}
