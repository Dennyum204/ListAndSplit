import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/core/theme/app_theme.dart';
import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/domain/active_list_repository.dart';
import 'package:list_and_split/features/lists/presentation/active_list_members_screen.dart';
import 'package:list_and_split/features/lists/presentation/active_list_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

import '../../helpers/fakes.dart';

void main() {
  for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
        'owner manages accepted and pending access in ${themeMode.name}',
        (tester) async {
      final repository = _MembersWidgetRepository(isOwner: true);
      await _pump(tester, repository, themeMode: themeMode);

      expect(find.text('Owner User'), findsOneWidget);
      expect(find.text('Member User'), findsOneWidget);
      expect(find.text('Pending User'), findsOneWidget);
      expect(find.text('Eligible User'), findsOneWidget);
      expect(find.byKey(const Key('removeMember-member-1')), findsOneWidget);
      expect(
        find.byKey(const Key('transferOwnership-member-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('cancelInvitation-pending-1')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('inviteMember-eligible-1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('accepted member sees only accepted participants',
      (tester) async {
    final repository = _MembersWidgetRepository(isOwner: false);
    await _pump(tester, repository);

    expect(find.text('Owner User'), findsOneWidget);
    expect(find.text('Member User'), findsOneWidget);
    expect(find.text('Pending invitations'), findsNothing);
    expect(find.text('Pending User'), findsNothing);
    expect(find.text('Invite friends'), findsNothing);
    expect(find.byIcon(Icons.person_remove_outlined), findsNothing);
    expect(find.byIcon(Icons.manage_accounts_outlined), findsNothing);
    expect(repository.pendingCalls, 0);
    expect(repository.eligibleCalls, 0);
  });

  testWidgets('owner remove requires confirmation and uses access version',
      (tester) async {
    final repository = _MembersWidgetRepository(isOwner: true);
    await _pump(tester, repository);

    await tester.tap(find.byKey(const Key('removeMember-member-1')));
    await tester.pumpAndSettle();
    expect(find.text('Remove this member?'), findsOneWidget);
    expect(repository.removeCalls, 0);

    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(repository.removeCalls, 0);

    await tester.tap(find.byKey(const Key('removeMember-member-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmRemoveMemberButton')));
    await tester.pumpAndSettle();
    expect(repository.removeCalls, 1);
    expect(repository.lastRemoveVersion, 4);
    expect(find.byKey(const Key('participant-member-1')), findsNothing);
  });

  testWidgets('ownership transfer names the member and requires confirmation',
      (tester) async {
    final repository = _MembersWidgetRepository(isOwner: true);
    await _pump(tester, repository);

    await tester.tap(find.byKey(const Key('transferOwnership-member-1')));
    await tester.pumpAndSettle();
    expect(find.text('Transfer list ownership?'), findsOneWidget);
    expect(
      find.text(
        'Transfer ownership to Member User? They will become the sole owner and can rename, archive, delete, and manage members. You will remain a member.',
      ),
      findsOneWidget,
    );
    expect(repository.transferCalls, 0);

    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(repository.transferCalls, 0);

    await tester.tap(find.byKey(const Key('transferOwnership-member-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmTransferOwnershipButton')));
    await tester.pumpAndSettle();

    expect(repository.transferCalls, 1);
    expect(repository.lastTransferListVersion, 2);
    expect(repository.lastTransferAccessVersion, 4);
    expect(
      find.text('Ownership transferred. You remain a member.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('transferOwnership-owner-1')), findsNothing);
    expect(find.text('Pending invitations'), findsNothing);
  });

  testWidgets('capacity error is specific and controls become usable again',
      (tester) async {
    final repository = _MembersWidgetRepository(isOwner: true)
      ..inviteFailure = const ActiveListFailure(ActiveListFailureCode.capacity);
    await _pump(tester, repository);

    await tester.tap(find.byKey(const Key('inviteMember-eligible-1')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'This list is full. It can have at most 20 participants, including pending invitations.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('inviteMember-eligible-1')),
          )
          .onPressed,
      isNotNull,
    );
  });
}

class _MembersWidgetRepository extends FakeActiveListRepository {
  _MembersWidgetRepository({required bool isOwner}) {
    activeLists = [_summary(isOwner: isOwner)];
    participantsByList['list-1'] = [_owner, _member];
    pendingByList['list-1'] = [_pending];
    eligibleByList['list-1'] = [_eligible];
  }

  var pendingCalls = 0;
  var eligibleCalls = 0;
  var removeCalls = 0;
  int? lastRemoveVersion;
  var transferCalls = 0;
  int? lastTransferListVersion;
  int? lastTransferAccessVersion;
  ActiveListFailure? inviteFailure;

  @override
  Future<List<ActiveListAccessProfile>> listPendingInvitations(String listId) {
    pendingCalls += 1;
    return super.listPendingInvitations(listId);
  }

  @override
  Future<List<ActiveListAccessProfile>> listEligibleInvitees(String listId) {
    eligibleCalls += 1;
    return super.listEligibleInvitees(listId);
  }

  @override
  Future<int> inviteMember(
    String listId,
    String profileId, {
    int? expectedAccessVersion,
  }) async {
    final failure = inviteFailure;
    inviteFailure = null;
    if (failure != null) throw failure;
    return super.inviteMember(
      listId,
      profileId,
      expectedAccessVersion: expectedAccessVersion,
    );
  }

  @override
  Future<int> removeMember(
    String listId,
    String profileId, {
    required int expectedAccessVersion,
  }) {
    removeCalls += 1;
    lastRemoveVersion = expectedAccessVersion;
    return super.removeMember(
      listId,
      profileId,
      expectedAccessVersion: expectedAccessVersion,
    );
  }

  @override
  Future<ActiveListOwnershipTransferResult> transferOwnership(
    String listId,
    String profileId, {
    required int expectedListVersion,
    required int expectedAccessVersion,
  }) {
    transferCalls += 1;
    lastTransferListVersion = expectedListVersion;
    lastTransferAccessVersion = expectedAccessVersion;
    return super.transferOwnership(
      listId,
      profileId,
      expectedListVersion: expectedListVersion,
      expectedAccessVersion: expectedAccessVersion,
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  FakeActiveListRepository repository, {
  ThemeMode themeMode = ThemeMode.light,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        verifiedUserIdProvider.overrideWithValue('user-1'),
        activeListRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ActiveListMembersScreen(listId: 'list-1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ActiveListSummary _summary({required bool isOwner}) => ActiveListSummary(
      id: 'list-1',
      title: 'Shared trip',
      status: ActiveListStatus.active,
      version: 2,
      itemCount: 1,
      completedItemCount: 0,
      createdAt: DateTime.utc(2026, 7, 20, 8),
      updatedAt: DateTime.utc(2026, 7, 20, 9),
      archivedAt: null,
      isOwner: isOwner,
      ownerProfileId: isOwner ? null : 'owner-1',
      ownerUsername: isOwner ? null : 'owner_user',
      ownerDisplayName: isOwner ? null : 'Owner User',
      callerAccessVersion: isOwner ? null : 6,
    );

const _owner = ActiveListParticipant(
  profileId: 'owner-1',
  username: 'owner_user',
  displayName: 'Owner User',
  isOwner: true,
);
const _member = ActiveListParticipant(
  profileId: 'member-1',
  username: 'member_user',
  displayName: 'Member User',
  isOwner: false,
  accessVersion: 4,
);
const _pending = ActiveListAccessProfile(
  profileId: 'pending-1',
  username: 'pending_user',
  displayName: 'Pending User',
  accessVersion: 3,
);
const _eligible = ActiveListAccessProfile(
  profileId: 'eligible-1',
  username: 'eligible_user',
  displayName: 'Eligible User',
  accessVersion: 8,
);
