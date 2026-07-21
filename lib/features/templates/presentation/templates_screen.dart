import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/features/notifications/presentation/notification_bell.dart';
import 'package:list_and_split/features/templates/domain/private_template.dart';
import 'package:list_and_split/features/templates/presentation/private_template_providers.dart';
import 'package:list_and_split/features/templates/presentation/private_templates_controller.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class TemplatesScreen extends ConsumerWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(privateTemplatesControllerProvider);
    ref.listen<PrivateTemplatesState>(privateTemplatesControllerProvider,
        (previous, next) {
      if (next.message != null && next.message != previous?.message) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_message(localizations, next.message!))),
        );
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.templatesTitle),
        actions: [
          IconButton(
            key: const Key('manageTemplateCategoriesButton'),
            onPressed: state.isMutating
                ? null
                : () => _showCategoryManagement(context),
            tooltip: localizations.templatesManageCategoriesButton,
            icon: const Icon(Icons.category_outlined),
          ),
          IconButton(
            onPressed: state.isMutating
                ? null
                : () => ref
                    .read(privateTemplatesControllerProvider.notifier)
                    .load(),
            tooltip: localizations.templatesRefreshTooltip,
            icon: const Icon(Icons.refresh),
          ),
          const NotificationBell(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('createTemplateButton'),
        onPressed:
            state.isMutating ? null : () => _showCreateTemplate(context, ref),
        icon: const Icon(Icons.add),
        label: Text(localizations.templatesCreateButton),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: _PrivateTemplateCatalog(
              state: state,
              onRefresh: () =>
                  ref.read(privateTemplatesControllerProvider.notifier).load(),
              onSearch: (value) => ref
                  .read(privateTemplatesControllerProvider.notifier)
                  .setSearch(value),
              onFilter: (categoryId, uncategorized) => ref
                  .read(privateTemplatesControllerProvider.notifier)
                  .setFilter(
                    categoryId: categoryId,
                    uncategorized: uncategorized,
                  ),
              onSort: (sort) => ref
                  .read(privateTemplatesControllerProvider.notifier)
                  .setSort(sort),
              onSelected: (template) => context.push(
                '${AppRoutes.templates}/${template.id}',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showCreateTemplate(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final state = ref.read(privateTemplatesControllerProvider);
    final input = await showDialog<_NamedCategoryInput>(
      context: context,
      builder: (_) => _NamedCategoryDialog(
        title: AppLocalizations.of(context).templatesCreateDialogTitle,
        initialName: '',
        initialCategoryId: null,
        categories: state.categories.valueOrNull ?? const [],
      ),
    );
    if (input == null || !context.mounted) return;
    await ref.read(privateTemplatesControllerProvider.notifier).createTemplate(
          input.name,
          categoryId: input.categoryId,
        );
  }

  Future<void> _showCategoryManagement(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CategoryManagementSheet(),
    );
  }
}

class PrivateTemplatePickerScreen extends ConsumerWidget {
  const PrivateTemplatePickerScreen({
    required this.destinationListId,
    super.key,
  });

  final String destinationListId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final provider = privateTemplatePickerControllerProvider(destinationListId);
    final state = ref.watch(provider);
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.templatesImportPickerTitle),
        actions: [
          IconButton(
            onPressed: state.isMutating
                ? null
                : () => ref.read(provider.notifier).load(),
            tooltip: localizations.templatesRefreshTooltip,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: _PrivateTemplateCatalog(
              state: state,
              onRefresh: () => ref.read(provider.notifier).load(),
              onSearch: (value) => ref.read(provider.notifier).setSearch(value),
              onFilter: (categoryId, uncategorized) =>
                  ref.read(provider.notifier).setFilter(
                        categoryId: categoryId,
                        uncategorized: uncategorized,
                      ),
              onSort: (sort) => ref.read(provider.notifier).setSort(sort),
              onSelected: (template) async {
                final imported = await context.push<bool>(
                  AppRoutes.listTemplateImportPreview(
                    destinationListId,
                    template.id,
                  ),
                );
                if (imported == true && context.mounted) {
                  context.pop(true);
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}

typedef _SetTemplateFilter = Future<void> Function(
  String? categoryId,
  bool uncategorized,
);

class _PrivateTemplateCatalog extends StatefulWidget {
  const _PrivateTemplateCatalog({
    required this.state,
    required this.onRefresh,
    required this.onSearch,
    required this.onFilter,
    required this.onSort,
    required this.onSelected,
  });

  final PrivateTemplatesState state;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String) onSearch;
  final _SetTemplateFilter onFilter;
  final Future<void> Function(PrivateTemplateSort) onSort;
  final ValueChanged<PrivateTemplateSummary> onSelected;

  @override
  State<_PrivateTemplateCatalog> createState() =>
      _PrivateTemplateCatalogState();
}

class _PrivateTemplateCatalogState extends State<_PrivateTemplateCatalog> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.state.search);
  }

  @override
  void didUpdateWidget(covariant _PrivateTemplateCatalog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.search != widget.state.search &&
        _searchController.text != widget.state.search) {
      _searchController.text = widget.state.search;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final state = widget.state;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            key: const Key('templateSearchField'),
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: localizations.templatesSearchHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                        widget.onSearch('');
                      },
                      icon: const Icon(Icons.clear),
                    ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: widget.onSearch,
          ),
        ),
        _TemplateFilters(state: state, onFilter: widget.onFilter),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonFormField<PrivateTemplateSort>(
            key: const Key('templateSortField'),
            // ignore: deprecated_member_use
            value: state.sort,
            decoration: InputDecoration(
              labelText: localizations.templatesSortLabel,
              isDense: true,
            ),
            items: [
              DropdownMenuItem(
                value: PrivateTemplateSort.recent,
                child: Text(localizations.templatesSortRecent),
              ),
              DropdownMenuItem(
                value: PrivateTemplateSort.alphabetic,
                child: Text(localizations.templatesSortAlphabetic),
              ),
              DropdownMenuItem(
                value: PrivateTemplateSort.newest,
                child: Text(localizations.templatesSortNewest),
              ),
            ],
            onChanged: state.isMutating
                ? null
                : (sort) {
                    if (sort != null) widget.onSort(sort);
                  },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _TemplatesBody(
            state: state,
            onRefresh: widget.onRefresh,
            onSelected: widget.onSelected,
          ),
        ),
      ],
    );
  }
}

class _TemplateFilters extends StatelessWidget {
  const _TemplateFilters({required this.state, required this.onFilter});

  final PrivateTemplatesState state;
  final _SetTemplateFilter onFilter;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final categories =
        state.categories.valueOrNull ?? const <TemplateCategory>[];
    return SizedBox(
      height: 56,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              key: const Key('allTemplatesFilter'),
              selected: state.categoryId == null && !state.uncategorizedOnly,
              label: Text(localizations.templatesAllFilter),
              onSelected: (_) => onFilter(null, false),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              key: const Key('uncategorizedTemplatesFilter'),
              selected: state.uncategorizedOnly,
              label: Text(localizations.templatesUncategorizedFilter),
              onSelected: (_) => onFilter(null, true),
            ),
          ),
          for (final category in categories)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                selected: state.categoryId == category.id,
                label: Text(category.name),
                onSelected: (_) => onFilter(category.id, false),
              ),
            ),
        ],
      ),
    );
  }
}

class _TemplatesBody extends StatelessWidget {
  const _TemplatesBody({
    required this.state,
    required this.onRefresh,
    required this.onSelected,
  });

  final PrivateTemplatesState state;
  final Future<void> Function() onRefresh;
  final ValueChanged<PrivateTemplateSummary> onSelected;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return state.templates.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _TemplateEmptyState(
        icon: Icons.cloud_off_outlined,
        title: localizations.templatesLoadFailed,
        description: '',
        action: FilledButton.tonal(
          onPressed: onRefresh,
          child: Text(localizations.templatesRetryButton),
        ),
      ),
      data: (templates) {
        if (templates.isEmpty) {
          final filtered = state.search.isNotEmpty ||
              state.categoryId != null ||
              state.uncategorizedOnly;
          return _TemplateEmptyState(
            icon: filtered ? Icons.search_off : Icons.copy_all_outlined,
            title: filtered
                ? localizations.templatesNoResultsTitle
                : localizations.templatesEmptyTitle,
            description: filtered
                ? localizations.templatesNoResultsDescription
                : localizations.templatesEmptyDescription,
          );
        }
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.separated(
            key: const Key('templatesList'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: templates.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final template = templates[index];
              return Card(
                child: ListTile(
                  key: Key('template-${template.id}'),
                  leading: const CircleAvatar(
                    child: Icon(Icons.copy_all_outlined),
                  ),
                  title: Text(template.name, maxLines: 2),
                  subtitle: Text(
                    '${template.categoryName ?? localizations.templatesNoCategoryLabel} · '
                    '${localizations.templatesItemCount(template.itemCount)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onSelected(template),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _TemplateEmptyState extends StatelessWidget {
  const _TemplateEmptyState({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 52),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(description, textAlign: TextAlign.center),
              ],
              if (action != null) ...[
                const SizedBox(height: 16),
                action!,
              ],
            ],
          ),
        ),
      );
}

class _CategoryManagementSheet extends ConsumerWidget {
  const _CategoryManagementSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(privateTemplatesControllerProvider);
    final categories =
        state.categories.valueOrNull ?? const <TemplateCategory>[];
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.82,
        child: Column(
          children: [
            ListTile(
              title: Text(
                localizations.templatesCategoryManagementTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              trailing: IconButton(
                onPressed:
                    state.isMutating ? null : () => _editCategory(context, ref),
                tooltip: localizations.templatesCreateCategoryButton,
                icon: const Icon(Icons.add),
              ),
            ),
            Expanded(
              child: categories.isEmpty
                  ? Center(
                      child: Text(localizations.templatesNoCategoryLabel),
                    )
                  : ListView.builder(
                      itemCount: categories.length,
                      itemBuilder: (context, index) {
                        final category = categories[index];
                        return ListTile(
                          title: Text(category.name),
                          subtitle: Text(
                            localizations.templatesCategoryCount(
                              category.templateCount,
                            ),
                          ),
                          trailing: Wrap(
                            children: [
                              IconButton(
                                onPressed: state.isMutating
                                    ? null
                                    : () => _editCategory(
                                          context,
                                          ref,
                                          category: category,
                                        ),
                                tooltip:
                                    localizations.templatesRenameCategoryButton,
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                onPressed: state.isMutating
                                    ? null
                                    : () => _deleteCategory(
                                          context,
                                          ref,
                                          category,
                                        ),
                                tooltip:
                                    localizations.templatesDeleteCategoryButton,
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editCategory(
    BuildContext context,
    WidgetRef ref, {
    TemplateCategory? category,
  }) async {
    final localizations = AppLocalizations.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _CategoryNameDialog(
        title: category == null
            ? localizations.templatesCreateCategoryButton
            : localizations.templatesRenameCategoryButton,
        initialName: category?.name ?? '',
      ),
    );
    if (name == null || !context.mounted) return;
    final notifier = ref.read(privateTemplatesControllerProvider.notifier);
    if (category == null) {
      await notifier.createCategory(name);
    } else {
      await notifier.renameCategory(category, name);
    }
  }

  Future<void> _deleteCategory(
    BuildContext context,
    WidgetRef ref,
    TemplateCategory category,
  ) async {
    final localizations = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.templatesDeleteCategoryTitle),
        content: Text(localizations.templatesDeleteCategoryDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(localizations.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(localizations.templatesDeleteCategoryButton),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref
          .read(privateTemplatesControllerProvider.notifier)
          .deleteCategory(category);
    }
  }
}

class _CategoryNameDialog extends StatefulWidget {
  const _CategoryNameDialog({
    required this.title,
    required this.initialName,
  });

  final String title;
  final String initialName;

  @override
  State<_CategoryNameDialog> createState() => _CategoryNameDialogState();
}

class _CategoryNameDialogState extends State<_CategoryNameDialog> {
  late final TextEditingController _nameController;
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _close([String? name]) {
    if (_isClosing) return;
    setState(() => _isClosing = true);
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('categoryNameField'),
        controller: _nameController,
        autofocus: true,
        decoration: InputDecoration(
          labelText: localizations.templatesCategoryNameLabel,
        ),
        onSubmitted: _isClosing ? null : _close,
      ),
      actions: [
        TextButton(
          key: const Key('cancelCategoryNameButton'),
          onPressed: _isClosing ? null : _close,
          child: Text(localizations.cancelButton),
        ),
        FilledButton(
          key: const Key('confirmCategoryNameButton'),
          onPressed: _isClosing ? null : () => _close(_nameController.text),
          child: Text(widget.title),
        ),
      ],
    );
  }
}

class _NamedCategoryInput {
  const _NamedCategoryInput(this.name, this.categoryId);

  final String name;
  final String? categoryId;
}

class _NamedCategoryDialog extends StatefulWidget {
  const _NamedCategoryDialog({
    required this.title,
    required this.initialName,
    required this.initialCategoryId,
    required this.categories,
  });

  final String title;
  final String initialName;
  final String? initialCategoryId;
  final List<TemplateCategory> categories;

  @override
  State<_NamedCategoryDialog> createState() => _NamedCategoryDialogState();
}

class _NamedCategoryDialogState extends State<_NamedCategoryDialog> {
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
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('templateNameField'),
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: localizations.templatesNameLabel,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: const Key('templateCategoryField'),
              // ignore: deprecated_member_use
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
            _NamedCategoryInput(_nameController.text, _categoryId),
          ),
          child: Text(localizations.saveButton),
        ),
      ],
    );
  }
}

String _message(
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
