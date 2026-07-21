import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/lists/presentation/active_list_providers.dart';
import 'package:list_and_split/features/notifications/presentation/notification_bell.dart';
import 'package:list_and_split/features/templates/domain/private_template.dart';
import 'package:list_and_split/features/templates/presentation/private_template_providers.dart';
import 'package:list_and_split/features/templates/presentation/private_templates_controller.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

enum _TemplateAction { edit, createList, import, delete }

class PrivateTemplateDetailScreen extends ConsumerWidget {
  const PrivateTemplateDetailScreen({required this.templateId, super.key});

  final String templateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final provider = privateTemplateDetailControllerProvider(templateId);
    final state = ref.watch(provider);
    final detail = state.detail.valueOrNull;
    ref.listen<PrivateTemplateDetailState>(provider, (previous, next) {
      if (next.message != null && next.message != previous?.message) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_detailMessage(localizations, next.message!))),
        );
        if (next.message == PrivateTemplatesMessage.deleted) {
          context.go(AppRoutes.templates);
        } else if (next.message == PrivateTemplatesMessage.unavailable) {
          context.go(AppRoutes.templates);
        }
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(detail?.summary.name ?? localizations.templatesTitle),
        actions: [
          const NotificationBell(),
          if (detail != null)
            PopupMenuButton<_TemplateAction>(
              key: const Key('templateActionsButton'),
              enabled: !state.isMutating,
              onSelected: (action) => _handleAction(context, ref, action),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _TemplateAction.edit,
                  child: Text(localizations.templatesEditButton),
                ),
                PopupMenuItem(
                  enabled: detail.items.isNotEmpty,
                  value: _TemplateAction.createList,
                  child: Text(localizations.templatesCreateListButton),
                ),
                PopupMenuItem(
                  enabled: detail.items.isNotEmpty,
                  value: _TemplateAction.import,
                  child: Text(localizations.templatesImportListButton),
                ),
                PopupMenuItem(
                  value: _TemplateAction.delete,
                  child: Text(localizations.templatesDeleteButton),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: detail == null
          ? null
          : FloatingActionButton.extended(
              key: const Key('addTemplateItemButton'),
              onPressed: state.isMutating || detail.remainingCapacity == 0
                  ? null
                  : () => _showItemEditor(context, ref),
              tooltip: detail.remainingCapacity == 0
                  ? localizations.templatesCapacityReached
                  : localizations.templatesAddItemButton,
              icon: const Icon(Icons.add),
              label: Text(localizations.templatesAddItemButton),
            ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: state.detail.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                child: FilledButton.tonal(
                  onPressed: () => ref.read(provider.notifier).load(),
                  child: Text(localizations.templatesRetryButton),
                ),
              ),
              data: (loaded) => RefreshIndicator(
                onRefresh: () => ref.read(provider.notifier).load(),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Card(
                          child: ListTile(
                            leading: const Icon(Icons.category_outlined),
                            title: Text(
                              loaded.summary.categoryName ??
                                  localizations.templatesNoCategoryLabel,
                            ),
                            subtitle: Text(
                              '${localizations.templatesItemCount(loaded.items.length)} · '
                              '${localizations.templatesRemainingCapacity(loaded.remainingCapacity)}',
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (loaded.items.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              localizations.templatesEmptyDescription,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                        sliver: SliverReorderableList(
                          itemCount: loaded.items.length,
                          onReorder: state.isMutating
                              ? (_, __) {}
                              : (oldIndex, newIndex) {
                                  if (newIndex > oldIndex) newIndex -= 1;
                                  final reordered = loaded.items.toList();
                                  final moved = reordered.removeAt(oldIndex);
                                  reordered.insert(newIndex, moved);
                                  ref.read(provider.notifier).reorderItems(
                                        reordered
                                            .map((item) => item.id)
                                            .toList(growable: false),
                                      );
                                },
                          itemBuilder: (context, index) {
                            final item = loaded.items[index];
                            return Card(
                              key: ValueKey(item.id),
                              child: ListTile(
                                title: Text(item.name, maxLines: 2),
                                subtitle: Text(item.quantity.format()),
                                onTap: state.isMutating
                                    ? null
                                    : () => _showItemEditor(
                                          context,
                                          ref,
                                          item: item,
                                        ),
                                trailing: Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    IconButton(
                                      onPressed: state.isMutating
                                          ? null
                                          : () => _confirmDeleteItem(
                                                context,
                                                ref,
                                                item,
                                              ),
                                      tooltip:
                                          localizations.templatesDeleteButton,
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: Icon(Icons.drag_handle),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
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
    _TemplateAction action,
  ) async {
    switch (action) {
      case _TemplateAction.edit:
        await _showTemplateEditor(context, ref);
      case _TemplateAction.createList:
        await _showCreateList(context, ref);
      case _TemplateAction.import:
        await _showImport(context, ref);
      case _TemplateAction.delete:
        await _confirmDeleteTemplate(context, ref);
    }
  }

  Future<void> _showTemplateEditor(BuildContext context, WidgetRef ref) async {
    final detail = ref
        .read(privateTemplateDetailControllerProvider(templateId))
        .detail
        .valueOrNull;
    if (detail == null) return;
    final categories =
        ref.read(privateTemplatesControllerProvider).categories.valueOrNull ??
            const <TemplateCategory>[];
    final input = await showDialog<_EditTemplateInput>(
      context: context,
      builder: (_) => _EditTemplateDialog(
        initialName: detail.summary.name,
        initialCategoryId: detail.summary.categoryId,
        categories: categories,
      ),
    );
    if (input != null && context.mounted) {
      await ref
          .read(privateTemplateDetailControllerProvider(templateId).notifier)
          .updateTemplate(input.name, categoryId: input.categoryId);
    }
  }

  Future<void> _confirmDeleteTemplate(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final localizations = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.templatesDeleteDialogTitle),
        content: Text(localizations.templatesDeleteDialogDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(localizations.cancelButton),
          ),
          FilledButton(
            key: const Key('confirmDeleteTemplateButton'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(localizations.templatesDeleteButton),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref
          .read(privateTemplateDetailControllerProvider(templateId).notifier)
          .deleteTemplate();
    }
  }

  Future<void> _showItemEditor(
    BuildContext context,
    WidgetRef ref, {
    PrivateTemplateItem? item,
  }) async {
    final result = await showDialog<_ItemInput>(
      context: context,
      builder: (_) => _TemplateItemDialog(item: item),
    );
    if (result == null || !context.mounted) return;
    final controller =
        ref.read(privateTemplateDetailControllerProvider(templateId).notifier);
    if (item == null) {
      await controller.createItem(result.name, result.quantity);
    } else {
      await controller.updateItem(item, result.name, result.quantity);
    }
  }

  Future<void> _confirmDeleteItem(
    BuildContext context,
    WidgetRef ref,
    PrivateTemplateItem item,
  ) async {
    final localizations = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.templatesDeleteButton),
        content: Text(item.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(localizations.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(localizations.templatesDeleteButton),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref
          .read(privateTemplateDetailControllerProvider(templateId).notifier)
          .deleteItem(item);
    }
  }

  Future<void> _showCreateList(BuildContext context, WidgetRef ref) async {
    final detail = ref
        .read(privateTemplateDetailControllerProvider(templateId))
        .detail
        .valueOrNull;
    if (detail == null) return;
    final selection = await showDialog<_SelectionInput>(
      context: context,
      builder: (_) => _TemplateSelectionDialog(
        title: AppLocalizations.of(context).templatesCreateListTitle,
        items: detail.items,
        remainingCapacity: privateTemplateItemCapacity,
        initialTitle: detail.summary.name,
        confirmLabel:
            AppLocalizations.of(context).templatesConfirmCreateListButton,
      ),
    );
    if (selection == null || !context.mounted) return;
    final result = await ref
        .read(privateTemplateDetailControllerProvider(templateId).notifier)
        .createList(selection.selectedIds, selection.title!);
    if (result != null && context.mounted) {
      context.go('${AppRoutes.lists}/${result.listId}');
    }
  }

  Future<void> _showImport(BuildContext context, WidgetRef ref) async {
    final listsController = ref.read(activeListsControllerProvider.notifier);
    await listsController.loadAll();
    var listsState = ref.read(activeListsControllerProvider);
    var pageGuard = 0;
    while (listsState.activeHasMore && pageGuard < 10) {
      await listsController.loadMore(ActiveListStatus.active);
      listsState = ref.read(activeListsControllerProvider);
      pageGuard += 1;
    }
    final lists =
        listsState.activeLists.valueOrNull ?? const <ActiveListSummary>[];
    if (!context.mounted) return;
    if (lists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context).templatesNoActiveLists)),
      );
      return;
    }
    final destination = await showDialog<ActiveListSummary>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(AppLocalizations.of(context).templatesChooseListTitle),
        children: [
          for (final list in lists)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, list),
              child: Text(list.title),
            ),
        ],
      ),
    );
    if (destination == null || !context.mounted) return;
    final controller =
        ref.read(privateTemplateDetailControllerProvider(templateId).notifier);
    final preparedSuccessfully = await controller.prepareImport(destination.id);
    if (!context.mounted) return;
    if (!preparedSuccessfully) return;
    final state = ref.read(privateTemplateDetailControllerProvider(templateId));
    final detail = state.detail.valueOrNull;
    final prepared = state.destination;
    if (detail == null || prepared == null) return;
    final selection = await showDialog<_SelectionInput>(
      context: context,
      builder: (_) => _TemplateSelectionDialog(
        title: AppLocalizations.of(context).templatesImportTitle,
        items: detail.items,
        remainingCapacity: prepared.remainingCapacity,
        duplicateIds: prepared.duplicateItemIds,
        confirmLabel: AppLocalizations.of(context).templatesConfirmImportButton,
      ),
    );
    if (selection != null && context.mounted) {
      await controller.importSelected(selection.selectedIds);
    }
  }
}

class _EditTemplateInput {
  const _EditTemplateInput(this.name, this.categoryId);
  final String name;
  final String? categoryId;
}

class _EditTemplateDialog extends StatefulWidget {
  const _EditTemplateDialog({
    required this.initialName,
    required this.initialCategoryId,
    required this.categories,
  });

  final String initialName;
  final String? initialCategoryId;
  final List<TemplateCategory> categories;

  @override
  State<_EditTemplateDialog> createState() => _EditTemplateDialogState();
}

class _EditTemplateDialogState extends State<_EditTemplateDialog> {
  late final TextEditingController _nameController;
  String? _categoryId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _categoryId = widget.initialCategoryId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(localizations.templatesEditDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: localizations.templatesNameLabel,
              ),
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(localizations.cancelButton),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _EditTemplateInput(_nameController.text, _categoryId),
          ),
          child: Text(localizations.saveButton),
        ),
      ],
    );
  }
}

class _ItemInput {
  const _ItemInput(this.name, this.quantity);
  final String name;
  final ListQuantity quantity;
}

class _TemplateItemDialog extends StatefulWidget {
  const _TemplateItemDialog({this.item});
  final PrivateTemplateItem? item;

  @override
  State<_TemplateItemDialog> createState() => _TemplateItemDialogState();
}

class _TemplateItemDialogState extends State<_TemplateItemDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _quantityController;
  bool _valid = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item?.name ?? '');
    _quantityController = TextEditingController(
      text: widget.item?.quantity.format() ?? '1',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(localizations.templatesItemDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('templateItemNameField'),
            controller: _nameController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: localizations.templatesItemNameLabel,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('templateItemQuantityField'),
            controller: _quantityController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: localizations.templatesItemQuantityLabel,
              errorText:
                  _valid ? null : localizations.templatesInvalidInputMessage,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(localizations.cancelButton),
        ),
        FilledButton(
          onPressed: () {
            final quantity = ListQuantity.tryParse(_quantityController.text);
            final name = _nameController.text.trim();
            if (quantity == null || name.isEmpty || name.length > 120) {
              setState(() => _valid = false);
              return;
            }
            Navigator.pop(context, _ItemInput(name, quantity));
          },
          child: Text(localizations.saveButton),
        ),
      ],
    );
  }
}

class _SelectionInput {
  const _SelectionInput(this.selectedIds, this.title);
  final Set<String> selectedIds;
  final String? title;
}

class _TemplateSelectionDialog extends StatefulWidget {
  const _TemplateSelectionDialog({
    required this.title,
    required this.items,
    required this.remainingCapacity,
    required this.confirmLabel,
    this.initialTitle,
    this.duplicateIds = const {},
  });

  final String title;
  final List<PrivateTemplateItem> items;
  final int remainingCapacity;
  final String confirmLabel;
  final String? initialTitle;
  final Set<String> duplicateIds;

  @override
  State<_TemplateSelectionDialog> createState() =>
      _TemplateSelectionDialogState();
}

class _TemplateSelectionDialogState extends State<_TemplateSelectionDialog> {
  late TemplateSelection _selection;
  TextEditingController? _titleController;

  @override
  void initState() {
    super.initState();
    _selection = TemplateSelection.all(
      widget.items.map((item) => item.id),
      remainingCapacity: widget.remainingCapacity,
    );
    if (widget.initialTitle != null) {
      _titleController = TextEditingController(text: widget.initialTitle);
    }
  }

  @override
  void dispose() {
    _titleController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final titleValid = _titleController == null ||
        (_titleController!.text.trim().isNotEmpty &&
            _titleController!.text.trim().length <= 80);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_titleController != null) ...[
              TextField(
                key: const Key('templateListTitleField'),
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: localizations.listsTitleLabel,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    localizations.templatesSelectionCount(
                      _selection.selectedCount,
                      widget.items.length,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _selection = TemplateSelection.all(
                      widget.items.map((item) => item.id),
                      remainingCapacity: widget.remainingCapacity,
                    );
                  }),
                  child: Text(localizations.templatesSelectAllButton),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _selection = TemplateSelection(
                      availableItemIds: widget.items.map((item) => item.id),
                      selectedItemIds: const [],
                      remainingCapacity: widget.remainingCapacity,
                    );
                  }),
                  child: Text(localizations.templatesClearSelectionButton),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                localizations.templatesRemainingCapacity(
                  widget.remainingCapacity,
                ),
              ),
            ),
            if (_selection.selectedCount > widget.remainingCapacity)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  localizations.templatesCapacityExceeded,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            const Divider(),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.items.length,
                itemBuilder: (context, index) {
                  final item = widget.items[index];
                  return CheckboxListTile(
                    key: Key('select-template-item-${item.id}'),
                    value: _selection.selectedItemIds.contains(item.id),
                    title: Text(item.name),
                    subtitle: Text(
                      widget.duplicateIds.contains(item.id)
                          ? '${item.quantity.format()} · ${localizations.templatesPossibleDuplicate}'
                          : item.quantity.format(),
                    ),
                    onChanged: (_) => setState(() {
                      _selection = _selection.toggled(item.id);
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
          key: const Key('confirmTemplateSelectionButton'),
          onPressed: !_selection.canConfirm || !titleValid
              ? null
              : () => Navigator.pop(
                    context,
                    _SelectionInput(
                      _selection.selectedItemIds,
                      _titleController?.text.trim(),
                    ),
                  ),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

String _detailMessage(
  AppLocalizations localizations,
  PrivateTemplatesMessage message,
) {
  return switch (message) {
    PrivateTemplatesMessage.created => localizations.templatesCreatedMessage,
    PrivateTemplatesMessage.saved => localizations.templatesSavedMessage,
    PrivateTemplatesMessage.updated => localizations.templatesUpdatedMessage,
    PrivateTemplatesMessage.deleted => localizations.templatesDeletedMessage,
    PrivateTemplatesMessage.categoryCreated ||
    PrivateTemplatesMessage.categoryUpdated ||
    PrivateTemplatesMessage.categoryDeleted =>
      localizations.templatesCategoryUpdatedMessage,
    PrivateTemplatesMessage.listCreated =>
      localizations.templatesListCreatedMessage,
    PrivateTemplatesMessage.imported => localizations.templatesImportedMessage,
    PrivateTemplatesMessage.invalidInput =>
      localizations.templatesInvalidInputMessage,
    PrivateTemplatesMessage.capacity => localizations.templatesCapacityExceeded,
    PrivateTemplatesMessage.staleRefreshed =>
      localizations.templatesStaleMessage,
    PrivateTemplatesMessage.unavailable =>
      localizations.templatesUnavailableMessage,
    PrivateTemplatesMessage.operationFailed =>
      localizations.templatesOperationFailedMessage,
  };
}
