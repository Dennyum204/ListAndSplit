class PushBinding {
  const PushBinding(
      {required this.available,
      required this.permission,
      required this.enabled,
      required this.installation,
      required this.binding,
      this.token});
  final bool available, permission, enabled;
  final String installation, binding;
  final String? token;
}

class PushTap {
  const PushTap(this.delivery, this.binding, this.account);
  final String delivery, binding, account;
}

class PushDestination {
  const PushDestination(this.kind, {this.listId});
  final String kind;
  final String? listId;
}

abstract interface class PushPlatform {
  Stream<PushTap?> get events; // null means token changed.
  Future<PushBinding?> bind(String? account, String language);
  Future<PushBinding> enable();
  Future<PushBinding> disable();
  Future<void> confirm(String binding);
  Future<PushTap?> takeTap();
  Future<void> visibleChat(String? list);
  Future<void> openSettings();
}

abstract interface class PushRepository {
  Future<void> register(String account, PushBinding binding);
  Future<void> unregister(String account, PushBinding binding);
  Future<PushDestination?> resolve(PushTap tap);
}
