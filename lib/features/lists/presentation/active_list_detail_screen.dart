import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/core/presentation/form_widgets.dart';
import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/lists/presentation/active_list_detail_controller.dart';
import 'package:list_and_split/features/lists/presentation/active_list_providers.dart';
import 'package:list_and_split/features/notifications/presentation/notification_bell.dart';
import 'package:list_and_split/features/templates/domain/private_template.dart';
import 'package:list_and_split/features/templates/presentation/private_template_providers.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

enum _ListAction { saveTemplate, rename, archive, restore, delete, leave }

class ActiveListDetailScreen extends ConsumerWidget {
  const ActiveListDetailScreen({required this.listId, super.key});

  final String listId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(activeListDetailControllerProvider(listId));
    final localizations = AppLocalizations.of(context);
    final detail = state.detail.valueOrNull;
    final archived = detail?.summary.status == ActiveListStatus.archived;
    ref.listen<ActiveListDetailState>(
      activeListDetailControllerProvider(listId),
      (previous, next) {
        if (next.message == ActiveListDetailMessage.remotelyArchived &&
            previous?.message != ActiveListDetailMessage.remotelyArchived) {
          context.go(AppRoutes.lists);
        } else if (next.message == ActiveListDetailMessage.unavailable &&
            previous?.message != ActiveListDetailMessage.unavailable) {
          context.go(AppRoutes.lists);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(localizations.listAccessRevokedMessage)),
          );
        }
      },
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(detail?.summary.title ?? localizations.listsTitle),
        actions: [
          const NotificationBell(),
          if (detail != null)
            IconButton(
              key: const Key('listMembersButton'),
              onPressed: state.isMutating
                  ? null
                  : () => context.push(
                        '${AppRoutes.lists}/$listId/members',
                      ),
              tooltip: detail.summary.isOwner
                  ? localizations.listManageMembersButton
                  : localizations.listViewMembersButton,
              icon: const Icon(Icons.group_outlined),
            ),
          if (detail != null && detail.summary.isOwner)
            PopupMenuButton<_ListAction>(
              key: const Key('listActionsButton'),
              enabled: !state.isMutating,
              onSelected: (action) => _handleAction(context, ref, action),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _ListAction.saveTemplate,
                  child: Text(localizations.templatesSaveListButton),
                ),
                if (!archived)
                  PopupMenuItem(
                    value: _ListAction.rename,
                    child: Text(localizations.listRenameButton),
                  ),
                PopupMenuItem(
                  value: archived ? _ListAction.restore : _ListAction.archive,
                  child: Text(
                    archived
                        ? localizations.listRestoreButton
                        : localizations.listArchiveButton,
                  ),
                ),
                if (!archived)
                  PopupMenuItem(
                    value: _ListAction.delete,
                    child: Text(localizations.listDeleteButton),
                  ),
              ],
            ),
          if (detail != null && !detail.summary.isOwner)
            PopupMenuButton<_ListAction>(
              key: const Key('memberListActionsButton'),
              enabled: !state.isMutating,
              onSelected: (action) => _handleAction(context, ref, action),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _ListAction.saveTemplate,
                  child: Text(localizations.templatesSaveListButton),
                ),
                PopupMenuItem(
                  value: _ListAction.leave,
                  child: Text(localizations.listLeaveButton),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: detail != null && !archived
          ? FloatingActionButton.extended(
              key: const Key('addItemButton'),
              onPressed: state.isMutating ||
                      detail.items.length >= activeListItemCapacity
                  ? null
                  : () => _showItemDialog(context, ref),
              tooltip: detail.items.length >= activeListItemCapacity
                  ? localizations.listItemCapacityReachedMessage
                  : localizations.itemAddButton,
              icon: const Icon(Icons.add_rounded),
              label: Text(localizations.itemAddButton),
            )
          : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: state.detail.when(
              loading: () => Semantics(
                liveRegion: true,
                label: localizations.listDetailLoadingLabel,
                child: const Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => _DetailError(
                onRetry: () => ref
                    .read(activeListDetailControllerProvider(listId).notifier)
                    .load(),
              ),
              data: (loaded) => _DetailBody(
                listId: listId,
                detail: loaded,
                state: state,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    _ListAction action,
  ) async {
    final controller =
        ref.read(activeListDetailControllerProvider(listId).notifier);
    switch (action) {
      case _ListAction.saveTemplate:
        await _showSaveAsTemplate(context, ref);
      case _ListAction.rename:
        await _showRenameDialog(context, ref);
      case _ListAction.archive:
        await controller.setArchived(true);
      case _ListAction.restore:
        await controller.setArchived(false);
      case _ListAction.delete:
        await _confirmDeleteList(context, ref);
      case _ListAction.leave:
        await _confirmLeaveList(context, ref);
    }
  }

  Future<void> _showSaveAsTemplate(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final detail =
        ref.read(activeListDetailControllerProvider(listId)).detail.valueOrNull;
    if (detail == null) return;
    await ref.read(privateTemplatesControllerProvider.notifier).load();
    if (!context.mounted) return;
    final categories =
        ref.read(privateTemplatesControllerProvider).categories.valueOrNull ??
            const <TemplateCategory>[];
    final input = await showDialog<_SaveTemplateInput>(
      context: context,
      builder: (_) => _SaveTemplateDialog(
        detail: detail,
        categories: categories,
      ),
    );
    if (input == null || !context.mounted) return;
    await ref
        .read(privateTemplatesControllerProvider.notifier)
        .saveListAsTemplate(
          detail,
          input.selectedItemIds,
          input.name,
          categoryId: input.categoryId,
        );
  }

  Future<void> _confirmLeaveList(BuildContext context, WidgetRef ref) async {
    final localizations = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.listLeaveTitle),
        content: Text(localizations.listLeaveDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(localizations.cancelButton),
          ),
          FilledButton(
            key: const Key('confirmLeaveListButton'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(localizations.listLeaveButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final outcome = await ref
        .read(activeListDetailControllerProvider(listId).notifier)
        .leaveList();
    if (outcome == ActiveListMutationOutcome.succeeded && context.mounted) {
      context.go(AppRoutes.lists);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.listLeftMessage)),
      );
    }
  }

  Future<void> _showRenameDialog(BuildContext context, WidgetRef ref) async {
    final existing =
        ref.read(activeListDetailControllerProvider(listId)).detail.valueOrNull;
    if (existing == null) return;
    var title = existing.summary.title;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (context, dialogRef, child) {
          final state =
              dialogRef.watch(activeListDetailControllerProvider(listId));
          final localizations = AppLocalizations.of(context);
          return AlertDialog(
            title: Text(localizations.listRenameTitle),
            content: TextFormField(
              key: const Key('renameListTitle'),
              initialValue: title,
              autofocus: true,
              enabled: !state.isMutating,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: localizations.listsTitleLabel,
                helperText: localizations.listsTitleHelper,
              ),
              onChanged: (value) => title = value,
            ),
            actions: [
              TextButton(
                onPressed: state.isMutating
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: Text(localizations.cancelButton),
              ),
              FilledButton(
                key: const Key('confirmRenameListButton'),
                onPressed: state.isMutating
                    ? null
                    : () async {
                        final outcome = await dialogRef
                            .read(
                              activeListDetailControllerProvider(listId)
                                  .notifier,
                            )
                            .rename(title);
                        if (outcome.dismissesEditor && dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                      },
                child: state.isMutating
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(localizations.saveButton),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDeleteList(BuildContext context, WidgetRef ref) async {
    final localizations = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.listDeleteTitle),
        content: Text(localizations.listDeleteDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(localizations.cancelButton),
          ),
          FilledButton(
            key: const Key('confirmDeleteListButton'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(localizations.listDeleteConfirmButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final outcome = await ref
        .read(activeListDetailControllerProvider(listId).notifier)
        .deleteList();
    if (outcome == ActiveListMutationOutcome.succeeded && context.mounted) {
      context.pop();
    }
  }

  Future<void> _showItemDialog(
    BuildContext context,
    WidgetRef ref, {
    ActiveListItem? item,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => _ItemDialog(listId: listId, item: item),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({
    required this.listId,
    required this.detail,
    required this.state,
  });

  final String listId;
  final ActiveListDetail detail;
  final ActiveListDetailState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final archived = detail.summary.status == ActiveListStatus.archived;
    final completed = detail.items.where((item) => item.isCompleted).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (archived)
            Semantics(
              liveRegion: true,
              child: Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.archive_outlined),
                      const SizedBox(width: 12),
                      Expanded(child: Text(localizations.listArchivedBanner)),
                    ],
                  ),
                ),
              ),
            ),
          FormMessageBanner(
            message: _detailMessageText(localizations, state.message),
          ),
          if (state.message == ActiveListDetailMessage.recoveryFailed ||
              state.message == ActiveListDetailMessage.refreshFailed)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: FilledButton.tonal(
                  key: const Key('retryListDetailRecoveryButton'),
                  onPressed: state.isMutating
                      ? null
                      : () => ref
                          .read(
                            activeListDetailControllerProvider(listId).notifier,
                          )
                          .load(),
                  child: Text(localizations.tryAgainButton),
                ),
              ),
            ),
          Text(
            localizations.listProgress(completed, detail.items.length),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: detail.items.isEmpty ? 0 : completed / detail.items.length,
            semanticsLabel:
                localizations.listProgress(completed, detail.items.length),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: detail.items.isEmpty
                ? _ItemsEmpty(archived: archived)
                : ReorderableListView.builder(
                    key: const Key('activeListItems'),
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: detail.items.length,
                    // Keep the callback supported by the Flutter 3.19 floor.
                    // ignore: deprecated_member_use
                    onReorder: archived || state.isMutating
                        ? (_, __) {}
                        : (oldIndex, newIndex) => ref
                            .read(
                              activeListDetailControllerProvider(listId)
                                  .notifier,
                            )
                            .reorder(oldIndex, newIndex),
                    itemBuilder: (context, index) => _ItemCard(
                      key: ValueKey(detail.items[index].id),
                      listId: listId,
                      item: detail.items[index],
                      index: index,
                      readOnly: archived,
                      isBusy: state.isMutating,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String? _detailMessageText(
    AppLocalizations localizations,
    ActiveListDetailMessage? message,
  ) {
    return switch (message) {
      ActiveListDetailMessage.renamed => localizations.listRenamedMessage,
      ActiveListDetailMessage.archived => localizations.listArchivedMessage,
      ActiveListDetailMessage.restored => localizations.listRestoredMessage,
      ActiveListDetailMessage.remotelyArchived => null,
      ActiveListDetailMessage.itemCreated => localizations.itemCreatedMessage,
      ActiveListDetailMessage.itemUpdated => localizations.itemUpdatedMessage,
      ActiveListDetailMessage.itemDeleted => localizations.itemDeletedMessage,
      ActiveListDetailMessage.orderUpdated =>
        localizations.itemOrderUpdatedMessage,
      ActiveListDetailMessage.left => localizations.listLeftMessage,
      ActiveListDetailMessage.recoveryInProgress =>
        localizations.listRecoveryInProgressMessage,
      ActiveListDetailMessage.staleRefreshed => localizations.listStaleMessage,
      ActiveListDetailMessage.reconciled => localizations.listReconciledMessage,
      ActiveListDetailMessage.recoveryFailed =>
        localizations.listRecoveryFailedMessage,
      ActiveListDetailMessage.refreshFailed =>
        localizations.listRefreshFailedMessage,
      ActiveListDetailMessage.invalidInput =>
        localizations.listInvalidInputMessage,
      ActiveListDetailMessage.itemCapacity =>
        localizations.listItemCapacityReachedMessage,
      ActiveListDetailMessage.archivedReadOnly =>
        localizations.listReadOnlyMessage,
      ActiveListDetailMessage.unavailable =>
        localizations.listUnavailableMessage,
      ActiveListDetailMessage.operationFailed =>
        localizations.operationFailedMessage,
      null => null,
    };
  }
}

class _ItemCard extends ConsumerWidget {
  const _ItemCard({
    required this.listId,
    required this.item,
    required this.index,
    required this.readOnly,
    required this.isBusy,
    super.key,
  });

  final String listId;
  final ActiveListItem item;
  final int index;
  final bool readOnly;
  final bool isBusy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final controller =
        ref.read(activeListDetailControllerProvider(listId).notifier);
    final quantity = '${item.quantity.format()}'
        '${item.unit == null ? '' : ' ${_unitLabel(localizations, item.unit!)}'}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsetsDirectional.fromSTEB(8, 4, 4, 4),
        leading: Semantics(
          label: item.isCompleted
              ? localizations.itemReopen(item.name)
              : localizations.itemMarkComplete(item.name),
          button: true,
          child: Checkbox(
            key: Key('completeItem-${item.id}'),
            value: item.isCompleted,
            onChanged: readOnly || isBusy
                ? null
                : (value) => controller.setItemCompleted(item, value ?? false),
          ),
        ),
        title: Text(
          item.name,
          style: item.isCompleted
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: Text(quantity),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!readOnly)
              PopupMenuButton<String>(
                key: Key('itemActions-${item.id}'),
                enabled: !isBusy,
                onSelected: (action) {
                  if (action == 'edit') {
                    showDialog<void>(
                      context: context,
                      builder: (_) => _ItemDialog(listId: listId, item: item),
                    );
                  } else {
                    _confirmDeleteItem(context, controller);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(localizations.itemEditButton),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(localizations.itemDeleteButton),
                  ),
                ],
              ),
            if (!readOnly)
              Semantics(
                label: localizations.itemReorder(item.name),
                button: true,
                child: ReorderableDragStartListener(
                  index: index,
                  enabled: !isBusy,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.drag_handle_rounded),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteItem(
    BuildContext context,
    ActiveListDetailController controller,
  ) async {
    final localizations = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.itemDeleteTitle),
        content: Text(localizations.itemDeleteDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(localizations.cancelButton),
          ),
          FilledButton(
            key: const Key('confirmDeleteItemButton'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(localizations.itemDeleteButton),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.deleteItem(item);
  }
}

class _ItemDialog extends ConsumerStatefulWidget {
  const _ItemDialog({required this.listId, this.item});

  final String listId;
  final ActiveListItem? item;

  @override
  ConsumerState<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends ConsumerState<_ItemDialog> {
  late final TextEditingController _name;
  late final TextEditingController _quantity;
  ListUnit? _unit;
  bool _showValidation = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.item?.name ?? '');
    _quantity = TextEditingController(
      text: widget.item?.quantity.format() ?? ListQuantity.one.format(),
    );
    _unit = widget.item?.unit;
  }

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(activeListDetailControllerProvider(widget.listId));
    final quantity = ListQuantity.tryParse(_quantity.text);
    final nameValid =
        _name.text.trim().isNotEmpty && _name.text.trim().length <= 120;
    return AlertDialog(
      title: Text(
        widget.item == null
            ? localizations.itemAddTitle
            : localizations.itemEditTitle,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('itemNameField'),
              controller: _name,
              autofocus: true,
              enabled: !state.isMutating,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: localizations.itemNameLabel,
                helperText: localizations.itemNameHelper,
                errorText: _showValidation && !nameValid
                    ? localizations.listInvalidInputMessage
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('itemQuantityField'),
              controller: _quantity,
              enabled: !state.isMutating,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: localizations.itemQuantityLabel,
                helperText: localizations.itemQuantityHelper,
                errorText: _showValidation && quantity == null
                    ? localizations.listInvalidInputMessage
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<ListUnit?>(
              key: const Key('itemUnitField'),
              // Keep the initializer supported by the Flutter 3.19 floor.
              // ignore: deprecated_member_use
              value: _unit,
              decoration:
                  InputDecoration(labelText: localizations.itemUnitLabel),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(localizations.itemNoUnit),
                ),
                ...ListUnit.values.map(
                  (unit) => DropdownMenuItem(
                    value: unit,
                    child: Text(_unitLabel(localizations, unit)),
                  ),
                ),
              ],
              onChanged: state.isMutating
                  ? null
                  : (value) => setState(() => _unit = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              state.isMutating ? null : () => Navigator.of(context).pop(),
          child: Text(localizations.cancelButton),
        ),
        FilledButton(
          key: const Key('saveItemButton'),
          onPressed: state.isMutating ? null : _submit,
          child: state.isMutating
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(localizations.itemSaveButton),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final quantity = ListQuantity.tryParse(_quantity.text);
    if (_name.text.trim().isEmpty ||
        _name.text.trim().length > 120 ||
        quantity == null) {
      setState(() => _showValidation = true);
      return;
    }
    final controller =
        ref.read(activeListDetailControllerProvider(widget.listId).notifier);
    final outcome = widget.item == null
        ? await controller.createItem(
            _name.text,
            quantity: quantity,
            unit: _unit,
          )
        : await controller.updateItem(
            widget.item!,
            _name.text,
            quantity: quantity,
            unit: _unit,
          );
    if (outcome.dismissesEditor && mounted) Navigator.of(context).pop();
  }
}

String _unitLabel(AppLocalizations localizations, ListUnit unit) {
  return switch (unit) {
    ListUnit.piece => localizations.unitPiece,
    ListUnit.kilogram => localizations.unitKilogram,
    ListUnit.gram => localizations.unitGram,
    ListUnit.litre => localizations.unitLitre,
    ListUnit.millilitre => localizations.unitMillilitre,
    ListUnit.pack => localizations.unitPack,
    ListUnit.box => localizations.unitBox,
    ListUnit.bottle => localizations.unitBottle,
    ListUnit.can => localizations.unitCan,
    ListUnit.bag => localizations.unitBag,
  };
}

class _ItemsEmpty extends StatelessWidget {
  const _ItemsEmpty({required this.archived});

  final bool archived;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.playlist_add_rounded, size: 52),
          const SizedBox(height: 12),
          Text(
            localizations.itemsEmptyTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            archived
                ? localizations.listArchivedBanner
                : localizations.itemsEmptyDescription,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SaveTemplateInput {
  const _SaveTemplateInput({
    required this.name,
    required this.categoryId,
    required this.selectedItemIds,
  });

  final String name;
  final String? categoryId;
  final Set<String> selectedItemIds;
}

class _SaveTemplateDialog extends StatefulWidget {
  const _SaveTemplateDialog({
    required this.detail,
    required this.categories,
  });

  final ActiveListDetail detail;
  final List<TemplateCategory> categories;

  @override
  State<_SaveTemplateDialog> createState() => _SaveTemplateDialogState();
}

class _SaveTemplateDialogState extends State<_SaveTemplateDialog> {
  late final TextEditingController _nameController;
  late Set<String> _selectedIds;
  String? _categoryId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.detail.summary.title);
    _selectedIds = widget.detail.items.map((item) => item.id).toSet();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final valid = _nameController.text.trim().isNotEmpty &&
        _selectedIds.isNotEmpty &&
        _selectedIds.length <= privateTemplateItemCapacity;
    return AlertDialog(
      title: Text(localizations.templatesSaveListTitle),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(localizations.templatesSaveListDescription),
            const SizedBox(height: 12),
            TextField(
              key: const Key('saveListTemplateNameField'),
              controller: _nameController,
              decoration: InputDecoration(
                labelText: localizations.templatesNameLabel,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              value: _categoryId,
              decoration: InputDecoration(
                labelText: localizations.templatesCategoryLabel,
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(localizations.templatesNoCategoryLabel),
                ),
                for (final category in widget.categories)
                  DropdownMenuItem<String?>(
                    value: category.id,
                    child: Text(category.name),
                  ),
              ],
              onChanged: (value) => setState(() => _categoryId = value),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    localizations.templatesSelectionCount(
                      _selectedIds.length,
                      widget.detail.items.length,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _selectedIds =
                        widget.detail.items.map((item) => item.id).toSet();
                  }),
                  child: Text(localizations.templatesSelectAllButton),
                ),
                TextButton(
                  onPressed: () => setState(_selectedIds.clear),
                  child: Text(localizations.templatesClearSelectionButton),
                ),
              ],
            ),
            if (_selectedIds.length > privateTemplateItemCapacity)
              Text(
                localizations.templatesCapacityExceeded,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const Divider(),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.detail.items.length,
                itemBuilder: (context, index) {
                  final item = widget.detail.items[index];
                  return CheckboxListTile(
                    key: Key('save-template-item-${item.id}'),
                    value: _selectedIds.contains(item.id),
                    title: Text(item.name),
                    subtitle: Text(item.quantity.format()),
                    secondary: item.isCompleted
                        ? const Icon(Icons.check_circle_outline)
                        : const Icon(Icons.radio_button_unchecked),
                    onChanged: (_) => setState(() {
                      _selectedIds.contains(item.id)
                          ? _selectedIds.remove(item.id)
                          : _selectedIds.add(item.id);
                    }),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(localizations.cancelButton),
        ),
        FilledButton(
          key: const Key('confirmSaveListTemplateButton'),
          onPressed: valid
              ? () => Navigator.pop(
                    context,
                    _SaveTemplateInput(
                      name: _nameController.text.trim(),
                      categoryId: _categoryId,
                      selectedItemIds: Set.unmodifiable(_selectedIds),
                    ),
                  )
              : null,
          child: Text(localizations.templatesConfirmSaveButton),
        ),
      ],
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off_rounded, size: 52),
          const SizedBox(height: 12),
          Text(
            localizations.listDetailUnavailableTitle,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            localizations.listDetailUnavailableDescription,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            key: const Key('retryListDetailButton'),
            onPressed: onRetry,
            child: Text(localizations.tryAgainButton),
          ),
        ],
      ),
    );
  }
}
