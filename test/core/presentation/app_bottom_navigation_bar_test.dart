import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/core/presentation/app_bottom_navigation_bar.dart';
import 'package:list_and_split/core/theme/app_palette.dart';
import 'package:list_and_split/core/theme/app_theme.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

void main() {
  for (final language in ['en', 'pt']) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
            '$language ${mode.name} at ${scale * 100}% encloses selected icon and label',
            (tester) async {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final semantics = tester.ensureSemantics();
          try {
            var selected = 0;
            final taps = <int>[];
            await tester.pumpWidget(MaterialApp(
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: mode,
              locale: Locale(language),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Builder(builder: (context) {
                final strings = AppLocalizations.of(context);
                return MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: StatefulBuilder(builder: (context, setState) {
                    return Scaffold(
                      body: const SizedBox.expand(),
                      bottomNavigationBar: AppBottomNavigationBar(
                        selectedIndex: selected,
                        onDestinationSelected: (index) {
                          taps.add(index);
                          setState(() => selected = index);
                        },
                        destinations: [
                          NavigationDestination(
                            key: const Key('destination-0'),
                            icon: const Icon(Icons.checklist_rounded),
                            label: strings.shellListsTab,
                          ),
                          NavigationDestination(
                            key: const Key('destination-1'),
                            icon: const Icon(Icons.copy_all_outlined),
                            label: strings.shellTemplatesTab,
                          ),
                          NavigationDestination(
                            key: const Key('destination-2'),
                            icon: const Icon(Icons.people_outline_rounded),
                            label: strings.shellCommunityTab,
                          ),
                          NavigationDestination(
                            key: const Key('destination-3'),
                            icon: const Icon(Icons.person_outline_rounded),
                            label: strings.shellProfileTab,
                          ),
                        ],
                      ),
                    );
                  }),
                );
              }),
            ));
            await tester.pumpAndSettle();

            for (var index = 0; index < 4; index++) {
              final destination = find.byKey(Key('destination-$index'));
              await tester.tap(destination);
              await tester.pumpAndSettle();
              expect(taps, [for (var i = 0; i <= index; i++) i]);
              for (var other = 0; other < 4; other++) {
                expect(
                    tester.getSemantics(find.byKey(Key('destination-$other'))),
                    containsSemantics(
                      isSelected: other == index,
                      isButton: true,
                      hasTapAction: true,
                    ));
              }
              final pill = find.byKey(Key('navigationPill-$index'));
              expect(tester.widget<Material>(pill).color, AppPalette.orange);
              final label =
                  find.descendant(of: pill, matching: find.byType(Text));
              final icon =
                  find.descendant(of: pill, matching: find.byType(Icon));
              expect(label, findsOneWidget);
              expect(icon, findsOneWidget);
              final pillBounds = tester.getRect(pill);
              for (final content in [label, icon]) {
                final bounds = tester.getRect(content);
                expect(pillBounds.contains(bounds.topLeft), isTrue);
                expect(pillBounds.contains(bounds.bottomRight), isTrue);
              }
              expect(tester.widget<Text>(label).style!.color, AppPalette.navy);
              expect(IconTheme.of(tester.element(icon)).color, AppPalette.navy);
              expect(
                  tester.getSize(destination).height, greaterThanOrEqualTo(48));
              expect(
                  tester.getSize(destination).width, greaterThanOrEqualTo(48));
              expect(tester.takeException(), isNull);
            }
          } finally {
            semantics.dispose();
          }
        });
      }
    }
  }
}
