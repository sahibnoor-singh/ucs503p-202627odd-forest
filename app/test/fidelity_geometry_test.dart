// Measured numbers from docs/design/home_prototype.html (phone width 432 dp):
// where the app drifts from the prototype, these fail.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:forest_app/features/home/stories_row.dart';
import 'package:forest_app/ui/action_bar.dart';
import 'package:forest_app/ui/forest_card.dart';
import 'package:forest_app/ui/post_media.dart';

import 'support/harness.dart';

void main() {
  testWidgets('cards sit 8dp from the screen edge (on a backdrop of another colour) with the prototype radius', (tester) async {
    useTallScreen(tester);
    await pumpHome(tester, sampleRepo());
    final card = find.byType(ForestCard).first;
    final rect = tester.getRect(card);
    expect(rect.left, 8);
    expect(rect.width, 432 - 16);
    expect(tester.widget<ForestCard>(card).radius, 14);
  });

  testWidgets('the first card follows the Home bar closely, with no divider', (tester) async {
    useTallScreen(tester);
    await pumpHome(tester, sampleRepo());
    final bar = tester.getRect(find.byKey(const Key('open-messages')));
    final firstCard = tester.getRect(find.byType(ForestCard).first);
    expect(find.byType(StoriesRow), findsNothing);
    expect(firstCard.top - bar.bottom, closeTo(2, 0.5));
  });

  testWidgets('the reel frame is 4:5 and fills the card inside its border', (tester) async {
    useTallScreen(tester);
    await pumpHome(tester, sampleRepo());
    final card = tester.getRect(find.byType(ForestCard).first);
    final media = tester.getRect(find.byType(PostMedia).first);
    expect(media.width, card.width - 2, reason: 'full card width inside the 1dp border');
    expect(media.height, closeTo(media.width * 5 / 4, 0.5));
  });

  testWidgets('the action row is 22dp tall', (tester) async {
    useTallScreen(tester);
    await pumpHome(tester, sampleRepo());
    expect(tester.getSize(find.byType(ActionBar).first).height, 22);
  });

  testWidgets('cards are 10dp apart, so the gap can be seen', (tester) async {
    useTallScreen(tester);
    await pumpHome(tester, sampleRepo());
    final cards = find.byType(ForestCard);
    final a = tester.getRect(cards.at(0));
    final b = tester.getRect(cards.at(1));
    expect(b.top - a.bottom, closeTo(10, 0.5));
  });
}
