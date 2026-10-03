import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ai/ai_models.dart';
import 'package:super_health/ai/api_key_store.dart';
import 'package:super_health/ai/chatgpt_auth.dart';

class _MemoryStorage extends ChatGptTokenStorage {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;

  @override
  Future<void> delete() async => value = null;
}

/// One scripted answer: a body, an HTTP error status, or a dropped connection.
class _Reply {
  const _Reply.ok(this.body) : status = 200, dropped = false;
  const _Reply.status(this.status, [this.body]) : dropped = false;
  const _Reply.dropped() : status = 0, body = null, dropped = true;

  final int status;
  final Object? body;
  final bool dropped;
}

/// Answers each URL from its own queue, repeating the last reply once the
/// queue is down to one, and records every request as sent.
class _Server {
  final replies = <String, List<_Reply>>{};
  final requests = <RequestOptions>[];

  int count(String url) =>
      requests.where((request) => request.uri.toString() == url).length;

  Dio dio() {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          final queue = replies[options.uri.toString()];
          if (queue == null || queue.isEmpty) {
            fail('unexpected request to ${options.uri}');
          }
          final reply = queue.length > 1 ? queue.removeAt(0) : queue.first;
          if (reply.dropped) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
              ),
            );
          } else if (reply.status >= 400) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                response: Response(
                  requestOptions: options,
                  statusCode: reply.status,
                  data: reply.body,
                ),
              ),
            );
          } else {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: reply.status,
                data: reply.body,
              ),
            );
          }
        },
      ),
    );
    return dio;
  }
}

const _userCodeUrl = 'https://auth.openai.com/api/accounts/deviceauth/usercode';
const _pollUrl = 'https://auth.openai.com/api/accounts/deviceauth/token';
const _tokenUrl = 'https://auth.openai.com/oauth/token';

String _jwt(Map<String, Object?> claims) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '')}.signature';

int _epoch(DateTime at) => at.millisecondsSinceEpoch ~/ 1000;

void main() {
  late _Server server;
  late _MemoryStorage storage;
  late DateTime now;
  late List<Duration> delays;

  ChatGptAuth auth() => ChatGptAuth(
    storage: storage,
    dio: server.dio(),
    clock: () => now,
    delay: (duration) async {
      delays.add(duration);
      now = now.add(duration);
    },
  );

  void store({
    required DateTime accessExpiresAt,
    String refresh = 'refresh-1',
  }) {
    storage.value = jsonEncode(
      ChatGptTokens(
        accessToken: _jwt({'exp': _epoch(accessExpiresAt)}),
        refreshToken: refresh,
        refreshedAt: now,
        accountId: 'acct-1',
        email: 'pat@example.com',
        planType: 'plus',
      ).toJson(),
    );
  }

  setUp(() {
    server = _Server();
    storage = _MemoryStorage();
    now = DateTime.utc(2026, 10, 3, 12);
    delays = [];
  });

  test(
    'device sign-in polls through pending answers and dropped connections, '
    'exchanges the code once as a form, and keeps identity but no id token',
    () async {
      final accessToken = _jwt({
        'exp': _epoch(now.add(const Duration(days: 10))),
      });
      server.replies
        ..[_userCodeUrl] = [
          const _Reply.ok({
            'device_auth_id': 'device-1',
            'user_code': 'ABCD-1234',
            'interval': '5',
          }),
        ]
        ..[_pollUrl] = [
          const _Reply.status(403),
          const _Reply.dropped(),
          const _Reply.ok({
            'authorization_code': 'code-1',
            'code_challenge': 'challenge-1',
            'code_verifier': 'verifier-1',
          }),
        ]
        ..[_tokenUrl] = [
          _Reply.ok({
            'id_token': _jwt({
              'email': 'pat@example.com',
              'https://api.openai.com/auth': {
                'chatgpt_account_id': 'acct-1',
                'chatgpt_plan_type': 'plus',
              },
            }),
            'access_token': accessToken,
            'refresh_token': 'refresh-1',
          }),
        ];
      final subject = auth();

      final code = await subject.startDeviceLogin();
      expect(code.userCode, 'ABCD-1234');
      expect(
        code.verificationUri.toString(),
        'https://auth.openai.com/codex/device',
      );
      expect(server.requests.single.data, {'client_id': ChatGptAuth.clientId});

      final account = await subject.completeDeviceLogin(code);

      expect(account.email, 'pat@example.com');
      expect(account.planType, 'plus');
      expect(account.accountId, 'acct-1');
      expect(delays, [const Duration(seconds: 5), const Duration(seconds: 5)]);
      expect(server.count(_pollUrl), 3);
      expect(server.count(_tokenUrl), 1, reason: 'a code is exchanged once');
      final exchange = server.requests.last;
      expect(exchange.contentType, Headers.formUrlEncodedContentType);
      expect(exchange.data, {
        'grant_type': 'authorization_code',
        'client_id': ChatGptAuth.clientId,
        'code': 'code-1',
        'redirect_uri': 'https://auth.openai.com/deviceauth/callback',
        'code_verifier': 'verifier-1',
      });
      final stored = jsonDecode(storage.value!) as Map<String, Object?>;
      expect(stored['access_token'], accessToken);
      expect(stored['refresh_token'], 'refresh-1');
      expect(stored.containsKey('id_token'), isFalse);
      expect(await subject.isSignedIn(), isTrue);
    },
  );

  test(
    'a device-code request OpenAI answers with 404 reads as unavailable',
    () async {
      server.replies[_userCodeUrl] = [const _Reply.status(404)];

      await expectLater(
        auth().startDeviceLogin(),
        throwsA(
          isA<ChatGptAuthException>().having(
            (error) => error.failure,
            'failure',
            ChatGptAuthFailure.deviceLoginUnavailable,
          ),
        ),
      );
    },
  );

  test('cancelling stops the polling before the next request', () async {
    server.replies[_pollUrl] = [const _Reply.status(403)];
    var cancelled = false;
    final subject = ChatGptAuth(
      storage: storage,
      dio: server.dio(),
      clock: () => now,
      delay: (_) async => cancelled = true,
    );
    final code = ChatGptDeviceCode(
      userCode: 'ABCD-1234',
      deviceAuthId: 'device-1',
      interval: const Duration(seconds: 5),
      issuedAt: now,
    );

    await expectLater(
      subject.completeDeviceLogin(code, isCancelled: () => cancelled),
      throwsA(
        isA<ChatGptAuthException>().having(
          (error) => error.failure,
          'failure',
          ChatGptAuthFailure.cancelled,
        ),
      ),
    );
    expect(server.count(_pollUrl), 1);
    expect(storage.value, isNull);
  });

  test('a code nobody approves gives up at its deadline', () async {
    server.replies[_pollUrl] = [const _Reply.status(403)];
    final code = ChatGptDeviceCode(
      userCode: 'ABCD-1234',
      deviceAuthId: 'device-1',
      interval: const Duration(minutes: 5),
      issuedAt: now,
    );

    await expectLater(
      auth().completeDeviceLogin(code),
      throwsA(
        isA<ChatGptAuthException>().having(
          (error) => error.failure,
          'failure',
          ChatGptAuthFailure.codeExpired,
        ),
      ),
    );
    expect(now.difference(code.issuedAt), ChatGptAuth.deviceCodeLifetime);
  });

  test('a token with time left is used without asking OpenAI', () async {
    store(accessExpiresAt: now.add(const Duration(days: 3)));

    final session = await auth().session();

    expect(session.accountId, 'acct-1');
    expect(server.requests, isEmpty);
  });

  test(
    'a token near its expiry is renewed with a JSON refresh, and the rotated '
    'refresh token replaces the old one',
    () async {
      store(accessExpiresAt: now.add(const Duration(minutes: 2)));
      final renewed = _jwt({'exp': _epoch(now.add(const Duration(days: 10)))});
      server.replies[_tokenUrl] = [
        _Reply.ok({'access_token': renewed, 'refresh_token': 'refresh-2'}),
      ];
      final subject = auth();
      var changes = 0;
      final subscription = subject.changes.listen((_) => changes++);

      final session = await subject.session();
      await pumpEventQueue();

      expect(session.accessToken, renewed);
      expect(
        session.accountId,
        'acct-1',
        reason: 'kept when no id token comes back',
      );
      final refresh = server.requests.single;
      expect(refresh.contentType, Headers.jsonContentType);
      expect(refresh.data, {
        'client_id': ChatGptAuth.clientId,
        'grant_type': 'refresh_token',
        'refresh_token': 'refresh-1',
      });
      final stored = jsonDecode(storage.value!) as Map<String, Object?>;
      expect(stored['refresh_token'], 'refresh-2');
      expect(stored['email'], 'pat@example.com');
      expect(changes, 1);
      await subscription.cancel();
    },
  );

  test('calls that need a renewal at the same time share one', () async {
    // A second use of a rotated refresh token is treated as theft and ends
    // the session, so parallel renewals would sign the person out.
    store(accessExpiresAt: now.subtract(const Duration(minutes: 1)));
    final renewed = _jwt({'exp': _epoch(now.add(const Duration(days: 10)))});
    server.replies[_tokenUrl] = [
      _Reply.ok({'access_token': renewed, 'refresh_token': 'refresh-2'}),
    ];
    final subject = auth();

    final sessions = await Future.wait([
      subject.session(),
      subject.session(),
      subject.session(forceRefresh: true),
    ]);

    expect(server.count(_tokenUrl), 1);
    expect(sessions.map((session) => session.accessToken).toSet(), {renewed});
  });

  test('a reused refresh token ends the session and says so', () async {
    store(accessExpiresAt: now.subtract(const Duration(minutes: 1)));
    server.replies[_tokenUrl] = [
      const _Reply.status(401, {
        'error': {'code': 'refresh_token_reused', 'message': 'reused'},
      }),
    ];
    final subject = auth();

    await expectLater(
      subject.session(),
      throwsA(
        isA<ChatGptAuthException>().having(
          (error) => error.failure,
          'failure',
          ChatGptAuthFailure.sessionExpired,
        ),
      ),
    );
    expect(storage.value, isNull);
    expect(await subject.isSignedIn(), isFalse);
  });

  test('an invalid_grant answer ends the session too', () async {
    store(accessExpiresAt: now.subtract(const Duration(minutes: 1)));
    server.replies[_tokenUrl] = [
      const _Reply.status(400, {'error': 'invalid_grant'}),
    ];

    await expectLater(
      auth().session(),
      throwsA(
        isA<ChatGptAuthException>().having(
          (error) => error.failure,
          'failure',
          ChatGptAuthFailure.sessionExpired,
        ),
      ),
    );
    expect(storage.value, isNull);
  });

  test('a renewal that cannot reach OpenAI keeps a token that is still valid, '
      'and fails a forced one without discarding the session', () async {
    store(accessExpiresAt: now.add(const Duration(minutes: 2)));
    server.replies[_tokenUrl] = [const _Reply.dropped()];
    final subject = auth();

    final kept = await subject.session();
    expect(kept.accountId, 'acct-1');

    await expectLater(
      subject.session(forceRefresh: true),
      throwsA(
        isA<ChatGptAuthException>().having(
          (error) => error.failure,
          'failure',
          ChatGptAuthFailure.unreachable,
        ),
      ),
    );
    expect(
      storage.value,
      isNotNull,
      reason: 'a server hiccup is not a sign-out',
    );
  });

  test('a server error during renewal does not end the session', () async {
    store(accessExpiresAt: now.subtract(const Duration(minutes: 1)));
    server.replies[_tokenUrl] = [const _Reply.status(503)];

    await expectLater(
      auth().session(),
      throwsA(
        isA<ChatGptAuthException>().having(
          (error) => error.failure,
          'failure',
          ChatGptAuthFailure.unreachable,
        ),
      ),
    );
    expect(storage.value, isNotNull);
  });

  test(
    'without a stored session the subscription reads as not signed in',
    () async {
      await expectLater(
        auth().session(),
        throwsA(
          isA<ChatGptAuthException>().having(
            (error) => error.failure,
            'failure',
            ChatGptAuthFailure.notSignedIn,
          ),
        ),
      );
    },
  );

  test('the key store answers for the subscription from the sign-in', () async {
    final subject = auth();
    final keys = ApiKeyStore(chatGpt: subject);

    expect(await keys.hasKey(AiProvider.chatgpt), isFalse);
    expect(
      ApiKeyStore.missingCredentialMessage(AiProvider.chatgpt),
      'Sign in with ChatGPT in Settings first.',
    );

    store(accessExpiresAt: now.add(const Duration(days: 3)));
    final signedIn = auth();
    final signedInKeys = ApiKeyStore(chatGpt: signedIn);
    expect(await signedInKeys.hasKey(AiProvider.chatgpt), isTrue);
    expect(await signedInKeys.read(AiProvider.chatgpt), isNotEmpty);
    await expectLater(
      signedInKeys.save(AiProvider.chatgpt, 'sk-anything'),
      throwsStateError,
    );

    await signedInKeys.delete(AiProvider.chatgpt);
    expect(await signedInKeys.hasKey(AiProvider.chatgpt), isFalse);
    expect(storage.value, isNull);
  });
}
