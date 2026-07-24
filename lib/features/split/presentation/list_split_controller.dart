import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/features/lists/domain/creation_request_id.dart';
import 'package:list_and_split/features/split/domain/list_split.dart';
import 'package:list_and_split/features/split/domain/list_split_repository.dart';

enum ListSplitMessage {
  enabled,
  currencyChanged,
  expenseCreated,
  expenseUpdated,
  expenseDeleted,
  settlementRecorded,
  settlementReversed,
  staleRefreshed,
  archivedReadOnly,
  unavailable,
  invalidInput,
  capacity,
  refreshFailed,
  operationFailed,
}

enum ListSplitMutationOutcome {
  succeeded,
  stale,
  archived,
  unavailable,
  invalid,
  capacity,
  failed,
}

extension ListSplitMutationOutcomePresentation on ListSplitMutationOutcome {
  bool get dismissesEditor => switch (this) {
        ListSplitMutationOutcome.succeeded ||
        ListSplitMutationOutcome.stale ||
        ListSplitMutationOutcome.archived ||
        ListSplitMutationOutcome.unavailable =>
          true,
        ListSplitMutationOutcome.invalid ||
        ListSplitMutationOutcome.capacity ||
        ListSplitMutationOutcome.failed =>
          false,
      };
}

class ListSplitState {
  const ListSplitState({
    required this.overview,
    this.settlementHistory = const AsyncData(ListSplitSettlementPage.empty()),
    this.isMutating = false,
    this.isLoadingMoreSettlements = false,
    this.message,
  });

  const ListSplitState.loading()
      : overview = const AsyncLoading(),
        settlementHistory = const AsyncData(ListSplitSettlementPage.empty()),
        isMutating = false,
        isLoadingMoreSettlements = false,
        message = null;

  final AsyncValue<ListSplitOverview> overview;
  final AsyncValue<ListSplitSettlementPage> settlementHistory;
  final bool isMutating;
  final bool isLoadingMoreSettlements;
  final ListSplitMessage? message;

  ListSplitState copyWith({
    AsyncValue<ListSplitOverview>? overview,
    AsyncValue<ListSplitSettlementPage>? settlementHistory,
    bool? isMutating,
    bool? isLoadingMoreSettlements,
    ListSplitMessage? message,
    bool clearMessage = false,
  }) {
    return ListSplitState(
      overview: overview ?? this.overview,
      settlementHistory: settlementHistory ?? this.settlementHistory,
      isMutating: isMutating ?? this.isMutating,
      isLoadingMoreSettlements:
          isLoadingMoreSettlements ?? this.isLoadingMoreSettlements,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class ListSplitController extends StateNotifier<ListSplitState> {
  ListSplitController(
    this._repository,
    this.listId, {
    required this.authenticatedProfileId,
    void Function()? invalidateLists,
    CreationRequestIdGenerator requestIdGenerator = secureCreationRequestId,
  })  : _invalidateLists = invalidateLists ?? _noop,
        _requestIdGenerator = requestIdGenerator,
        super(const ListSplitState.loading());

  final ListSplitRepository _repository;
  final String listId;
  final String authenticatedProfileId;
  final void Function() _invalidateLists;
  final CreationRequestIdGenerator _requestIdGenerator;
  int _loadGeneration = 0;
  bool _reconciliationPending = false;
  bool _pendingLoadReportsFailure = false;
  Completer<void>? _pendingLoadCompleter;

  String newExpenseRequestId() => _requestIdGenerator();

  String newSettlementRequestId() => _requestIdGenerator();

  Future<void> load() => _requestLoad(reportFailure: true);

  Future<void> reconcile() => _requestLoad(
        preserveMessage: true,
        reportFailure: false,
      );

  Future<void> refresh() => _requestLoad(reportFailure: true);

  Future<void> _requestLoad({
    bool preserveMessage = false,
    required bool reportFailure,
  }) {
    if (!state.isMutating) {
      return _load(
        preserveMessage: preserveMessage,
        reportFailure: reportFailure,
      );
    }
    _reconciliationPending = true;
    _pendingLoadReportsFailure |= reportFailure;
    return (_pendingLoadCompleter ??= Completer<void>()).future;
  }

  Future<ListSplitMutationOutcome> enable(SplitCurrency currency) {
    final overview = state.overview.valueOrNull;
    if (overview == null ||
        overview.enabled ||
        !overview.isOwner ||
        overview.listStatus != SplitListStatus.active) {
      return Future.value(_invalidOutcome());
    }
    return _mutate(
      () => _repository.enableSplit(
        listId,
        currency,
        expectedListVersion: overview.listVersion,
      ),
      ListSplitMessage.enabled,
      invalidateLists: true,
    );
  }

  Future<ListSplitMutationOutcome> changeCurrency(SplitCurrency currency) {
    final overview = state.overview.valueOrNull;
    final settings = overview?.settings;
    if (overview == null ||
        settings == null ||
        !overview.isOwner ||
        overview.listStatus != SplitListStatus.active ||
        overview.expenses.isNotEmpty ||
        state.settlementHistory.valueOrNull?.entries.isNotEmpty == true) {
      return Future.value(_invalidOutcome());
    }
    if (settings.currency == currency) {
      state = state.copyWith(clearMessage: true);
      return Future.value(ListSplitMutationOutcome.succeeded);
    }
    return _mutate(
      () => _repository.changeCurrency(
        listId,
        currency,
        expectedSplitVersion: settings.version,
      ),
      ListSplitMessage.currencyChanged,
    );
  }

  Future<ListSplitMutationOutcome> createExpense({
    required String description,
    required int amountMinor,
    required String payerParticipantId,
    required Iterable<String> beneficiaryParticipantIds,
    required String requestId,
  }) async {
    final overview = state.overview.valueOrNull;
    final settings = overview?.settings;
    final normalized = description.trim();
    final beneficiaryIds = _orderedUniqueIds(beneficiaryParticipantIds);
    if (overview == null ||
        settings == null ||
        !overview.writable ||
        overview.expenses.length >= splitExpenseCapacity ||
        !_validDescriptionAndAmount(normalized, amountMinor) ||
        requestId.isEmpty ||
        beneficiaryIds.isEmpty ||
        !_isEligible(overview, payerParticipantId) ||
        beneficiaryIds.any((id) => !_isEligible(overview, id))) {
      if (overview != null &&
          overview.expenses.length >= splitExpenseCapacity) {
        return _finishWith(
          ListSplitMessage.capacity,
          ListSplitMutationOutcome.capacity,
        );
      }
      return _invalidOutcome();
    }
    return _mutate(
      () => _repository.createExpense(
        listId,
        description: normalized,
        amountMinor: amountMinor,
        payerParticipantId: payerParticipantId,
        beneficiaryParticipantIds: beneficiaryIds,
        requestId: requestId,
        expectedSplitVersion: settings.version,
      ),
      ListSplitMessage.expenseCreated,
    );
  }

  Future<ListSplitMutationOutcome> updateExpense(
    ListSplitExpense expense, {
    required String description,
    required int amountMinor,
    required String payerParticipantId,
    required Iterable<String> beneficiaryParticipantIds,
  }) {
    final overview = state.overview.valueOrNull;
    final settings = overview?.settings;
    final currentExpense =
        overview == null ? null : _expenseById(overview, expense.id);
    final normalized = description.trim();
    final beneficiaryIds = _orderedUniqueIds(beneficiaryParticipantIds);
    if (overview == null ||
        settings == null ||
        currentExpense == null ||
        !overview.writable ||
        !_validDescriptionAndAmount(normalized, amountMinor) ||
        beneficiaryIds.isEmpty) {
      return Future.value(_invalidOutcome());
    }
    final payerAllowed = _isEligible(overview, payerParticipantId) ||
        payerParticipantId == currentExpense.payerParticipantId;
    final retainedBeneficiaryIds =
        currentExpense.beneficiaryParticipantIds.toSet();
    final beneficiariesAllowed = beneficiaryIds.every(
      (id) => _isEligible(overview, id) || retainedBeneficiaryIds.contains(id),
    );
    if (!payerAllowed || !beneficiariesAllowed) {
      return Future.value(_invalidOutcome());
    }
    return _mutate(
      () => _repository.updateExpense(
        listId,
        expense.id,
        description: normalized,
        amountMinor: amountMinor,
        payerParticipantId: payerParticipantId,
        beneficiaryParticipantIds: beneficiaryIds,
        expectedSplitVersion: settings.version,
        expectedExpenseVersion: expense.version,
      ),
      ListSplitMessage.expenseUpdated,
    );
  }

  Future<ListSplitMutationOutcome> deleteExpense(
    ListSplitExpense expense,
  ) {
    final overview = state.overview.valueOrNull;
    final settings = overview?.settings;
    if (overview == null ||
        settings == null ||
        !overview.writable ||
        _expenseById(overview, expense.id) == null) {
      return Future.value(_invalidOutcome());
    }
    return _mutate(
      () => _repository.deleteExpense(
        listId,
        expense.id,
        expectedSplitVersion: settings.version,
        expectedExpenseVersion: expense.version,
      ),
      ListSplitMessage.expenseDeleted,
    );
  }

  Future<ListSplitMutationOutcome> recordSettlement({
    required String payerParticipantId,
    required String recipientParticipantId,
    required int amountMinor,
    required String? note,
    required String requestId,
  }) {
    final overview = state.overview.valueOrNull;
    final settings = overview?.settings;
    final payer = overview?.participantById(payerParticipantId);
    final recipient = overview?.participantById(recipientParticipantId);
    final canonicalNote = note?.trim();
    final maximum = payer == null || recipient == null
        ? 0
        : (-payer.balanceMinor < recipient.balanceMinor
            ? -payer.balanceMinor
            : recipient.balanceMinor);
    if (overview == null ||
        settings == null ||
        !overview.writable ||
        payerParticipantId == recipientParticipantId ||
        payer?.balanceMinor == null ||
        payer!.balanceMinor >= 0 ||
        recipient?.balanceMinor == null ||
        recipient!.balanceMinor <= 0 ||
        amountMinor < 1 ||
        amountMinor > maximum ||
        requestId.isEmpty ||
        (canonicalNote != null &&
            canonicalNote.isNotEmpty &&
            canonicalNote.length > splitSettlementNoteMaxLength)) {
      return Future.value(_invalidOutcome());
    }
    return _mutate(
      () => _repository.recordSettlement(
        listId,
        payerParticipantId: payerParticipantId,
        recipientParticipantId: recipientParticipantId,
        amountMinor: amountMinor,
        note: canonicalNote == null || canonicalNote.isEmpty
            ? null
            : canonicalNote,
        requestId: requestId,
        expectedSplitVersion: settings.version,
      ),
      ListSplitMessage.settlementRecorded,
      refreshSettlementHistory: true,
    );
  }

  Future<ListSplitMutationOutcome> reverseSettlement(
    ListSplitSettlement settlement, {
    required String reason,
    required String requestId,
  }) {
    final overview = state.overview.valueOrNull;
    final settings = overview?.settings;
    final current = _settlementById(settlement.id);
    final canonicalReason = reason.trim();
    if (overview == null ||
        settings == null ||
        !overview.writable ||
        current == null ||
        current.isReversed ||
        !current.canReverse ||
        canonicalReason.isEmpty ||
        canonicalReason.length > splitSettlementReversalReasonMaxLength ||
        requestId.isEmpty) {
      return Future.value(_invalidOutcome());
    }
    return _mutate(
      () => _repository.reverseSettlement(
        listId,
        settlement.id,
        reason: canonicalReason,
        requestId: requestId,
        expectedSplitVersion: settings.version,
      ),
      ListSplitMessage.settlementReversed,
      refreshSettlementHistory: true,
    );
  }

  Future<void> loadMoreSettlements() async {
    final overview = state.overview.valueOrNull;
    final currentPage = state.settlementHistory.valueOrNull;
    final cursor = currentPage?.nextCursor;
    if (overview?.enabled != true ||
        cursor == null ||
        state.isMutating ||
        state.isLoadingMoreSettlements) {
      return;
    }
    final generation = _loadGeneration;
    final expectedSplitVersion = overview!.settings!.version;
    state = state.copyWith(isLoadingMoreSettlements: true, clearMessage: true);
    try {
      final nextPage = await _repository.listSettlements(
        listId,
        cursor: cursor,
      );
      if (!mounted) return;
      if (!_paginationIsCurrent(
        generation: generation,
        expectedSplitVersion: expectedSplitVersion,
        cursor: cursor,
      )) {
        state = state.copyWith(isLoadingMoreSettlements: false);
        return;
      }
      _validateSettlementPage(nextPage, overview);
      final existingIds = currentPage!.entries.map((entry) => entry.id).toSet();
      if (nextPage.entries.any((entry) => existingIds.contains(entry.id))) {
        throw const ListSplitFailure(ListSplitFailureCode.generic);
      }
      state = state.copyWith(
        settlementHistory: AsyncData(
          ListSplitSettlementPage(
            listId: currentPage.listId,
            currency: currentPage.currency,
            entries: List.unmodifiable([
              ...currentPage.entries,
              ...nextPage.entries,
            ]),
            nextCursor: nextPage.nextCursor,
          ),
        ),
        isLoadingMoreSettlements: false,
      );
    } on ListSplitFailure catch (failure) {
      if (!mounted) return;
      if (generation != _loadGeneration) {
        state = state.copyWith(isLoadingMoreSettlements: false);
        return;
      }
      state = state.copyWith(
        isLoadingMoreSettlements: false,
        message: failure.code == ListSplitFailureCode.unavailable
            ? ListSplitMessage.unavailable
            : ListSplitMessage.refreshFailed,
      );
      if (failure.code == ListSplitFailureCode.unavailable) {
        await _load(preserveMessage: true, reportFailure: true);
      }
    } catch (_) {
      if (!mounted) return;
      if (generation != _loadGeneration) {
        state = state.copyWith(isLoadingMoreSettlements: false);
        return;
      }
      state = state.copyWith(
        isLoadingMoreSettlements: false,
        message: ListSplitMessage.refreshFailed,
      );
    }
  }

  bool _paginationIsCurrent({
    required int generation,
    required int expectedSplitVersion,
    required ListSplitSettlementCursor cursor,
  }) {
    final currentOverview = state.overview.valueOrNull;
    final currentCursor = state.settlementHistory.valueOrNull?.nextCursor;
    return generation == _loadGeneration &&
        currentOverview?.settings?.version == expectedSplitVersion &&
        currentCursor?.createdAt == cursor.createdAt &&
        currentCursor?.id == cursor.id;
  }

  Future<ListSplitMutationOutcome> _mutate(
    Future<ListSplitOverview> Function() operation,
    ListSplitMessage successMessage, {
    bool invalidateLists = false,
    bool refreshSettlementHistory = false,
  }) async {
    if (state.isMutating) return ListSplitMutationOutcome.failed;
    ++_loadGeneration;
    state = state.copyWith(isMutating: true, clearMessage: true);
    try {
      final overview = await operation();
      if (!mounted) return ListSplitMutationOutcome.failed;
      var history = state.settlementHistory;
      if (refreshSettlementHistory) {
        history = await _loadSettlementHistory(overview);
        if (!mounted) return ListSplitMutationOutcome.failed;
      }
      state = ListSplitState(
        overview: AsyncData(overview),
        settlementHistory: history,
        message: successMessage,
      );
      if (invalidateLists) _invalidateLists();
      _drainReconciliation();
      return ListSplitMutationOutcome.succeeded;
    } on ListSplitFailure catch (failure) {
      if (!mounted) return ListSplitMutationOutcome.failed;
      final outcome = await _handleFailure(failure);
      _drainReconciliation();
      return outcome;
    } catch (_) {
      if (!mounted) return ListSplitMutationOutcome.failed;
      state = state.copyWith(
        isMutating: false,
        message: ListSplitMessage.operationFailed,
      );
      _drainReconciliation();
      return ListSplitMutationOutcome.failed;
    }
  }

  Future<ListSplitMutationOutcome> _handleFailure(
    ListSplitFailure failure,
  ) async {
    switch (failure.code) {
      case ListSplitFailureCode.stale:
        return _reloadThenFinish(
          ListSplitMessage.staleRefreshed,
          ListSplitMutationOutcome.stale,
        );
      case ListSplitFailureCode.archived:
        return _reloadThenFinish(
          ListSplitMessage.archivedReadOnly,
          ListSplitMutationOutcome.archived,
        );
      case ListSplitFailureCode.unavailable:
        state = ListSplitState(
          overview: AsyncError(failure, StackTrace.current),
          settlementHistory: state.settlementHistory,
          message: ListSplitMessage.unavailable,
        );
        return ListSplitMutationOutcome.unavailable;
      case ListSplitFailureCode.invalid:
        return _reloadThenFinish(
          ListSplitMessage.invalidInput,
          ListSplitMutationOutcome.invalid,
        );
      case ListSplitFailureCode.capacity:
        return _reloadThenFinish(
          ListSplitMessage.capacity,
          ListSplitMutationOutcome.capacity,
        );
      case ListSplitFailureCode.transport:
      case ListSplitFailureCode.generic:
        return _finishWith(
          ListSplitMessage.operationFailed,
          ListSplitMutationOutcome.failed,
        );
    }
  }

  Future<ListSplitMutationOutcome> _reloadThenFinish(
    ListSplitMessage message,
    ListSplitMutationOutcome outcome,
  ) async {
    final loaded = await _load(preserveMessage: true, reportFailure: true);
    if (!mounted) return ListSplitMutationOutcome.failed;
    if (state.message == ListSplitMessage.unavailable) {
      return ListSplitMutationOutcome.unavailable;
    }
    if (!loaded) return ListSplitMutationOutcome.failed;
    return _finishWith(message, outcome);
  }

  Future<bool> _load({
    bool preserveMessage = false,
    bool reportFailure = true,
  }) async {
    final generation = ++_loadGeneration;
    final cached = state.overview.valueOrNull;
    if (cached == null) state = const ListSplitState.loading();
    try {
      final overview = await _repository.getSplit(listId);
      if (!mounted || generation != _loadGeneration) return false;
      final settlementHistory = await _loadSettlementHistory(overview);
      if (!mounted || generation != _loadGeneration) return false;
      state = ListSplitState(
        overview: AsyncData(overview),
        settlementHistory: settlementHistory,
        message: preserveMessage ? state.message : null,
      );
      return true;
    } on ListSplitFailure catch (failure, stackTrace) {
      if (!mounted || generation != _loadGeneration) return false;
      if (failure.code == ListSplitFailureCode.unavailable) {
        state = ListSplitState(
          overview: AsyncError(failure, stackTrace),
          settlementHistory: state.settlementHistory,
          message: ListSplitMessage.unavailable,
        );
      } else {
        state = ListSplitState(
          overview: cached == null
              ? AsyncError(failure, stackTrace)
              : AsyncData(cached),
          message:
              reportFailure ? ListSplitMessage.refreshFailed : state.message,
          settlementHistory: state.settlementHistory,
        );
      }
      return false;
    } catch (error, stackTrace) {
      if (!mounted || generation != _loadGeneration) return false;
      state = ListSplitState(
        overview:
            cached == null ? AsyncError(error, stackTrace) : AsyncData(cached),
        message: reportFailure ? ListSplitMessage.refreshFailed : state.message,
        settlementHistory: state.settlementHistory,
      );
      return false;
    }
  }

  bool _validDescriptionAndAmount(String description, int amountMinor) =>
      description.isNotEmpty &&
      description.length <= splitExpenseDescriptionMaxLength &&
      amountMinor >= 1 &&
      amountMinor <= splitExpenseAmountMaxMinor;

  bool _isEligible(ListSplitOverview overview, String participantId) =>
      overview.participantById(participantId)?.isCurrent == true;

  List<String> _orderedUniqueIds(Iterable<String> participantIds) {
    final unique = participantIds.toSet().toList(growable: false)..sort();
    return unique;
  }

  ListSplitExpense? _expenseById(
    ListSplitOverview overview,
    String expenseId,
  ) {
    for (final expense in overview.expenses) {
      if (expense.id == expenseId) return expense;
    }
    return null;
  }

  ListSplitSettlement? _settlementById(String settlementId) {
    final page = state.settlementHistory.valueOrNull;
    if (page == null) return null;
    for (final settlement in page.entries) {
      if (settlement.id == settlementId) return settlement;
    }
    return null;
  }

  Future<AsyncValue<ListSplitSettlementPage>> _loadSettlementHistory(
    ListSplitOverview overview,
  ) async {
    if (!overview.enabled) {
      return AsyncData(
        ListSplitSettlementPage(
          listId: overview.listId,
          currency: null,
          entries: const [],
          nextCursor: null,
        ),
      );
    }
    try {
      final page = await _repository.listSettlements(listId);
      _validateSettlementPage(page, overview);
      return AsyncData(page);
    } on ListSplitFailure catch (failure, stackTrace) {
      if (failure.code == ListSplitFailureCode.unavailable) rethrow;
      final cached = state.settlementHistory.valueOrNull;
      if (failure.code == ListSplitFailureCode.transport &&
          cached != null &&
          cached.listId == overview.listId) {
        try {
          _validateSettlementPage(cached, overview);
          return AsyncData(cached);
        } on ListSplitFailure {
          // A projection for an older participant set is not safe to retain.
        }
      }
      return AsyncError(failure, stackTrace);
    } catch (error, stackTrace) {
      return AsyncError(error, stackTrace);
    }
  }

  void _validateSettlementPage(
    ListSplitSettlementPage page,
    ListSplitOverview overview,
  ) {
    final participantIds =
        overview.participants.map((participant) => participant.id).toSet();
    final hasForeignReference = page.entries.any(
      (settlement) =>
          !participantIds.contains(settlement.payerParticipantId) ||
          !participantIds.contains(settlement.recipientParticipantId) ||
          !participantIds.contains(settlement.recordedByParticipantId) ||
          (settlement.reversal != null &&
              !participantIds.contains(
                settlement.reversal!.reversedByParticipantId,
              )),
    );
    if (page.listId != overview.listId ||
        page.currency != overview.currency ||
        hasForeignReference) {
      throw const ListSplitFailure(ListSplitFailureCode.generic);
    }
  }

  ListSplitMutationOutcome _invalidOutcome() => _finishWith(
        ListSplitMessage.invalidInput,
        ListSplitMutationOutcome.invalid,
      );

  ListSplitMutationOutcome _finishWith(
    ListSplitMessage message,
    ListSplitMutationOutcome outcome,
  ) {
    state = state.copyWith(isMutating: false, message: message);
    return outcome;
  }

  void _drainReconciliation() {
    if (!_reconciliationPending || !mounted || state.isMutating) return;
    _reconciliationPending = false;
    final reportFailure = _pendingLoadReportsFailure;
    _pendingLoadReportsFailure = false;
    final completer = _pendingLoadCompleter;
    _pendingLoadCompleter = null;
    unawaited(
      _load(
        preserveMessage: true,
        reportFailure: reportFailure,
      ).whenComplete(() {
        if (completer?.isCompleted == false) completer!.complete();
      }),
    );
  }

  @override
  void dispose() {
    final completer = _pendingLoadCompleter;
    if (completer?.isCompleted == false) completer!.complete();
    super.dispose();
  }

  static void _noop() {}
}
