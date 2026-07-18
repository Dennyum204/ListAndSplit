import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/supabase/supabase_client_provider.dart';
import 'package:list_and_split/features/community/data/supabase_community_repository.dart';
import 'package:list_and_split/features/community/domain/community_repository.dart';

final communityRepositoryProvider = Provider<CommunityRepository>(
  (ref) => SupabaseCommunityRepository(ref.watch(supabaseClientProvider)),
);
