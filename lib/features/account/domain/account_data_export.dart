class AccountDataExportFailure implements Exception {
  const AccountDataExportFailure();
}

class AccountDataExportDocument {
  AccountDataExportDocument({
    required this.product,
    required this.schemaVersion,
    required this.exportedAt,
    required this.authIdentity,
    required this.profile,
    required List<AccountOutgoingBlock> outgoingBlocks,
    required List<AccountActiveRelationship> activeRelationships,
    required List<AccountVisibleNotification> visibleNotifications,
    required List<AccountActiveListExport> activeLists,
    List<AccountSharedListAccessExport> sharedListAccess = const [],
    List<AccountTemplateCategoryExport> templateCategories = const [],
    List<AccountPrivateTemplateExport> templates = const [],
  })  : outgoingBlocks = List.unmodifiable(outgoingBlocks),
        activeRelationships = List.unmodifiable(activeRelationships),
        visibleNotifications = List.unmodifiable(visibleNotifications),
        activeLists = List.unmodifiable(activeLists),
        sharedListAccess = List.unmodifiable(sharedListAccess),
        templateCategories = List.unmodifiable(templateCategories),
        templates = List.unmodifiable(templates) {
    if (product != supportedProduct ||
        !supportedSchemaVersions.contains(schemaVersion) ||
        authIdentity.id != profile.id ||
        activeLists.any(
          (activeList) => activeList.includesSplitField != (schemaVersion >= 5),
        )) {
      throw const AccountDataExportFailure();
    }
  }

  factory AccountDataExportDocument.fromJson(Map<String, dynamic> json) {
    final product = _requiredString(json, 'product');
    final schemaVersion = _requiredInt(json, 'schema_version');
    if (!supportedSchemaVersions.contains(schemaVersion)) {
      throw const AccountDataExportFailure();
    }
    _expectExactKeys(
      json,
      switch (schemaVersion) {
        1 => _schemaOneRootKeys,
        2 => _schemaTwoRootKeys,
        3 => _schemaThreeRootKeys,
        4 => _schemaFourRootKeys,
        5 => _schemaFiveRootKeys,
        _ => const <String>{},
      },
    );

    return AccountDataExportDocument(
      product: product,
      schemaVersion: schemaVersion,
      exportedAt: _requiredUtcDateTime(json, 'exported_at'),
      authIdentity: AccountAuthIdentity.fromJson(
        _requiredObject(json, 'auth_identity'),
      ),
      profile: AccountProfileExport.fromJson(
        _requiredObject(json, 'profile'),
      ),
      outgoingBlocks: _requiredObjects(json, 'outgoing_blocks')
          .map(AccountOutgoingBlock.fromJson)
          .toList(growable: false),
      activeRelationships: _requiredObjects(json, 'active_relationships')
          .map(AccountActiveRelationship.fromJson)
          .toList(growable: false),
      visibleNotifications: _requiredObjects(json, 'visible_notifications')
          .map(AccountVisibleNotification.fromJson)
          .toList(growable: false),
      activeLists: schemaVersion == 1
          ? const []
          : _requiredObjects(json, 'active_lists')
              .map(
                (activeList) => AccountActiveListExport.fromJson(
                  activeList,
                  includeSplit: schemaVersion >= 5,
                ),
              )
              .toList(growable: false),
      sharedListAccess: schemaVersion < 3
          ? const []
          : _requiredObjects(json, 'shared_list_access')
              .map(AccountSharedListAccessExport.fromJson)
              .toList(growable: false),
      templateCategories: schemaVersion < 4
          ? const []
          : _requiredObjects(json, 'template_categories')
              .map(AccountTemplateCategoryExport.fromJson)
              .toList(growable: false),
      templates: schemaVersion < 4
          ? const []
          : _requiredObjects(json, 'templates')
              .map(AccountPrivateTemplateExport.fromJson)
              .toList(growable: false),
    );
  }

  static const supportedProduct = 'list_and_split';
  static const supportedSchemaVersion = 5;
  static const supportedSchemaVersions = {1, 2, 3, 4, supportedSchemaVersion};
  static const _schemaOneRootKeys = {
    'product',
    'schema_version',
    'exported_at',
    'auth_identity',
    'profile',
    'outgoing_blocks',
    'active_relationships',
    'visible_notifications',
  };
  static const _schemaTwoRootKeys = {
    ..._schemaOneRootKeys,
    'active_lists',
  };
  static const _schemaThreeRootKeys = {
    ..._schemaTwoRootKeys,
    'shared_list_access',
  };
  static const _schemaFourRootKeys = {
    ..._schemaThreeRootKeys,
    'template_categories',
    'templates',
  };
  static const _schemaFiveRootKeys = _schemaFourRootKeys;

  final String product;
  final int schemaVersion;
  final DateTime exportedAt;
  final AccountAuthIdentity authIdentity;
  final AccountProfileExport profile;
  final List<AccountOutgoingBlock> outgoingBlocks;
  final List<AccountActiveRelationship> activeRelationships;
  final List<AccountVisibleNotification> visibleNotifications;
  final List<AccountActiveListExport> activeLists;
  final List<AccountSharedListAccessExport> sharedListAccess;
  final List<AccountTemplateCategoryExport> templateCategories;
  final List<AccountPrivateTemplateExport> templates;

  Map<String, dynamic> toJson() => {
        'product': product,
        'schema_version': schemaVersion,
        'exported_at': _encodeDateTime(exportedAt),
        'auth_identity': authIdentity.toJson(),
        'profile': profile.toJson(),
        'outgoing_blocks': outgoingBlocks
            .map((block) => block.toJson())
            .toList(growable: false),
        'active_relationships': activeRelationships
            .map((relationship) => relationship.toJson())
            .toList(growable: false),
        'visible_notifications': visibleNotifications
            .map((notification) => notification.toJson())
            .toList(growable: false),
        if (schemaVersion >= 2)
          'active_lists': activeLists
              .map((activeList) => activeList.toJson())
              .toList(growable: false),
        if (schemaVersion >= 3)
          'shared_list_access': sharedListAccess
              .map((access) => access.toJson())
              .toList(growable: false),
        if (schemaVersion >= 4)
          'template_categories': templateCategories
              .map((category) => category.toJson())
              .toList(growable: false),
        if (schemaVersion >= 4)
          'templates': templates
              .map((template) => template.toJson())
              .toList(growable: false),
      };
}

class AccountTemplateCategoryExport {
  const AccountTemplateCategoryExport({
    required this.id,
    required this.name,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AccountTemplateCategoryExport.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(json, _keys);
    final name = _requiredString(json, 'name');
    if (name != name.trim().replaceAll(RegExp(r'\s+'), ' ')) {
      throw const AccountDataExportFailure();
    }
    return AccountTemplateCategoryExport(
      id: _requiredUuid(json, 'category_id'),
      name: name,
      version: _requiredPositiveInt(json, 'version'),
      createdAt: _requiredUtcDateTime(json, 'created_at'),
      updatedAt: _requiredUtcDateTime(json, 'updated_at'),
    );
  }

  static const _keys = {
    'category_id',
    'name',
    'version',
    'created_at',
    'updated_at',
  };

  final String id;
  final String name;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'category_id': id,
        'name': name,
        'version': version,
        'created_at': _encodeDateTime(createdAt),
        'updated_at': _encodeDateTime(updatedAt),
      };
}

class AccountPrivateTemplateExport {
  AccountPrivateTemplateExport({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    required List<AccountPrivateTemplateItemExport> items,
  }) : items = List.unmodifiable(items);

  factory AccountPrivateTemplateExport.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(json, _keys);
    final name = _requiredString(json, 'name');
    if (name != name.trim()) throw const AccountDataExportFailure();
    return AccountPrivateTemplateExport(
      id: _requiredUuid(json, 'template_id'),
      categoryId: json['category_id'] == null
          ? null
          : _requiredUuid(json, 'category_id'),
      name: name,
      version: _requiredPositiveInt(json, 'version'),
      createdAt: _requiredUtcDateTime(json, 'created_at'),
      updatedAt: _requiredUtcDateTime(json, 'updated_at'),
      items: _requiredObjects(json, 'items')
          .map(AccountPrivateTemplateItemExport.fromJson)
          .toList(growable: false),
    );
  }

  static const _keys = {
    'template_id',
    'category_id',
    'name',
    'version',
    'created_at',
    'updated_at',
    'items',
  };

  final String id;
  final String? categoryId;
  final String name;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<AccountPrivateTemplateItemExport> items;

  Map<String, dynamic> toJson() => {
        'template_id': id,
        'category_id': categoryId,
        'name': name,
        'version': version,
        'created_at': _encodeDateTime(createdAt),
        'updated_at': _encodeDateTime(updatedAt),
        'items': items.map((item) => item.toJson()).toList(growable: false),
      };
}

class AccountPrivateTemplateItemExport {
  const AccountPrivateTemplateItemExport({
    required this.id,
    required this.name,
    required this.quantityThousandths,
    required this.position,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AccountPrivateTemplateItemExport.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(json, _keys);
    final name = _requiredString(json, 'name');
    final quantity = _requiredPositiveInt(json, 'quantity_thousandths');
    if (name != name.trim() || name.length > 120 || quantity > 999999999) {
      throw const AccountDataExportFailure();
    }
    return AccountPrivateTemplateItemExport(
      id: _requiredUuid(json, 'item_id'),
      name: name,
      quantityThousandths: quantity,
      position: _requiredPositiveInt(json, 'position'),
      version: _requiredPositiveInt(json, 'version'),
      createdAt: _requiredUtcDateTime(json, 'created_at'),
      updatedAt: _requiredUtcDateTime(json, 'updated_at'),
    );
  }

  static const _keys = {
    'item_id',
    'name',
    'quantity_thousandths',
    'position',
    'version',
    'created_at',
    'updated_at',
  };

  final String id;
  final String name;
  final int quantityThousandths;
  final int position;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'item_id': id,
        'name': name,
        'quantity_thousandths': quantityThousandths,
        'position': position,
        'version': version,
        'created_at': _encodeDateTime(createdAt),
        'updated_at': _encodeDateTime(updatedAt),
      };
}

enum AccountSharedListAccessState {
  pending('pending'),
  member('member'),
  declined('declined'),
  cancelled('cancelled'),
  removed('removed'),
  left('left');

  const AccountSharedListAccessState(this.wireValue);
  final String wireValue;
}

class AccountSharedListAccessExport {
  AccountSharedListAccessExport({
    required this.listId,
    required this.listTitle,
    required this.listStatus,
    required this.accessState,
    required this.accessVersion,
    required this.createdAt,
    required this.stateChangedAt,
  });

  factory AccountSharedListAccessExport.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(json, _keys);
    final title = _requiredString(json, 'list_title');
    if (title != title.trim() || title.length > 80) {
      throw const AccountDataExportFailure();
    }
    final createdAt = _requiredUtcDateTime(json, 'created_at');
    final stateChangedAt = _requiredUtcDateTime(json, 'state_changed_at');
    if (stateChangedAt.isBefore(createdAt)) {
      throw const AccountDataExportFailure();
    }
    return AccountSharedListAccessExport(
      listId: _requiredUuid(json, 'list_id'),
      listTitle: title,
      listStatus: _activeListStatus(_requiredString(json, 'list_status')),
      accessState: _sharedAccessState(_requiredString(json, 'access_state')),
      accessVersion: _requiredPositiveInt(json, 'access_version'),
      createdAt: createdAt,
      stateChangedAt: stateChangedAt,
    );
  }

  static const _keys = {
    'list_id',
    'list_title',
    'list_status',
    'access_state',
    'access_version',
    'created_at',
    'state_changed_at',
  };

  final String listId;
  final String listTitle;
  final AccountActiveListStatus listStatus;
  final AccountSharedListAccessState accessState;
  final int accessVersion;
  final DateTime createdAt;
  final DateTime stateChangedAt;

  Map<String, dynamic> toJson() => {
        'list_id': listId,
        'list_title': listTitle,
        'list_status': listStatus.wireValue,
        'access_state': accessState.wireValue,
        'access_version': accessVersion,
        'created_at': _encodeDateTime(createdAt),
        'state_changed_at': _encodeDateTime(stateChangedAt),
      };
}

class AccountAuthIdentity {
  AccountAuthIdentity({
    required this.id,
    required this.email,
    required this.emailConfirmedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.lastSignInAt,
  });

  factory AccountAuthIdentity.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(json, _keys);
    return AccountAuthIdentity(
      id: _requiredUuid(json, 'id'),
      email: _requiredString(json, 'email'),
      emailConfirmedAt: _requiredUtcDateTime(json, 'email_confirmed_at'),
      createdAt: _requiredUtcDateTime(json, 'created_at'),
      updatedAt: _requiredUtcDateTime(json, 'updated_at'),
      lastSignInAt: _nullableUtcDateTime(json, 'last_sign_in_at'),
    );
  }

  static const _keys = {
    'id',
    'email',
    'email_confirmed_at',
    'created_at',
    'updated_at',
    'last_sign_in_at',
  };

  final String id;
  final String email;
  final DateTime emailConfirmedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastSignInAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'email_confirmed_at': _encodeDateTime(emailConfirmedAt),
        'created_at': _encodeDateTime(createdAt),
        'updated_at': _encodeDateTime(updatedAt),
        'last_sign_in_at': _encodeNullableDateTime(lastSignInAt),
      };
}

class AccountProfileExport {
  AccountProfileExport({
    required this.id,
    required this.username,
    required this.displayName,
    required this.createdAt,
    required this.updatedAt,
    required this.onboardingCompletedAt,
  });

  factory AccountProfileExport.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(json, _keys);
    final username = _nullableString(json, 'username');
    final displayName = _nullableString(json, 'display_name');
    final onboardingCompletedAt =
        _nullableUtcDateTime(json, 'onboarding_completed_at');
    if (onboardingCompletedAt != null &&
        (username == null || displayName == null)) {
      throw const AccountDataExportFailure();
    }
    return AccountProfileExport(
      id: _requiredUuid(json, 'id'),
      username: username,
      displayName: displayName,
      createdAt: _requiredUtcDateTime(json, 'created_at'),
      updatedAt: _requiredUtcDateTime(json, 'updated_at'),
      onboardingCompletedAt: onboardingCompletedAt,
    );
  }

  static const _keys = {
    'id',
    'username',
    'display_name',
    'created_at',
    'updated_at',
    'onboarding_completed_at',
  };

  final String id;
  final String? username;
  final String? displayName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? onboardingCompletedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'display_name': displayName,
        'created_at': _encodeDateTime(createdAt),
        'updated_at': _encodeDateTime(updatedAt),
        'onboarding_completed_at':
            _encodeNullableDateTime(onboardingCompletedAt),
      };
}

class AccountOutgoingBlock {
  AccountOutgoingBlock({
    required this.profileId,
    required this.username,
    required this.displayName,
    required this.createdAt,
  });

  factory AccountOutgoingBlock.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(json, _keys);
    return AccountOutgoingBlock(
      profileId: _requiredUuid(json, 'profile_id'),
      username: _requiredString(json, 'username'),
      displayName: _requiredString(json, 'display_name'),
      createdAt: _requiredUtcDateTime(json, 'created_at'),
    );
  }

  static const _keys = {
    'profile_id',
    'username',
    'display_name',
    'created_at',
  };

  final String profileId;
  final String username;
  final String displayName;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'profile_id': profileId,
        'username': username,
        'display_name': displayName,
        'created_at': _encodeDateTime(createdAt),
      };
}

enum AccountRelationshipStatus {
  friends('friends'),
  incomingPending('incoming-pending'),
  outgoingPending('outgoing-pending');

  const AccountRelationshipStatus(this.wireValue);

  final String wireValue;
}

class AccountActiveRelationship {
  AccountActiveRelationship({
    required this.profileId,
    required this.username,
    required this.displayName,
    required this.status,
    required this.version,
    required this.stateChangedAt,
  });

  factory AccountActiveRelationship.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(json, _keys);
    return AccountActiveRelationship(
      profileId: _requiredUuid(json, 'profile_id'),
      username: _requiredString(json, 'username'),
      displayName: _requiredString(json, 'display_name'),
      status: _relationshipStatus(_requiredString(json, 'status')),
      version: _requiredPositiveInt(json, 'version'),
      stateChangedAt: _requiredUtcDateTime(json, 'state_changed_at'),
    );
  }

  static const _keys = {
    'profile_id',
    'username',
    'display_name',
    'status',
    'version',
    'state_changed_at',
  };

  final String profileId;
  final String username;
  final String displayName;
  final AccountRelationshipStatus status;
  final int version;
  final DateTime stateChangedAt;

  Map<String, dynamic> toJson() => {
        'profile_id': profileId,
        'username': username,
        'display_name': displayName,
        'status': status.wireValue,
        'version': version,
        'state_changed_at': _encodeDateTime(stateChangedAt),
      };
}

enum AccountNotificationActionStatus {
  actionable('actionable'),
  friends('friends'),
  unavailable('unavailable');

  const AccountNotificationActionStatus(this.wireValue);

  final String wireValue;
}

class AccountVisibleNotification {
  AccountVisibleNotification({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.isRead,
    required this.readAt,
    required this.expiresAt,
    required this.actorProfileId,
    required this.actorUsername,
    required this.actorDisplayName,
    required this.actionStatus,
    required this.expectedRelationshipVersion,
  });

  factory AccountVisibleNotification.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(json, _keys);
    final type = _requiredString(json, 'type');
    if (type != 'friend_request') throw const AccountDataExportFailure();
    final isRead = _requiredBool(json, 'is_read');
    final readAt = _nullableUtcDateTime(json, 'read_at');
    if (isRead != (readAt != null)) throw const AccountDataExportFailure();
    final actionStatus =
        _notificationStatus(_requiredString(json, 'action_status'));
    final expectedVersion =
        _nullablePositiveInt(json, 'expected_relationship_version');
    if ((actionStatus == AccountNotificationActionStatus.actionable) !=
        (expectedVersion != null)) {
      throw const AccountDataExportFailure();
    }
    final createdAt = _requiredUtcDateTime(json, 'created_at');
    final expiresAt = _requiredUtcDateTime(json, 'expires_at');
    if (!expiresAt.isAfter(createdAt)) throw const AccountDataExportFailure();
    return AccountVisibleNotification(
      id: _requiredUuid(json, 'id'),
      type: type,
      createdAt: createdAt,
      isRead: isRead,
      readAt: readAt,
      expiresAt: expiresAt,
      actorProfileId: _requiredUuid(json, 'actor_profile_id'),
      actorUsername: _requiredString(json, 'actor_username'),
      actorDisplayName: _requiredString(json, 'actor_display_name'),
      actionStatus: actionStatus,
      expectedRelationshipVersion: expectedVersion,
    );
  }

  static const _keys = {
    'id',
    'type',
    'created_at',
    'is_read',
    'read_at',
    'expires_at',
    'actor_profile_id',
    'actor_username',
    'actor_display_name',
    'action_status',
    'expected_relationship_version',
  };

  final String id;
  final String type;
  final DateTime createdAt;
  final bool isRead;
  final DateTime? readAt;
  final DateTime expiresAt;
  final String actorProfileId;
  final String actorUsername;
  final String actorDisplayName;
  final AccountNotificationActionStatus actionStatus;
  final int? expectedRelationshipVersion;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'created_at': _encodeDateTime(createdAt),
        'is_read': isRead,
        'read_at': _encodeNullableDateTime(readAt),
        'expires_at': _encodeDateTime(expiresAt),
        'actor_profile_id': actorProfileId,
        'actor_username': actorUsername,
        'actor_display_name': actorDisplayName,
        'action_status': actionStatus.wireValue,
        'expected_relationship_version': expectedRelationshipVersion,
      };
}

enum AccountActiveListStatus {
  active('active'),
  archived('archived');

  const AccountActiveListStatus(this.wireValue);

  final String wireValue;
}

class AccountActiveListExport {
  AccountActiveListExport({
    required this.id,
    required this.title,
    required this.status,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    required this.archivedAt,
    required List<AccountActiveListItemExport> items,
    this.split,
    this.includesSplitField = false,
  }) : items = List.unmodifiable(items) {
    if (!includesSplitField && split != null) {
      throw const AccountDataExportFailure();
    }
  }

  factory AccountActiveListExport.fromJson(
    Map<String, dynamic> json, {
    bool includeSplit = false,
  }) {
    _expectExactKeys(json, includeSplit ? _schemaFiveKeys : _legacyKeys);
    final title = _requiredString(json, 'title');
    if (title != title.trim() || title.length > 80) {
      throw const AccountDataExportFailure();
    }
    final status = _activeListStatus(_requiredString(json, 'status'));
    final archivedAt = _nullableUtcDateTime(json, 'archived_at');
    if ((status == AccountActiveListStatus.archived) != (archivedAt != null)) {
      throw const AccountDataExportFailure();
    }
    return AccountActiveListExport(
      id: _requiredUuid(json, 'id'),
      title: title,
      status: status,
      version: _requiredPositiveInt(json, 'version'),
      createdAt: _requiredUtcDateTime(json, 'created_at'),
      updatedAt: _requiredUtcDateTime(json, 'updated_at'),
      archivedAt: archivedAt,
      items: _requiredObjects(json, 'items')
          .map(AccountActiveListItemExport.fromJson)
          .toList(growable: false),
      split: includeSplit && json['split'] != null
          ? AccountListSplitExport.fromJson(_requiredObject(json, 'split'))
          : null,
      includesSplitField: includeSplit,
    );
  }

  static const _legacyKeys = {
    'id',
    'title',
    'status',
    'version',
    'created_at',
    'updated_at',
    'archived_at',
    'items',
  };
  static const _schemaFiveKeys = {..._legacyKeys, 'split'};

  final String id;
  final String title;
  final AccountActiveListStatus status;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;
  final List<AccountActiveListItemExport> items;
  final AccountListSplitExport? split;
  final bool includesSplitField;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'status': status.wireValue,
        'version': version,
        'created_at': _encodeDateTime(createdAt),
        'updated_at': _encodeDateTime(updatedAt),
        'archived_at': _encodeNullableDateTime(archivedAt),
        'items': items.map((item) => item.toJson()).toList(growable: false),
        if (includesSplitField) 'split': split?.toJson(),
      };
}

class AccountListSplitExport {
  AccountListSplitExport({
    required this.settings,
    required List<AccountListSplitParticipantExport> participants,
    required List<AccountListSplitExpenseExport> expenses,
  })  : participants = List.unmodifiable(participants),
        expenses = List.unmodifiable(expenses) {
    final participantIds = participants.map((entry) => entry.id).toSet();
    if (participantIds.length != participants.length ||
        expenses.any((expense) => !expense.referencesOnly(participantIds))) {
      throw const AccountDataExportFailure();
    }
  }

  factory AccountListSplitExport.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(json, _keys);
    return AccountListSplitExport(
      settings: AccountListSplitSettingsExport.fromJson(
        _requiredObject(json, 'settings'),
      ),
      participants: _requiredObjects(json, 'participants')
          .map(AccountListSplitParticipantExport.fromJson)
          .toList(growable: false),
      expenses: _requiredObjects(json, 'expenses')
          .map(AccountListSplitExpenseExport.fromJson)
          .toList(growable: false),
    );
  }

  static const _keys = {'settings', 'participants', 'expenses'};

  final AccountListSplitSettingsExport settings;
  final List<AccountListSplitParticipantExport> participants;
  final List<AccountListSplitExpenseExport> expenses;

  Map<String, dynamic> toJson() => {
        'settings': settings.toJson(),
        'participants': participants
            .map((participant) => participant.toJson())
            .toList(growable: false),
        'expenses':
            expenses.map((expense) => expense.toJson()).toList(growable: false),
      };
}

class AccountListSplitSettingsExport {
  const AccountListSplitSettingsExport({
    required this.currencyCode,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AccountListSplitSettingsExport.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(json, _keys);
    final currencyCode = _requiredString(json, 'currency_code');
    final createdAt = _requiredUtcDateTime(json, 'created_at');
    final updatedAt = _requiredUtcDateTime(json, 'updated_at');
    if (!currencyCodes.contains(currencyCode) ||
        updatedAt.isBefore(createdAt)) {
      throw const AccountDataExportFailure();
    }
    return AccountListSplitSettingsExport(
      currencyCode: currencyCode,
      version: _requiredPositiveInt(json, 'version'),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static const currencyCodes = {'CHF', 'EUR'};
  static const _keys = {
    'currency_code',
    'version',
    'created_at',
    'updated_at',
  };

  final String currencyCode;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'currency_code': currencyCode,
        'version': version,
        'created_at': _encodeDateTime(createdAt),
        'updated_at': _encodeDateTime(updatedAt),
      };
}

class AccountListSplitParticipantExport {
  const AccountListSplitParticipantExport({
    required this.id,
    required this.profileId,
    required this.username,
    required this.displayName,
    required this.isAnonymized,
    required this.isCurrent,
  });

  factory AccountListSplitParticipantExport.fromJson(
    Map<String, dynamic> json,
  ) {
    _expectExactKeys(json, _keys);
    final profileId = _nullableUuid(json, 'profile_id');
    final username = _nullableString(json, 'username');
    final displayName = _nullableString(json, 'display_name');
    final isAnonymized = _requiredBool(json, 'is_anonymized');
    final isCurrent = _requiredBool(json, 'is_current');
    if (isAnonymized != (profileId == null) ||
        (isAnonymized && isCurrent) ||
        (isAnonymized && (username != null || displayName != null)) ||
        (!isAnonymized && (username == null || displayName == null))) {
      throw const AccountDataExportFailure();
    }
    return AccountListSplitParticipantExport(
      id: _requiredUuid(json, 'id'),
      profileId: profileId,
      username: username,
      displayName: displayName,
      isAnonymized: isAnonymized,
      isCurrent: isCurrent,
    );
  }

  static const _keys = {
    'id',
    'profile_id',
    'username',
    'display_name',
    'is_anonymized',
    'is_current',
  };

  final String id;
  final String? profileId;
  final String? username;
  final String? displayName;
  final bool isAnonymized;
  final bool isCurrent;

  Map<String, dynamic> toJson() => {
        'id': id,
        'profile_id': profileId,
        'username': username,
        'display_name': displayName,
        'is_anonymized': isAnonymized,
        'is_current': isCurrent,
      };
}

class AccountListSplitExpenseExport {
  AccountListSplitExpenseExport({
    required this.id,
    required this.description,
    required this.amountMinor,
    required this.payerParticipantId,
    required this.creatorParticipantId,
    required this.lastEditorParticipantId,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    required List<String> beneficiaryParticipantIds,
    required List<AccountListSplitShareExport> shares,
  })  : beneficiaryParticipantIds = List.unmodifiable(
          beneficiaryParticipantIds,
        ),
        shares = List.unmodifiable(shares) {
    final beneficiaryIds = beneficiaryParticipantIds.toSet();
    final shareIds = shares.map((share) => share.participantId).toSet();
    if (beneficiaryParticipantIds.isEmpty ||
        beneficiaryIds.length != beneficiaryParticipantIds.length ||
        shares.length != beneficiaryParticipantIds.length ||
        shareIds.length != shares.length ||
        !shareIds.containsAll(beneficiaryIds) ||
        shares.fold<int>(0, (sum, share) => sum + share.amountMinor) !=
            amountMinor ||
        updatedAt.isBefore(createdAt)) {
      throw const AccountDataExportFailure();
    }
  }

  factory AccountListSplitExpenseExport.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(json, _keys);
    final description = _requiredString(json, 'description');
    final amountMinor = _requiredPositiveInt(json, 'amount_minor');
    if (description != description.trim() ||
        description.length > 120 ||
        amountMinor > 999999999) {
      throw const AccountDataExportFailure();
    }
    return AccountListSplitExpenseExport(
      id: _requiredUuid(json, 'id'),
      description: description,
      amountMinor: amountMinor,
      payerParticipantId: _requiredUuid(json, 'payer_participant_id'),
      creatorParticipantId: _requiredUuid(json, 'creator_participant_id'),
      lastEditorParticipantId: _requiredUuid(
        json,
        'last_editor_participant_id',
      ),
      version: _requiredPositiveInt(json, 'version'),
      createdAt: _requiredUtcDateTime(json, 'created_at'),
      updatedAt: _requiredUtcDateTime(json, 'updated_at'),
      beneficiaryParticipantIds: _requiredArray(
        json,
        'beneficiary_participant_ids',
        (value) => _uuidValue(value),
      ),
      shares: _requiredObjects(json, 'shares')
          .map(AccountListSplitShareExport.fromJson)
          .toList(growable: false),
    );
  }

  static const _keys = {
    'id',
    'description',
    'amount_minor',
    'payer_participant_id',
    'creator_participant_id',
    'last_editor_participant_id',
    'version',
    'created_at',
    'updated_at',
    'beneficiary_participant_ids',
    'shares',
  };

  final String id;
  final String description;
  final int amountMinor;
  final String payerParticipantId;
  final String creatorParticipantId;
  final String lastEditorParticipantId;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> beneficiaryParticipantIds;
  final List<AccountListSplitShareExport> shares;

  bool referencesOnly(Set<String> participantIds) =>
      participantIds.containsAll({
        payerParticipantId,
        creatorParticipantId,
        lastEditorParticipantId,
        ...beneficiaryParticipantIds,
      });

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'amount_minor': amountMinor,
        'payer_participant_id': payerParticipantId,
        'creator_participant_id': creatorParticipantId,
        'last_editor_participant_id': lastEditorParticipantId,
        'version': version,
        'created_at': _encodeDateTime(createdAt),
        'updated_at': _encodeDateTime(updatedAt),
        'beneficiary_participant_ids': beneficiaryParticipantIds,
        'shares': shares.map((share) => share.toJson()).toList(growable: false),
      };
}

class AccountListSplitShareExport {
  const AccountListSplitShareExport({
    required this.participantId,
    required this.amountMinor,
  });

  factory AccountListSplitShareExport.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(json, _keys);
    return AccountListSplitShareExport(
      participantId: _requiredUuid(json, 'participant_id'),
      amountMinor: _requiredNonNegativeInt(json, 'amount_minor'),
    );
  }

  static const _keys = {'participant_id', 'amount_minor'};

  final String participantId;
  final int amountMinor;

  Map<String, dynamic> toJson() => {
        'participant_id': participantId,
        'amount_minor': amountMinor,
      };
}

class AccountActiveListItemExport {
  AccountActiveListItemExport({
    required this.id,
    required this.name,
    required this.quantityThousandths,
    required this.unitCode,
    required this.position,
    required this.version,
    required this.completedAt,
    required this.completedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AccountActiveListItemExport.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(json, _keys);
    final name = _requiredString(json, 'name');
    if (name != name.trim() || name.length > 120) {
      throw const AccountDataExportFailure();
    }
    final quantity = _requiredPositiveInt(json, 'quantity_thousandths');
    if (quantity > 999999999) throw const AccountDataExportFailure();
    final unitCode = _nullableString(json, 'unit_code');
    if (unitCode != null && !_unitCodes.contains(unitCode)) {
      throw const AccountDataExportFailure();
    }
    final completedAt = _nullableUtcDateTime(json, 'completed_at');
    final completedBy = json['completed_by'] == null
        ? null
        : _requiredUuid(json, 'completed_by');
    if (completedAt == null && completedBy != null) {
      throw const AccountDataExportFailure();
    }
    return AccountActiveListItemExport(
      id: _requiredUuid(json, 'id'),
      name: name,
      quantityThousandths: quantity,
      unitCode: unitCode,
      position: _requiredPositiveInt(json, 'position'),
      version: _requiredPositiveInt(json, 'version'),
      completedAt: completedAt,
      completedBy: completedBy,
      createdAt: _requiredUtcDateTime(json, 'created_at'),
      updatedAt: _requiredUtcDateTime(json, 'updated_at'),
    );
  }

  static const _keys = {
    'id',
    'name',
    'quantity_thousandths',
    'unit_code',
    'position',
    'version',
    'completed_at',
    'completed_by',
    'created_at',
    'updated_at',
  };
  static const _unitCodes = {
    'piece',
    'kg',
    'g',
    'l',
    'ml',
    'pack',
    'box',
    'bottle',
    'can',
    'bag',
  };

  final String id;
  final String name;
  final int quantityThousandths;
  final String? unitCode;
  final int position;
  final int version;
  final DateTime? completedAt;
  final String? completedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'quantity_thousandths': quantityThousandths,
        'unit_code': unitCode,
        'position': position,
        'version': version,
        'completed_at': _encodeNullableDateTime(completedAt),
        'completed_by': completedBy,
        'created_at': _encodeDateTime(createdAt),
        'updated_at': _encodeDateTime(updatedAt),
      };
}

final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

void _expectExactKeys(Map<String, dynamic> json, Set<String> expected) {
  if (json.length != expected.length ||
      !json.keys.toSet().containsAll(expected)) {
    throw const AccountDataExportFailure();
  }
}

Map<String, dynamic> _requiredObject(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! Map) throw const AccountDataExportFailure();
  try {
    return Map<String, dynamic>.unmodifiable(
      value.map((objectKey, objectValue) {
        if (objectKey is! String) throw const AccountDataExportFailure();
        return MapEntry(objectKey, objectValue);
      }),
    );
  } on AccountDataExportFailure {
    rethrow;
  } catch (_) {
    throw const AccountDataExportFailure();
  }
}

List<Map<String, dynamic>> _requiredObjects(
  Map<String, dynamic> json,
  String key,
) {
  final value = json[key];
  if (value is! List) throw const AccountDataExportFailure();
  return value
      .map((item) => _requiredObject({'item': item}, 'item'))
      .toList(growable: false);
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw const AccountDataExportFailure();
  }
  return value;
}

String? _nullableString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw const AccountDataExportFailure();
  }
  return value;
}

String _requiredUuid(Map<String, dynamic> json, String key) {
  final value = _requiredString(json, key);
  if (!_uuidPattern.hasMatch(value)) throw const AccountDataExportFailure();
  return value;
}

String? _nullableUuid(Map<String, dynamic> json, String key) {
  if (json[key] == null) return null;
  return _requiredUuid(json, key);
}

String _uuidValue(Object? value) => _requiredUuid({'value': value}, 'value');

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) throw const AccountDataExportFailure();
  return value;
}

int _requiredPositiveInt(Map<String, dynamic> json, String key) {
  final value = _requiredInt(json, key);
  if (value < 1) throw const AccountDataExportFailure();
  return value;
}

int _requiredNonNegativeInt(Map<String, dynamic> json, String key) {
  final value = _requiredInt(json, key);
  if (value < 0) throw const AccountDataExportFailure();
  return value;
}

List<T> _requiredArray<T>(
  Map<String, dynamic> json,
  String key,
  T Function(Object? value) parse,
) {
  final value = json[key];
  if (value is! List) throw const AccountDataExportFailure();
  return value.map(parse).toList(growable: false);
}

int? _nullablePositiveInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! int || value < 1) throw const AccountDataExportFailure();
  return value;
}

bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw const AccountDataExportFailure();
  return value;
}

DateTime _requiredUtcDateTime(Map<String, dynamic> json, String key) {
  final parsed = DateTime.tryParse(_requiredString(json, key));
  if (parsed == null || !parsed.isUtc) throw const AccountDataExportFailure();
  return parsed;
}

DateTime? _nullableUtcDateTime(Map<String, dynamic> json, String key) {
  if (json[key] == null) return null;
  return _requiredUtcDateTime(json, key);
}

AccountRelationshipStatus _relationshipStatus(String value) {
  return AccountRelationshipStatus.values.firstWhere(
    (status) => status.wireValue == value,
    orElse: () => throw const AccountDataExportFailure(),
  );
}

AccountNotificationActionStatus _notificationStatus(String value) {
  return AccountNotificationActionStatus.values.firstWhere(
    (status) => status.wireValue == value,
    orElse: () => throw const AccountDataExportFailure(),
  );
}

AccountActiveListStatus _activeListStatus(String value) {
  return AccountActiveListStatus.values.firstWhere(
    (status) => status.wireValue == value,
    orElse: () => throw const AccountDataExportFailure(),
  );
}

AccountSharedListAccessState _sharedAccessState(String value) {
  return AccountSharedListAccessState.values.firstWhere(
    (state) => state.wireValue == value,
    orElse: () => throw const AccountDataExportFailure(),
  );
}

String _encodeDateTime(DateTime value) => value.toUtc().toIso8601String();

String? _encodeNullableDateTime(DateTime? value) {
  return value == null ? null : _encodeDateTime(value);
}
