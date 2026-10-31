import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/services/feedback_consent_store.dart';
import 'package:whispaste/services/feedback_submission_service.dart';

FeedbackSubmissionService _service(
  http.Client client, {
  String url = 'https://x.supabase.co',
  Duration timeout = const Duration(seconds: 15),
  void Function(Breadcrumb)? breadcrumbs,
}) => FeedbackSubmissionService(
  client: client,
  supabaseUrl: url,
  supabasePublishableKey: 'key',
  timeout: timeout,
  breadcrumbSink: breadcrumbs ?? (_) {},
);

/// Answers every withdrawal with the next status of [statuses] (the last one
/// repeats) and counts the calls.
final class _Server {
  _Server(this.statuses);

  final List<int> statuses;
  final sent = <String>[];

  FeedbackSubmissionService get service => _service(
    MockClient((request) async {
      sent.add((jsonDecode(request.body) as Map)['p_token'] as String);
      final i = sent.length - 1;
      return http.Response(
        '',
        statuses[i < statuses.length ? i : statuses.length - 1],
      );
    }),
  );
}

/// Consent state kept in memory; can fail writes like a crash would.
final class _MemoryStorage implements ConsentStateStorage {
  _MemoryStorage([this.state = const ConsentState()]);

  ConsentState state;
  bool failWrites = false;
  bool failReads = false;

  /// Makes every write take a while, like real storage, so two unserialized
  /// read-change-write cycles would overlap.
  bool slowWrites = false;

  @override
  Future<ConsentState> read() async {
    if (failReads) throw StateError('storage unavailable');
    return state;
  }

  @override
  Future<void> write(ConsentState next) async {
    if (failWrites) throw StateError('crash during write');
    if (slowWrites) await Future<void>.delayed(const Duration(milliseconds: 5));
    state = next;
  }
}

final class _FakeSecureKeyStore implements SecureKeyStore {
  final values = <String, String>{};
  bool unavailable = false;

  @override
  Future<String?> readKey(String key) async {
    if (unavailable) throw StateError('no libsecret');
    return values[key];
  }

  @override
  Future<void> writeKey(String key, String value) async {
    if (unavailable) throw StateError('no libsecret');
    values[key] = value;
  }

  @override
  Future<void> deleteKey(String key) async {
    if (unavailable) throw StateError('no libsecret');
    values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Prefs whose removals fail, as when the platform store rejects a write.
final class _NoRemovePrefs implements SharedPreferences {
  _NoRemovePrefs(this._inner);

  final SharedPreferences _inner;
  bool failRemoves = true;

  @override
  String? getString(String key) => _inner.getString(key);

  @override
  List<String>? getStringList(String key) => _inner.getStringList(key);

  @override
  Future<bool> setString(String key, String value) =>
      _inner.setString(key, value);

  @override
  Future<bool> remove(String key) async {
    if (failRemoves) throw StateError('prefs write failed');
    return _inner.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Writes fail while reads and deletes still work.
final class _FlakyWriteSecureKeyStore extends _FakeSecureKeyStore {
  bool failWrites = false;
  bool failDeletes = false;

  @override
  Future<void> writeKey(String key, String value) async {
    if (failWrites) throw StateError('locked keyring');
    await super.writeKey(key, value);
  }

  @override
  Future<void> deleteKey(String key) async {
    if (failDeletes) throw StateError('locked keyring');
    await super.deleteKey(key);
  }
}

final _t0 = DateTime(2026, 10, 18, 12);

void main() {
  setUp(() {
    resetConsentStoreQueueForTesting();
    SharedPreferences.setMockInitialValues({});
  });

  group('consent secret and hash (GS-054)', () {
    test('a token carries at least 128 bit of randomness', () {
      final token = newConsentToken();
      // 32 random bytes, base64url without padding: 43 characters.
      expect(base64Url.decode(_pad(token)).length, greaterThanOrEqualTo(16));
      expect(token, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    });

    test('tokens are not repeated', () {
      final tokens = {for (var i = 0; i < 50; i++) newConsentToken()};
      expect(tokens, hasLength(50));
    });

    test('the hash is lowercase hex SHA-256 of the token', () {
      // NIST vector for "abc".
      expect(
        consentTokenHash('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('the payload carries only the hash, never the secret', () {
      const token = 'secret-token-value-1234567890';
      final json = FeedbackPayload(
        rating: 5,
        feedbackText: 'x',
        category: 'general',
        appVersion: '1',
        deviceIdHash: 'abc123def456',
        locale: 'en',
        publishConsent: true,
        withdrawTokenHash: consentTokenHash(token),
      ).toJson();
      expect(json['withdraw_token_hash'], consentTokenHash(token));
      expect(json.values, isNot(contains(token)));
      expect(json['consent_text_version'], kFeedbackConsentTextVersion);
    });

    test('no hash is sent without consent', () {
      final json = FeedbackPayload(
        rating: 5,
        feedbackText: 'x',
        category: 'general',
        appVersion: '1',
        deviceIdHash: 'abc123def456',
        locale: 'en',
        withdrawTokenHash: consentTokenHash('t'),
      ).toJson();
      expect(json.containsKey('withdraw_token_hash'), isFalse);
    });
  });

  group('withdrawal request (GS-068)', () {
    test('calls the RPC with the plain token and confirms on 2xx', () async {
      late http.Request seen;
      final service = _service(
        MockClient((request) async {
          seen = request;
          return http.Response('', 204);
        }),
      );

      expect(
        await service.withdrawPublishConsent('tok-one-long-enough'),
        WithdrawalOutcome.confirmed,
      );
      expect(
        seen.url.toString(),
        'https://x.supabase.co/rest/v1/rpc/withdraw_feedback_publish_consent',
      );
      expect(seen.method, 'POST');
      expect(jsonDecode(seen.body), {'p_token': 'tok-one-long-enough'});
    });

    for (final status in [500, 503, 408, 429, 401, 403, 404, 418]) {
      test('HTTP $status is worth a retry and logged by status', () async {
        final crumbs = <Breadcrumb>[];
        final service = _service(
          MockClient((_) async => http.Response('nope', status)),
          breadcrumbs: crumbs.add,
        );
        expect(
          await service.withdrawPublishConsent('secret-not-in-logs'),
          WithdrawalOutcome.retry,
        );
        expect(crumbs.single.data, {'result': 'retry', 'status': status});
        expect(
          jsonEncode(crumbs.single.toJson()),
          isNot(contains('secret-not-in-logs')),
        );
      });
    }

    for (final status in [400, 409, 410, 422]) {
      test('HTTP $status is final and logged without the secret', () async {
        final crumbs = <Breadcrumb>[];
        final service = _service(
          MockClient((_) async => http.Response('nope', status)),
          breadcrumbs: crumbs.add,
        );
        expect(
          await service.withdrawPublishConsent('secret-not-in-logs'),
          WithdrawalOutcome.rejected,
        );
        expect(crumbs, hasLength(1));
        expect(crumbs.single.data, {'result': 'rejected', 'status': status});
        expect(
          jsonEncode(crumbs.single.toJson()),
          isNot(contains('secret-not-in-logs')),
        );
      });
    }

    test('a network failure is worth a retry, not thrown', () async {
      final service = _service(
        MockClient((_) async {
          throw http.ClientException('offline');
        }),
      );
      expect(
        await service.withdrawPublishConsent('tok'),
        WithdrawalOutcome.retry,
      );
    });

    test('a request that never answers times out as a retry', () async {
      final service = _service(
        MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 20),
      );
      expect(
        await service.withdrawPublishConsent('tok'),
        WithdrawalOutcome.retry,
      );
    });

    test('without a configured backend nothing is sent', () async {
      final server = _Server([204]);
      final service = _service(
        MockClient((_) async {
          server.sent.add('x');
          return http.Response('', 200);
        }),
        url: '',
      );
      expect(service.isConfigured, isFalse);
      expect(
        await service.withdrawPublishConsent('tok'),
        WithdrawalOutcome.retry,
      );
      expect(server.sent, isEmpty);
    });
  });

  group('consent store', () {
    FeedbackConsentStore storeOn(
      _MemoryStorage storage, {
      DateTime Function()? now,
    }) => FeedbackConsentStore(storage: storage, now: now ?? () => _t0);

    test('never drops an active consent secret, however many', () async {
      final storage = _MemoryStorage();
      final store = storeOn(storage);
      for (var i = 0; i < 25; i++) {
        await store.addConsent('token-$i-long-enough-value');
      }
      final active = await store.activeTokens();
      expect(active, hasLength(25));
      expect(active.first, 'token-0-long-enough-value');
      expect(active.last, 'token-24-long-enough-value');
    });

    test('one withdrawal clears everything when the server confirms', () async {
      final storage = _MemoryStorage(
        const ConsentState(
          active: ['token-a-long-enough', 'token-b-long-enough'],
        ),
      );
      final server = _Server([204]);

      expect(await storeOn(storage).withdrawAll(server.service), isTrue);

      expect(server.sent, ['token-a-long-enough', 'token-b-long-enough']);
      expect(storage.state.isEmpty, isTrue);
    });

    test('an offline withdrawal stays pending and is sent later', () async {
      final storage = _MemoryStorage(
        const ConsentState(active: ['token-a-long-enough']),
      );
      final store = storeOn(storage);

      expect(await store.withdrawAll(_Server([500]).service), isFalse);
      expect(storage.state.active, isEmpty);
      expect(storage.state.pending.single.token, 'token-a-long-enough');
      expect(storage.state.pending.single.attempts, 1);
      expect(storage.state.pending.single.failed, isFalse);

      final online = _Server([204]);
      expect(await store.flushPending(online.service), isTrue);
      expect(online.sent, ['token-a-long-enough']);
      expect(storage.state.isEmpty, isTrue);
    });

    test('a rejected withdrawal is final and not sent again', () async {
      final storage = _MemoryStorage(
        const ConsentState(active: ['token-a-long-enough']),
      );
      final store = storeOn(storage);

      // Nothing is left to retry, but the entry stays visible as failed.
      expect(await store.withdrawAll(_Server([422]).service), isTrue);
      expect(storage.state.pending.single.failed, isTrue);

      final later = _Server([204]);
      expect(await store.flushPending(later.service), isTrue);
      expect(later.sent, isEmpty);
      expect(storage.state.pending.single.failed, isTrue);
    });

    test('1000 network errors over 29 days leave the entry pending', () async {
      var now = _t0;
      final storage = _MemoryStorage(
        ConsentState(
          pending: [
            PendingWithdrawal(token: 'token-a-long-enough', since: _t0),
          ],
        ),
      );
      final store = storeOn(storage, now: () => now);
      final offline = _service(
        MockClient((_) async => throw http.ClientException('offline')),
      );
      const step = Duration(days: 29);
      for (var i = 1; i <= 1000; i++) {
        now = _t0.add(step * (i / 1000));
        expect(await store.flushPending(offline), isFalse);
      }
      final entry = storage.state.pending.single;
      expect(entry.failed, isFalse);
      expect(entry.attempts, 1000);
    });

    test('a timeout never makes the entry final before day 30', () async {
      final storage = _MemoryStorage(
        ConsentState(
          pending: [
            PendingWithdrawal(token: 'token-a-long-enough', since: _t0),
          ],
        ),
      );
      final store = storeOn(
        storage,
        now: () => _t0.add(const Duration(days: 29, hours: 23)),
      );
      final hanging = _service(
        MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 10),
      );
      expect(await store.flushPending(hanging), isFalse);
      expect(storage.state.pending.single.failed, isFalse);
    });

    test('a 403 stays pending, for example after a key rotation', () async {
      final storage = _MemoryStorage(
        ConsentState(
          pending: [
            PendingWithdrawal(token: 'token-a-long-enough', since: _t0),
          ],
        ),
      );
      expect(
        await storeOn(storage).flushPending(_Server([403]).service),
        isFalse,
      );
      expect(storage.state.pending.single.failed, isFalse);
    });

    test('a 422 is final at once', () async {
      final storage = _MemoryStorage(
        ConsentState(
          pending: [
            PendingWithdrawal(token: 'token-a-long-enough', since: _t0),
          ],
        ),
      );
      expect(
        await storeOn(storage).flushPending(_Server([422]).service),
        isTrue,
      );
      expect(storage.state.pending.single.failed, isTrue);
      expect(storage.state.pending.single.attempts, 1);
    });

    test('taking the e-mail route deletes failed entries only', () async {
      final storage = _MemoryStorage(
        ConsentState(
          active: const ['token-x-long-enough'],
          pending: [
            PendingWithdrawal(
              token: 'token-f-long-enough',
              since: _t0,
              failed: true,
            ),
            PendingWithdrawal(token: 'token-p-long-enough', since: _t0),
          ],
        ),
      );
      await storeOn(storage).acknowledgeFailed();
      expect(storage.state.active, ['token-x-long-enough']);
      expect(
        [for (final p in storage.state.pending) p.token],
        ['token-p-long-enough'],
      );
    });

    test('failed entries are deleted after 90 days', () async {
      ConsentState withFailed(Duration age) => ConsentState(
        pending: [
          PendingWithdrawal(
            token: 'token-f-long-enough',
            since: _t0.subtract(age),
            failed: true,
          ),
        ],
      );
      final young = _MemoryStorage(
        withFailed(kFailedWithdrawalRetention - const Duration(days: 1)),
      );
      await storeOn(young).flushPending(_Server([204]).service);
      expect(young.state.pending, hasLength(1));

      final old = _MemoryStorage(withFailed(kFailedWithdrawalRetention));
      await storeOn(old).flushPending(_Server([204]).service);
      expect(old.state.isEmpty, isTrue);
    });

    test('at day 30 a retried entry becomes final', () async {
      final storage = _MemoryStorage(
        ConsentState(
          pending: [
            PendingWithdrawal(
              token: 'token-a-long-enough',
              since: _t0.subtract(kMaxWithdrawalAge),
            ),
          ],
        ),
      );
      expect(
        await storeOn(storage).flushPending(_Server([500]).service),
        isTrue,
      );
      expect(storage.state.pending.single.failed, isTrue);
    });

    test('without a backend nothing is sent and the entry stays', () async {
      final storage = _MemoryStorage(
        ConsentState(
          pending: [
            PendingWithdrawal(token: 'token-a-long-enough', since: _t0),
          ],
        ),
      );
      var calls = 0;
      final service = _service(
        MockClient((_) async {
          calls++;
          return http.Response('', 204);
        }),
        url: '',
      );
      expect(await storeOn(storage).flushPending(service), isFalse);
      expect(calls, 0);
      expect(storage.state.pending, hasLength(1));
    });

    test('a crash while withdrawing loses no secret (GS-063)', () async {
      final storage = _MemoryStorage(
        const ConsentState(active: ['token-a-long-enough']),
      )..failWrites = true;
      final store = storeOn(storage);

      await expectLater(
        store.withdrawAll(_Server([204]).service),
        throwsA(isA<StateError>()),
      );
      // Active and pending change in one write: the secret is still there.
      expect(storage.state.active, ['token-a-long-enough']);

      storage.failWrites = false;
      final server = _Server([204]);
      expect(await store.withdrawAll(server.service), isTrue);
      expect(server.sent, ['token-a-long-enough']);
      expect(storage.state.isEmpty, isTrue);
    });

    test(
      'a flush in flight cannot overwrite a withdrawal made meanwhile (GS-064)',
      () async {
        final storage = _MemoryStorage(
          ConsentState(
            active: const ['token-new-long-enough'],
            pending: [
              PendingWithdrawal(token: 'token-old-long-enough', since: _t0),
            ],
          ),
        );
        final store = storeOn(storage);
        final firstAnswer = Completer<http.Response>();
        final sent = <String>[];
        final service = _service(
          MockClient((request) {
            sent.add((jsonDecode(request.body) as Map)['p_token'] as String);
            // Only the first request (the screen-open flush) answers late;
            // the new token fails (offline) and must stay pending.
            if (sent.length == 1) return firstAnswer.future;
            return Future.value(http.Response('', 500));
          }),
        );

        final flush = store.flushPending(service);
        await pumpEventQueue();
        final withdraw = store.withdrawAll(service);
        await pumpEventQueue();
        firstAnswer.complete(http.Response('', 204));

        // Both report the whole state: the new withdrawal is still pending.
        expect(await flush, isFalse);
        expect(await withdraw, isFalse);
        // The old token was in flight, so it was not sent twice.
        expect(sent, ['token-old-long-enough', 'token-new-long-enough']);
        expect(
          [for (final p in storage.state.pending) p.token],
          ['token-new-long-enough'],
        );
        expect(storage.state.active, isEmpty);
      },
    );

    test('changes at the same time are all kept (GS-064)', () async {
      final storage = _MemoryStorage(
        ConsentState(
          active: const ['token-x-long-enough'],
          pending: [
            PendingWithdrawal(token: 'token-p-long-enough', since: _t0),
          ],
        ),
      )..slowWrites = true;
      final store = storeOn(storage);

      await Future.wait([
        store.addConsent('token-a-long-enough'),
        store.flushPending(_Server([204]).service),
        store.addConsent('token-b-long-enough'),
      ]);

      expect(storage.state.active, [
        'token-x-long-enough',
        'token-a-long-enough',
        'token-b-long-enough',
      ]);
      expect(storage.state.pending, isEmpty);
    });

    test('a hanging withdrawal does not block addConsent (DEV-249)', () async {
      final storage = _MemoryStorage(
        ConsentState(
          pending: [
            PendingWithdrawal(token: 'token-old-long-enough', since: _t0),
          ],
        ),
      );
      final store = storeOn(storage);
      final never = Completer<http.Response>();
      final flush = store.flushPending(
        _service(MockClient((_) => never.future)),
      );
      await pumpEventQueue();

      await store
          .addConsent('token-new-long-enough')
          .timeout(const Duration(seconds: 1));
      expect(storage.state.active, ['token-new-long-enough']);

      never.complete(http.Response('', 204));
      expect(await flush, isTrue);
      expect(storage.state.active, ['token-new-long-enough']);
      expect(storage.state.pending, isEmpty);
    });
  });

  group('credential store with prefs fallback', () {
    test('older prefs lists move to the credential store once', () async {
      SharedPreferences.setMockInitialValues({
        kLegacyConsentTokensKey: ['token-a-long-enough'],
        kLegacyPendingWithdrawalsKey: ['token-p-long-enough'],
      });
      final secure = _FakeSecureKeyStore();
      final storage = SecureConsentStateStorage(secure: secure);

      final state = await storage.read();
      expect(state.active, ['token-a-long-enough']);
      expect([for (final p in state.pending) p.token], ['token-p-long-enough']);
      expect(secure.values[kSecureConsentStateKey], isNotNull);

      // Only the non-secret mirror stays: hashes, never a secret.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {kConsentMirrorKey});
      final mirror = prefs.getString(kConsentMirrorKey)!;
      expect(mirror, isNot(contains('token-a-long-enough')));
      expect(mirror, isNot(contains('token-p-long-enough')));
      expect(mirror, contains(consentTokenHash('token-p-long-enough')));
    });

    test('without a credential store the state is kept in the prefs', () async {
      final secure = _FakeSecureKeyStore()..unavailable = true;
      final storage = SecureConsentStateStorage(secure: secure);

      await storage.write(const ConsentState(active: ['token-a-long-enough']));
      expect((await storage.read()).active, ['token-a-long-enough']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kConsentStateKey), isNotNull);

      // Once the credential store works, the state moves there.
      secure.unavailable = false;
      expect((await storage.read()).active, ['token-a-long-enough']);
      expect(prefs.getString(kConsentStateKey), isNull);
      expect(
        ConsentState.decode(secure.values[kSecureConsentStateKey]).active,
        ['token-a-long-enough'],
      );
    });
  });

  test('on the prefs fallback a deleted secret leaves no copy', () async {
    SharedPreferences.setMockInitialValues({
      kLegacyPendingWithdrawalsKey: ['token-old-long-enough'],
    });
    final secure = _FakeSecureKeyStore()..unavailable = true;
    final store = FeedbackConsentStore(
      storage: SecureConsentStateStorage(secure: secure),
      now: () => _t0,
    );

    // Rejected, then acknowledged via the e-mail route.
    await store.flushPending(_Server([422]).service);
    await store.acknowledgeFailed();

    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      expect(
        '${prefs.get(key)}',
        isNot(contains('token-old-long-enough')),
        reason: 'stray copy in $key',
      );
    }
    expect(secure.values, isEmpty);
  });

  group('a stale secure copy never wins (GS-087)', () {
    late _FlakyWriteSecureKeyStore secure;
    late SecureConsentStateStorage storage;
    FeedbackConsentStore storeNow() =>
        FeedbackConsentStore(storage: storage, now: () => _t0);

    setUp(() {
      secure = _FlakyWriteSecureKeyStore();
      // Pinned to _t0 like the store, so the mirror's 90-day limit (GS-141)
      // never depends on the day the suite runs.
      storage = SecureConsentStateStorage(
        secure: secure,
        clock: () => _t0.millisecondsSinceEpoch,
      );
    });

    // Reads still work, writes and deletes fail, so the old copy stays in
    // the credential store next to the newer fallback copy.
    void breakWrites() => secure
      ..failWrites = true
      ..failDeletes = true;

    test('a confirmed withdrawal stays withdrawn', () async {
      await storeNow().addConsent('token-a-long-enough');
      final stale = secure.values[kSecureConsentStateKey];

      breakWrites();
      expect(await storeNow().withdrawAll(_Server([204]).service), isTrue);
      expect(secure.values[kSecureConsentStateKey], stale);
      expect((await storeNow().state()).isEmpty, isTrue);

      // Working again, with a fresh storage as after an app restart.
      secure
        ..failWrites = false
        ..failDeletes = false;
      storage = SecureConsentStateStorage(secure: secure);
      expect((await storeNow().state()).isEmpty, isTrue);
      expect(secure.values[kSecureConsentStateKey], isNot(stale));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kConsentStateKey), isNull);
    });

    test('a purged failed entry stays purged', () async {
      await storage.write(
        ConsentState(
          pending: [
            PendingWithdrawal(
              token: 'token-f-long-enough',
              since: _t0,
              failed: true,
            ),
          ],
        ),
      );

      breakWrites();
      await storeNow().acknowledgeFailed();
      expect((await storeNow().state()).isEmpty, isTrue);

      secure
        ..failWrites = false
        ..failDeletes = false;
      storage = SecureConsentStateStorage(secure: secure);
      expect((await storeNow().state()).isEmpty, isTrue);
    });

    test('on a revision tie the credential store wins, once', () async {
      secure.values[kSecureConsentStateKey] = const ConsentState(
        active: ['token-s-long-enough'],
      ).encode();
      SharedPreferences.setMockInitialValues({
        kConsentStateKey: const ConsentState(
          active: ['token-p-long-enough'],
        ).encode(),
      });

      expect((await storeNow().state()).active, ['token-s-long-enough']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kConsentStateKey), isNull);
      final moved = ConsentState.decode(secure.values[kSecureConsentStateKey]);
      expect(moved.revision, greaterThan(0));
    });

    test('a clock jump backwards cannot make a stale copy win', () async {
      var clock = 5000000;
      SecureConsentStateStorage at() =>
          SecureConsentStateStorage(secure: secure, clock: () => clock);
      await at().write(const ConsentState(active: ['token-a-long-enough']));

      // Restart with the clock far behind, while the credential store
      // cannot write or delete.
      clock = 10;
      breakWrites();
      await at().write(const ConsentState());

      secure
        ..failWrites = false
        ..failDeletes = false;
      expect((await at().read()).isEmpty, isTrue);
    });

    test(
      'an unreadable secure copy from before a clock jump never wins',
      () async {
        var clock = 5000000;
        SecureConsentStateStorage at() =>
            SecureConsentStateStorage(secure: secure, clock: () => clock);
        await at().write(const ConsentState(active: ['token-a-long-enough']));

        // Restart with the clock far behind and a credential store that cannot
        // even be read, so its higher revision is unknown.
        clock = 10;
        final blind = _FakeSecureKeyStore()..unavailable = true;
        await SecureConsentStateStorage(
          secure: blind,
          clock: () => clock,
        ).write(const ConsentState());

        // Readable again, still holding the stale copy with the higher revision.
        expect((await at().read()).isEmpty, isTrue);
        expect(
          ConsentState.decode(secure.values[kSecureConsentStateKey]).isEmpty,
          isTrue,
          reason: 'the stale secure copy is overwritten',
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(kConsentStateKey), isNull);
      },
    );

    test('revisions are validated and clamped, never wrapped', () async {
      String withRevision(Object? r) => jsonEncode({
        'active': ['token-a-long-enough'],
        'pending': <Object>[],
        'r': r,
      });
      for (final bad in [-5, null, 'x', kMaxConsentRevision + 1, 1.5]) {
        expect(ConsentState.decode(withRevision(bad)).revision, 0);
      }
      expect(ConsentState.decode(withRevision(42)).revision, 42);

      secure.values[kSecureConsentStateKey] = const ConsentState(
        active: ['token-a-long-enough'],
      ).encode(revision: kMaxConsentRevision);
      final atMax = SecureConsentStateStorage(
        secure: secure,
        clock: () => kMaxConsentRevision + 99,
      );
      await atMax.write(const ConsentState());
      final stored = ConsentState.decode(secure.values[kSecureConsentStateKey]);
      expect(stored.revision, kMaxConsentRevision);
      expect(stored.isEmpty, isTrue);
    });

    test('a fallback copy the secure write replaced stays stale', () async {
      // GS-123: back in the credential store, but deleting the fallback
      // copy from the prefs keeps failing.
      final inner = await SharedPreferences.getInstance();
      final prefs = _NoRemovePrefs(inner);
      await inner.setString(
        kConsentStateKey,
        const ConsentState(
          active: ['token-a-long-enough'],
        ).encode(revision: 5000, supersedesSecure: true),
      );
      SecureConsentStateStorage at() =>
          SecureConsentStateStorage(secure: secure, prefs: () async => prefs);

      expect((await at().read()).active, ['token-a-long-enough']);
      await FeedbackConsentStore(
        storage: at(),
        now: () => _t0,
      ).withdrawAll(_Server([204]).service);
      expect(inner.getString(kConsentStateKey), isNotNull);

      expect((await at().read()).isEmpty, isTrue);
    });

    test('pending withdrawals stay reachable by hash when the credential '
        'store turns unreadable', () async {
      await storeNow().addConsent('token-a-long-enough');
      await storeNow().withdrawAll(_Server([500]).service);

      secure.unavailable = true;
      final state = await storeNow().state();
      expect(state.isEmpty, isTrue);
      final locked = state.locked.single;
      expect(locked.hash, consentTokenHash('token-a-long-enough'));
      expect(locked.withdrawn, isTrue);
      expect(locked.since, _t0);

      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        expect('${prefs.get(key)}', isNot(contains('token-a-long-enough')));
      }
    });

    test('the mirror keeps an active consent and forgets a withdrawal '
        'after 90 days (GS-141, BIZ-114)', () async {
      var now = _t0;
      final at = SecureConsentStateStorage(
        secure: secure,
        clock: () => now.millisecondsSinceEpoch,
      );
      FeedbackConsentStore store() =>
          FeedbackConsentStore(storage: at, now: () => now);
      await store().addConsent('token-a-long-enough');
      await store().withdrawAll(_Server([500]).service);
      await store().addConsent('token-b-long-enough');

      secure.unavailable = true;
      now = _t0.add(const Duration(days: 89));
      expect(
        (await store().state()).locked.map((r) => r.hash),
        unorderedEquals([
          consentTokenHash('token-a-long-enough'),
          consentTokenHash('token-b-long-enough'),
        ]),
      );

      // The withdrawal ages from day 0; the active consent stays as long
      // as it is active.
      now = _t0.add(const Duration(days: 91));
      final locked = (await store().state()).locked;
      expect(locked.map((r) => r.hash), [
        consentTokenHash('token-b-long-enough'),
      ]);
      expect(locked.single.withdrawn, isFalse);
      now = _t0.add(const Duration(days: 400));
      expect((await store().state()).locked.map((r) => r.hash), [
        consentTokenHash('token-b-long-enough'),
      ]);
    });

    test('older mirror entries: a withdrawal without a time counts as '
        'expired, an active consent stays (GS-141)', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        kConsentMirrorKey,
        jsonEncode([
          {'h': 'active-hash'},
          {'h': 'withdrawn-no-time', 'w': true},
          {'h': 'failed-no-time', 'w': true, 'f': true},
          {
            'h': 'withdrawn-recent',
            'w': true,
            's': _t0.subtract(const Duration(days: 10)).millisecondsSinceEpoch,
          },
          {
            'h': 'failed-old',
            'w': true,
            'f': true,
            's': _t0.subtract(const Duration(days: 91)).millisecondsSinceEpoch,
          },
        ]),
      );
      secure.unavailable = true;
      expect(
        (await storeNow().state()).locked.map((r) => r.hash),
        unorderedEquals(['active-hash', 'withdrawn-recent']),
      );
    });

    test('a confirmed withdrawal leaves no mirror behind', () async {
      await storeNow().addConsent('token-a-long-enough');
      await storeNow().withdrawAll(_Server([204]).service);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kConsentMirrorKey), isNull);
    });

    test('a fallback write deletes the secure copy when it can', () async {
      await storage.write(const ConsentState(active: ['token-a-long-enough']));
      secure.failWrites = true;
      await storage.write(const ConsentState());
      expect(secure.values, isEmpty);
    });
  });

  group('retry while pending', () {
    ConsentState pendingOne() => ConsentState(
      pending: [PendingWithdrawal(token: 'token-p-long-enough', since: _t0)],
    );

    test('sends at start and retries with backoff until confirmed', () {
      fakeAsync((async) {
        final storage = _MemoryStorage(pendingOne());
        final server = _Server([500, 500, 204]);
        final retry = FeedbackWithdrawalRetry(
          store: FeedbackConsentStore(storage: storage, now: () => _t0),
        );

        unawaited(retry.kick(server.service));
        async.flushMicrotasks();
        expect(server.sent, hasLength(1), reason: 'one attempt at start');
        expect(retry.isScheduled, isTrue);

        async.elapse(const Duration(seconds: 14));
        expect(server.sent, hasLength(1));
        async.elapse(const Duration(seconds: 1));
        expect(server.sent, hasLength(2), reason: 'first retry after 15 s');

        // The second pause doubles to 30 s.
        async.elapse(const Duration(seconds: 29));
        expect(server.sent, hasLength(2));
        async.elapse(const Duration(seconds: 1));
        expect(server.sent, hasLength(3));

        expect(retry.isScheduled, isFalse);
        expect(storage.state.isEmpty, isTrue);
      });
    });

    test('the pause never exceeds the cap', () {
      fakeAsync((async) {
        final server = _Server([500]);
        final retry = FeedbackWithdrawalRetry(
          store: FeedbackConsentStore(
            storage: _MemoryStorage(pendingOne()),
            now: () => _t0,
          ),
        );
        unawaited(retry.kick(server.service));
        // 15 s doubling: 15 + 30 + ... + 1920 s = 3825 s for 8 retries,
        // then one-hour steps.
        async.elapse(const Duration(seconds: 3825));
        expect(server.sent, hasLength(9));
        async.elapse(const Duration(minutes: 59));
        expect(server.sent, hasLength(9));
        async.elapse(const Duration(minutes: 1));
        expect(server.sent, hasLength(10));
        retry.cancel();
      });
    });

    test('a final rejection stops the retries', () {
      fakeAsync((async) {
        final server = _Server([422]);
        final retry = FeedbackWithdrawalRetry(
          store: FeedbackConsentStore(
            storage: _MemoryStorage(pendingOne()),
            now: () => _t0,
          ),
        );
        unawaited(retry.kick(server.service));
        async.flushMicrotasks();
        expect(retry.isScheduled, isFalse);
        async.elapse(const Duration(hours: 1));
        expect(server.sent, hasLength(1));
      });
    });

    test('a storage failure keeps the loop alive', () {
      fakeAsync((async) {
        final storage = _MemoryStorage(pendingOne())..failReads = true;
        final server = _Server([204]);
        final retry = FeedbackWithdrawalRetry(
          store: FeedbackConsentStore(storage: storage, now: () => _t0),
        );
        unawaited(retry.kick(server.service));
        async.flushMicrotasks();
        expect(retry.isScheduled, isTrue);

        storage.failReads = false;
        async.elapse(const Duration(seconds: 15));
        expect(server.sent, ['token-p-long-enough']);
        expect(retry.isScheduled, isFalse);
      });
    });

    test('nothing pending schedules nothing', () {
      fakeAsync((async) {
        final retry = FeedbackWithdrawalRetry(
          store: FeedbackConsentStore(storage: _MemoryStorage()),
        );
        unawaited(retry.kick(_Server([204]).service));
        async.flushMicrotasks();
        expect(retry.isScheduled, isFalse);
      });
    });

    test('without a backend nothing is retried', () {
      fakeAsync((async) {
        final storage = _MemoryStorage(pendingOne());
        final retry = FeedbackWithdrawalRetry(
          store: FeedbackConsentStore(storage: storage),
        );
        unawaited(
          retry.kick(
            _service(MockClient((_) async => http.Response('', 204)), url: ''),
          ),
        );
        async.flushMicrotasks();
        retry.retryLater();
        expect(retry.isScheduled, isFalse);
        expect(storage.state.pending, hasLength(1));
      });
    });

    test('a withdrawal left pending on the screen is retried later', () {
      fakeAsync((async) {
        final storage = _MemoryStorage();
        final store = FeedbackConsentStore(storage: storage, now: () => _t0);
        final server = _Server([204]);
        final retry = FeedbackWithdrawalRetry(store: store);
        unawaited(retry.kick(server.service));
        async.flushMicrotasks();
        expect(retry.isScheduled, isFalse);

        unawaited(store.addConsent('token-s-long-enough'));
        unawaited(store.withdrawAll(_Server([500]).service));
        async.flushMicrotasks();
        retry.retryLater();
        expect(retry.isScheduled, isTrue);

        async.elapse(const Duration(seconds: 15));
        expect(server.sent, ['token-s-long-enough']);
        expect(storage.state.isEmpty, isTrue);
      });
    });
  });

  test(
    'the withdrawal mail goes to the contact with encoded subject and body',
    () {
      final uri = consentWithdrawalMailUri(
        subject: 'Widerruf der Zustimmung',
        body: 'Feedback vom 2026-10-18\nBitte zurückziehen.',
      );
      expect(uri.scheme, 'mailto');
      expect(uri.path, kConsentWithdrawalContact);
      expect(uri.query, contains('subject=Widerruf%20der%20Zustimmung'));
      expect(uri.query, contains('%0A'));
    },
  );
}

/// Restores base64 padding so [base64Url] can decode an unpadded token.
String _pad(String token) =>
    token.padRight(token.length + (4 - token.length % 4) % 4, '=');
