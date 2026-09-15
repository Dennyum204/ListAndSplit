import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/branding/list_split_mark.dart';
import 'package:list_and_split/core/theme/app_theme.dart';
import 'package:list_and_split/features/settings/presentation/language_preference_controller.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

/// Runs initialization immediately. The cover never owns or replaces a route,
/// and its clock is process-local, so background resume cannot replay it.
class StartupHost extends StatefulWidget {
  const StartupHost(
      {super.key,
      required this.initialize,
      this.destinationChannel =
          const MethodChannel('com.ferbatech.listandsplit/startup')});
  final Future<Widget> Function() initialize;
  final MethodChannel destinationChannel;
  @override
  State<StartupHost> createState() => _StartupHostState();
}

class _StartupHostState extends State<StartupHost> with WidgetsBindingObserver {
  Widget? _app;
  bool _cover = true;
  bool _failed = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer(const Duration(seconds: 3), _dismiss);
    widget.destinationChannel.setMethodCallHandler((call) async {
      if (call.method == 'urgentDestination') _dismiss();
    });
    unawaited(_checkDestination());
    unawaited(_initialize());
  }

  Future<void> _checkDestination() async {
    try {
      if (await widget.destinationChannel
              .invokeMethod<bool>('hasDestination') ==
          true) {
        _dismiss();
      }
    } on MissingPluginException {
      /* Non-Android and tests. */
    } on PlatformException {/* A normal launch remains usable. */}
  }

  Future<void> _initialize() async {
    try {
      final app = await widget.initialize();
      if (mounted) {
        setState(() {
          _app = app;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _dismiss() {
    _timer?.cancel();
    if (mounted && _cover) setState(() => _cover = false);
  }

  @override
  Future<bool> didPushRouteInformation(
      RouteInformation routeInformation) async {
    _dismiss();
    return false; // The existing router/auth callback remains the handler.
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations) {
      _dismiss();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.destinationChannel.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ??
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
            .disableAnimations;
    final show = _app == null || (_cover && !reduced);
    return Stack(
        textDirection: TextDirection.ltr,
        fit: StackFit.expand,
        children: [
          if (_app != null)
            ExcludeSemantics(
                excluding: show,
                child: IgnorePointer(ignoring: show, child: _app!)),
          if (show)
            ProviderScope(
                child: WelcomeApp(
                    key: const ValueKey('coldLaunchWelcome'),
                    reducedMotion: reduced,
                    failed: _failed,
                    onRetry: () {
                      setState(() => _failed = false);
                      unawaited(_initialize());
                    })),
        ]);
  }
}

class WelcomeApp extends ConsumerWidget {
  const WelcomeApp(
      {super.key,
      this.reducedMotion = false,
      this.failed = false,
      this.onRetry});
  final bool reducedMotion;
  final bool failed;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        locale: ref.watch(
            languagePreferenceControllerProvider.select((s) => s.locale)),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
            builder: (context) => Scaffold(
                  backgroundColor: ListSplitMarkPainter.background,
                  body: SafeArea(
                      child: Center(
                          child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: reducedMotion ? 1 : 0, end: 1),
                      duration: reducedMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) => Opacity(
                          opacity: value,
                          child: Transform.scale(
                              scale: 0.94 + 0.06 * value, child: child)),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const ListSplitMark(),
                        const SizedBox(height: 8),
                        Text('List & Split',
                            style: Theme.of(context).textTheme.headlineLarge,
                            textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        Text(AppLocalizations.of(context).welcomeMessage,
                            style: Theme.of(context).textTheme.titleMedium,
                            textAlign: TextAlign.center),
                        if (failed) ...[
                          const SizedBox(height: 24),
                          Text(AppLocalizations.of(context).welcomeRetryMessage,
                              textAlign: TextAlign.center),
                          TextButton(
                              onPressed: onRetry,
                              child: Text(AppLocalizations.of(context)
                                  .welcomeRetryButton)),
                        ],
                      ]),
                    ),
                  ))),
                )),
      );
}
