import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/core/presentation/design_widgets.dart';
import 'package:list_and_split/core/presentation/form_widgets.dart';
import 'package:list_and_split/core/theme/app_palette.dart';
import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/domain/general_note.dart';
import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/lists/presentation/active_list_chat_providers.dart';
import 'package:list_and_split/features/lists/presentation/active_list_detail_controller.dart';
import 'package:list_and_split/features/lists/presentation/active_list_providers.dart';
import 'package:list_and_split/features/notifications/presentation/notification_bell.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_avatar.dart';
import 'package:list_and_split/features/templates/domain/private_template.dart';
import 'package:list_and_split/features/templates/presentation/private_template_providers.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

enum _ListAction {
  split,
  saveTemplate,
  importTemplate,
  rename,
  archive,
  restore,
  delete,
  leave,
}

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
        final chatIsOpen = GoRouter.maybeOf(context)
                ?.routeInformationProvider
                .value
                .uri
                .path ==
            AppRoutes.listChat(listId);
        if (next.message == ActiveListDetailMessage.remotelyArchived &&
            previous?.message != ActiveListDetailMessage.remotelyArchived &&
            !chatIsOpen) {
          context.go(AppRoutes.lists);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(localizations.listRemotelyArchivedMessage)),
          );
        } else if (next.message == ActiveListDetailMessage.unavailable &&
            previous?.message != ActiveListDetailMessage.unavailable &&
            !chatIsOpen) {
          context.go(AppRoutes.lists);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(localizations.listAccessRevokedMessage)),
          );
        }
      },
    );
    return Scaffold(
      appBar: AppPageHeader(
        title: Text(detail?.summary.title ?? localizations.listsTitle),
        actions: [
          const NotificationBell(),
          if (detail != null)
            IconButton(
              key: const Key('listMembersButton'),
              disabledColor: AppPalette.lightText,
              onPressed: state.isMutating
                  ? null
                  : () => context.push(
                        '${AppRoutes.lists}/$listId/members',
                      ),
              tooltip: detail.summary.isOwner
                  ? localizations.listManageMembersButton
                  : localizations.listViewMembersButton,
              icon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${detail.participants.length}',
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 4),
                  const Icon(Icons.group_outlined),
                ],
              ),
            ),
          if (detail != null && detail.summary.isOwner)
            PopupMenuButton<_ListAction>(
              key: const Key('listActionsButton'),
              icon: const Icon(Icons.settings_outlined,
                  color: AppPalette.lightText),
              enabled: !state.isMutating,
              onSelected: (action) => _handleAction(context, ref, action),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _ListAction.split,
                  child: Text(localizations.splitTitle),
                ),
                PopupMenuItem(
                  value: _ListAction.saveTemplate,
                  child: Text(localizations.templatesSaveListButton),
                ),
                if (!archived)
                  PopupMenuItem(
                    value: _ListAction.importTemplate,
                    child: Text(
                      localizations.templatesImportFromTemplateButton,
                    ),
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
              icon: const Icon(Icons.settings_outlined,
                  color: AppPalette.lightText),
              enabled: !state.isMutating,
              onSelected: (action) => _handleAction(context, ref, action),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _ListAction.split,
                  child: Text(localizations.splitTitle),
                ),
                PopupMenuItem(
                  value: _ListAction.saveTemplate,
                  child: Text(localizations.templatesSaveListButton),
                ),
                if (!archived)
                  PopupMenuItem(
                    value: _ListAction.importTemplate,
                    child: Text(
                      localizations.templatesImportFromTemplateButton,
                    ),
                  ),
                PopupMenuItem(
                  value: _ListAction.leave,
                  child: Text(localizations.listLeaveButton),
                ),
              ],
            ),
        ],
      ),
      bottomNavigationBar: detail != null && !archived
          ? _QuickAddItem(key: ValueKey('quickAdd-$listId'), listId: listId)
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
      case _ListAction.split:
        await context.push<void>(AppRoutes.listSplit(listId));
      case _ListAction.saveTemplate:
        await _showSaveAsTemplate(context, ref);
      case _ListAction.importTemplate:
        await context.push<bool>(AppRoutes.listTemplateImport(listId));
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
        titlePadding: EdgeInsets.zero,
        title: AppDialogTitle(localizations.listLeaveTitle),
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
            scrollable: true,
            titlePadding: EdgeInsets.zero,
            title: AppDialogTitle(localizations.listRenameTitle),
            content: SingleChildScrollView(
                child: AppDialogField(
              label: localizations.listsTitleLabel,
              child: TextFormField(
                style: AppPalette.inputTextStyle(context),
                key: const Key('renameListTitle'),
                initialValue: title,
                autofocus: true,
                enabled: !state.isMutating,
                maxLength: 80,
                decoration: InputDecoration(
                  helperText: localizations.listsTitleHelper,
                ),
                onChanged: (value) => title = value,
              ),
            )),
            actions: [
              OutlinedButton(
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
        titlePadding: EdgeInsets.zero,
        title: AppDialogTitle(localizations.listDeleteTitle),
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
}

enum ListDetailSection { items, split, chat }

/// Presentation-only navigation over the existing list routes. Chat keeps its
/// route-owned provider lifetime; no conversation is embedded into another tab.
class ListSectionNavigation extends StatefulWidget {
  const ListSectionNavigation({
    required this.listId,
    required this.selected,
    this.enabled = true,
    super.key,
  });

  final String listId;
  final ListDetailSection selected;
  final bool enabled;

  @override
  State<ListSectionNavigation> createState() => _ListSectionNavigationState();
}

class _ListSectionNavigationState extends State<ListSectionNavigation> {
  bool _openingSplit = false;

  Future<void> _openSplit() async {
    if (_openingSplit || !widget.enabled) return;
    setState(() => _openingSplit = true);
    try {
      if (widget.selected == ListDetailSection.chat) {
        // Chat must leave the route tree, not remain mounted under Split: its
        // bottom-anchored read marker applies only to a visible conversation.
        context.go(AppRoutes.listSplit(widget.listId));
      } else {
        await context.push<void>(AppRoutes.listSplit(widget.listId));
      }
    } finally {
      if (mounted) setState(() => _openingSplit = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final enabled = widget.enabled && !_openingSplit;
    final listId = widget.listId;
    Widget section(ListDetailSection value, String label, VoidCallback onTap) {
      final isSelected = selected == value;
      return Expanded(
        child: Semantics(
          selected: isSelected,
          child: TextButton(
            key: Key('listSection-${value.name}'),
            onPressed: enabled && !isSelected ? onTap : null,
            style: TextButton.styleFrom(
              backgroundColor:
                  isSelected ? AppPalette.orange : Colors.transparent,
              foregroundColor: isSelected ? AppPalette.navy : colors.onSurface,
              disabledForegroundColor:
                  isSelected ? AppPalette.navy : colors.onSurfaceVariant,
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            ),
            child: Text(label, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Card(
      key: const Key('listSectionNavigation'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            section(
              ListDetailSection.items,
              localizations.listSectionLabel,
              () => context.go(AppRoutes.listDetail(listId)),
            ),
            section(
              ListDetailSection.split,
              localizations.splitTitle,
              _openSplit,
            ),
            Expanded(
              child: _ListChatButton(
                listId: listId,
                enabled: enabled,
                selected: selected == ListDetailSection.chat,
                showUnread: selected == ListDetailSection.items,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListChatButton extends ConsumerWidget {
  const _ListChatButton({
    required this.listId,
    required this.enabled,
    this.selected = false,
    this.showUnread = true,
  });

  final String listId;
  final bool enabled;
  final bool selected;
  final bool showUnread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final unread = !showUnread || selected
        ? null
        : ref.watch(activeListChatUnreadControllerProvider(listId)).valueOrNull;
    final label = unread == null || unread.count == 0
        ? localizations.listChatOpenButton
        : unread.count == 1
            ? localizations.listChatOpenOneUnreadLabel
            : localizations.listChatOpenUnreadLabel(unread.compactLabel);
    final onOpen = enabled && !selected
        ? () => context.go(AppRoutes.listChat(listId))
        : null;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      enabled: onOpen != null,
      excludeSemantics: true,
      label: label,
      onTap: onOpen,
      child: TextButton(
        key: const Key('listChatButton'),
        onPressed: onOpen,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          backgroundColor: selected ? AppPalette.orange : Colors.transparent,
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          disabledForegroundColor: selected
              ? AppPalette.navy
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Text(localizations.listChatSectionLabel),
            if (unread != null && unread.count > 0)
              PositionedDirectional(
                end: -9,
                top: -9,
                child: ExcludeSemantics(
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      unread.compactLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.onError,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _QuickAddItem extends ConsumerStatefulWidget {
  const _QuickAddItem({required this.listId, super.key});
  final String listId;

  @override
  ConsumerState<_QuickAddItem> createState() => _QuickAddItemState();
}

class _QuickAddItemState extends ConsumerState<_QuickAddItem> {
  final _name = TextEditingController();
  final _focus = FocusNode();
  bool _submitting = false;
  int _draftRevision = 0;

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final state = ref.read(activeListDetailControllerProvider(widget.listId));
    final detail = state.detail.valueOrNull;
    final draft = _name.text;
    if (_submitting ||
        state.isMutating ||
        detail == null ||
        detail.summary.status != ActiveListStatus.active ||
        detail.items.length >= activeListItemCapacity ||
        draft.trim().isEmpty ||
        draft.trim().length > 120) {
      return;
    }
    final revision = _draftRevision;
    setState(() => _submitting = true);
    final result = await ref
        .read(activeListDetailControllerProvider(widget.listId).notifier)
        .createItem(draft,
            quantity: ListQuantity.one,
            unit: null,
            assigneeProfileIds: const {});
    if (!mounted) return;
    setState(() {
      _submitting = false;
      if (result == ActiveListMutationOutcome.succeeded &&
          revision == _draftRevision &&
          _name.text == draft) {
        _name.clear();
      }
    });
    if (result == ActiveListMutationOutcome.succeeded) _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final state = ref.watch(activeListDetailControllerProvider(widget.listId));
    final detail = state.detail.valueOrNull;
    final atCapacity = (detail?.items.length ?? 0) >= activeListItemCapacity;
    final valid =
        _name.text.trim().isNotEmpty && _name.text.trim().length <= 120;
    final enabled = !_submitting && !state.isMutating && !atCapacity && valid;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const Key('quickAddItemName'),
                  style: AppPalette.inputTextStyle(context),
                  controller: _name,
                  focusNode: _focus,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() => _draftRevision++),
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: strings.itemQuickAddHint,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(32),
                        borderSide: const BorderSide(
                            color: AppPalette.orange, width: 1.5)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(32),
                        borderSide: const BorderSide(
                            color: AppPalette.orange, width: 1.5)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(32),
                        borderSide:
                            const BorderSide(color: AppPalette.navy, width: 2)),
                    errorText: _name.text.trim().length > 120
                        ? strings.listInvalidInputMessage
                        : null,
                    helperText: atCapacity
                        ? strings.listItemCapacityReachedMessage
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const Key('addItemButton'),
                tooltip: strings.itemAddButton,
                onPressed: enabled ? _submit : null,
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  backgroundColor: AppPalette.inputCream,
                  foregroundColor: AppPalette.navy,
                  disabledBackgroundColor:
                      valid && !atCapacity ? AppPalette.inputCream : null,
                  disabledForegroundColor:
                      valid && !atCapacity ? AppPalette.navy : null,
                ),
                icon: const Icon(Icons.add_rounded, size: 30),
              ),
            ],
          ),
        ),
      ),
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
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListSectionNavigation(
          listId: listId,
          selected: ListDetailSection.items,
          enabled: !state.isMutating,
        ),
        const SizedBox(height: 12),
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
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: detail.items.isEmpty
          ? ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                header,
                _ItemsEmpty(archived: archived),
                _GeneralNoteCard(
                  listId: listId,
                  detail: detail,
                  readOnly: archived,
                  isBusy: state.isMutating,
                ),
              ],
            )
          : ReorderableListView.builder(
              key: const Key('activeListItems'),
              header: header,
              footer: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _GeneralNoteCard(
                  listId: listId,
                  detail: detail,
                  readOnly: archived,
                  isBusy: state.isMutating,
                ),
              ),
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: detail.items.length,
              // Keep the callback supported by the Flutter 3.19 floor.
              // ignore: deprecated_member_use
              onReorder: archived || state.isMutating
                  ? (_, __) {}
                  : (oldIndex, newIndex) => ref
                      .read(
                        activeListDetailControllerProvider(listId).notifier,
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
      ActiveListDetailMessage.itemCreated => null,
      // The checked state is the completion confirmation. Inserting a success
      // banner here moved every row by 60px after each toggle, then back on
      // the next mutation. Failures/recovery remain visible below.
      ActiveListDetailMessage.itemUpdated => null,
      ActiveListDetailMessage.itemDeleted => localizations.itemDeletedMessage,
      ActiveListDetailMessage.noteSaved =>
        localizations.generalNoteSavedMessage,
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

class _GeneralNoteCard extends StatelessWidget {
  const _GeneralNoteCard({
    required this.listId,
    required this.detail,
    required this.readOnly,
    required this.isBusy,
  });

  final String listId;
  final ActiveListDetail detail;
  final bool readOnly;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final note = detail.generalNote;
    final text = note.text;
    return Card(
      key: const Key('generalNoteCard'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppPalette.orange,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: IconTheme(
              data: const IconThemeData(color: AppPalette.navy),
              child: Row(
                children: [
                  const Icon(Icons.sticky_note_2_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      localizations.generalNoteTitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppPalette.navy,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  if (readOnly)
                    Semantics(
                      container: true,
                      label: localizations.generalNoteReadOnlyLabel,
                      child: const Icon(Icons.lock_outline_rounded, size: 20),
                    ),
                ],
              ),
            ),
          ),
          if (!readOnly)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                key: const Key('editGeneralNoteButton'),
                style: TextButton.styleFrom(
                  disabledForegroundColor:
                      Theme.of(context).colorScheme.primary,
                ),
                onPressed: isBusy
                    ? null
                    : () => showDialog<void>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => _GeneralNoteDialog(
                            listId: listId,
                            initialNote: note,
                          ),
                        ),
                icon: const Icon(Icons.edit_outlined),
                label: Text(localizations.generalNoteEditButton),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: text == null
                ? Text(
                    readOnly
                        ? localizations.generalNoteEmptyArchivedMessage
                        : localizations.generalNoteEmptyMessage,
                    key: const Key('generalNoteEmpty'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  )
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: SingleChildScrollView(
                      key: const Key('generalNoteScroll'),
                      child: _ResolvedGeneralNoteText(note: note),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ResolvedGeneralNoteText extends StatelessWidget {
  const _ResolvedGeneralNoteText({required this.note});

  final ActiveListGeneralNote note;

  @override
  Widget build(BuildContext context) {
    final text = note.text!;
    final localizations = AppLocalizations.of(context);
    final occurrences = generalNoteMentionOccurrences(text, note.mentions);
    final semantics = occurrences
        .map(
          (occurrence) => localizations.generalNoteResolvedMentionSemantic(
            occurrence.mention.displayName,
            occurrence.mention.username,
          ),
        )
        .toSet()
        .join('. ');
    final regularStyle = Theme.of(context).textTheme.bodyLarge;
    final mentionStyle = regularStyle?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w700,
      backgroundColor:
          Theme.of(context).colorScheme.primaryContainer.withAlpha(115),
    );
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final occurrence in occurrences) {
      if (occurrence.start < offset) continue;
      if (occurrence.start > offset) {
        spans.add(TextSpan(text: text.substring(offset, occurrence.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(occurrence.start, occurrence.end),
          style: mentionStyle,
        ),
      );
      offset = occurrence.end;
    }
    if (offset < text.length) spans.add(TextSpan(text: text.substring(offset)));
    return Semantics(
      key: const Key('generalNoteText'),
      label: semantics.isEmpty ? text : '$text. $semantics',
      readOnly: true,
      child: ExcludeSemantics(
        child: SelectableText.rich(
          TextSpan(style: regularStyle, children: spans),
        ),
      ),
    );
  }
}

class _GeneralNoteDialog extends ConsumerStatefulWidget {
  const _GeneralNoteDialog({
    required this.listId,
    required this.initialNote,
  });

  final String listId;
  final ActiveListGeneralNote initialNote;

  @override
  ConsumerState<_GeneralNoteDialog> createState() => _GeneralNoteDialogState();
}

class _GeneralNoteDialogState extends ConsumerState<_GeneralNoteDialog> {
  late final TextEditingController _text;
  late final FocusNode _focusNode;
  late ActiveListGeneralNote _baseline;
  late ActiveListGeneralNote _latest;
  late Set<String> _resolvedProfileIds;
  Set<String> _eligibleProfileIds = {};
  bool _eligibilityInitialized = false;
  GeneralNoteMentionFragment? _fragment;
  bool _dirty = false;
  bool _conflict = false;
  bool _submitted = false;
  bool _showValidation = false;
  bool _closing = false;
  ModalRoute<void>? _dialogRoute;

  @override
  void initState() {
    super.initState();
    _baseline = widget.initialNote;
    _latest = widget.initialNote;
    _resolvedProfileIds = widget.initialNote.mentionedProfileIds;
    _text = TextEditingController(text: widget.initialNote.text ?? '');
    _focusNode = FocusNode();
    _text.addListener(_handleTextOrSelection);
  }

  @override
  void dispose() {
    _text.removeListener(_handleTextOrSelection);
    _text.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _dialogRoute ??= ModalRoute.of(context);
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(activeListDetailControllerProvider(widget.listId));
    final detail = state.detail.valueOrNull;
    final participants =
        detail?.participants ?? const <ActiveListParticipant>[];
    if (!_eligibilityInitialized) {
      _eligibleProfileIds =
          participants.map((participant) => participant.profileId).toSet();
      _eligibilityInitialized = true;
    }
    ref.listen<ActiveListDetailState>(
      activeListDetailControllerProvider(widget.listId),
      (_, next) => _handleAuthoritativeChange(next),
    );
    final count = generalNoteCodePointLength(_text.text);
    final overLimit = count > generalNoteMaximumCodePoints;
    final suggestions = _suggestions(participants);
    final selectedMentions = _selectedMentions(participants);
    final recoveryInProgress =
        state.message == ActiveListDetailMessage.recoveryInProgress;
    final dialogStatus = _dialogStatus(localizations, state.message);
    final formEnabled = !state.isMutating &&
        !_submitted &&
        !_closing &&
        !_conflict &&
        !recoveryInProgress;
    return AlertDialog(
      titlePadding: EdgeInsets.zero,
      title: AppDialogTitle(localizations.generalNoteEditorTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_conflict)
                Semantics(
                  key: const Key('generalNoteConflict'),
                  liveRegion: true,
                  child: Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(localizations.generalNoteDraftConflictMessage),
                          const SizedBox(height: 8),
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton(
                                key: const Key('keepGeneralNoteDraftButton'),
                                onPressed: _keepDraftAgainstLatest,
                                child: Text(
                                  localizations.generalNoteKeepDraftButton,
                                ),
                              ),
                              FilledButton.tonal(
                                key: const Key('useLatestGeneralNoteButton'),
                                onPressed: _useLatest,
                                child: Text(
                                  localizations.generalNoteUseLatestButton,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_conflict) const SizedBox(height: 12),
              if (dialogStatus != null) ...[
                Semantics(
                  key: const Key('generalNoteDialogStatus'),
                  container: true,
                  liveRegion: true,
                  child: Card(
                    color: _isGeneralNoteFailureMessage(state.message)
                        ? Theme.of(context).colorScheme.errorContainer
                        : Theme.of(context).colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(dialogStatus),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              AppDialogField(
                label: localizations.generalNoteFieldLabel,
                child: TextField(
                  style: AppPalette.inputTextStyle(context),
                  key: const Key('generalNoteField'),
                  controller: _text,
                  focusNode: _focusNode,
                  autofocus: true,
                  enabled: formEnabled,
                  minLines: 6,
                  maxLines: 12,
                  textCapitalization: TextCapitalization.sentences,
                  keyboardType: TextInputType.multiline,
                  inputFormatters: const [_GeneralNoteCodePointFormatter()],
                  decoration: InputDecoration(
                    helperText: localizations.generalNoteFieldHelper,
                    errorText: (_showValidation || overLimit) && overLimit
                        ? localizations.generalNoteCharacterLimitError
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Semantics(
                key: const Key('generalNoteRemainingCount'),
                liveRegion: true,
                label: localizations.generalNoteRemainingCount(
                  generalNoteMaximumCodePoints - count,
                  generalNoteMaximumCodePoints,
                ),
                child: ExcludeSemantics(
                  child: Text(
                    localizations.generalNoteRemainingCount(
                      generalNoteMaximumCodePoints - count,
                      generalNoteMaximumCodePoints,
                    ),
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ),
              if (_fragment != null) ...[
                const SizedBox(height: 8),
                Semantics(
                  container: true,
                  label: localizations.generalNoteMentionSuggestionsLabel,
                  child: suggestions.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(localizations.generalNoteNoSuggestions),
                        )
                      : Column(
                          key: const Key('generalNoteMentionSuggestions'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final participant in suggestions)
                              Semantics(
                                container: true,
                                button: true,
                                enabled: formEnabled,
                                label: localizations
                                    .generalNoteMentionSuggestionSemantic(
                                  participant.displayName,
                                  participant.username,
                                ),
                                onTap: formEnabled
                                    ? () => _selectMention(participant)
                                    : null,
                                child: ExcludeSemantics(
                                  child: ListTile(
                                    key: Key(
                                      'generalNoteMention-${participant.profileId}',
                                    ),
                                    leading: ProfileAvatar(
                                      label: participant.displayName,
                                      target: AvatarTarget.profile(
                                          participant.profileId),
                                    ),
                                    title: Text(
                                      _identityName(
                                        displayName: participant.displayName,
                                        username: participant.username,
                                      ),
                                    ),
                                    subtitle: Text('@${participant.username}'),
                                    onTap: formEnabled
                                        ? () => _selectMention(participant)
                                        : null,
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
              if (selectedMentions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Semantics(
                  container: true,
                  label: localizations.generalNoteSelectedMentionsLabel,
                  child: Wrap(
                    key: const Key('generalNoteSelectedMentions'),
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final participant in selectedMentions)
                        Semantics(
                          key: Key(
                            'generalNoteSelectedSemantic-${participant.profileId}',
                          ),
                          selected: true,
                          button: formEnabled,
                          enabled: formEnabled,
                          label:
                              localizations.generalNoteSelectedMentionSemantic(
                            participant.displayName,
                            participant.username,
                          ),
                          onTap: formEnabled
                              ? () => _removeResolvedMention(
                                    participant.profileId,
                                  )
                              : null,
                          child: ExcludeSemantics(
                            child: InputChip(
                              key: Key(
                                'generalNoteSelected-${participant.profileId}',
                              ),
                              avatar: ProfileAvatar(
                                label: participant.displayName,
                                target:
                                    AvatarTarget.profile(participant.profileId),
                                size: 24,
                              ),
                              label: Text(
                                '${_identityName(
                                  displayName: participant.displayName,
                                  username: participant.username,
                                )} (@${participant.username})',
                              ),
                              onSelected: formEnabled
                                  ? (_) => _removeResolvedMention(
                                        participant.profileId,
                                      )
                                  : null,
                              onDeleted: formEnabled
                                  ? () => _removeResolvedMention(
                                        participant.profileId,
                                      )
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          key: const Key('cancelGeneralNoteButton'),
          onPressed:
              state.isMutating || _submitted || _closing ? null : _closeNow,
          child: Text(localizations.cancelButton),
        ),
        FilledButton(
          key: const Key('saveGeneralNoteButton'),
          onPressed: formEnabled && !overLimit ? _submit : null,
          child: state.isMutating || _submitted
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(localizations.generalNoteSaveButton),
        ),
      ],
    );
  }

  List<ActiveListParticipant> _suggestions(
    List<ActiveListParticipant> participants,
  ) {
    final fragment = _fragment;
    if (fragment == null) return const [];
    final candidates = participants
        .where(
          (participant) => participant.username.startsWith(fragment.query),
        )
        .toList(growable: false)
      ..sort((left, right) {
        final usernameOrder = left.username.compareTo(right.username);
        return usernameOrder != 0
            ? usernameOrder
            : left.profileId.compareTo(right.profileId);
      });
    return candidates;
  }

  List<ActiveListParticipant> _selectedMentions(
    List<ActiveListParticipant> participants,
  ) {
    final selected = participants
        .where(
          (participant) => _resolvedProfileIds.contains(participant.profileId),
        )
        .toList(growable: false)
      ..sort((left, right) {
        final usernameOrder = left.username.compareTo(right.username);
        return usernameOrder != 0
            ? usernameOrder
            : left.profileId.compareTo(right.profileId);
      });
    return selected;
  }

  void _handleTextOrSelection() {
    if (!mounted || _closing) return;
    final selection = _text.selection;
    final nextFragment = selection.isValid && selection.isCollapsed
        ? generalNoteMentionFragmentAt(_text.text, selection.extentOffset)
        : null;
    _resolvedProfileIds.removeWhere((profileId) {
      final participant = _participantFor(profileId);
      return participant == null ||
          !containsGeneralNoteMentionToken(
            _text.text,
            participant.username,
          );
    });
    final baselineIds = _baseline.mentionedProfileIds;
    final nextDirty =
        normalizedGeneralNoteOrNull(_text.text) != _baseline.text ||
            !setEquals(_resolvedProfileIds, baselineIds);
    if (_fragment?.start != nextFragment?.start ||
        _fragment?.end != nextFragment?.end ||
        _fragment?.query != nextFragment?.query ||
        _dirty != nextDirty) {
      setState(() {
        _fragment = nextFragment;
        _dirty = nextDirty;
      });
    }
  }

  ActiveListParticipant? _participantFor(String profileId) {
    final detail = ref
        .read(activeListDetailControllerProvider(widget.listId))
        .detail
        .valueOrNull;
    if (detail == null) return null;
    for (final participant in detail.participants) {
      if (participant.profileId == profileId) return participant;
    }
    return null;
  }

  void _selectMention(ActiveListParticipant participant) {
    final selection = _text.selection;
    final insertion = insertGeneralNoteMention(
      text: _text.text,
      selectionStart: selection.start,
      selectionEnd: selection.end,
      username: participant.username,
    );
    if (insertion == null) return;
    _resolvedProfileIds.add(participant.profileId);
    _text.value = TextEditingValue(
      text: insertion.text,
      selection: TextSelection.collapsed(offset: insertion.caretOffset),
    );
    _focusNode.requestFocus();
    _handleTextOrSelection();
  }

  void _removeResolvedMention(String profileId) {
    if (_closing || _submitted || _conflict) return;
    if (!_resolvedProfileIds.remove(profileId)) return;
    setState(() {});
    _handleTextOrSelection();
    _focusNode.requestFocus();
  }

  Future<void> _submit() async {
    if (_submitted || _closing || _conflict) return;
    if (generalNoteCodePointLength(_text.text) > generalNoteMaximumCodePoints) {
      setState(() => _showValidation = true);
      return;
    }
    _submitted = true;
    setState(() {});
    final outcome = await ref
        .read(activeListDetailControllerProvider(widget.listId).notifier)
        .updateGeneralNote(
          _text.text,
          mentionedProfileIds: _resolvedProfileIds,
          expectedGeneralNoteVersion: _baseline.version,
        );
    if (!mounted) return;
    if (outcome == ActiveListMutationOutcome.succeeded) {
      _closeNow();
      return;
    }
    if (outcome == ActiveListMutationOutcome.unavailable) {
      _scheduleClose();
      return;
    }
    setState(() => _submitted = false);
  }

  void _handleAuthoritativeChange(ActiveListDetailState next) {
    if (_closing) return;
    if (next.message == ActiveListDetailMessage.unavailable ||
        next.message == ActiveListDetailMessage.remotelyArchived) {
      _scheduleClose();
      return;
    }
    final detail = next.detail.valueOrNull;
    if (detail == null) return;
    final latest = detail.generalNote;
    final latestEligible =
        detail.participants.map((participant) => participant.profileId).toSet();
    final eligibilityChanged = !setEquals(
      latestEligible,
      _eligibleProfileIds,
    );
    final authoritativeNoteChanged = latest.version != _baseline.version;
    _latest = latest;
    _eligibleProfileIds = latestEligible;
    if (!eligibilityChanged && !authoritativeNoteChanged) {
      _baseline = latest;
      return;
    }
    if (!_dirty) {
      _applyLatest();
      return;
    }
    if (!_conflict) {
      setState(() => _conflict = true);
    }
  }

  void _keepDraftAgainstLatest() {
    _baseline = _latest;
    _resolvedProfileIds.retainAll(_eligibleProfileIds);
    _resolvedProfileIds.removeWhere((profileId) {
      final participant = _participantFor(profileId);
      return participant == null ||
          !containsGeneralNoteMentionToken(
            _text.text,
            participant.username,
          );
    });
    setState(() {
      _conflict = false;
      _fragment = null;
      _dirty = normalizedGeneralNoteOrNull(_text.text) != _baseline.text ||
          !setEquals(
            _resolvedProfileIds,
            _baseline.mentionedProfileIds,
          );
    });
    _focusNode.requestFocus();
  }

  void _useLatest() {
    _applyLatest();
    _focusNode.requestFocus();
  }

  void _applyLatest() {
    _baseline = _latest;
    _resolvedProfileIds = _latest.mentionedProfileIds;
    _text.value = TextEditingValue(
      text: _latest.text ?? '',
      selection: TextSelection.collapsed(
        offset: (_latest.text ?? '').length,
      ),
    );
    setState(() {
      _conflict = false;
      _dirty = false;
      _fragment = null;
    });
  }

  void _scheduleClose() {
    if (_closing) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _popOwnedDialogRoute());
  }

  void _closeNow() {
    if (_closing) return;
    _closing = true;
    _popOwnedDialogRoute();
  }

  void _popOwnedDialogRoute() {
    final route = _dialogRoute;
    if (!mounted || route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    navigator.popUntil((candidate) => identical(candidate, route));
    if (route.isCurrent) navigator.pop();
  }

  String? _dialogStatus(
    AppLocalizations localizations,
    ActiveListDetailMessage? message,
  ) {
    return switch (message) {
      ActiveListDetailMessage.recoveryInProgress =>
        localizations.listRecoveryInProgressMessage,
      ActiveListDetailMessage.recoveryFailed =>
        localizations.listRecoveryFailedMessage,
      ActiveListDetailMessage.refreshFailed =>
        localizations.listRefreshFailedMessage,
      ActiveListDetailMessage.operationFailed =>
        localizations.operationFailedMessage,
      ActiveListDetailMessage.invalidInput =>
        localizations.listInvalidInputMessage,
      _ => null,
    };
  }
}

bool _isGeneralNoteFailureMessage(ActiveListDetailMessage? message) {
  return message == ActiveListDetailMessage.recoveryFailed ||
      message == ActiveListDetailMessage.refreshFailed ||
      message == ActiveListDetailMessage.operationFailed ||
      message == ActiveListDetailMessage.invalidInput;
}

class _GeneralNoteCodePointFormatter extends TextInputFormatter {
  const _GeneralNoteCodePointFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return generalNoteCodePointLength(newValue.text) <=
            generalNoteMaximumCodePoints
        ? newValue
        : oldValue;
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
      color: item.isCompleted
          ? Color.lerp(Theme.of(context).cardTheme.color,
              Theme.of(context).colorScheme.onSurface, .09)
          : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            checkColor:
                readOnly ? null : Theme.of(context).colorScheme.onPrimary,
            // Disabling the mutation callback must not dim unchecked outlines.
            // Archived controls still use the normal disabled appearance.
            side: readOnly
                ? null
                // Retain the Flutter 3.19 floor.
                // ignore: deprecated_member_use
                : MaterialStateBorderSide.resolveWith((states) {
                    // ignore: deprecated_member_use
                    if (states.contains(MaterialState.selected)) {
                      return const BorderSide(
                          width: 0, color: Colors.transparent);
                    }
                    final colors = Theme.of(context).colorScheme;
                    // ignore: deprecated_member_use
                    if (states.contains(MaterialState.error)) {
                      return BorderSide(color: colors.error, width: 2);
                    }
                    final interactive =
                        // ignore: deprecated_member_use
                        states.contains(MaterialState.pressed) ||
                            // ignore: deprecated_member_use
                            states.contains(MaterialState.hovered) ||
                            // ignore: deprecated_member_use
                            states.contains(MaterialState.focused);
                    return BorderSide(
                      color: interactive
                          ? colors.onSurface
                          : colors.onSurfaceVariant,
                      width: 2,
                    );
                  }),
            // A pending mutation disables interaction without flashing every
            // checkbox into the disabled palette and back.
            fillColor: readOnly
                ? null
                // Retain the Flutter 3.19 floor; renamed WidgetState APIs
                // are unavailable there.
                // ignore: deprecated_member_use
                : MaterialStateProperty.resolveWith(
                    // ignore: deprecated_member_use
                    (states) => states.contains(MaterialState.selected)
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                  ),
            onChanged: readOnly || isBusy
                ? null
                : (value) => controller.setItemCompleted(item, value ?? false),
          ),
        ),
        title: Text(
          item.name,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            decoration: item.isCompleted ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.assignees.isEmpty)
              Semantics(
                key: Key('itemAssignees-${item.id}'),
                label: localizations.itemUnassignedSemanticLabel(item.name),
                child: Text(quantity),
              )
            else ...[
              Text(quantity),
              const SizedBox(height: 2),
              _AssigneeSummary(item: item),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!readOnly)
              PopupMenuButton<String>(
                key: Key('itemActions-${item.id}'),
                icon: Icon(Icons.more_vert,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
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
        titlePadding: EdgeInsets.zero,
        title: AppDialogTitle(localizations.itemDeleteTitle),
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
  late final Set<String> _assigneeProfileIds;
  late final Set<String> _initialAssigneeProfileIds;
  ListUnit? _unit;
  bool _showValidation = false;
  bool _submitted = false;
  bool _dialogClosing = false;
  ModalRoute<void>? _dialogRoute;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.item?.name ?? '');
    _quantity = TextEditingController(
      text: widget.item?.quantity.format() ?? ListQuantity.one.format(),
    );
    _assigneeProfileIds =
        widget.item?.assignees.map((assignee) => assignee.profileId).toSet() ??
            {};
    _initialAssigneeProfileIds = Set.unmodifiable(_assigneeProfileIds);
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
    _dialogRoute ??= ModalRoute.of(context);
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(activeListDetailControllerProvider(widget.listId));
    final detail = state.detail.valueOrNull;
    final participants =
        detail?.participants ?? const <ActiveListParticipant>[];
    final authenticatedProfileId = ref.watch(verifiedUserIdProvider);
    ref.listen<ActiveListDetailState>(
      activeListDetailControllerProvider(widget.listId),
      (_, next) => _handleAuthoritativeChange(next),
    );
    final quantity = ListQuantity.tryParse(_quantity.text);
    final nameValid =
        _name.text.trim().isNotEmpty && _name.text.trim().length <= 120;
    final formEnabled = !state.isMutating && !_submitted && !_dialogClosing;
    return AlertDialog(
      titlePadding: EdgeInsets.zero,
      title: AppDialogTitle(
        widget.item == null
            ? localizations.itemAddTitle
            : localizations.itemEditTitle,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppDialogField(
              label: localizations.itemNameLabel,
              child: TextField(
                style: AppPalette.inputTextStyle(context),
                key: const Key('itemNameField'),
                controller: _name,
                autofocus: true,
                enabled: formEnabled,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  helperText: localizations.itemNameHelper,
                  errorText: _showValidation && !nameValid
                      ? localizations.listInvalidInputMessage
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 8),
            AppDialogField(
              label: localizations.itemQuantityLabel,
              child: TextField(
                style: AppPalette.inputTextStyle(context),
                key: const Key('itemQuantityField'),
                controller: _quantity,
                enabled: formEnabled,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  helperText: localizations.itemQuantityHelper,
                  errorText: _showValidation && quantity == null
                      ? localizations.listInvalidInputMessage
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 8),
            AppDialogField(
              label: localizations.itemUnitLabel,
              child: DropdownButtonFormField<ListUnit?>(
                isExpanded: true,
                isDense: false,
                iconEnabledColor: AppPalette.navy,
                style: AppPalette.inputTextStyle(context),
                dropdownColor: AppPalette.inputCream,
                key: const Key('itemUnitField'),
                // Keep the initializer supported by the Flutter 3.19 floor.
                // ignore: deprecated_member_use
                value: _unit,
                decoration: const InputDecoration(
                  contentPadding: AppDialogField.dropdownPadding,
                ),
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
                onChanged: formEnabled
                    ? (value) => setState(() => _unit = value)
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                localizations.itemAssigneesLabel,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                localizations.itemAssigneesHelper,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            const SizedBox(height: 4),
            if (participants.isEmpty)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(localizations.itemUnassignedLabel),
              )
            else
              for (final participant in participants)
                CheckboxListTile(
                  key: Key('itemAssignee-${participant.profileId}'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _assigneeProfileIds.contains(participant.profileId),
                  onChanged: formEnabled
                      ? (selected) => setState(() {
                            if (selected == true) {
                              _assigneeProfileIds.add(participant.profileId);
                            } else {
                              _assigneeProfileIds.remove(participant.profileId);
                            }
                          })
                      : null,
                  secondary: ProfileAvatar(
                    label: participant.displayName,
                    target: AvatarTarget.profile(participant.profileId),
                  ),
                  title: Text(
                    participant.profileId == authenticatedProfileId
                        ? localizations.itemAssigneeYouLabel(
                            _identityName(
                              displayName: participant.displayName,
                              username: participant.username,
                            ),
                          )
                        : _identityName(
                            displayName: participant.displayName,
                            username: participant.username,
                          ),
                  ),
                  subtitle: Text('@${participant.username}'),
                ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: formEnabled ? _closeNow : null,
          child: Text(localizations.cancelButton),
        ),
        FilledButton(
          key: const Key('saveItemButton'),
          onPressed: formEnabled ? _submit : null,
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
    if (_submitted || _dialogClosing) return;
    final quantity = ListQuantity.tryParse(_quantity.text);
    if (_name.text.trim().isEmpty ||
        _name.text.trim().length > 120 ||
        quantity == null) {
      setState(() => _showValidation = true);
      return;
    }
    _submitted = true;
    setState(() {});
    final controller =
        ref.read(activeListDetailControllerProvider(widget.listId).notifier);
    final outcome = widget.item == null
        ? await controller.createItem(
            _name.text,
            quantity: quantity,
            unit: _unit,
            assigneeProfileIds: _assigneeProfileIds,
          )
        : await controller.updateItem(
            widget.item!,
            _name.text,
            quantity: quantity,
            unit: _unit,
            assigneeProfileIds: _assigneeProfileIds,
          );
    if (!mounted) return;
    if (outcome.dismissesEditor) {
      _closeNow();
    } else {
      setState(() => _submitted = false);
    }
  }

  void _handleAuthoritativeChange(ActiveListDetailState next) {
    if (_dialogClosing || _submitted || next.isMutating) {
      return;
    }
    if (next.message == ActiveListDetailMessage.unavailable ||
        next.message == ActiveListDetailMessage.remotelyArchived) {
      _scheduleClose();
      return;
    }
    final detail = next.detail.valueOrNull;
    if (detail == null) return;
    final participantIds =
        detail.participants.map((participant) => participant.profileId).toSet();
    var changed = !participantIds.containsAll(_assigneeProfileIds);
    final original = widget.item;
    if (original != null) {
      ActiveListItem? current;
      for (final item in detail.items) {
        if (item.id == original.id) {
          current = item;
          break;
        }
      }
      changed = changed ||
          current == null ||
          current.version != original.version ||
          !setEquals(
            current.assignees.map((assignee) => assignee.profileId).toSet(),
            _initialAssigneeProfileIds,
          );
    }
    if (!changed) return;

    _scheduleClose(showRefreshMessage: true);
  }

  void _scheduleClose({bool showRefreshMessage = false}) {
    if (_dialogClosing) return;
    _dialogClosing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger =
          showRefreshMessage ? ScaffoldMessenger.maybeOf(context) : null;
      final message = showRefreshMessage
          ? AppLocalizations.of(context).itemEditorRefreshedMessage
          : null;
      _popOwnedDialogRoute();
      if (messenger != null && message != null) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    });
  }

  void _closeNow() {
    if (_dialogClosing) return;
    _dialogClosing = true;
    _popOwnedDialogRoute();
  }

  void _popOwnedDialogRoute() {
    final route = _dialogRoute;
    if (!mounted || route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    navigator.popUntil((candidate) => identical(candidate, route));
    if (route.isCurrent) navigator.pop();
  }
}

class _AssigneeSummary extends StatelessWidget {
  const _AssigneeSummary({required this.item});

  final ActiveListItem item;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final names = item.assignees
        .map(
          (assignee) => _identityName(
            displayName: assignee.displayName,
            username: assignee.username,
          ),
        )
        .toList(growable: false);
    final compact = switch (names.length) {
      0 => localizations.itemUnassignedLabel,
      1 => names.single,
      2 => '${names.first}, ${names.last}',
      _ => localizations.itemAssigneesCompactMore(
          names[0],
          names[1],
          names.length - 2,
        ),
    };
    final full =
        names.isEmpty ? localizations.itemUnassignedLabel : names.join(', ');
    return Semantics(
      key: Key('itemAssignees-${item.id}'),
      label: names.isEmpty
          ? localizations.itemUnassignedSemanticLabel(item.name)
          : localizations.itemAssigneesSemanticLabel(item.name, full),
      child: ExcludeSemantics(
        child: Row(
          children: [
            if (item.assignees.isEmpty)
              const Icon(Icons.person_off_outlined, size: 18)
            else
              for (final assignee in item.assignees.take(2)) ...[
                ProfileAvatar(
                  key: Key(
                    'itemAssigneeAvatar-${item.id}-${assignee.profileId}',
                  ),
                  size: 20,
                  label: assignee.displayName,
                  target: AvatarTarget.profile(assignee.profileId),
                ),
                const SizedBox(width: 2),
              ],
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                compact,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _identityName({
  required String displayName,
  required String username,
}) {
  final normalizedDisplayName = displayName.trim();
  if (normalizedDisplayName.isNotEmpty) return normalizedDisplayName;
  final normalizedUsername = username.trim();
  return normalizedUsername.isNotEmpty ? normalizedUsername : '?';
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
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
      titlePadding: EdgeInsets.zero,
      title: AppDialogTitle(localizations.templatesSaveListTitle),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(localizations.templatesSaveListDescription),
            const SizedBox(height: 12),
            AppDialogField(
              label: localizations.templatesNameLabel,
              child: TextField(
                style: AppPalette.inputTextStyle(context),
                key: const Key('saveListTemplateNameField'),
                controller: _nameController,
                decoration: const InputDecoration(),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 12),
            AppDialogField(
              label: localizations.templatesCategoryLabel,
              child: DropdownButtonFormField<String?>(
                isExpanded: true,
                isDense: false,
                iconEnabledColor: AppPalette.navy,
                style: AppPalette.inputTextStyle(context),
                dropdownColor: AppPalette.inputCream,
                // ignore: deprecated_member_use
                value: _categoryId,
                decoration: const InputDecoration(
                  contentPadding: AppDialogField.dropdownPadding,
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
        OutlinedButton(
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
