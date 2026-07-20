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
  })  : outgoingBlocks = List.unmodifiable(outgoingBlocks),
        activeRelationships = List.unmodifiable(activeRelationships),
        visibleNotifications = List.unmodifiable(visibleNotifications),
        activeLists = List.unmodifiable(activeLists) {
    if (product != supportedProduct ||
        !supportedSchemaVersions.contains(schemaVersion) ||
        authIdentity.id != profile.id) {
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
      schemaVersion == 1 ? _schemaOneRootKeys : _schemaTwoRootKeys,
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
              .map(AccountActiveListExport.fromJson)
              .toList(growable: false),
    );
  }

  static const supportedProduct = 'list_and_split';
  static const supportedSchemaVersion = 2;
  static const supportedSchemaVersions = {1, supportedSchemaVersion};
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

  final String product;
  final int schemaVersion;
  final DateTime exportedAt;
  final AccountAuthIdentity authIdentity;
  final AccountProfileExport profile;
  final List<AccountOutgoingBlock> outgoingBlocks;
  final List<AccountActiveRelationship> activeRelationships;
  final List<AccountVisibleNotification> visibleNotifications;
  final List<AccountActiveListExport> activeLists;

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
        if (schemaVersion == 2)
          'active_lists': activeLists
              .map((activeList) => activeList.toJson())
              .toList(growable: false),
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
  }) : items = List.unmodifiable(items);

  factory AccountActiveListExport.fromJson(Map<String, dynamic> json) {
    _expectExactKeys(json, _keys);
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
    );
  }

  static const _keys = {
    'id',
    'title',
    'status',
    'version',
    'created_at',
    'updated_at',
    'archived_at',
    'items',
  };

  final String id;
  final String title;
  final AccountActiveListStatus status;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;
  final List<AccountActiveListItemExport> items;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'status': status.wireValue,
        'version': version,
        'created_at': _encodeDateTime(createdAt),
        'updated_at': _encodeDateTime(updatedAt),
        'archived_at': _encodeNullableDateTime(archivedAt),
        'items': items.map((item) => item.toJson()).toList(growable: false),
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

String _encodeDateTime(DateTime value) => value.toUtc().toIso8601String();

String? _encodeNullableDateTime(DateTime? value) {
  return value == null ? null : _encodeDateTime(value);
}
