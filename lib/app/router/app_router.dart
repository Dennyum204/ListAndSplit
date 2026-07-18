import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/app/screens/foundation_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'foundation',
        builder: (context, state) => const FoundationScreen(),
      ),
    ],
  );

  ref.onDispose(router.dispose);
  return router;
});
