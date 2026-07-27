import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/templates/domain/friend_public_template_feed_repository.dart';
import 'package:list_and_split/features/templates/domain/public_template.dart';
import 'package:list_and_split/features/templates/domain/public_template_repository.dart';
import 'package:list_and_split/features/templates/presentation/friend_public_template_feed_controller.dart';

void main() {
  test('initial load and explicit paging deduplicate live boundary rows',
      () async {
    final repository = _FakeFriendFeedRepository()
      ..outcomes.add(
        _page(
          [_entry(_firstTemplateId), _entry(_secondTemplateId)],
          nextCursor: _cursor,
        ),
      )
      ..outcomes.add(
        _page(
          [_entry(_secondTemplateId), _entry(_thirdTemplateId)],
        ),
      );
    final controller = _controller(repository);

    await controller.load();
    await controller.loadMore();

    expect(
      controller.state.page.value!.entries.map((entry) => entry.template.id),
      [_firstTemplateId, _secondTemplateId, _thirdTemplateId],
    );
    expect(controller.state.page.value!.nextCursor, isNull);
    expect(repository.cursors, [null, _cursor]);
    controller.dispose();
  });

  test('initial error is retryable and empty success is neutral', () async {
    final repository = _FakeFriendFeedRepository()
      ..outcomes.add(
        const PublicTemplateFailure(PublicTemplateFailureCode.transport),
      )
      ..outcomes.add(_page(const []));
    final controller = _controller(repository);

    await controller.load();
    expect(controller.state.page, isA<AsyncError<FriendPublicTemplatePage>>());
    expect(controller.state.message, isNull);

    await controller.load();
    expect(controller.state.page.value!.entries, isEmpty);
    expect(controller.state.message, isNull);
    controller.dispose();
  });

  test('refresh failure retains cached rows and emits one retryable message',
      () async {
    final repository = _FakeFriendFeedRepository()
      ..outcomes.add(_page([_entry(_firstTemplateId)]))
      ..outcomes.add(StateError('offline'))
      ..outcomes.add(_page([_entry(_secondTemplateId)]));
    final controller = _controller(repository);
    await controller.load();

    await controller.load();
    expect(
      controller.state.page.value!.entries.single.template.id,
      _firstTemplateId,
    );
    expect(
      controller.state.message,
      FriendPublicTemplateFeedMessage.refreshFailed,
    );
    expect(controller.state.isRefreshing, isFalse);

    await controller.load();
    expect(
      controller.state.page.value!.entries.single.template.id,
      _secondTemplateId,
    );
    expect(controller.state.message, isNull);
    controller.dispose();
  });

  test('load-more failure retains rows and explicit retry advances', () async {
    final repository = _FakeFriendFeedRepository()
      ..outcomes.add(
        _page([_entry(_firstTemplateId)], nextCursor: _cursor),
      )
      ..outcomes.add(
        const PublicTemplateFailure(PublicTemplateFailureCode.transport),
      )
      ..outcomes.add(_page([_entry(_secondTemplateId)]));
    final controller = _controller(repository);
    await controller.load();

    await controller.loadMore();
    expect(controller.state.loadMoreFailed, isTrue);
    expect(
      controller.state.message,
      FriendPublicTemplateFeedMessage.loadMoreFailed,
    );
    expect(
      controller.state.page.value!.entries.single.template.id,
      _firstTemplateId,
    );

    await controller.loadMore();
    expect(controller.state.loadMoreFailed, isFalse);
    expect(
      controller.state.page.value!.entries.map((entry) => entry.template.id),
      [_firstTemplateId, _secondTemplateId],
    );
    controller.dispose();
  });

  test('repeated actions are guarded and invalidations coalesce after request',
      () async {
    final first = Completer<FriendPublicTemplatePage>();
    final repository = _FakeFriendFeedRepository();
    repository.handler = (_, __) => first.future;
    repository.outcomes.add(_page([_entry(_secondTemplateId)]));
    final controller = _controller(repository);

    final loading = controller.load();
    final repeated = controller.load();
    final reconcileOne = controller.reconcile();
    final reconcileTwo = controller.reconcile();
    await Future.wait([repeated, reconcileOne, reconcileTwo]);
    expect(repository.calls, 1);

    repository.handler = null;
    first.complete(_page([_entry(_firstTemplateId)]));
    await loading;
    await pumpEventQueue();

    expect(repository.calls, 2);
    expect(
      controller.state.page.value!.entries.single.template.id,
      _secondTemplateId,
    );
    controller.dispose();
  });

  test('late completion after disposal cannot update controller state',
      () async {
    final completion = Completer<FriendPublicTemplatePage>();
    final repository = _FakeFriendFeedRepository()
      ..handler = (_, __) => completion.future;
    final controller = _controller(repository);

    final loading = controller.load();
    controller.dispose();
    completion.complete(_page([_entry(_firstTemplateId)]));

    await loading;
    expect(repository.calls, 1);
  });

  test('two mounted account projections reconcile independently', () async {
    final firstRepository = _FakeFriendFeedRepository()
      ..outcomes.add(_page([_entry(_firstTemplateId)]))
      ..outcomes.add(_page([_entry(_secondTemplateId)]));
    final secondRepository = _FakeFriendFeedRepository()
      ..outcomes.add(_page([_entry(_secondTemplateId)]))
      ..outcomes.add(_page([_entry(_thirdTemplateId)]));
    final first = _controller(firstRepository);
    final second = _controller(secondRepository);

    await Future.wait([first.load(), second.load()]);
    await Future.wait([first.reconcile(), second.reconcile()]);

    expect(
      first.state.page.value!.entries.single.template.id,
      _secondTemplateId,
    );
    expect(
      second.state.page.value!.entries.single.template.id,
      _thirdTemplateId,
    );
    expect(firstRepository.calls, 2);
    expect(secondRepository.calls, 2);
    first.dispose();
    second.dispose();
  });
}

FriendPublicTemplateFeedController _controller(
  _FakeFriendFeedRepository repository,
) {
  return FriendPublicTemplateFeedController(
    repository,
    hasAuthenticatedUser: true,
  );
}

class _FakeFriendFeedRepository implements FriendPublicTemplateFeedRepository {
  final Queue<Object> outcomes = Queue();
  final List<PublicTemplateCursor?> cursors = [];
  Future<FriendPublicTemplatePage> Function(
    int pageSize,
    PublicTemplateCursor? cursor,
  )? handler;
  int calls = 0;

  @override
  Future<FriendPublicTemplatePage> listFriendFeed({
    int pageSize = 20,
    PublicTemplateCursor? cursor,
  }) async {
    calls += 1;
    cursors.add(cursor);
    final activeHandler = handler;
    if (activeHandler != null) return activeHandler(pageSize, cursor);
    final outcome = outcomes.removeFirst();
    if (outcome is FriendPublicTemplatePage) return outcome;
    throw outcome;
  }
}

FriendPublicTemplatePage _page(
  List<FriendPublicTemplateEntry> entries, {
  PublicTemplateCursor? nextCursor,
}) {
  return FriendPublicTemplatePage(
    entries: entries,
    nextCursor: nextCursor,
  );
}

FriendPublicTemplateEntry _entry(String templateId) {
  return FriendPublicTemplateEntry(
    profile: const PublicTemplateProfile(
      id: _profileId,
      username: 'public_friend',
      displayName: 'Public Friend',
    ),
    template: PublicTemplateSummary(
      id: templateId,
      name: 'Public kit',
      version: 1,
      itemCount: 0,
      publishedAt: DateTime.utc(2026, 7, 27, 12),
    ),
  );
}

final _cursor = PublicTemplateCursor(
  publishedAt: DateTime.utc(2026, 7, 27, 12),
  templateId: _secondTemplateId,
);

const _profileId = '11111111-1111-4111-8111-111111111111';
const _firstTemplateId = '22222222-2222-4222-8222-222222222222';
const _secondTemplateId = '33333333-3333-4333-8333-333333333333';
const _thirdTemplateId = '44444444-4444-4444-8444-444444444444';
