import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/presentation/form_widgets.dart';
import 'package:list_and_split/features/notifications/presentation/notification_bell.dart';
import 'package:list_and_split/features/split/domain/list_split.dart';
import 'package:list_and_split/features/split/presentation/list_split_controller.dart';
import 'package:list_and_split/features/split/presentation/list_split_providers.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class ListSplitScreen extends ConsumerWidget {
  const ListSplitScreen({required this.listId, super.key});

  final String listId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(listSplitControllerProvider(listId));
    final overview = state.overview.valueOrNull;
    final localizations = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          overview == null
              ? localizations.splitTitle
              : localizations.splitListTitle(overview.listTitle),
        ),
        actions: const [NotificationBell()],
      ),
      floatingActionButton:
          overview?.enabled == true && overview?.writable == true
              ? FloatingActionButton.extended(
                  key: const Key('addExpenseButton'),
                  onPressed: state.isMutating ||
                          overview!.expenses.length >= splitExpenseCapacity
                      ? null
                      : () => _showExpenseDialog(context, ref, overview),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(localizations.splitAddExpenseButton),
                )
              : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: state.overview.when(
              loading: () => Semantics(
                liveRegion: true,
                label: localizations.splitLoadingLabel,
                child: const Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => _SplitError(
                onRetry: () => ref
                    .read(listSplitControllerProvider(listId).notifier)
                    .load(),
              ),
              data: (loaded) => RefreshIndicator(
                onRefresh: () => ref
                    .read(listSplitControllerProvider(listId).notifier)
                    .refresh(),
                child: _SplitBody(
                  listId: listId,
                  overview: loaded,
                  state: state,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showExpenseDialog(
    BuildContext context,
    WidgetRef ref,
    ListSplitOverview overview, {
    ListSplitExpense? expense,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible:
          !ref.read(listSplitControllerProvider(listId)).isMutating,
      builder: (_) => ExpenseFormDialog(
        listId: listId,
        initialOverview: overview,
        expense: expense,
      ),
    );
  }
}

class _SplitBody extends ConsumerWidget {
  const _SplitBody({
    required this.listId,
    required this.overview,
    required this.state,
  });

  final String listId;
  final ListSplitOverview overview;
  final ListSplitState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    return ListView(
      key: const Key('splitOverview'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        if (overview.listStatus == SplitListStatus.archived)
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(localizations.splitArchivedBanner),
            ),
          ),
        FormMessageBanner(message: _messageText(localizations, state.message)),
        if (!overview.enabled)
          _DisabledSplitState(listId: listId, overview: overview, state: state)
        else ...[
          _SplitSummaryCard(listId: listId, overview: overview, state: state),
          const SizedBox(height: 16),
          Text(
            localizations.splitBalancesTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (overview.participants.isEmpty)
            Text(localizations.splitNoBalancesMessage)
          else
            ...overview.participants.map(
              (participant) => _BalanceTile(
                participant: participant,
                currency: overview.currency!,
              ),
            ),
          const SizedBox(height: 20),
          _SettlementSuggestionsSection(
            listId: listId,
            overview: overview,
            state: state,
          ),
          const SizedBox(height: 20),
          _SettlementHistorySection(
            listId: listId,
            overview: overview,
            state: state,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  localizations.splitExpensesTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Text(localizations.splitExpenseCount(overview.expenses.length)),
            ],
          ),
          const SizedBox(height: 8),
          if (overview.expenses.isEmpty)
            _EmptyExpenses(writable: overview.writable)
          else
            ...overview.expenses.map(
              (expense) => _ExpenseCard(
                listId: listId,
                overview: overview,
                expense: expense,
                isBusy: state.isMutating,
              ),
            ),
        ],
      ],
    );
  }
}

class _DisabledSplitState extends ConsumerStatefulWidget {
  const _DisabledSplitState({
    required this.listId,
    required this.overview,
    required this.state,
  });

  final String listId;
  final ListSplitOverview overview;
  final ListSplitState state;

  @override
  ConsumerState<_DisabledSplitState> createState() =>
      _DisabledSplitStateState();
}

class _DisabledSplitStateState extends ConsumerState<_DisabledSplitState> {
  SplitCurrency _currency = SplitCurrency.chf;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final canEnable = widget.overview.isOwner &&
        widget.overview.listStatus == SplitListStatus.active;
    return Card(
      key: const Key('splitDisabledState'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              canEnable ? Icons.receipt_long_outlined : Icons.lock_outline,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              canEnable
                  ? localizations.splitEnableTitle
                  : widget.overview.listStatus == SplitListStatus.archived
                      ? localizations.splitArchivedDisabledMessage
                      : localizations.splitOwnerMustEnableMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (canEnable) ...[
              const SizedBox(height: 20),
              DropdownButtonFormField<SplitCurrency>(
                key: const Key('splitCurrencyField'),
                // Keep the initializer supported by the Flutter 3.19 floor.
                // ignore: deprecated_member_use
                value: _currency,
                decoration: InputDecoration(
                  labelText: localizations.splitCurrencyLabel,
                ),
                items: [
                  for (final currency in SplitCurrency.values)
                    DropdownMenuItem(
                      value: currency,
                      child: Text(currency.code),
                    ),
                ],
                onChanged: widget.state.isMutating
                    ? null
                    : (value) {
                        if (value != null) setState(() => _currency = value);
                      },
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('enableSplitButton'),
                onPressed: widget.state.isMutating
                    ? null
                    : () => ref
                        .read(
                          listSplitControllerProvider(widget.listId).notifier,
                        )
                        .enable(_currency),
                child: widget.state.isMutating
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(localizations.splitEnableButton),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SplitSummaryCard extends ConsumerWidget {
  const _SplitSummaryCard({
    required this.listId,
    required this.overview,
    required this.state,
  });

  final String listId;
  final ListSplitOverview overview;
  final ListSplitState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final userId = ref
        .watch(listSplitControllerProvider(listId).notifier)
        .authenticatedProfileId;
    final caller = overview.participantForProfile(userId);
    final currency = overview.currency!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    localizations.splitCurrencyValue(currency.code),
                    key: const Key('splitCurrencyValue'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (overview.isOwner &&
                    overview.writable &&
                    overview.expenses.isEmpty &&
                    state.settlementHistory.valueOrNull?.entries.isEmpty ==
                        true)
                  TextButton(
                    key: const Key('changeSplitCurrencyButton'),
                    onPressed: state.isMutating
                        ? null
                        : () => _showCurrencyDialog(context, ref),
                    child: Text(localizations.splitChangeCurrencyButton),
                  ),
              ],
            ),
            const Divider(),
            Text(
              _callerBalanceText(
                  localizations, caller?.balanceMinor ?? 0, currency),
              key: const Key('currentSplitBalance'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCurrencyDialog(BuildContext context, WidgetRef ref) async {
    var selected = overview.currency!;
    final confirmed = await showDialog<SplitCurrency>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(AppLocalizations.of(context).splitChangeCurrencyTitle),
          content: DropdownButtonFormField<SplitCurrency>(
            key: const Key('changeSplitCurrencyField'),
            // Keep the initializer supported by the Flutter 3.19 floor.
            // ignore: deprecated_member_use
            value: selected,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context).splitCurrencyLabel,
            ),
            items: [
              for (final currency in SplitCurrency.values)
                DropdownMenuItem(value: currency, child: Text(currency.code)),
            ],
            onChanged: (value) {
              if (value != null) setDialogState(() => selected = value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context).cancelButton),
            ),
            FilledButton(
              key: const Key('confirmSplitCurrencyButton'),
              onPressed: () => Navigator.pop(context, selected),
              child: Text(AppLocalizations.of(context).saveButton),
            ),
          ],
        ),
      ),
    );
    if (confirmed != null && context.mounted) {
      await ref
          .read(listSplitControllerProvider(listId).notifier)
          .changeCurrency(confirmed);
    }
  }
}

class _BalanceTile extends StatelessWidget {
  const _BalanceTile({required this.participant, required this.currency});

  final ListSplitParticipant participant;
  final SplitCurrency currency;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final name = _participantName(localizations, participant);
    final balance = participant.balanceMinor;
    final text = balance > 0
        ? localizations.splitParticipantIsOwed(
            name,
            _formatMinor(balance, currency),
          )
        : balance < 0
            ? localizations.splitParticipantOwes(
                name,
                _formatMinor(balance.abs(), currency),
              )
            : localizations.splitParticipantSettled(name);
    return Card(
      child: ListTile(
        key: ValueKey('splitBalance-${participant.id}'),
        leading: CircleAvatar(
          child: Icon(
            participant.isAnonymized
                ? Icons.person_off_outlined
                : Icons.person_outline,
          ),
        ),
        title: Text(name),
        subtitle: Text(text),
      ),
    );
  }
}

class _SettlementSuggestionsSection extends StatelessWidget {
  const _SettlementSuggestionsSection({
    required this.listId,
    required this.overview,
    required this.state,
  });

  final String listId;
  final ListSplitOverview overview;
  final ListSplitState state;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      key: const Key('settlementSuggestionsSection'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          localizations.splitSuggestedPaymentsTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (overview.suggestions.isEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text(localizations.splitNoSuggestedPaymentsMessage),
            ),
          )
        else
          for (final suggestion in overview.suggestions)
            _SettlementSuggestionCard(
              listId: listId,
              overview: overview,
              suggestion: suggestion,
              isBusy: state.isMutating,
            ),
      ],
    );
  }
}

class _SettlementSuggestionCard extends StatelessWidget {
  const _SettlementSuggestionCard({
    required this.listId,
    required this.overview,
    required this.suggestion,
    required this.isBusy,
  });

  final String listId;
  final ListSplitOverview overview;
  final ListSettlementSuggestion suggestion;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final payer = overview.participantById(suggestion.payerParticipantId);
    final recipient =
        overview.participantById(suggestion.recipientParticipantId);
    final payerName = payer == null
        ? localizations.splitFormerParticipant
        : _participantName(localizations, payer);
    final recipientName = recipient == null
        ? localizations.splitFormerParticipant
        : _participantName(localizations, recipient);
    final description = localizations.splitSuggestedPayment(
      payerName,
      recipientName,
      _formatMinor(suggestion.amountMinor, overview.currency!),
    );
    return Card(
      key: ValueKey(
        'splitSuggestion-${suggestion.payerParticipantId}-'
        '${suggestion.recipientParticipantId}',
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.payments_outlined),
                const SizedBox(width: 12),
                Expanded(child: Text(description)),
              ],
            ),
            if (overview.writable) ...[
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton.tonal(
                  key: ValueKey(
                    'recordSuggestedPayment-'
                    '${suggestion.payerParticipantId}-'
                    '${suggestion.recipientParticipantId}',
                  ),
                  onPressed: isBusy
                      ? null
                      : () => showDialog<void>(
                            context: context,
                            barrierDismissible: !isBusy,
                            builder: (_) => SettlementFormDialog(
                              listId: listId,
                              initialOverview: overview,
                              initialSuggestion: suggestion,
                            ),
                          ),
                  child: Text(localizations.splitRecordPaymentButton),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettlementHistorySection extends ConsumerWidget {
  const _SettlementHistorySection({
    required this.listId,
    required this.overview,
    required this.state,
  });

  final String listId;
  final ListSplitOverview overview;
  final ListSplitState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    return Column(
      key: const Key('settlementHistorySection'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          localizations.splitSettlementHistoryTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        state.settlementHistory.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Card(
            child: ListTile(
              leading: const Icon(Icons.error_outline),
              title: Text(localizations.splitSettlementHistoryLoadFailed),
            ),
          ),
          data: (page) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (page.entries.isEmpty)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.history_outlined),
                    title: Text(localizations.splitNoSettlementHistoryMessage),
                  ),
                )
              else
                for (final settlement in page.entries)
                  _SettlementHistoryCard(
                    listId: listId,
                    overview: overview,
                    settlement: settlement,
                    isBusy: state.isMutating,
                  ),
              if (page.nextCursor != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton(
                    key: const Key('loadMoreSettlementsButton'),
                    onPressed:
                        state.isLoadingMoreSettlements || state.isMutating
                            ? null
                            : () => ref
                                .read(
                                  listSplitControllerProvider(listId).notifier,
                                )
                                .loadMoreSettlements(),
                    child: state.isLoadingMoreSettlements
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            localizations.splitLoadMoreSettlementsButton,
                          ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettlementHistoryCard extends ConsumerWidget {
  const _SettlementHistoryCard({
    required this.listId,
    required this.overview,
    required this.settlement,
    required this.isBusy,
  });

  final String listId;
  final ListSplitOverview overview;
  final ListSplitSettlement settlement;
  final bool isBusy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final payer = overview.participantById(settlement.payerParticipantId);
    final recipient =
        overview.participantById(settlement.recipientParticipantId);
    final recorder =
        overview.participantById(settlement.recordedByParticipantId);
    final reverser = settlement.reversal == null
        ? null
        : overview.participantById(
            settlement.reversal!.reversedByParticipantId,
          );
    final payerName = payer == null
        ? localizations.splitFormerParticipant
        : _participantName(localizations, payer);
    final recipientName = recipient == null
        ? localizations.splitFormerParticipant
        : _participantName(localizations, recipient);
    final recorderName = recorder == null
        ? localizations.splitFormerParticipant
        : _participantName(localizations, recorder);
    final title = localizations.splitSettlementHistoryEntry(
      payerName,
      recipientName,
      _formatMinor(settlement.amountMinor, overview.currency!),
    );
    final date = MaterialLocalizations.of(context)
        .formatMediumDate(settlement.createdAt.toLocal());
    final reversal = settlement.reversal;
    return Card(
      child: Semantics(
        container: true,
        label: reversal == null
            ? title
            : localizations.splitReversedSettlementSemantics(title),
        child: ListTile(
          key: ValueKey('splitSettlement-${settlement.id}'),
          leading: Icon(
            reversal == null ? Icons.payments_outlined : Icons.undo_outlined,
          ),
          title: Text(title),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                localizations.splitSettlementRecordedBy(recorderName, date),
              ),
              if (settlement.note != null) Text(settlement.note!),
              if (reversal != null)
                Text(
                  localizations.splitSettlementReversed(
                    reverser == null
                        ? localizations.splitFormerParticipant
                        : _participantName(localizations, reverser),
                    reversal.reason,
                  ),
                ),
            ],
          ),
          trailing:
              settlement.canReverse && reversal == null && overview.writable
                  ? IconButton(
                      key: ValueKey('reverseSettlement-${settlement.id}'),
                      tooltip: localizations.splitReverseSettlementButton,
                      onPressed: isBusy
                          ? null
                          : () => showDialog<void>(
                                context: context,
                                barrierDismissible: !isBusy,
                                builder: (_) => SettlementReversalDialog(
                                  listId: listId,
                                  initialOverview: overview,
                                  settlement: settlement,
                                ),
                              ),
                      icon: const Icon(Icons.undo_outlined),
                    )
                  : null,
        ),
      ),
    );
  }
}

class SettlementFormDialog extends ConsumerStatefulWidget {
  const SettlementFormDialog({
    required this.listId,
    required this.initialOverview,
    required this.initialSuggestion,
    super.key,
  });

  final String listId;
  final ListSplitOverview initialOverview;
  final ListSettlementSuggestion initialSuggestion;

  @override
  ConsumerState<SettlementFormDialog> createState() =>
      _SettlementFormDialogState();
}

class _SettlementFormDialogState extends ConsumerState<SettlementFormDialog> {
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late final String _requestId;
  late final int _initialSplitVersion;
  late String _payerId;
  late String _recipientId;
  bool _showValidation = false;
  bool _submitted = false;
  bool _retryLocked = false;
  bool _dialogClosing = false;
  ModalRoute<void>? _dialogRoute;

  @override
  void initState() {
    super.initState();
    _payerId = widget.initialSuggestion.payerParticipantId;
    _recipientId = widget.initialSuggestion.recipientParticipantId;
    _initialSplitVersion = widget.initialOverview.settings!.version;
    _requestId = ref
        .read(listSplitControllerProvider(widget.listId).notifier)
        .newSettlementRequestId();
    _amount = TextEditingController(
      text: MoneyAmount.fromMinorUnits(
        widget.initialSuggestion.amountMinor,
        widget.initialOverview.currency!,
      ).format(includeCode: false),
    );
    _note = TextEditingController();
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _dialogRoute ??= ModalRoute.of(context);
    final provider = listSplitControllerProvider(widget.listId);
    final state = ref.watch(provider);
    final overview = state.overview.valueOrNull ?? widget.initialOverview;
    final unavailable = state.message == ListSplitMessage.unavailable;
    final versionChanged =
        overview.settings?.version != _initialSplitVersion && !_submitted;
    if (unavailable || !overview.writable || versionChanged) {
      _scheduleClose();
    }
    final payerChoices = overview.participants
        .where((participant) => participant.balanceMinor < 0)
        .toList(growable: false);
    final recipientChoices = overview.participants
        .where((participant) => participant.balanceMinor > 0)
        .toList(growable: false);
    final payer = overview.participantById(_payerId);
    final recipient = overview.participantById(_recipientId);
    final maximum = payer == null || recipient == null
        ? 0
        : (-payer.balanceMinor < recipient.balanceMinor
            ? -payer.balanceMinor
            : recipient.balanceMinor);
    final parsed = MoneyAmount.tryParse(
      _amount.text,
      currency: overview.currency!,
      maxMinor: maximum,
    );
    final noteValid = _note.text.trim().length <= splitSettlementNoteMaxLength;
    final endpointsValid = payer != null &&
        recipient != null &&
        payer.balanceMinor < 0 &&
        recipient.balanceMinor > 0 &&
        payer.id != recipient.id;
    final operationEnabled = !unavailable &&
        overview.writable &&
        !versionChanged &&
        !state.isMutating &&
        !_submitted &&
        !_dialogClosing;
    final fieldsEnabled = operationEnabled && !_retryLocked;
    final localizations = AppLocalizations.of(context);
    return PopScope(
      canPop: !state.isMutating && !_submitted,
      child: AlertDialog(
        title: Text(localizations.splitRecordPaymentTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(localizations.splitRecordPaymentBookkeepingNotice),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: const Key('settlementPayerField'),
                // Keep the initializer supported by the Flutter 3.19 floor.
                // ignore: deprecated_member_use
                value: payerChoices.any((entry) => entry.id == _payerId)
                    ? _payerId
                    : null,
                decoration: InputDecoration(
                  labelText: localizations.splitSettlementPayerLabel,
                  errorText: _showValidation && !endpointsValid
                      ? localizations.splitSettlementEndpointsInvalid
                      : null,
                ),
                items: [
                  for (final participant in payerChoices)
                    DropdownMenuItem(
                      value: participant.id,
                      child: Text(_participantName(localizations, participant)),
                    ),
                ],
                onChanged: fieldsEnabled
                    ? (value) {
                        if (value != null) setState(() => _payerId = value);
                      }
                    : null,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const Key('settlementRecipientField'),
                // Keep the initializer supported by the Flutter 3.19 floor.
                // ignore: deprecated_member_use
                value: recipientChoices.any((entry) => entry.id == _recipientId)
                    ? _recipientId
                    : null,
                decoration: InputDecoration(
                  labelText: localizations.splitSettlementRecipientLabel,
                ),
                items: [
                  for (final participant in recipientChoices)
                    DropdownMenuItem(
                      value: participant.id,
                      child: Text(_participantName(localizations, participant)),
                    ),
                ],
                onChanged: fieldsEnabled
                    ? (value) {
                        if (value != null) setState(() => _recipientId = value);
                      }
                    : null,
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('settlementAmountField'),
                controller: _amount,
                autofocus: true,
                enabled: fieldsEnabled,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: localizations
                      .splitExpenseAmountLabel(overview.currency!.code),
                  helperText: maximum > 0
                      ? localizations.splitSettlementMaximum(
                          _formatMinor(maximum, overview.currency!),
                        )
                      : null,
                  errorText: _showValidation && parsed == null
                      ? localizations.splitSettlementAmountInvalid
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('settlementNoteField'),
                controller: _note,
                enabled: fieldsEnabled,
                maxLength: splitSettlementNoteMaxLength,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: localizations.splitSettlementNoteLabel,
                  errorText: _showValidation && !noteValid
                      ? localizations.splitSettlementNoteInvalid
                      : null,
                ),
              ),
              if (_retryLocked) ...[
                const SizedBox(height: 8),
                Text(
                  localizations.splitSettlementUncertainRetryMessage,
                  key: const Key('settlementRetryMessage'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: state.isMutating || _dialogClosing
                ? null
                : () {
                    _dialogClosing = true;
                    Navigator.pop(context);
                  },
            child: Text(localizations.cancelButton),
          ),
          FilledButton(
            key: const Key('saveSettlementButton'),
            onPressed: operationEnabled &&
                    endpointsValid &&
                    parsed != null &&
                    noteValid
                ? _submit
                : null,
            child: state.isMutating
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(localizations.splitRecordPaymentButton),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitted) return;
    final provider = listSplitControllerProvider(widget.listId);
    final overview = ref.read(provider).overview.valueOrNull;
    final payer = overview?.participantById(_payerId);
    final recipient = overview?.participantById(_recipientId);
    final maximum = payer == null || recipient == null
        ? 0
        : (-payer.balanceMinor < recipient.balanceMinor
            ? -payer.balanceMinor
            : recipient.balanceMinor);
    final amount = overview == null
        ? null
        : MoneyAmount.tryParse(
            _amount.text,
            currency: overview.currency!,
            maxMinor: maximum,
          );
    if (overview?.writable != true ||
        payer?.balanceMinor == null ||
        payer!.balanceMinor >= 0 ||
        recipient?.balanceMinor == null ||
        recipient!.balanceMinor <= 0 ||
        payer.id == recipient.id ||
        amount == null ||
        _note.text.trim().length > splitSettlementNoteMaxLength) {
      setState(() => _showValidation = true);
      return;
    }
    _submitted = true;
    setState(() {});
    final outcome = await ref.read(provider.notifier).recordSettlement(
          payerParticipantId: payer.id,
          recipientParticipantId: recipient.id,
          amountMinor: amount.minorUnits,
          note: _note.text,
          requestId: _requestId,
        );
    if (!mounted) return;
    if (outcome.dismissesEditor) {
      _closeNow();
    } else {
      setState(() {
        _submitted = false;
        _retryLocked = outcome == ListSplitMutationOutcome.failed;
        _showValidation = !_retryLocked;
      });
    }
  }

  void _scheduleClose() {
    if (_dialogClosing) return;
    _dialogClosing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _popOwnedRoute());
  }

  void _closeNow() {
    if (_dialogClosing) return;
    _dialogClosing = true;
    _popOwnedRoute();
  }

  void _popOwnedRoute() {
    final route = _dialogRoute;
    if (!mounted || route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    navigator.popUntil((candidate) => identical(candidate, route));
    if (route.isCurrent) navigator.pop();
  }
}

class SettlementReversalDialog extends ConsumerStatefulWidget {
  const SettlementReversalDialog({
    required this.listId,
    required this.initialOverview,
    required this.settlement,
    super.key,
  });

  final String listId;
  final ListSplitOverview initialOverview;
  final ListSplitSettlement settlement;

  @override
  ConsumerState<SettlementReversalDialog> createState() =>
      _SettlementReversalDialogState();
}

class _SettlementReversalDialogState
    extends ConsumerState<SettlementReversalDialog> {
  late final TextEditingController _reason;
  late final String _requestId;
  late final int _initialSplitVersion;
  bool _submitted = false;
  bool _retryLocked = false;
  bool _dialogClosing = false;
  bool _showValidation = false;
  ModalRoute<void>? _dialogRoute;

  @override
  void initState() {
    super.initState();
    _reason = TextEditingController();
    _initialSplitVersion = widget.initialOverview.settings!.version;
    _requestId = ref
        .read(listSplitControllerProvider(widget.listId).notifier)
        .newSettlementRequestId();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _dialogRoute ??= ModalRoute.of(context);
    final provider = listSplitControllerProvider(widget.listId);
    final state = ref.watch(provider);
    final overview = state.overview.valueOrNull ?? widget.initialOverview;
    ListSplitSettlement? liveSettlement;
    for (final entry
        in state.settlementHistory.valueOrNull?.entries ?? const []) {
      if (entry.id == widget.settlement.id) {
        liveSettlement = entry;
        break;
      }
    }
    final versionChanged =
        overview.settings?.version != _initialSplitVersion && !_submitted;
    if (state.message == ListSplitMessage.unavailable ||
        !overview.writable ||
        liveSettlement == null ||
        liveSettlement.isReversed ||
        versionChanged) {
      _scheduleClose();
    }
    final reason = _reason.text.trim();
    final valid = reason.isNotEmpty &&
        reason.length <= splitSettlementReversalReasonMaxLength;
    final operationEnabled = overview.writable &&
        !state.isMutating &&
        !_submitted &&
        !_dialogClosing &&
        !versionChanged;
    final fieldEnabled = operationEnabled && !_retryLocked;
    final localizations = AppLocalizations.of(context);
    return PopScope(
      canPop: !state.isMutating && !_submitted,
      child: AlertDialog(
        title: Text(localizations.splitReverseSettlementTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(localizations.splitReverseSettlementDescription),
              const SizedBox(height: 12),
              TextField(
                key: const Key('settlementReversalReasonField'),
                controller: _reason,
                autofocus: true,
                enabled: fieldEnabled,
                maxLength: splitSettlementReversalReasonMaxLength,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: localizations.splitReversalReasonLabel,
                  errorText: _showValidation && !valid
                      ? localizations.splitReversalReasonInvalid
                      : null,
                ),
              ),
              if (_retryLocked) ...[
                const SizedBox(height: 8),
                Text(
                  localizations.splitSettlementUncertainRetryMessage,
                  key: const Key('settlementReversalRetryMessage'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: state.isMutating || _dialogClosing
                ? null
                : () {
                    _dialogClosing = true;
                    Navigator.pop(context);
                  },
            child: Text(localizations.cancelButton),
          ),
          FilledButton(
            key: const Key('confirmReverseSettlementButton'),
            onPressed: operationEnabled && valid ? _submit : null,
            child: state.isMutating
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(localizations.splitReverseSettlementButton),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitted) return;
    final reason = _reason.text.trim();
    if (reason.isEmpty ||
        reason.length > splitSettlementReversalReasonMaxLength) {
      setState(() => _showValidation = true);
      return;
    }
    _submitted = true;
    setState(() {});
    final outcome = await ref
        .read(listSplitControllerProvider(widget.listId).notifier)
        .reverseSettlement(
          widget.settlement,
          reason: reason,
          requestId: _requestId,
        );
    if (!mounted) return;
    if (outcome.dismissesEditor) {
      _closeNow();
    } else {
      setState(() {
        _submitted = false;
        _retryLocked = outcome == ListSplitMutationOutcome.failed;
        _showValidation = !_retryLocked;
      });
    }
  }

  void _scheduleClose() {
    if (_dialogClosing) return;
    _dialogClosing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _popOwnedRoute());
  }

  void _closeNow() {
    if (_dialogClosing) return;
    _dialogClosing = true;
    _popOwnedRoute();
  }

  void _popOwnedRoute() {
    final route = _dialogRoute;
    if (!mounted || route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    navigator.popUntil((candidate) => identical(candidate, route));
    if (route.isCurrent) navigator.pop();
  }
}

class _ExpenseCard extends ConsumerStatefulWidget {
  const _ExpenseCard({
    required this.listId,
    required this.overview,
    required this.expense,
    required this.isBusy,
  });

  final String listId;
  final ListSplitOverview overview;
  final ListSplitExpense expense;
  final bool isBusy;

  @override
  ConsumerState<_ExpenseCard> createState() => _ExpenseCardState();
}

class _ExpenseCardState extends ConsumerState<_ExpenseCard> {
  bool _deleteFlowOpen = false;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final currency = widget.overview.currency!;
    final payer = widget.overview.participantById(
      widget.expense.payerParticipantId,
    );
    return Card(
      child: ListTile(
        key: ValueKey('splitExpense-${widget.expense.id}'),
        onTap: !widget.overview.writable || widget.isBusy
            ? null
            : () => showDialog<void>(
                  context: context,
                  builder: (_) => ExpenseFormDialog(
                    listId: widget.listId,
                    initialOverview: widget.overview,
                    expense: widget.expense,
                  ),
                ),
        title: Text(widget.expense.description),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localizations.splitExpensePaidBy(
                payer == null
                    ? localizations.splitFormerParticipant
                    : _participantName(localizations, payer),
                widget.expense.beneficiaryParticipantIds.length,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatMinor(widget.expense.amountMinor, currency),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        trailing: widget.overview.writable
            ? IconButton(
                key: ValueKey('deleteSplitExpense-${widget.expense.id}'),
                onPressed: widget.isBusy || _deleteFlowOpen
                    ? null
                    : () => _confirmDelete(context, ref),
                tooltip: localizations.splitDeleteExpenseButton,
                icon: const Icon(Icons.delete_outline),
              )
            : null,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    if (_deleteFlowOpen) return;
    setState(() => _deleteFlowOpen = true);
    try {
      var decisionMade = false;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(AppLocalizations.of(context).splitDeleteExpenseTitle),
          content: Text(
            AppLocalizations.of(context).splitDeleteExpenseConfirmation(
              widget.expense.description,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (decisionMade) return;
                decisionMade = true;
                Navigator.pop(context, false);
              },
              child: Text(AppLocalizations.of(context).cancelButton),
            ),
            FilledButton(
              key: const Key('confirmDeleteSplitExpenseButton'),
              onPressed: () {
                if (decisionMade) return;
                decisionMade = true;
                Navigator.pop(context, true);
              },
              child: Text(AppLocalizations.of(context).splitDeleteButton),
            ),
          ],
        ),
      );
      if (confirmed == true && context.mounted) {
        await ref
            .read(listSplitControllerProvider(widget.listId).notifier)
            .deleteExpense(widget.expense);
      }
    } finally {
      if (mounted) setState(() => _deleteFlowOpen = false);
    }
  }
}

class ExpenseFormDialog extends ConsumerStatefulWidget {
  const ExpenseFormDialog({
    required this.listId,
    required this.initialOverview,
    this.expense,
    super.key,
  });

  final String listId;
  final ListSplitOverview initialOverview;
  final ListSplitExpense? expense;

  @override
  ConsumerState<ExpenseFormDialog> createState() => _ExpenseFormDialogState();
}

class _ExpenseFormDialogState extends ConsumerState<ExpenseFormDialog> {
  late final TextEditingController _description;
  late final TextEditingController _amount;
  late final String? _creationRequestId;
  late String? _payerId;
  late final Set<String> _beneficiaryIds;
  bool _showValidation = false;
  bool _submitted = false;
  bool _dialogClosing = false;
  bool _overlayDismissScheduled = false;
  String? _payerChoiceSignature;
  ModalRoute<void>? _dialogRoute;

  @override
  void initState() {
    super.initState();
    final expense = widget.expense;
    _creationRequestId = expense == null
        ? ref
            .read(listSplitControllerProvider(widget.listId).notifier)
            .newExpenseRequestId()
        : null;
    final currency = widget.initialOverview.currency!;
    _description = TextEditingController(text: expense?.description ?? '');
    _amount = TextEditingController(
      text: expense == null
          ? ''
          : MoneyAmount.fromMinorUnits(expense.amountMinor, currency)
              .format(includeCode: false),
    );
    final current = widget.initialOverview.participants
        .where((participant) => participant.isCurrent)
        .toList(growable: false);
    _payerId = expense?.payerParticipantId ??
        (current.isEmpty ? null : current.first.id);
    _beneficiaryIds = {
      if (expense != null)
        ...expense.beneficiaryParticipantIds
      else
        ...current.map((participant) => participant.id),
    };
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _dialogRoute ??= ModalRoute.of(context);
    final provider = listSplitControllerProvider(widget.listId);
    final state = ref.watch(provider);
    final unavailable = state.message == ListSplitMessage.unavailable;
    final overview = state.overview.valueOrNull ?? widget.initialOverview;
    final currency = overview.currency ?? widget.initialOverview.currency!;
    ListSplitExpense? liveExpense;
    if (widget.expense != null) {
      for (final candidate in overview.expenses) {
        if (candidate.id == widget.expense!.id) {
          liveExpense = candidate;
          break;
        }
      }
    }
    if (unavailable ||
        (widget.expense != null && liveExpense == null) ||
        !overview.writable) {
      _scheduleClose();
    }
    final currentExpense = liveExpense ?? widget.expense;
    final payerChoices = overview.participants
        .where(
          (participant) =>
              participant.isCurrent ||
              participant.id == currentExpense?.payerParticipantId,
        )
        .toList(growable: false);
    final payerChoiceSignature =
        payerChoices.map((participant) => participant.id).join('|');
    if (_payerChoiceSignature == null) {
      _payerChoiceSignature = payerChoiceSignature;
    } else if (_payerChoiceSignature != payerChoiceSignature) {
      _payerChoiceSignature = payerChoiceSignature;
      _scheduleOverlayDismissal();
    }
    final retainedBeneficiaryIds =
        currentExpense?.beneficiaryParticipantIds.toSet() ?? const <String>{};
    final beneficiaryChoices = overview.participants
        .where(
          (participant) =>
              participant.isCurrent ||
              retainedBeneficiaryIds.contains(participant.id),
        )
        .toList(growable: false);
    final parsed = MoneyAmount.tryParse(_amount.text, currency: currency);
    final descriptionValid = _description.text.trim().isNotEmpty &&
        _description.text.trim().length <= splitExpenseDescriptionMaxLength;
    final payerValid = payerChoices.any((entry) => entry.id == _payerId);
    final beneficiariesValid = _beneficiaryIds.isNotEmpty &&
        _beneficiaryIds.every(
          (id) => beneficiaryChoices.any((entry) => entry.id == id),
        );
    final localizations = AppLocalizations.of(context);
    final formEnabled = !unavailable &&
        overview.writable &&
        !state.isMutating &&
        !_submitted &&
        !_dialogClosing;
    return PopScope(
      canPop: !state.isMutating && !_submitted,
      child: AlertDialog(
        title: Text(
          widget.expense == null
              ? localizations.splitAddExpenseTitle
              : localizations.splitEditExpenseTitle,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('splitExpenseDescriptionField'),
                controller: _description,
                autofocus: true,
                enabled: formEnabled,
                maxLength: splitExpenseDescriptionMaxLength,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: localizations.splitExpenseDescriptionLabel,
                  errorText: _showValidation && !descriptionValid
                      ? localizations.splitInvalidDescriptionMessage
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('splitExpenseAmountField'),
                controller: _amount,
                enabled: formEnabled,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText:
                      localizations.splitExpenseAmountLabel(currency.code),
                  helperText: localizations.splitExpenseAmountHelper,
                  errorText: _showValidation && parsed == null
                      ? localizations.splitInvalidAmountMessage
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const Key('splitExpensePayerField'),
                // Keep the initializer supported by the Flutter 3.19 floor.
                // ignore: deprecated_member_use
                value: payerValid ? _payerId : null,
                decoration: InputDecoration(
                  labelText: localizations.splitExpensePayerLabel,
                  errorText: _showValidation && !payerValid
                      ? localizations.splitPayerRequiredMessage
                      : null,
                ),
                items: [
                  for (final participant in payerChoices)
                    DropdownMenuItem(
                      value: participant.id,
                      child: Text(_participantName(localizations, participant)),
                    ),
                ],
                onChanged: formEnabled
                    ? (value) => setState(() => _payerId = value)
                    : null,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      localizations.splitExpenseParticipantsLabel,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  TextButton(
                    key: const Key('selectAllSplitParticipantsButton'),
                    onPressed: formEnabled
                        ? () => setState(() {
                              _beneficiaryIds
                                ..clear()
                                ..addAll(
                                  beneficiaryChoices
                                      .where((participant) =>
                                          participant.isCurrent)
                                      .map((participant) => participant.id),
                                );
                            })
                        : null,
                    child: Text(localizations.splitSelectAllButton),
                  ),
                ],
              ),
              for (final participant in beneficiaryChoices)
                CheckboxListTile(
                  key: ValueKey('splitBeneficiary-${participant.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(_participantName(localizations, participant)),
                  subtitle: participant.isCurrent
                      ? null
                      : Text(localizations.splitHistoricalParticipantLabel),
                  value: _beneficiaryIds.contains(participant.id),
                  onChanged: formEnabled
                      ? (selected) => setState(() {
                            if (selected == true) {
                              _beneficiaryIds.add(participant.id);
                            } else {
                              _beneficiaryIds.remove(participant.id);
                            }
                          })
                      : null,
                ),
              if (_showValidation && !beneficiariesValid)
                Text(
                  localizations.splitParticipantRequiredMessage,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: state.isMutating || _dialogClosing
                ? null
                : () {
                    _dialogClosing = true;
                    Navigator.pop(context);
                  },
            child: Text(localizations.cancelButton),
          ),
          FilledButton(
            key: const Key('saveSplitExpenseButton'),
            onPressed: formEnabled ? _submit : null,
            child: state.isMutating
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(localizations.saveButton),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final provider = listSplitControllerProvider(widget.listId);
    final overview = ref.read(provider).overview.valueOrNull;
    final currency = overview?.currency ?? widget.initialOverview.currency!;
    final amount = MoneyAmount.tryParse(_amount.text, currency: currency);
    ListSplitExpense? currentExpense;
    if (overview != null && widget.expense != null) {
      for (final candidate in overview.expenses) {
        if (candidate.id == widget.expense!.id) {
          currentExpense = candidate;
          break;
        }
      }
    }
    final payerAllowed = overview != null &&
        _payerId != null &&
        (overview.participantById(_payerId!)?.isCurrent == true ||
            currentExpense?.payerParticipantId == _payerId);
    final retainedBeneficiaries =
        currentExpense?.beneficiaryParticipantIds.toSet() ?? const <String>{};
    final beneficiariesAllowed = overview != null &&
        _beneficiaryIds.every(
          (id) =>
              overview.participantById(id)?.isCurrent == true ||
              retainedBeneficiaries.contains(id),
        );
    if (_description.text.trim().isEmpty ||
        _description.text.trim().length > splitExpenseDescriptionMaxLength ||
        amount == null ||
        overview?.writable != true ||
        !payerAllowed ||
        _beneficiaryIds.isEmpty ||
        !beneficiariesAllowed) {
      setState(() => _showValidation = true);
      return;
    }
    _submitted = true;
    setState(() {});
    final controller = ref.read(provider.notifier);
    final outcome = widget.expense == null
        ? await controller.createExpense(
            description: _description.text,
            amountMinor: amount.minorUnits,
            payerParticipantId: _payerId!,
            beneficiaryParticipantIds: _beneficiaryIds,
            requestId: _creationRequestId!,
          )
        : await controller.updateExpense(
            widget.expense!,
            description: _description.text,
            amountMinor: amount.minorUnits,
            payerParticipantId: _payerId!,
            beneficiaryParticipantIds: _beneficiaryIds,
          );
    if (!mounted) return;
    if (outcome.dismissesEditor) {
      _closeNow();
    } else {
      _submitted = false;
      setState(() => _showValidation = true);
    }
  }

  void _scheduleClose() {
    if (_dialogClosing) return;
    _dialogClosing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _popOwnedDialogRoute();
    });
  }

  void _scheduleOverlayDismissal() {
    if (_overlayDismissScheduled || _dialogClosing) return;
    _overlayDismissScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _overlayDismissScheduled = false;
      final route = _dialogRoute;
      if (!mounted || route == null || !route.isActive) return;
      Navigator.of(context)
          .popUntil((candidate) => identical(candidate, route));
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

class _EmptyExpenses extends StatelessWidget {
  const _EmptyExpenses({required this.writable});

  final bool writable;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          const Icon(Icons.receipt_long_outlined, size: 48),
          const SizedBox(height: 12),
          Text(
            writable
                ? localizations.splitEmptyExpensesMessage
                : localizations.splitEmptyExpensesReadOnlyMessage,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SplitError extends StatelessWidget {
  const _SplitError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.sync_problem_rounded, size: 52),
          const SizedBox(height: 16),
          Text(localizations.splitLoadFailedMessage,
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.tonal(
            key: const Key('retrySplitButton'),
            onPressed: onRetry,
            child: Text(localizations.tryAgainButton),
          ),
        ],
      ),
    );
  }
}

String _participantName(
  AppLocalizations localizations,
  ListSplitParticipant participant,
) {
  if (participant.isAnonymized) return localizations.splitFormerParticipant;
  return participant.displayName ??
      participant.username ??
      localizations.splitFormerParticipant;
}

String _formatMinor(int minorUnits, SplitCurrency currency) =>
    MoneyAmount.fromMinorUnits(minorUnits, currency).format();

String _callerBalanceText(
  AppLocalizations localizations,
  int balanceMinor,
  SplitCurrency currency,
) {
  if (balanceMinor > 0) {
    return localizations.splitYouAreOwed(_formatMinor(balanceMinor, currency));
  }
  if (balanceMinor < 0) {
    return localizations
        .splitYouOwe(_formatMinor(balanceMinor.abs(), currency));
  }
  return localizations.splitSettledUp;
}

String? _messageText(
  AppLocalizations localizations,
  ListSplitMessage? message,
) {
  return switch (message) {
    ListSplitMessage.enabled => localizations.splitEnabledMessage,
    ListSplitMessage.currencyChanged =>
      localizations.splitCurrencyChangedMessage,
    ListSplitMessage.expenseCreated => localizations.splitExpenseCreatedMessage,
    ListSplitMessage.expenseUpdated => localizations.splitExpenseUpdatedMessage,
    ListSplitMessage.expenseDeleted => localizations.splitExpenseDeletedMessage,
    ListSplitMessage.settlementRecorded =>
      localizations.splitSettlementRecordedMessage,
    ListSplitMessage.settlementReversed =>
      localizations.splitSettlementReversedMessage,
    ListSplitMessage.staleRefreshed => localizations.splitStaleMessage,
    ListSplitMessage.archivedReadOnly => localizations.splitArchivedMessage,
    ListSplitMessage.unavailable => null,
    ListSplitMessage.invalidInput => localizations.splitInvalidInputMessage,
    ListSplitMessage.capacity => localizations.splitCapacityMessage,
    ListSplitMessage.refreshFailed => localizations.splitRefreshFailedMessage,
    ListSplitMessage.operationFailed => localizations.operationFailedMessage,
    null => null,
  };
}
