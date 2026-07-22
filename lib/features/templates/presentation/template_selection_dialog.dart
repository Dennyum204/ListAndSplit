import 'package:flutter/material.dart';
import 'package:list_and_split/features/templates/domain/private_template.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class TemplateSelectionInput {
  const TemplateSelectionInput(this.selectedIds, this.title);

  final Set<String> selectedIds;
  final String? title;
}

class TemplateSelectionDialog extends StatefulWidget {
  const TemplateSelectionDialog({
    required this.title,
    required this.items,
    required this.remainingCapacity,
    required this.confirmLabel,
    this.initialTitle,
    this.destinationName,
    this.duplicateIds = const {},
    this.submissionEnabled = true,
    super.key,
  });

  final String title;
  final List<PrivateTemplateItem> items;
  final int remainingCapacity;
  final String confirmLabel;
  final String? initialTitle;
  final String? destinationName;
  final Set<String> duplicateIds;
  final bool submissionEnabled;

  @override
  State<TemplateSelectionDialog> createState() =>
      _TemplateSelectionDialogState();
}

class _TemplateSelectionDialogState extends State<TemplateSelectionDialog> {
  late TemplateSelection _selection;
  TextEditingController? _titleController;
  bool _submitted = false;

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
  void didUpdateWidget(covariant TemplateSelectionDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items ||
        oldWidget.remainingCapacity != widget.remainingCapacity) {
      final availableIds = widget.items.map((item) => item.id).toSet();
      _selection = TemplateSelection(
        availableItemIds: availableIds,
        selectedItemIds:
            _selection.selectedItemIds.where(availableIds.contains),
        remainingCapacity: widget.remainingCapacity,
      );
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
            if (widget.destinationName != null) ...[
              ListTile(
                key: const Key('fixedTemplateImportDestination'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.checklist_rounded),
                title: Text(
                  localizations.templatesImportDestinationLabel(
                    widget.destinationName!,
                  ),
                ),
              ),
              const SizedBox(height: 4),
            ],
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
                  onPressed: _submitted
                      ? null
                      : () => setState(() {
                            _selection = TemplateSelection.all(
                              widget.items.map((item) => item.id),
                              remainingCapacity: widget.remainingCapacity,
                            );
                          }),
                  child: Text(localizations.templatesSelectAllButton),
                ),
                TextButton(
                  onPressed: _submitted
                      ? null
                      : () => setState(() {
                            _selection = TemplateSelection(
                              availableItemIds:
                                  widget.items.map((item) => item.id),
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
            if (!widget.submissionEnabled)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  localizations.templatesUnavailableMessage,
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
                    onChanged: _submitted
                        ? null
                        : (_) => setState(() {
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
          onPressed: _submitted ? null : () => Navigator.pop(context),
          child: Text(localizations.cancelButton),
        ),
        FilledButton(
          key: const Key('confirmTemplateSelectionButton'),
          onPressed: !_selection.canConfirm ||
                  !titleValid ||
                  !widget.submissionEnabled ||
                  _submitted
              ? null
              : () {
                  if (_submitted) return;
                  _submitted = true;
                  setState(() {});
                  Navigator.pop(
                    context,
                    TemplateSelectionInput(
                      _selection.selectedItemIds,
                      _titleController?.text.trim(),
                    ),
                  );
                },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
