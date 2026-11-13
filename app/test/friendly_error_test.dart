// friendlyError: what a person reads when an action fails. Never a raw exception.
import 'package:flutter_test/flutter_test.dart';

import 'package:forest_app/services/api_client.dart';
import 'package:forest_app/services/app_errors.dart';

void main() {
  test('the server\'s own message is shown as it is', () {
    expect(friendlyError(const ApiException('Too many requests'), 'fallback'), 'Too many requests');
  });

  test('anything else gets the plain fallback, never the exception text', () {
    final text = friendlyError(StateError('Bad state: socket closed 0xDEAD'), 'Could not load the replies.');
    expect(text, 'Could not load the replies.');
    expect(text, isNot(contains('Bad state')));
    expect(friendlyError(null, 'x'), 'x');
  });
}
