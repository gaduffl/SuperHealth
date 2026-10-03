import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Why signing in with ChatGPT, or staying signed in, did not work.
///
/// An enum rather than prose so the one settings card can phrase each case in
/// both languages; [ChatGptAuthException.toString] is the English fallback for
/// the services that only surface an error.
enum ChatGptAuthFailure {
  /// OpenAI answered the device-code request with 404: the flow is switched
  /// off on its side, which no retry from here can change.
  deviceLoginUnavailable,

  /// Nobody approved the code within [ChatGptAuth.deviceCodeLifetime].
  codeExpired,

  /// The person cancelled the sign-in.
  cancelled,

  /// OpenAI refused the approval or the code exchange.
  rejected,

  /// The refresh token was expired, reused or revoked. The stored session has
  /// been removed, because only a new sign-in can replace it.
  sessionExpired,

  /// OpenAI could not be reached to renew a token that is no longer usable.
  unreachable,

  /// No ChatGPT session is stored on this device.
  notSignedIn,
}

class ChatGptAuthException implements Exception {
  const ChatGptAuthException(this.failure, {this.detail});

  final ChatGptAuthFailure failure;
  final String? detail;

  @override
  String toString() {
    final message = switch (failure) {
      ChatGptAuthFailure.deviceLoginUnavailable =>
        'OpenAI does not offer device-code sign-in right now.',
      ChatGptAuthFailure.codeExpired =>
        'The ChatGPT sign-in code expired before it was approved.',
      ChatGptAuthFailure.cancelled => 'ChatGPT sign-in was cancelled.',
      ChatGptAuthFailure.rejected => 'OpenAI refused the ChatGPT sign-in.',
      ChatGptAuthFailure.sessionExpired =>
        'The ChatGPT sign-in has expired. Sign in with ChatGPT again in '
            'Settings.',
      ChatGptAuthFailure.unreachable =>
        'Could not reach OpenAI to renew the ChatGPT sign-in.',
      ChatGptAuthFailure.notSignedIn =>
        'Sign in with ChatGPT in Settings first.',
    };
    return detail == null ? message : '$message ($detail)';
  }
}

/// What the settings card shows about the signed-in subscription.
class ChatGptAccount {
  const ChatGptAccount({this.email, this.planType, this.accountId});

  final String? email;

  /// As OpenAI names it: `plus`, `pro`, `business` and so on.
  final String? planType;
  final String? accountId;
}

/// The two things a subscription request has to carry.
class ChatGptSession {
  const ChatGptSession({required this.accessToken, this.accountId});

  final String accessToken;

  /// Sent as `ChatGPT-Account-ID`. Someone in several workspaces is billed to
  /// whichever one this names, so it comes from the token they signed in with
  /// rather than from the server's default.
  final String? accountId;
}

/// A source of a currently valid subscription session.
///
/// The client asks for one per request instead of receiving a key, because the
/// access token rotates: a lab plan runs for minutes and a stored copy taken at
/// the start is the wrong one to retry with after a 401.
abstract interface class ChatGptSessionSource {
  Future<ChatGptSession> session({bool forceRefresh = false});
}

/// A code waiting for someone to approve it in a browser.
class ChatGptDeviceCode {
  const ChatGptDeviceCode({
    required this.userCode,
    required this.deviceAuthId,
    required this.interval,
    required this.issuedAt,
  });

  final String userCode;
  final String deviceAuthId;
  final Duration interval;
  final DateTime issuedAt;

  Uri get verificationUri => ChatGptAuth.verificationUri;
  DateTime get expiresAt => issuedAt.add(ChatGptAuth.deviceCodeLifetime);
}

/// The stored session. Holds no id token: the claims the app needs are copied
/// out at sign-in, and keeping less of a credential on disk is the point.
class ChatGptTokens {
  const ChatGptTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.refreshedAt,
    this.accountId,
    this.email,
    this.planType,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime refreshedAt;
  final String? accountId;
  final String? email;
  final String? planType;

  /// The access token's own `exp`, or null when it does not carry one.
  DateTime? get accessExpiresAt {
    final exp = jwtClaims(accessToken)?['exp'];
    if (exp is! num) return null;
    return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true);
  }

  ChatGptAccount get account =>
      ChatGptAccount(email: email, planType: planType, accountId: accountId);

  ChatGptSession get session =>
      ChatGptSession(accessToken: accessToken, accountId: accountId);

  Map<String, Object?> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'refreshed_at': refreshedAt.toUtc().toIso8601String(),
    'account_id': ?accountId,
    'email': ?email,
    'plan_type': ?planType,
  };

  static ChatGptTokens? fromJson(Object? value) {
    if (value is! Map) return null;
    final access = value['access_token'];
    final refresh = value['refresh_token'];
    if (access is! String || access.isEmpty) return null;
    if (refresh is! String || refresh.isEmpty) return null;
    return ChatGptTokens(
      accessToken: access,
      refreshToken: refresh,
      refreshedAt:
          DateTime.tryParse('${value['refreshed_at']}')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      accountId: _optionalText(value['account_id']),
      email: _optionalText(value['email']),
      planType: _optionalText(value['plan_type']),
    );
  }

  static String? _optionalText(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  /// Builds the stored session from a token response, reading identity from
  /// the id token first and the access token second — the same order Codex
  /// uses, since only the id token is guaranteed to carry the email.
  static ChatGptTokens fromTokenResponse(
    Map<String, Object?> data, {
    required DateTime now,
    ChatGptTokens? previous,
  }) {
    String? text(String key) {
      final value = data[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    final access = text('access_token') ?? previous?.accessToken;
    final refresh = text('refresh_token') ?? previous?.refreshToken;
    if (access == null || access.isEmpty) {
      throw const ChatGptAuthException(
        ChatGptAuthFailure.rejected,
        detail: 'no access token in the response',
      );
    }
    if (refresh == null || refresh.isEmpty) {
      throw const ChatGptAuthException(
        ChatGptAuthFailure.rejected,
        detail: 'no refresh token in the response',
      );
    }
    final idToken = text('id_token');
    final identity = idToken == null ? null : jwtClaims(idToken);
    final accessClaims = jwtClaims(access);
    String? authClaim(Map<String, Object?>? claims, String key) {
      final auth = claims?['https://api.openai.com/auth'];
      final value = auth is Map ? auth[key] : null;
      return value is String && value.isNotEmpty ? value : null;
    }

    String? email(Map<String, Object?>? claims) {
      final direct = claims?['email'];
      if (direct is String && direct.isNotEmpty) return direct;
      final profile = claims?['https://api.openai.com/profile'];
      final nested = profile is Map ? profile['email'] : null;
      return nested is String && nested.isNotEmpty ? nested : null;
    }

    return ChatGptTokens(
      accessToken: access,
      refreshToken: refresh,
      refreshedAt: now.toUtc(),
      accountId:
          authClaim(identity, 'chatgpt_account_id') ??
          authClaim(accessClaims, 'chatgpt_account_id') ??
          previous?.accountId,
      email: email(identity) ?? email(accessClaims) ?? previous?.email,
      planType:
          authClaim(identity, 'chatgpt_plan_type') ??
          authClaim(accessClaims, 'chatgpt_plan_type') ??
          previous?.planType,
    );
  }
}

/// The unverified payload of a JWT, or null when [token] is not one.
///
/// Unverified is fine here: these are claims about our own session that only
/// decide what to display and which header to send. OpenAI verifies the token
/// on every request, so a forged claim buys nothing.
Map<String, Object?>? jwtClaims(String token) {
  final parts = token.split('.');
  if (parts.length != 3 || parts[1].isEmpty) return null;
  try {
    final payload = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    final decoded = jsonDecode(payload);
    return decoded is Map ? Map<String, Object?>.from(decoded) : null;
  } on FormatException {
    return null;
  }
}

/// The subscription session, in Android encrypted storage beside the API keys
/// and outside every snapshot, export and sync allowlist.
class ChatGptTokenStorage {
  ChatGptTokenStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ?? const FlutterSecureStorage(aOptions: AndroidOptions());

  final FlutterSecureStorage _storage;

  static const _key = 'ai_chatgpt_session';

  Future<String?> read() => _storage.read(key: _key);

  Future<void> write(String value) => _storage.write(key: _key, value: value);

  Future<void> delete() => _storage.delete(key: _key);
}

/// Signs in to a ChatGPT subscription the way the Codex CLI does, and keeps
/// that session alive.
///
/// The device-code flow rather than a browser redirect, because a phone has
/// nowhere sensible to redirect to: the person opens one OpenAI page, types a
/// short code, and this polls until it is approved. The sign-in completes on
/// OpenAI's own page; the app never sees a password.
class ChatGptAuth implements ChatGptSessionSource {
  ChatGptAuth({
    ChatGptTokenStorage? storage,
    Dio? dio,
    DateTime Function()? clock,
    Future<void> Function(Duration)? delay,
  }) : _storage = storage ?? ChatGptTokenStorage(),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 20),
               receiveTimeout: const Duration(seconds: 30),
             ),
           ),
       _clock = clock ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed;

  /// The public client Codex signs in with. OpenAI issues no per-app client
  /// for subscription sign-in; third-party tools it has endorsed (OpenCode,
  /// Zed, OpenClaw) use this one, and identify themselves on requests instead.
  static const clientId = 'app_EMoamEEZ73f0CkXaXp7hrann';
  static const issuer = 'https://auth.openai.com';
  static final verificationUri = Uri.parse('$issuer/codex/device');
  static const _userCodeUrl = '$issuer/api/accounts/deviceauth/usercode';
  static const _devicePollUrl = '$issuer/api/accounts/deviceauth/token';
  static const _deviceRedirectUri = '$issuer/deviceauth/callback';
  static const _tokenUrl = '$issuer/oauth/token';

  /// As long as OpenAI keeps a device code open.
  static const deviceCodeLifetime = Duration(minutes: 15);

  /// Renew this long before the access token's own expiry, so a call that
  /// starts just before it does not fail halfway through a tool loop.
  static const refreshMargin = Duration(minutes: 5);

  /// Renew a token that carries no `exp` once it is this old — Codex's own
  /// interval for the same case.
  static const refreshAge = Duration(days: 8);

  final ChatGptTokenStorage _storage;
  final Dio _dio;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _delay;

  ChatGptTokens? _cached;
  bool _loaded = false;

  final _changes = StreamController<void>.broadcast();

  /// Fires whenever the stored session appears, is renewed or goes away —
  /// including when a renewal finds it dead in the middle of a run, which
  /// Settings would otherwise keep showing as signed in.
  Stream<void> get changes => _changes.stream;

  /// The refresh in flight, shared by every caller that needs one.
  ///
  /// OpenAI rotates the refresh token on use and treats a second use of the
  /// old one as theft — `refresh_token_reused`, which ends the session. Two
  /// calls refreshing side by side would therefore sign the person out, so
  /// they wait on one.
  Future<ChatGptTokens>? _refreshing;

  Future<ChatGptTokens?> _load() async {
    if (_loaded) return _cached;
    final raw = await _storage.read();
    ChatGptTokens? tokens;
    if (raw != null && raw.isNotEmpty) {
      try {
        tokens = ChatGptTokens.fromJson(jsonDecode(raw));
      } on FormatException {
        tokens = null;
      }
    }
    _cached = tokens;
    _loaded = true;
    return tokens;
  }

  Future<void> _persist(ChatGptTokens tokens) async {
    await _storage.write(jsonEncode(tokens.toJson()));
    _cached = tokens;
    _loaded = true;
    _changes.add(null);
  }

  Future<bool> isSignedIn() async => await _load() != null;

  Future<ChatGptAccount?> account() async => (await _load())?.account;

  /// The stored access token, without renewing it. A presence check for the
  /// call sites that gate on "has a credential"; requests go through
  /// [session], which renews.
  Future<String?> storedAccessToken() async => (await _load())?.accessToken;

  Future<void> signOut() async {
    await _storage.delete();
    _cached = null;
    _loaded = true;
    _changes.add(null);
  }

  Future<ChatGptDeviceCode> startDeviceLogin() async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _userCodeUrl,
        data: {'client_id': clientId},
        options: Options(contentType: Headers.jsonContentType),
      );
      final data = response.data ?? const <String, dynamic>{};
      final userCode = (data['user_code'] ?? data['usercode'])?.toString();
      final deviceAuthId = data['device_auth_id']?.toString();
      if (userCode == null ||
          userCode.isEmpty ||
          deviceAuthId == null ||
          deviceAuthId.isEmpty) {
        throw const ChatGptAuthException(
          ChatGptAuthFailure.rejected,
          detail: 'no device code in the response',
        );
      }
      // Codex receives the interval as a string; accept a number too. A zero
      // or missing one would poll in a tight loop, so it gets a floor.
      final seconds = int.tryParse('${data['interval'] ?? ''}'.trim()) ?? 0;
      return ChatGptDeviceCode(
        userCode: userCode,
        deviceAuthId: deviceAuthId,
        interval: Duration(seconds: seconds < 1 ? 5 : seconds),
        issuedAt: _clock(),
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        throw const ChatGptAuthException(
          ChatGptAuthFailure.deviceLoginUnavailable,
        );
      }
      throw ChatGptAuthException(
        error.response == null
            ? ChatGptAuthFailure.unreachable
            : ChatGptAuthFailure.rejected,
        detail: _describe(error),
      );
    }
  }

  /// Waits for [code] to be approved, then stores the session.
  ///
  /// A dropped connection while polling is not a failure: on a phone the
  /// person is in the browser approving the code, and Android may freeze this
  /// process until they come back. Only an answer from OpenAI, the deadline or
  /// [isCancelled] ends the wait.
  Future<ChatGptAccount> completeDeviceLogin(
    ChatGptDeviceCode code, {
    bool Function()? isCancelled,
  }) async {
    bool cancelled() => isCancelled?.call() ?? false;
    Map<String, Object?> approval;
    while (true) {
      if (cancelled()) {
        throw const ChatGptAuthException(ChatGptAuthFailure.cancelled);
      }
      try {
        final response = await _dio.post<Map<String, dynamic>>(
          _devicePollUrl,
          data: {
            'device_auth_id': code.deviceAuthId,
            'user_code': code.userCode,
          },
          options: Options(contentType: Headers.jsonContentType),
        );
        approval = Map<String, Object?>.from(response.data ?? const {});
        break;
      } on DioException catch (error) {
        final status = error.response?.statusCode;
        // 403 and 404 mean "not approved yet" in this flow.
        final pending = status == 403 || status == 404 || status == null;
        if (!pending) {
          throw ChatGptAuthException(
            ChatGptAuthFailure.rejected,
            detail: _describe(error),
          );
        }
      }
      if (!_clock().isBefore(code.expiresAt)) {
        throw const ChatGptAuthException(ChatGptAuthFailure.codeExpired);
      }
      await _delay(code.interval);
    }
    if (cancelled()) {
      throw const ChatGptAuthException(ChatGptAuthFailure.cancelled);
    }

    final authorizationCode = approval['authorization_code']?.toString();
    final verifier = approval['code_verifier']?.toString();
    if (authorizationCode == null || verifier == null) {
      throw const ChatGptAuthException(
        ChatGptAuthFailure.rejected,
        detail: 'the approval carried no authorization code',
      );
    }
    try {
      // Sent exactly once. A timeout here may mean the code was already
      // consumed, and a second exchange would only be refused.
      final response = await _dio.post<Map<String, dynamic>>(
        _tokenUrl,
        data: {
          'grant_type': 'authorization_code',
          'client_id': clientId,
          'code': authorizationCode,
          'redirect_uri': _deviceRedirectUri,
          'code_verifier': verifier,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final tokens = ChatGptTokens.fromTokenResponse(
        Map<String, Object?>.from(response.data ?? const {}),
        now: _clock(),
      );
      await _persist(tokens);
      return tokens.account;
    } on DioException catch (error) {
      throw ChatGptAuthException(
        error.response == null
            ? ChatGptAuthFailure.unreachable
            : ChatGptAuthFailure.rejected,
        detail: _describe(error),
      );
    }
  }

  @override
  Future<ChatGptSession> session({bool forceRefresh = false}) async {
    final current = await _load();
    if (current == null) {
      throw const ChatGptAuthException(ChatGptAuthFailure.notSignedIn);
    }
    if (!forceRefresh && !_needsRefresh(current)) return current.session;
    try {
      final refreshed = await (_refreshing ??= _refresh(
        current,
      ).whenComplete(() => _refreshing = null));
      return refreshed.session;
    } on ChatGptAuthException catch (error) {
      // A proactive renewal that could not reach OpenAI does not make a token
      // that is still valid unusable. Only a forced renewal — the server just
      // said 401 — or an expired token has nothing to fall back on.
      if (error.failure == ChatGptAuthFailure.unreachable &&
          !forceRefresh &&
          !_isExpired(current)) {
        return current.session;
      }
      rethrow;
    }
  }

  bool _needsRefresh(ChatGptTokens tokens) {
    final now = _clock().toUtc();
    final expiresAt = tokens.accessExpiresAt;
    if (expiresAt != null) {
      return !now.isBefore(expiresAt.subtract(refreshMargin));
    }
    return now.difference(tokens.refreshedAt) >= refreshAge;
  }

  bool _isExpired(ChatGptTokens tokens) {
    final expiresAt = tokens.accessExpiresAt;
    return expiresAt != null && !_clock().toUtc().isBefore(expiresAt);
  }

  Future<ChatGptTokens> _refresh(ChatGptTokens current) async {
    try {
      // JSON, not a form: the refresh endpoint takes JSON while the
      // authorization-code exchange takes a form, as in Codex.
      final response = await _dio.post<Map<String, dynamic>>(
        _tokenUrl,
        data: {
          'client_id': clientId,
          'grant_type': 'refresh_token',
          'refresh_token': current.refreshToken,
        },
        options: Options(contentType: Headers.jsonContentType),
      );
      final next = ChatGptTokens.fromTokenResponse(
        Map<String, Object?>.from(response.data ?? const {}),
        now: _clock(),
        previous: current,
      );
      await _persist(next);
      return next;
    } on DioException catch (error) {
      final response = error.response;
      if (response != null &&
          _isPermanentRefreshFailure(response.statusCode, response.data)) {
        // A dead refresh token can never be renewed again; keeping it would
        // leave Settings claiming a sign-in that every request then refuses.
        await signOut();
        throw ChatGptAuthException(
          ChatGptAuthFailure.sessionExpired,
          detail: _describe(error),
        );
      }
      throw ChatGptAuthException(
        ChatGptAuthFailure.unreachable,
        detail: _describe(error),
      );
    }
  }
}

/// Whether a failed refresh means the session is over, rather than that the
/// request failed.
///
/// The same classification Codex applies: 401, an OAuth `invalid_grant` 400,
/// or one of the three refresh-token codes. Everything else — a 5xx, a rate
/// limit — leaves the session in place for the next attempt.
bool _isPermanentRefreshFailure(int? status, Object? body) {
  if (status == 401) return true;
  final code = _errorCode(body)?.toLowerCase();
  if (status == 400 && code == 'invalid_grant') return true;
  return const {
    'refresh_token_expired',
    'refresh_token_reused',
    'refresh_token_invalidated',
  }.contains(code);
}

String? _errorCode(Object? body) {
  if (body is! Map) return null;
  final error = body['error'];
  if (error is String) return error;
  if (error is Map && error['code'] != null) return '${error['code']}';
  final code = body['code'];
  return code == null ? null : '$code';
}

/// A short, secret-free account of an auth failure. Token request bodies are
/// never echoed: they contain the very codes and tokens being exchanged.
String _describe(DioException error) {
  final status = error.response?.statusCode;
  final code = _errorCode(error.response?.data);
  if (status == null) return error.type.name;
  return code == null ? 'HTTP $status' : 'HTTP $status, $code';
}
