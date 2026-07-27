import 'dart:async';
import 'dart:collection';

import 'package:list_and_split/features/templates/domain/friend_public_template_feed_repository.dart';
import 'package:list_and_split/features/templates/domain/public_template.dart';

class FakeFriendPublicTemplateFeedRepository
    implements FriendPublicTemplateFeedRepository {
  final Queue<Object> outcomes = Queue();
  final List<PublicTemplateCursor?> cursors = [];
  Completer<FriendPublicTemplatePage>? completer;
  int calls = 0;

  @override
  Future<FriendPublicTemplatePage> listFriendFeed({
    int pageSize = 20,
    PublicTemplateCursor? cursor,
  }) async {
    calls += 1;
    cursors.add(cursor);
    final pending = completer;
    if (pending != null) return pending.future;
    final outcome = outcomes.removeFirst();
    if (outcome is FriendPublicTemplatePage) return outcome;
    throw outcome;
  }
}
