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
    this.isMutating = false,
    this.message,
  });

  const ListSplitState.loading()
      : overview = const AsyncLoading(),
        isMutating = false,
        message = null;

  final AsyncValue<ListSplitOverview> overview;
  final bool isMutating;
  final ListSplitMessage? message;

  ListSplitState copyWith({
    AsyncValue<ListSplitOverview>? overview,
    bool? isMutating,
    ListSplitMessage? message,
    bool clearMessage = false,
  }) {
    return ListSplitState(
      overview: overview ?? this.overview,
      isMutating: isMutating ?? this.isMutating,
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
        overview.expenses.isNotEmpty) {
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

  Future<ListSplitMutationOutcome> _mutate(
    Future<ListSplitOverview> Function() operation,
    ListSplitMessage successMessage, {
    bool invalidateLists = false,
  }) async {
    if (state.isMutating) return ListSplitMutationOutcome.failed;
    ++_loadGeneration;
    state = state.copyWith(isMutating: true, clearMessage: true);
    try {
      final overview = await operation();
      if (!mounted) return ListSplitMutationOutcome.failed;
      state = ListSplitState(
        overview: AsyncData(overview),
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
      state = ListSplitState(
        overview: AsyncData(overview),
        message: preserveMessage ? state.message : null,
      );
      return true;
    } on ListSplitFailure catch (failure, stackTrace) {
      if (!mounted || generation != _loadGeneration) return false;
      if (failure.code == ListSplitFailureCode.unavailable) {
        state = ListSplitState(
          overview: AsyncError(failure, stackTrace),
          message: ListSplitMessage.unavailable,
        );
      } else {
        state = ListSplitState(
          overview: cached == null
              ? AsyncError(failure, stackTrace)
              : AsyncData(cached),
          message:
              reportFailure ? ListSplitMessage.refreshFailed : state.message,
        );
      }
      return false;
    } catch (error, stackTrace) {
      if (!mounted || generation != _loadGeneration) return false;
      state = ListSplitState(
        overview:
            cached == null ? AsyncError(error, stackTrace) : AsyncData(cached),
        message: reportFailure ? ListSplitMessage.refreshFailed : state.message,
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
