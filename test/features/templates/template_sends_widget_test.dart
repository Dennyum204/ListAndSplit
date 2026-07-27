import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/core/theme/app_theme.dart';
import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/notifications/presentation/notification_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/templates/domain/template_send.dart';
import 'package:list_and_split/features/templates/domain/template_send_repository.dart';
import 'package:list_and_split/features/templates/presentation/template_send_providers.dart';
import 'package:list_and_split/features/templates/presentation/template_send_screens.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

import '../../helpers/fakes.dart';

void main() {
  testWidgets('Received and Sent render privacy-safe persistent projections',
      (tester) async {
    final repository = _WidgetTemplateSendRepository();
    await _pump(
      tester,
      repository: repository,
      child: const SharedTemplateSendsScreen(),
    );

    expect(find.text('Beach trip'), findsOneWidget);
    expect(find.text('From Sender User (@sender_user)'), findsOneWidget);
    expect(find.text('Pending'), findsWidgets);
    expect(find.textContaining('accepted_template'), findsNothing);

    await tester.tap(find.text('Sent'));
    await tester.pumpAndSettle();

    expect(find.text('Cabin list'), findsOneWidget);
    expect(find.text('To Friend User (@friend_user)'), findsOneWidget);
    expect(find.byTooltip('Revoke'), findsOneWidget);
    expect(find.textContaining('accepted_template'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('revoke requires confirmation and terminal row is not actionable',
      (tester) async {
    final repository = _WidgetTemplateSendRepository();
    await _pump(
      tester,
      repository: repository,
      child: const SharedTemplateSendsScreen(),
    );
    await tester.tap(find.text('Sent'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Revoke'));
    await tester.pumpAndSettle();

    expect(find.text('Revoke this invitation?'), findsOneWidget);
    expect(repository.revokeCalls, 0);
    await tester.tap(
      find.byKey(const Key('confirmRevokeTemplateSendButton')),
    );
    await tester.pumpAndSettle();

    expect(repository.revokeCalls, 1);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('Revoked'), findsOneWidget);
    expect(find.byTooltip('Revoke'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'blank received snapshot accepts once and offers its private copy',
      (tester) async {
    final repository = _WidgetTemplateSendRepository();
    await _pump(
      tester,
      repository: repository,
      child: const ReceivedTemplateSendScreen(templateSendId: _receivedId),
    );

    expect(find.byKey(const Key('templateSendEmptySnapshot')), findsOneWidget);
    expect(find.byKey(const Key('acceptTemplateSendButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('acceptTemplateSendButton')));
    await tester.tap(find.byKey(const Key('acceptTemplateSendButton')));
    await tester.pumpAndSettle();

    expect(repository.acceptCalls, 1);
    expect(find.byKey(const Key('openAcceptedTemplateButton')), findsOneWidget);
    expect(find.byKey(const Key('acceptTemplateSendButton')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('capacity rejection stops progress and leaves invitation pending',
      (tester) async {
    final repository = _WidgetTemplateSendRepository()
      ..acceptFailure = const TemplateSendFailure(
        TemplateSendFailureCode.capacity,
      );
    await _pump(
      tester,
      repository: repository,
      child: const ReceivedTemplateSendScreen(templateSendId: _receivedId),
    );

    await tester.tap(find.byKey(const Key('acceptTemplateSendButton')));
    await tester.pumpAndSettle();

    expect(find.textContaining('already have 200 templates'), findsOneWidget);
    expect(find.byKey(const Key('acceptTemplateSendButton')), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('acceptTemplateSendButton')),
    );
    expect(button.onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a 200-item immutable snapshot renders and remains scrollable',
      (tester) async {
    final repository = _WidgetTemplateSendRepository()
      ..detail = _receivedDetailWithItems(200);
    await _pump(
      tester,
      repository: repository,
      child: const ReceivedTemplateSendScreen(templateSendId: _receivedId),
    );

    expect(find.byKey(const ValueKey('templateSendItem-1')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('templateSendItem-200')),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey('templateSendItem-200')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'send dialog shows immutable snapshot and blocks rapid submission',
      (tester) async {
    final repository = _WidgetTemplateSendRepository();
    repository.sendCompleter = Completer<TemplateSendMutationResult>();
    await _pump(
      tester,
      repository: repository,
      child: const _SendDialogLauncher(),
    );
    await tester.tap(find.byKey(const Key('openSendDialogButton')));
    await tester.pumpAndSettle();

    expect(find.text('Snapshot to send'), findsOneWidget);
    expect(find.text('Coffee'), findsOneWidget);
    expect(find.text('1.5'), findsOneWidget);
    await tester.tap(find.byKey(const Key('templateSendRecipientField')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('@friend_user').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmTemplateSendButton')));
    await tester.tap(find.byKey(const Key('confirmTemplateSendButton')));
    await tester.pump();

    expect(repository.sendCalls, 1);
    repository.sendCompleter!.complete(
      _mutation(TemplateSendState.pending, _receivedId),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(repository.lastRequestId, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared area remains usable in dark mode at 200 percent text',
      (tester) async {
    await _pump(
      tester,
      repository: _WidgetTemplateSendRepository(),
      child: const SharedTemplateSendsScreen(),
      themeMode: ThemeMode.dark,
      textScaleFactor: 2,
    );

    expect(find.text('Shared templates'), findsOneWidget);
    expect(find.text('Beach trip'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _SendDialogLauncher extends StatelessWidget {
  const _SendDialogLauncher();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          key: const Key('openSendDialogButton'),
          onPressed: () => showTemplateSendDialog(
            context,
            TemplateSendPreview(
              templateId: _sourceId,
              templateVersion: 4,
              name: 'Beach trip',
              items: [
                TemplateSendPreviewItem(
                  name: 'Coffee',
                  quantity: ListQuantity.fromThousandths(1500),
                ),
              ],
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    );
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required _WidgetTemplateSendRepository repository,
  required Widget child,
  ThemeMode themeMode = ThemeMode.light,
  double textScaleFactor = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        verifiedUserIdProvider.overrideWithValue(_userId),
        templateSendRepositoryProvider.overrideWithValue(repository),
        notificationRepositoryProvider.overrideWithValue(
          FakeNotificationRepository(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, widget) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScaleFactor),
          ),
          child: widget!,
        ),
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _WidgetTemplateSendRepository implements TemplateSendRepository {
  _WidgetTemplateSendRepository()
      : detail = _receivedDetail(TemplateSendState.pending);

  ReceivedTemplateSendDetail detail;
  TemplateSendFailure? acceptFailure;
  Completer<TemplateSendMutationResult>? sendCompleter;
  int sendCalls = 0;
  int acceptCalls = 0;
  int revokeCalls = 0;
  String? lastRequestId;
  var sentState = TemplateSendState.pending;

  @override
  Future<List<TemplateSendProfile>> listEligibleRecipients(
    String templateId, {
    int pageSize = 20,
    TemplateSendRecipientCursor? cursor,
  }) async =>
      const [
        TemplateSendProfile(
          id: _friendId,
          username: 'friend_user',
          displayName: 'Friend User',
        ),
      ];

  @override
  Future<TemplateSendMutationResult> sendTemplate(
    String templateId,
    String recipientProfileId, {
    required int expectedTemplateVersion,
    required String requestId,
  }) {
    sendCalls += 1;
    lastRequestId = requestId;
    return sendCompleter?.future ??
        Future.value(_mutation(TemplateSendState.pending, _receivedId));
  }

  @override
  Future<List<ReceivedTemplateSendSummary>> listReceived({
    TemplateSendHistoryFilter filter = TemplateSendHistoryFilter.pending,
    int pageSize = 20,
    TemplateSendCursor? cursor,
  }) async {
    if (filter == TemplateSendHistoryFilter.history) return const [];
    return [_receivedSummary(TemplateSendState.pending)];
  }

  @override
  Future<List<SentTemplateSendSummary>> listSent({
    TemplateSendHistoryFilter filter = TemplateSendHistoryFilter.pending,
    int pageSize = 20,
    TemplateSendCursor? cursor,
  }) async {
    final isPending = sentState == TemplateSendState.pending;
    if ((filter == TemplateSendHistoryFilter.pending) != isPending) {
      return const [];
    }
    return [_sentSummary(sentState)];
  }

  @override
  Future<ReceivedTemplateSendDetail> getReceived(
    String templateSendId,
  ) async =>
      detail;

  @override
  Future<TemplateSendMutationResult> accept(
    String templateSendId, {
    required int expectedVersion,
    required String requestId,
  }) async {
    acceptCalls += 1;
    if (acceptFailure != null) throw acceptFailure!;
    detail = _receivedDetail(
      TemplateSendState.accepted,
      acceptedTemplateId: _acceptedTemplateId,
    );
    return _mutation(
      TemplateSendState.accepted,
      _receivedId,
      acceptedTemplateId: _acceptedTemplateId,
    );
  }

  @override
  Future<TemplateSendMutationResult> decline(
    String templateSendId, {
    required int expectedVersion,
    required String requestId,
  }) async {
    detail = _receivedDetail(TemplateSendState.declined);
    return _mutation(TemplateSendState.declined, _receivedId);
  }

  @override
  Future<TemplateSendMutationResult> revoke(
    String templateSendId, {
    required int expectedVersion,
    required String requestId,
  }) async {
    revokeCalls += 1;
    sentState = TemplateSendState.revoked;
    return _mutation(TemplateSendState.revoked, _sentId);
  }
}

ReceivedTemplateSendDetail _receivedDetail(
  TemplateSendState state, {
  String? acceptedTemplateId,
}) {
  return ReceivedTemplateSendDetail(
    summary: _receivedSummary(state),
    acceptedTemplateId: acceptedTemplateId,
    items: const [],
  );
}

ReceivedTemplateSendDetail _receivedDetailWithItems(int count) {
  return ReceivedTemplateSendDetail(
    summary: ReceivedTemplateSendSummary(
      id: _receivedId,
      sender: const TemplateSendProfile(
        id: _senderId,
        username: 'sender_user',
        displayName: 'Sender User',
      ),
      snapshotName: 'Full template',
      itemCount: count,
      state: TemplateSendState.pending,
      version: 1,
      createdAt: DateTime.utc(2026, 7, 27, 8),
      stateChangedAt: DateTime.utc(2026, 7, 27, 8),
    ),
    acceptedTemplateId: null,
    items: [
      for (var index = 1; index <= count; index += 1)
        TemplateSendSnapshotItem(
          name: 'Item $index',
          quantity: ListQuantity.one,
          position: index,
        ),
    ],
  );
}

ReceivedTemplateSendSummary _receivedSummary(TemplateSendState state) {
  return ReceivedTemplateSendSummary(
    id: _receivedId,
    sender: const TemplateSendProfile(
      id: _senderId,
      username: 'sender_user',
      displayName: 'Sender User',
    ),
    snapshotName: 'Beach trip',
    itemCount: 0,
    state: state,
    version: state == TemplateSendState.pending ? 1 : 2,
    createdAt: DateTime.utc(2026, 7, 27, 8),
    stateChangedAt: DateTime.utc(2026, 7, 27, 8),
  );
}

SentTemplateSendSummary _sentSummary(TemplateSendState state) {
  return SentTemplateSendSummary(
    id: _sentId,
    recipient: const TemplateSendProfile(
      id: _friendId,
      username: 'friend_user',
      displayName: 'Friend User',
    ),
    snapshotName: 'Cabin list',
    itemCount: 200,
    state: state,
    version: state == TemplateSendState.pending ? 1 : 2,
    createdAt: DateTime.utc(2026, 7, 27, 8),
    stateChangedAt: DateTime.utc(2026, 7, 27, 8),
  );
}

TemplateSendMutationResult _mutation(
  TemplateSendState state,
  String id, {
  String? acceptedTemplateId,
}) {
  return TemplateSendMutationResult(
    id: id,
    state: state,
    version: state == TemplateSendState.pending ? 1 : 2,
    stateChangedAt: DateTime.utc(2026, 7, 27, 8),
    acceptedTemplateId: acceptedTemplateId,
    snapshotName: state == TemplateSendState.pending ? 'Beach trip' : null,
    itemCount: state == TemplateSendState.pending ? 1 : null,
    createdAt: state == TemplateSendState.pending
        ? DateTime.utc(2026, 7, 27, 8)
        : null,
  );
}

const _userId = '11111111-1111-4111-8111-111111111111';
const _sourceId = '22222222-2222-4222-8222-222222222222';
const _senderId = '33333333-3333-4333-8333-333333333333';
const _friendId = '44444444-4444-4444-8444-444444444444';
const _receivedId = '55555555-5555-4555-8555-555555555555';
const _sentId = '66666666-6666-4666-8666-666666666666';
const _acceptedTemplateId = '77777777-7777-4777-8777-777777777777';
