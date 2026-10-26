import 'package:discourse_core/discourse_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// What decides whether the composer offers the poll builder, and how:
/// the poll plugin's client settings, and the reader's can_create_poll.
void main() {
  const site = 'https://forum.example';
  setUp(DiscourseSiteCapabilities.reset);

  test('off until the forum says the plugin is on and the reader may', () {
    DiscourseSiteCapabilities caps() => DiscourseSiteCapabilities.forSite(site);
    expect(caps().pollEnabled, isFalse);
    expect(caps().canCreatePoll, isFalse);
    expect(caps().pollMaximumOptions, 20);
    expect(caps().pollDefaultPublic, isTrue);

    DiscourseSiteCapabilities.storeClientSettings(site, {
      'poll_enabled': true,
      'poll_maximum_options': 8,
      'poll_default_public': false,
    });
    DiscourseSiteCapabilities.storeCurrentUser(site, {'can_create_poll': true});
    expect(caps().pollEnabled, isTrue);
    expect(caps().pollMaximumOptions, 8);
    expect(caps().pollDefaultPublic, isFalse);
    expect(caps().canCreatePoll, isTrue);

    // Someone else signs in.
    DiscourseSiteCapabilities.storeCurrentUser(site, {'username': 'newbie'});
    expect(caps().canCreatePoll, isFalse);
  });

  test('a sign-in\'s settings re-read keeps what current_user said', () {
    // Signing in reads current_user, then starts the forum's capabilities
    // afresh for the new key and reads its settings again.
    final before = Object();
    DiscourseSiteCapabilities.beginSession(site, before);
    DiscourseSiteCapabilities.storeCurrentUser(site, {'can_create_poll': true});
    DiscourseSiteCapabilities.beginSession(site, Object());
    DiscourseSiteCapabilities.storeClientSettings(site, {'poll_enabled': true});

    final caps = DiscourseSiteCapabilities.forSite(site);
    expect(caps.pollEnabled, isTrue);
    expect(caps.canCreatePoll, isTrue);
  });
}
