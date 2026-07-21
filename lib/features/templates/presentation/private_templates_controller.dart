import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/domain/active_list_repository.dart';
import 'package:list_and_split/features/lists/domain/creation_request_id.dart';
import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/templates/domain/private_template.dart';
import 'package:list_and_split/features/templates/domain/private_template_repository.dart';

enum PrivateTemplatesMessage {
  created,
  saved,
  updated,
  deleted,
  categoryCreated,
  categoryUpdated,
  categoryDeleted,
  listCreated,
  imported,
  invalidInput,
  capacity,
  staleRefreshed,
  unavailable,
  operationFailed,
}

class PrivateTemplatesState {
  const PrivateTemplatesState({
    required this.templates,
    required this.categories,
    this.search = '',
    this.categoryId,
    this.uncategorizedOnly = false,
    this.sort = PrivateTemplateSort.recent,
    this.isMutating = false,
    this.message,
  });

  const PrivateTemplatesState.loading()
      : templates = const AsyncLoading(),
        categories = const AsyncLoading(),
        search = '',
        categoryId = null,
        uncategorizedOnly = false,
        sort = PrivateTemplateSort.recent,
        isMutating = false,
        message = null;

  final AsyncValue<List<PrivateTemplateSummary>> templates;
  final AsyncValue<List<TemplateCategory>> categories;
  final String search;
  final String? categoryId;
  final bool uncategorizedOnly;
  final PrivateTemplateSort sort;
  final bool isMutating;
  final PrivateTemplatesMessage? message;

  PrivateTemplatesState copyWith({
    AsyncValue<List<PrivateTemplateSummary>>? templates,
    AsyncValue<List<TemplateCategory>>? categories,
    String? search,
    String? categoryId,
    bool clearCategory = false,
    bool? uncategorizedOnly,
    PrivateTemplateSort? sort,
    bool? isMutating,
    PrivateTemplatesMessage? message,
    bool clearMessage = false,
  }) {
    return PrivateTemplatesState(
      templates: templates ?? this.templates,
      categories: categories ?? this.categories,
      search: search ?? this.search,
      categoryId: clearCategory ? null : categoryId ?? this.categoryId,
      uncategorizedOnly: uncategorizedOnly ?? this.uncategorizedOnly,
      sort: sort ?? this.sort,
      isMutating: isMutating ?? this.isMutating,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class PrivateTemplatesController extends StateNotifier<PrivateTemplatesState> {
  PrivateTemplatesController(
    this._repository, {
    required bool hasAuthenticatedUser,
    CreationRequestIdGenerator requestIdGenerator = secureCreationRequestId,
  })  : _hasAuthenticatedUser = hasAuthenticatedUser,
        _requestIdGenerator = requestIdGenerator,
        super(const PrivateTemplatesState.loading());

  final PrivateTemplateRepository _repository;
  final bool _hasAuthenticatedUser;
  final CreationRequestIdGenerator _requestIdGenerator;
  int _generation = 0;
  bool _reconciliationPending = false;
  String? _pendingPayload;
  String? _pendingRequestId;

  Future<void> load() async {
    if (!_hasAuthenticatedUser) return;
    final generation = ++_generation;
    final hadTemplates = state.templates.valueOrNull != null;
    final hadCategories = state.categories.valueOrNull != null;
    if (!hadTemplates || !hadCategories) {
      state = state.copyWith(
        templates: hadTemplates ? state.templates : const AsyncLoading(),
        categories: hadCategories ? state.categories : const AsyncLoading(),
        clearMessage: true,
      );
    }
    try {
      final results = await Future.wait<Object>([
        _repository.listCategories(),
        _repository.listTemplates(
          search: state.search.isEmpty ? null : state.search,
          categoryId: state.categoryId,
          uncategorizedOnly: state.uncategorizedOnly,
          sort: state.sort,
        ),
      ]);
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        categories: AsyncData(results[0] as List<TemplateCategory>),
        templates: AsyncData(results[1] as List<PrivateTemplateSummary>),
        clearMessage: true,
      );
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        categories:
            hadCategories ? state.categories : AsyncError(error, stackTrace),
        templates:
            hadTemplates ? state.templates : AsyncError(error, stackTrace),
        message: PrivateTemplatesMessage.operationFailed,
      );
    }
  }

  Future<void> reconcile() async {
    if (state.isMutating) {
      _reconciliationPending = true;
      return;
    }
    await load();
  }

  Future<void> setSearch(String search) async {
    state = state.copyWith(search: search.trim(), clearMessage: true);
    await load();
  }

  Future<void> setFilter(
      {String? categoryId, bool uncategorized = false}) async {
    state = state.copyWith(
      categoryId: categoryId,
      clearCategory: categoryId == null,
      uncategorizedOnly: uncategorized,
      clearMessage: true,
    );
    await load();
  }

  Future<void> setSort(PrivateTemplateSort sort) async {
    state = state.copyWith(sort: sort, clearMessage: true);
    await load();
  }

  Future<bool> createTemplate(String name, {String? categoryId}) {
    final normalized = name.trim();
    return _create(
      payload: 'template\u0000$normalized\u0000${categoryId ?? ''}',
      valid: normalized.isNotEmpty,
      operation: (requestId) => _repository.createTemplate(
        normalized,
        categoryId: categoryId,
        requestId: requestId,
      ),
      message: PrivateTemplatesMessage.created,
    );
  }

  Future<bool> saveListAsTemplate(
    ActiveListDetail source,
    Iterable<String> selectedItemIds,
    String name, {
    String? categoryId,
  }) {
    final ids = selectedItemIds.toList(growable: false);
    final normalized = name.trim();
    return _create(
      payload:
          'snapshot\u0000${source.summary.id}\u0000${ids.join(',')}\u0000$normalized\u0000${categoryId ?? ''}',
      valid: normalized.isNotEmpty &&
          ids.isNotEmpty &&
          ids.length <= privateTemplateItemCapacity,
      operation: (requestId) => _repository.saveListAsTemplate(
        source.summary.id,
        ids,
        normalized,
        categoryId: categoryId,
        requestId: requestId,
        expectedListVersion: source.summary.version,
      ),
      message: PrivateTemplatesMessage.saved,
    );
  }

  Future<bool> createCategory(String name) {
    final normalized = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    return _create(
      payload: 'category\u0000$normalized',
      valid: normalized.isNotEmpty,
      operation: (requestId) =>
          _repository.createCategory(normalized, requestId: requestId),
      message: PrivateTemplatesMessage.categoryCreated,
    );
  }

  Future<bool> renameCategory(TemplateCategory category, String name) async {
    final normalized = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (state.isMutating || normalized.isEmpty) {
      _setMessage(PrivateTemplatesMessage.invalidInput);
      return false;
    }
    return _mutate(
      () => _repository.renameCategory(
        category.id,
        normalized,
        expectedVersion: category.version,
      ),
      PrivateTemplatesMessage.categoryUpdated,
    );
  }

  Future<bool> deleteCategory(TemplateCategory category) => _mutate(
        () => _repository.deleteCategory(
          category.id,
          expectedVersion: category.version,
        ),
        PrivateTemplatesMessage.categoryDeleted,
      );

  Future<bool> _create({
    required String payload,
    required bool valid,
    required Future<Object?> Function(String requestId) operation,
    required PrivateTemplatesMessage message,
  }) async {
    if (state.isMutating) return false;
    if (!valid) {
      _setMessage(PrivateTemplatesMessage.invalidInput);
      return false;
    }
    final requestId =
        _pendingPayload == payload ? _pendingRequestId! : _requestIdGenerator();
    _pendingPayload = payload;
    _pendingRequestId = requestId;
    final succeeded = await _mutate(() => operation(requestId), message);
    if (succeeded) {
      _pendingPayload = null;
      _pendingRequestId = null;
    }
    return succeeded;
  }

  Future<bool> _mutate(
    Future<Object?> Function() operation,
    PrivateTemplatesMessage message,
  ) async {
    if (state.isMutating) return false;
    state = state.copyWith(isMutating: true, clearMessage: true);
    try {
      await operation();
      if (!mounted) return false;
      state = state.copyWith(isMutating: false, message: message);
      await load();
      _drainReconciliation();
      return true;
    } on PrivateTemplateFailure catch (failure) {
      if (!mounted) return false;
      final failureMessage = _messageFor(failure);
      state = state.copyWith(
        isMutating: false,
        message: failureMessage,
      );
      if (failure.code == PrivateTemplateFailureCode.stale ||
          failure.code == PrivateTemplateFailureCode.capacity) {
        await load();
      }
      if (mounted) state = state.copyWith(message: failureMessage);
      _drainReconciliation();
      return false;
    } catch (_) {
      if (mounted) {
        state = state.copyWith(
          isMutating: false,
          message: PrivateTemplatesMessage.operationFailed,
        );
      }
      _drainReconciliation();
      return false;
    }
  }

  void _setMessage(PrivateTemplatesMessage message) {
    state = state.copyWith(message: message);
  }

  void _drainReconciliation() {
    if (!_reconciliationPending || !mounted || state.isMutating) return;
    _reconciliationPending = false;
    unawaited(load());
  }
}

class TemplateImportDestination {
  TemplateImportDestination({
    required this.detail,
    required Set<String> duplicateItemIds,
  }) : duplicateItemIds = Set.unmodifiable(duplicateItemIds);

  final ActiveListDetail detail;
  final Set<String> duplicateItemIds;
  int get remainingCapacity =>
      (shoppingListItemCapacity - detail.items.length).clamp(0, 200);
}

class PrivateTemplateDetailState {
  const PrivateTemplateDetailState({
    required this.detail,
    this.destination,
    this.isMutating = false,
    this.message,
  });

  const PrivateTemplateDetailState.loading()
      : detail = const AsyncLoading(),
        destination = null,
        isMutating = false,
        message = null;

  final AsyncValue<PrivateTemplateDetail> detail;
  final TemplateImportDestination? destination;
  final bool isMutating;
  final PrivateTemplatesMessage? message;

  PrivateTemplateDetailState copyWith({
    AsyncValue<PrivateTemplateDetail>? detail,
    TemplateImportDestination? destination,
    bool clearDestination = false,
    bool? isMutating,
    PrivateTemplatesMessage? message,
    bool clearMessage = false,
  }) {
    return PrivateTemplateDetailState(
      detail: detail ?? this.detail,
      destination: clearDestination ? null : destination ?? this.destination,
      isMutating: isMutating ?? this.isMutating,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class PrivateTemplateDetailController
    extends StateNotifier<PrivateTemplateDetailState> {
  PrivateTemplateDetailController(
    this._repository,
    this._listRepository,
    this.templateId, {
    required void Function() invalidateTemplates,
    required void Function() invalidateLists,
    required void Function(String listId) invalidateListDetail,
    CreationRequestIdGenerator requestIdGenerator = secureCreationRequestId,
  })  : _invalidateTemplates = invalidateTemplates,
        _invalidateLists = invalidateLists,
        _invalidateListDetail = invalidateListDetail,
        _requestIdGenerator = requestIdGenerator,
        super(const PrivateTemplateDetailState.loading());

  final PrivateTemplateRepository _repository;
  final ActiveListRepository _listRepository;
  final String templateId;
  final void Function() _invalidateTemplates;
  final void Function() _invalidateLists;
  final void Function(String listId) _invalidateListDetail;
  final CreationRequestIdGenerator _requestIdGenerator;
  int _generation = 0;
  bool _reconciliationPending = false;
  String? _pendingPayload;
  String? _pendingListRequestId;
  List<String>? _pendingItemRequestIds;

  Future<void> load() async {
    final generation = ++_generation;
    final cached = state.detail.valueOrNull;
    if (cached == null) state = const PrivateTemplateDetailState.loading();
    try {
      final detail = await _repository.getTemplate(templateId);
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        detail: AsyncData(detail),
        clearMessage: true,
      );
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        detail:
            cached == null ? AsyncError(error, stackTrace) : AsyncData(cached),
        message: error is PrivateTemplateFailure &&
                error.code == PrivateTemplateFailureCode.unavailable
            ? PrivateTemplatesMessage.unavailable
            : PrivateTemplatesMessage.operationFailed,
      );
    }
  }

  Future<void> reconcile() async {
    if (state.isMutating) {
      _reconciliationPending = true;
      return;
    }
    await load();
    final destinationId = state.destination?.detail.summary.id;
    if (destinationId != null) await prepareImport(destinationId);
  }

  Future<bool> updateTemplate(String name, {String? categoryId}) {
    final detail = state.detail.valueOrNull;
    final normalized = name.trim();
    if (detail == null || normalized.isEmpty) {
      _setMessage(PrivateTemplatesMessage.invalidInput);
      return Future.value(false);
    }
    return _mutate(
      () => _repository.updateTemplate(
        templateId,
        normalized,
        categoryId: categoryId,
        expectedVersion: detail.summary.version,
      ),
      PrivateTemplatesMessage.updated,
    );
  }

  Future<bool> deleteTemplate() {
    final detail = state.detail.valueOrNull;
    if (detail == null) return Future.value(false);
    return _mutate(
      () => _repository.deleteTemplate(
        templateId,
        expectedVersion: detail.summary.version,
      ),
      PrivateTemplatesMessage.deleted,
      reload: false,
    );
  }

  Future<bool> createItem(String name, ListQuantity quantity) {
    final detail = state.detail.valueOrNull;
    final normalized = name.trim();
    if (detail == null ||
        normalized.isEmpty ||
        normalized.length > 120 ||
        detail.remainingCapacity == 0) {
      _setMessage(detail?.remainingCapacity == 0
          ? PrivateTemplatesMessage.capacity
          : PrivateTemplatesMessage.invalidInput);
      return Future.value(false);
    }
    return _mutate(
      () => _repository.createItem(
        templateId,
        normalized,
        quantity: quantity,
        requestId: _requestIdGenerator(),
        expectedTemplateVersion: detail.summary.version,
      ),
      PrivateTemplatesMessage.updated,
    );
  }

  Future<bool> updateItem(
    PrivateTemplateItem item,
    String name,
    ListQuantity quantity,
  ) {
    final detail = state.detail.valueOrNull;
    final normalized = name.trim();
    if (detail == null || normalized.isEmpty || normalized.length > 120) {
      _setMessage(PrivateTemplatesMessage.invalidInput);
      return Future.value(false);
    }
    return _mutate(
      () => _repository.updateItem(
        templateId,
        item.id,
        normalized,
        quantity: quantity,
        expectedTemplateVersion: detail.summary.version,
        expectedItemVersion: item.version,
      ),
      PrivateTemplatesMessage.updated,
    );
  }

  Future<bool> deleteItem(PrivateTemplateItem item) {
    final detail = state.detail.valueOrNull;
    if (detail == null) return Future.value(false);
    return _mutate(
      () => _repository.deleteItem(
        templateId,
        item.id,
        expectedTemplateVersion: detail.summary.version,
        expectedItemVersion: item.version,
      ),
      PrivateTemplatesMessage.updated,
    );
  }

  Future<bool> reorderItems(List<String> itemIds) {
    final detail = state.detail.valueOrNull;
    if (detail == null) return Future.value(false);
    return _mutate(
      () => _repository.reorderItems(
        templateId,
        itemIds,
        expectedTemplateVersion: detail.summary.version,
      ),
      PrivateTemplatesMessage.updated,
    );
  }

  Future<bool> prepareImport(String listId) async {
    if (state.isMutating) return false;
    try {
      final values = await Future.wait<Object>([
        _listRepository.getList(listId),
        _listRepository.listItems(listId),
      ]);
      if (!mounted) return false;
      final summary = values[0] as ActiveListSummary;
      final items = values[1] as List<ActiveListItem>;
      if (summary.status != ActiveListStatus.active) {
        state = state.copyWith(message: PrivateTemplatesMessage.unavailable);
        return false;
      }
      final template = state.detail.valueOrNull;
      if (template == null) return false;
      state = state.copyWith(
        destination: TemplateImportDestination(
          detail: ActiveListDetail(summary: summary, items: items),
          duplicateItemIds: duplicateTemplateItemIds(
            template.items,
            items.map((item) => item.name),
          ),
        ),
        clearMessage: true,
      );
      return true;
    } catch (_) {
      if (mounted) {
        state =
            state.copyWith(message: PrivateTemplatesMessage.operationFailed);
      }
      return false;
    }
  }

  Future<TemplateListCreationResult?> createList(
    Iterable<String> selectedIds,
    String title,
  ) async {
    final detail = state.detail.valueOrNull;
    final ids = _orderedSelection(detail, selectedIds);
    final normalized = title.trim();
    if (detail == null ||
        normalized.isEmpty ||
        normalized.length > 80 ||
        ids.isEmpty ||
        ids.length > privateTemplateItemCapacity) {
      _setMessage(PrivateTemplatesMessage.invalidInput);
      return null;
    }
    final payload = '$normalized\u0000${ids.join(',')}';
    if (_pendingPayload != payload) {
      _pendingPayload = payload;
      _pendingListRequestId = _requestIdGenerator();
      _pendingItemRequestIds =
          List.generate(ids.length, (_) => _requestIdGenerator());
    }
    state = state.copyWith(isMutating: true, clearMessage: true);
    try {
      final result = await _repository.createListFromTemplate(
        templateId,
        ids,
        normalized,
        listRequestId: _pendingListRequestId!,
        itemRequestIds: _pendingItemRequestIds!,
        expectedTemplateVersion: detail.summary.version,
      );
      if (!mounted) return null;
      _clearPending();
      state = state.copyWith(
        isMutating: false,
        message: PrivateTemplatesMessage.listCreated,
      );
      _invalidateLists();
      _drainReconciliation();
      return result;
    } on PrivateTemplateFailure catch (failure) {
      if (mounted) {
        final failureMessage = _messageFor(failure);
        state = state.copyWith(isMutating: false, message: failureMessage);
        if (failure.code == PrivateTemplateFailureCode.stale) await load();
        if (mounted) state = state.copyWith(message: failureMessage);
      }
      _drainReconciliation();
      return null;
    } catch (_) {
      if (mounted) {
        state = state.copyWith(
          isMutating: false,
          message: PrivateTemplatesMessage.operationFailed,
        );
      }
      _drainReconciliation();
      return null;
    }
  }

  Future<bool> importSelected(Iterable<String> selectedIds) async {
    final detail = state.detail.valueOrNull;
    final destination = state.destination;
    final ids = _orderedSelection(detail, selectedIds);
    if (detail == null ||
        destination == null ||
        ids.isEmpty ||
        ids.length > destination.remainingCapacity) {
      _setMessage(ids.length > (destination?.remainingCapacity ?? 0)
          ? PrivateTemplatesMessage.capacity
          : PrivateTemplatesMessage.invalidInput);
      return false;
    }
    final payload = '${destination.detail.summary.id}\u0000${ids.join(',')}';
    if (_pendingPayload != payload) {
      _pendingPayload = payload;
      _pendingItemRequestIds =
          List.generate(ids.length, (_) => _requestIdGenerator());
    }
    state = state.copyWith(isMutating: true, clearMessage: true);
    try {
      await _repository.importIntoList(
        templateId,
        ids,
        destination.detail.summary.id,
        itemRequestIds: _pendingItemRequestIds!,
        expectedTemplateVersion: detail.summary.version,
        expectedListVersion: destination.detail.summary.version,
      );
      if (!mounted) return false;
      final listId = destination.detail.summary.id;
      _clearPending();
      state = state.copyWith(
        isMutating: false,
        message: PrivateTemplatesMessage.imported,
      );
      _invalidateLists();
      _invalidateListDetail(listId);
      await prepareImport(listId);
      _drainReconciliation();
      return true;
    } on PrivateTemplateFailure catch (failure) {
      if (!mounted) return false;
      final failureMessage = _messageFor(failure);
      state = state.copyWith(isMutating: false, message: failureMessage);
      if (failure.code == PrivateTemplateFailureCode.stale ||
          failure.code == PrivateTemplateFailureCode.capacity ||
          failure.code == PrivateTemplateFailureCode.archived) {
        await load();
        await prepareImport(destination.detail.summary.id);
      }
      if (mounted) state = state.copyWith(message: failureMessage);
      _drainReconciliation();
      return false;
    } catch (_) {
      if (mounted) {
        state = state.copyWith(
          isMutating: false,
          message: PrivateTemplatesMessage.operationFailed,
        );
      }
      _drainReconciliation();
      return false;
    }
  }

  Future<bool> _mutate(
    Future<Object?> Function() operation,
    PrivateTemplatesMessage message, {
    bool reload = true,
  }) async {
    if (state.isMutating) return false;
    state = state.copyWith(isMutating: true, clearMessage: true);
    try {
      await operation();
      if (!mounted) return false;
      state = state.copyWith(isMutating: false, message: message);
      _invalidateTemplates();
      if (reload) await load();
      _drainReconciliation();
      return true;
    } on PrivateTemplateFailure catch (failure) {
      if (!mounted) return false;
      final failureMessage = _messageFor(failure);
      state = state.copyWith(isMutating: false, message: failureMessage);
      if (failure.code == PrivateTemplateFailureCode.stale ||
          failure.code == PrivateTemplateFailureCode.capacity) {
        await load();
      }
      if (mounted) state = state.copyWith(message: failureMessage);
      _drainReconciliation();
      return false;
    } catch (_) {
      if (mounted) {
        state = state.copyWith(
          isMutating: false,
          message: PrivateTemplatesMessage.operationFailed,
        );
      }
      _drainReconciliation();
      return false;
    }
  }

  List<String> _orderedSelection(
    PrivateTemplateDetail? detail,
    Iterable<String> selectedIds,
  ) {
    if (detail == null) return const [];
    final selected = selectedIds.toSet();
    return detail.items
        .where((item) => selected.contains(item.id))
        .map((item) => item.id)
        .toList(growable: false);
  }

  void _setMessage(PrivateTemplatesMessage message) {
    state = state.copyWith(message: message);
  }

  void _clearPending() {
    _pendingPayload = null;
    _pendingListRequestId = null;
    _pendingItemRequestIds = null;
  }

  void _drainReconciliation() {
    if (!_reconciliationPending || !mounted || state.isMutating) return;
    _reconciliationPending = false;
    unawaited(reconcile());
  }
}

PrivateTemplatesMessage _messageFor(PrivateTemplateFailure failure) {
  return switch (failure.code) {
    PrivateTemplateFailureCode.invalid ||
    PrivateTemplateFailureCode.retryConflict =>
      PrivateTemplatesMessage.invalidInput,
    PrivateTemplateFailureCode.unavailable ||
    PrivateTemplateFailureCode.archived =>
      PrivateTemplatesMessage.unavailable,
    PrivateTemplateFailureCode.stale => PrivateTemplatesMessage.staleRefreshed,
    PrivateTemplateFailureCode.capacity => PrivateTemplatesMessage.capacity,
    PrivateTemplateFailureCode.transport ||
    PrivateTemplateFailureCode.generic =>
      PrivateTemplatesMessage.operationFailed,
  };
}
