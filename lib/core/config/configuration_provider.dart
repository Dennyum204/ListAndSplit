import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/config/supabase_config.dart';

final appConfigurationProvider = Provider<AppConfiguration>(
  (ref) => AppConfiguration.fromEnvironment(),
);
