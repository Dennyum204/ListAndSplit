import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/app/app.dart';

void main() {
  testWidgets('shows the List & Split foundation screen', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: ListAndSplitApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('List & Split'), findsOneWidget);
    expect(find.text('Plan together. Settle simply.'), findsOneWidget);
    expect(find.text('Foundation ready'), findsOneWidget);
    expect(find.byIcon(Icons.checklist_rounded), findsOneWidget);
  });
}
