import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/app/app.dart';
import 'package:list_and_split/core/config/configuration_provider.dart';
import 'package:list_and_split/core/config/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final configuration = await loadAppConfiguration();
  await initializeSupabase(configuration);

  runApp(
    ProviderScope(
      overrides: [
        appConfigurationProvider.overrideWithValue(configuration),
      ],
      child: const ListAndSplitApp(),
    ),
  );
}
