import 'dart:convert';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:discourse_core/discourse_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forumcopilot_sdk/forumcopilot_sdk.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:shared_preferences/shared_preferences.dart';

/// Minting a one-time password, with this test playing Discourse's
/// `user_api_keys#create_otp`.
///
/// The real flow is: POST `/user-api-key/otp` with the `User-Api-Key` header,
/// Discourse puts `SecureRandom.hex` in Redis for ten minutes, encrypts it to
/// the public key we sent and hands it back on `auth_redirect` as
/// `oneTimePassword`. The app decrypts it and builds the `/session/otp/:token`
/// URL a web view opens. Everything here is pure Dart, so it runs without a
/// network or a web view.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const url = 'https://forum.example';

  Future<SiteContext> signedIn({String site = url, bool withKey = true}) async {
    final context = SiteContext(
      siteType: 'discourse',
      site: Site(
        id: null,
        name: 'Example',
        url: site,
        description: 'otp test site',
        endpoint: null,
        baseUrl: site,
        logoUrl: null,
        backgroundUrl: null,
        siteType: 'discourse',
      ),
    );
    if (withKey) {
      await context.setUserApiCredentials(
        userApiKey: 'test-user-api-key',
        userApiClientId: 'test-client-id',
        pushEnabled: false,
      );
    }
    return context;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<String?> mint(DiscourseAuthManager manager) => manager.oneTimeLoginUrl(
        applicationName: 'Victorious Christians',
        authRedirect: 'discourse://auth_redirect',
      );

  test('asks create_otp for JSON, with what it requires', () async {
    final server = _Discourse();
    final manager = DiscourseAuthManager(await signedIn(), client: server);

    await mint(manager);

    expect(server.path, '/user-api-key/otp.json',
        reason: 'the HTML branch answers with a 302 to a discourse:// URL '
            'instead of the payload');
    final q = server.query!;
    expect(q['application_name'], 'Victorious Christians');
    expect(q['auth_redirect'], 'discourse://auth_redirect');
    expect(q['padding'], 'oaep');
    expect(_publicKeyFromPem(q['public_key']! as String).modulus!.bitLength,
        2048);
  });

  test('turns the password into the URL a web view opens', () async {
    final server = _Discourse(otp: 'a1b2c3d4e5f6');
    final manager = DiscourseAuthManager(await signedIn(), client: server);

    expect(await mint(manager), '$url/session/otp/a1b2c3d4e5f6');
  });

  test("survives Ruby's base64 line wrapping", () async {
    // Base64.encode64 wraps at 60 characters, so a 2048-bit payload comes
    // back with newlines in it. base64.decode rejects those.
    final server = _Discourse(otp: 'deadbeef');
    final manager = DiscourseAuthManager(await signedIn(), client: server);

    final minted = await mint(manager);

    expect(server.wrapsBase64, isTrue,
        reason: 'guard: the fake must actually wrap, or this test proves '
            'nothing — and it can only be checked after the request');
    expect(minted, '$url/session/otp/deadbeef');
  });

  test('falls back to PKCS1 v1.5 when the forum ignores padding=oaep',
      () async {
    final server = _Discourse(otp: 'cafef00d', oaep: false);
    final manager = DiscourseAuthManager(await signedIn(), client: server);

    expect(await mint(manager), '$url/session/otp/cafef00d');
  });

  test('keeps a subfolder install in its subfolder', () async {
    const sub = 'https://example.com/forum';
    final server = _Discourse(otp: 'abc123');
    final manager =
        DiscourseAuthManager(await signedIn(site: sub), client: server);

    expect(await mint(manager), '$sub/session/otp/abc123');
  });

  test('signed out: no key, no request, no URL', () async {
    final server = _Discourse();
    final manager =
        DiscourseAuthManager(await signedIn(withKey: false), client: server);

    expect(await mint(manager), isNull);
    expect(server.path, isNull,
        reason: 'nothing to authenticate the mint with, so do not ask');
  });

  test('a refusal opens the page signed out rather than throwing', () async {
    // What a forum whose allow_user_api_key_scopes omits one_time_password
    // answers, and what a member outside user_api_key_allowed_groups gets.
    final server = _Discourse(status: 403);
    final manager = DiscourseAuthManager(await signedIn(), client: server);

    expect(await mint(manager), isNull);
  });

  test('a password that is not hex is refused, not sent to a 404', () async {
    // Discourse constrains the route's :token to hex. Decryption down the
    // wrong padding branch yields plausible bytes rather than throwing.
    final server = _Discourse(otp: 'not a hex token');
    final manager = DiscourseAuthManager(await signedIn(), client: server);

    expect(await mint(manager), isNull);
  });

  test('a body that is not the expected JSON yields null', () async {
    final server = _Discourse(body: '<html>nope</html>');
    final manager = DiscourseAuthManager(await signedIn(), client: server);

    expect(await mint(manager), isNull);
  });
}

/// Stands in for `user_api_keys#create_otp`.
class _Discourse extends DiscourseClient {
  _Discourse({
    this.otp = 'f00d',
    this.oaep = true,
    this.status = 200,
    this.body,
  });

  final String otp;
  final bool oaep;
  final int status;
  final String? body;

  String? path;
  Map<String, dynamic>? query;
  bool wrapsBase64 = false;

  @override
  Future<FCCallResult> post(
    SiteContext context,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    Map<String, String>? extraHeaders,
  }) async {
    this.path = path;
    this.query = query;

    if (status != 200) return FCCallResult(statusCode: status, body: '{}');
    if (this.body != null) {
      return FCCallResult(statusCode: 200, body: this.body!);
    }

    final q = query!;
    final publicKey = _publicKeyFromPem(q['public_key'] as String);
    final payload = _encrypt(otp, publicKey, oaep: oaep);
    wrapsBase64 = payload.contains('\n');

    final redirect = Uri.parse(q['auth_redirect'] as String).replace(
      queryParameters: <String, String>{'oneTimePassword': payload},
    );
    return FCCallResult(
      statusCode: 200,
      body: jsonEncode({'redirect_url': redirect.toString()}),
    );
  }
}

/// X.509 SubjectPublicKeyInfo PEM -> pointycastle key, the way OpenSSL on the
/// Discourse side reads what the app sent.
pc.RSAPublicKey _publicKeyFromPem(String pem) {
  final b64 = pem
      .replaceAll(RegExp(r'-----[A-Z ]+-----'), '')
      .replaceAll(RegExp(r'\s'), '');
  final spki = ASN1Parser(Uint8List.fromList(base64.decode(b64)))
      .nextObject() as ASN1Sequence;
  final bits = spki.elements[1] as ASN1BitString;
  final rsa = ASN1Parser(Uint8List.fromList(bits.stringValue)).nextObject()
      as ASN1Sequence;
  return pc.RSAPublicKey(
    (rsa.elements[0] as ASN1Integer).valueAsBigInteger,
    (rsa.elements[1] as ASN1Integer).valueAsBigInteger,
  );
}

/// What `one_time_password` does with the token: RSA-encrypt the raw hex to
/// the app's public key, then `Base64.encode64`, which wraps at 60 characters.
String _encrypt(String otp, pc.RSAPublicKey publicKey, {required bool oaep}) {
  final random = pc.FortunaRandom()
    ..seed(pc.KeyParameter(
        Uint8List.fromList(List.generate(32, (i) => i * 7 + 1))));
  final pc.AsymmetricBlockCipher cipher =
      oaep ? pc.OAEPEncoding(pc.RSAEngine()) : pc.PKCS1Encoding(pc.RSAEngine());
  cipher.init(
    true,
    pc.ParametersWithRandom(
      pc.PublicKeyParameter<pc.RSAPublicKey>(publicKey),
      random,
    ),
  );
  final raw = base64.encode(cipher.process(Uint8List.fromList(utf8.encode(otp))));
  final wrapped = StringBuffer();
  for (var i = 0; i < raw.length; i += 60) {
    wrapped.writeln(raw.substring(i, i + 60 > raw.length ? raw.length : i + 60));
  }
  return wrapped.toString();
}
