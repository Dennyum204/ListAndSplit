import 'package:list_and_split/features/templates/domain/public_template.dart';

abstract interface class FriendPublicTemplateFeedRepository {
  Future<FriendPublicTemplatePage> listFriendFeed({
    int pageSize = 20,
    PublicTemplateCursor? cursor,
  });
}
