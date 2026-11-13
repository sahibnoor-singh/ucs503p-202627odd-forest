// The "Friends shape my Discover" switch: shows the server's value, saves changes, and puts the old value back when saving fails.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:forest_app/features/discover/friend_taste_switch.dart';

import 'support/fake_server.dart';

http.Response _reply(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Future<FakeServer> _pump(WidgetTester tester, {required bool initial, bool saveFails = false, bool meFails = false}) async {
  final server = FakeServer()
    ..on('GET /api/me', (_) => meFails ? _reply({'error': 'down'}, status: 503) : _reply({'user': {}, 'settings': {'friendTaste': initial}}))
    ..on('PUT /api/me/settings', (s) => saveFails ? _reply({'error': 'Could not save'}, status: 500) : _reply({'settings': s.json}));
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: FriendTasteSwitch(api: server.client()))));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return server;
}

bool _isOn(WidgetTester tester) => tester.widget<SwitchListTile>(find.byKey(const Key('friend-taste-switch'))).value;

void main() {
  testWidgets('shows what the server says, and saves a change', (tester) async {
    final server = await _pump(tester, initial: true);
    expect(_isOn(tester), isTrue);
    await tester.tap(find.byKey(const Key('friend-taste-switch')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_isOn(tester), isFalse);
    expect(server.last('PUT /api/me/settings').json, {'friendTaste': false});
  });

  testWidgets('a save that fails puts the switch back and says why', (tester) async {
    await _pump(tester, initial: true, saveFails: true);
    await tester.tap(find.byKey(const Key('friend-taste-switch')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_isOn(tester), isTrue, reason: 'still on: nothing was saved');
    expect(find.text('Could not save'), findsOneWidget);
  });

  testWidgets('when the setting cannot be read there is no switch to get wrong', (tester) async {
    await _pump(tester, initial: true, meFails: true);
    expect(find.byKey(const Key('friend-taste-switch')), findsNothing);
  });
}
