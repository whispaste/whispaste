/// Device-held consent secrets and pending withdrawals for the website quote
/// consent (BIZ-63, GS-054, GS-055).
///
/// The secret of each consented submission stays on the device, in the
/// platform credential store where available. A withdrawal is kept locally
/// until the server confirmed it, so an offline withdrawal is retried (at app
/// start, on the feedback screen and with backoff while anything is pending)
/// and is never lost. A final rejection, or the 30-day limit, ends the
/// retries and the screen points to the e-mail route instead (GS-068).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/secure_key_store.dart';
import '../core/logging/app_logger.dart';
import 'feedback_submission_service.dart';

final _log = AppLogger('FeedbackConsentStore');

/// Prefs key of the consent state when the credential store is unavailable.
const kConsentStateKey = 'feedback_publish_consent_state';

/// Older prefs keys (plain secret lists). Moved once, then deleted.
const kLegacyConsentTokensKey = 'feedback_publish_consent_tokens';
const kLegacyPendingWithdrawalsKey = 'feedback_pending_withdrawals';

/// Prefs key of the non-secret mirror of what the credential store holds
/// (GS-124): one hash per consent or withdrawal, never the secret.
const kConsentMirrorKey = 'feedback_publish_consent_refs';

/// Credential store key of the consent state.
const kSecureConsentStateKey = 'wp_feedback_consent_state';

/// A withdrawal stops retrying this long after the user withdrew. The
/// number of attempts is no stopping rule: a laptop that is offline for a
/// day must still deliver it.
const kMaxWithdrawalAge = Duration(days: 30);

/// A failed withdrawal and its secret are deleted this long after the user
/// withdrew, or as soon as the user takes the e-mail route.
const kFailedWithdrawalRetention = Duration(days: 90);

/// The contact address that receives consent withdrawal requests by e-mail.
const kConsentWithdrawalContact = 'contact@whispaste.de';

typedef PrefsLoader = Future<SharedPreferences> Function();

/// One withdrawal the server has not confirmed yet.
final class PendingWithdrawal {
  const PendingWithdrawal({
    required this.token,
    required this.since,
    this.attempts = 0,
    this.failed = false,
  });

  factory PendingWithdrawal.fromJson(Map<String, dynamic> json) =>
      PendingWithdrawal(
        token: json['t'] as String,
        since: DateTime.fromMillisecondsSinceEpoch(json['s'] as int),
        attempts: json['a'] as int? ?? 0,
        failed: json['f'] as bool? ?? false,
      );

  final String token;

  /// When the user withdrew.
  final DateTime since;
  final int attempts;

  /// Final: rejected by the server or older than [kMaxWithdrawalAge]. Not
  /// retried; the screen shows the e-mail route.
  final bool failed;

  PendingWithdrawal copyWith({int? attempts, bool? failed}) =>
      PendingWithdrawal(
        token: token,
        since: since,
        attempts: attempts ?? this.attempts,
        failed: failed ?? this.failed,
      );

  Map<String, dynamic> toJson() => {
    't': token,
    's': since.millisecondsSinceEpoch,
    'a': attempts,
    'f': failed,
  };
}

/// Non-secret trace of a consent or withdrawal kept in the credential store:
/// enough for a withdrawal by e-mail while that store cannot be read
/// (GS-124).
final class ConsentReference {
  const ConsentReference({
    required this.hash,
    this.since,
    this.failed = false,
    this.withdrawn = false,
  });

  factory ConsentReference.fromJson(Map<String, dynamic> json) =>
      ConsentReference(
        hash: json['h'] as String,
        since: json['s'] is int
            ? DateTime.fromMillisecondsSinceEpoch(json['s'] as int)
            : null,
        failed: json['f'] == true,
        withdrawn: json['w'] == true,
      );

  /// [consentTokenHash] of the secret, as stored on the server.
  final String hash;

  /// When the user withdrew; null for a consent not withdrawn.
  final DateTime? since;
  final bool failed;
  final bool withdrawn;

  Map<String, dynamic> toJson() => {
    'h': hash,
    if (since != null) 's': since!.millisecondsSinceEpoch,
    if (failed) 'f': true,
    if (withdrawn) 'w': true,
  };
}

/// Everything the device keeps about website-quote consents.
final class ConsentState {
  const ConsentState({
    this.active = const [],
    this.pending = const [],
    this.revision = 0,
    this.supersedesSecure = false,
    this.replacesFallback = 0,
    this.locked = const [],
  });

  factory ConsentState.decode(String? raw) {
    if (raw == null || raw.isEmpty) return const ConsentState();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return ConsentState(
      active: [
        for (final t in json['active'] as List? ?? const []) t as String,
      ],
      pending: [
        for (final p in json['pending'] as List? ?? const [])
          PendingWithdrawal.fromJson(p as Map<String, dynamic>),
      ],
      revision: _validRevision(json['r']),
      supersedesSecure: json['f'] == true,
      replacesFallback: _validRevision(json['sf']),
    );
  }

  /// Secrets of consents that were not withdrawn.
  final List<String> active;
  final List<PendingWithdrawal> pending;

  /// Stamped by [SecureConsentStateStorage] on every write, so of two stored
  /// copies the newer one wins. 0 when never stored.
  final int revision;

  /// Set on a copy in the prefs fallback. It is only written when the
  /// credential store could not be written, and deleted after the next
  /// successful write there, so while it exists it is newer than any secure
  /// copy, whatever the revisions say (GS-109: a secure copy stamped before
  /// the clock went back, while the credential store could not be read).
  final bool supersedesSecure;

  /// Set on a copy in the credential store: the revision of the newest
  /// fallback copy it was written over. A fallback copy at or below it is
  /// stale, for example when deleting it from the prefs failed (GS-123).
  final int replacesFallback;

  /// Consents and withdrawals that only the unreadable credential store
  /// holds, known from the prefs mirror. Not stored; the screen offers the
  /// e-mail route for them (GS-124).
  final List<ConsentReference> locked;

  /// The non-secret mirror of this state.
  List<ConsentReference> get references => [
    for (final t in active) ConsentReference(hash: consentTokenHash(t)),
    for (final p in pending)
      ConsentReference(
        hash: consentTokenHash(p.token),
        since: p.since,
        failed: p.failed,
        withdrawn: true,
      ),
  ];

  ConsentState withLocked(List<ConsentReference> locked) => ConsentState(
    active: active,
    pending: pending,
    revision: revision,
    supersedesSecure: supersedesSecure,
    replacesFallback: replacesFallback,
    locked: locked,
  );

  bool get isEmpty => active.isEmpty && pending.isEmpty;

  String encode({
    int revision = 0,
    bool supersedesSecure = false,
    int replacesFallback = 0,
  }) => jsonEncode({
    'active': active,
    'pending': [for (final p in pending) p.toJson()],
    'r': revision,
    if (supersedesSecure) 'f': true,
    if (replacesFallback > 0) 'sf': replacesFallback,
  });

  /// Union with the older plain prefs lists, which carry no revision. Never
  /// used between the credential store and the prefs fallback: there a
  /// union would bring back a withdrawn consent or a purged entry (GS-087).
  /// A secret pending in either copy is not active; of two pending copies
  /// the more advanced one wins.
  ConsentState merge(ConsentState other) {
    final pendingByToken = <String, PendingWithdrawal>{};
    for (final p in [...pending, ...other.pending]) {
      final known = pendingByToken[p.token];
      if (known == null ||
          (p.failed && !known.failed) ||
          p.attempts > known.attempts) {
        pendingByToken[p.token] = p;
      }
    }
    return ConsentState(
      active: {
        for (final t in [...active, ...other.active])
          if (!pendingByToken.containsKey(t)) t,
      }.toList(),
      pending: pendingByToken.values.toList(),
    );
  }
}

/// Highest accepted revision, far above any wall clock in milliseconds and
/// safe as a JSON number. Revisions never wrap; they stop here.
const kMaxConsentRevision = 1 << 52;

/// A negative, missing or absurd revision counts as 0, so a damaged copy
/// never beats a sound one.
int _validRevision(Object? raw) =>
    raw is int && raw > 0 && raw <= kMaxConsentRevision ? raw : 0;

/// Where the consent state lives.
abstract interface class ConsentStateStorage {
  Future<ConsentState> read();
  Future<void> write(ConsentState state);
}

/// Keeps the state in the platform credential store (Keychain, Credential
/// Manager, libsecret). When that fails, for example without libsecret or
/// with a locked keyring on Linux, it falls back to the prefs and logs it
/// once. Accepted low risk: the state holds only withdrawal secrets, never
/// feedback content, and a secret can do nothing but withdraw the quote
/// consent it belongs to. State found in the prefs (fallback or the older plain lists) is
/// moved to the credential store as soon as it works, then deleted there.
final class SecureConsentStateStorage implements ConsentStateStorage {
  SecureConsentStateStorage({
    SecureKeyStore? secure,
    PrefsLoader? prefs,
    int Function()? clock,
  }) : _secure = secure ?? SecureKeyStore(),
       _prefs = prefs ?? SharedPreferences.getInstance,
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final SecureKeyStore _secure;
  final PrefsLoader _prefs;

  /// Wall clock in milliseconds.
  final int Function() _clock;
  bool _loggedFallback = false;

  void _logFallback(Object error) {
    if (_loggedFallback) return;
    _loggedFallback = true;
    _log.warning(
      'Credential store unavailable (${error.runtimeType}); keeping consent '
      'secrets in the app preferences',
    );
  }

  int _revision = 0;

  /// Above the clock and every revision read from either store, so it stays
  /// increasing when the clock goes back (GS-108). Clamped, never wrapped.
  int _nextRevision() {
    final now = _clock().clamp(0, kMaxConsentRevision);
    final base = now > _revision ? now : _revision;
    return _revision = base < kMaxConsentRevision ? base + 1 : base;
  }

  ConsentState? _legacyFromPrefs(SharedPreferences prefs) {
    final legacyActive = prefs.getStringList(kLegacyConsentTokensKey);
    final legacyPending = prefs.getStringList(kLegacyPendingWithdrawalsKey);
    if (legacyActive == null && legacyPending == null) return null;
    final now = DateTime.now();
    return ConsentState(
      active: legacyActive ?? const [],
      pending: [
        for (final t in legacyPending ?? const <String>[])
          PendingWithdrawal(token: t, since: now),
      ],
    );
  }

  ConsentState? _decodeOrNull(String? raw) =>
      raw == null ? null : ConsentState.decode(raw);

  Future<void> _clearPrefs(SharedPreferences prefs) async {
    await prefs.remove(kConsentStateKey);
    await prefs.remove(kLegacyConsentTokensKey);
    await prefs.remove(kLegacyPendingWithdrawalsKey);
  }

  /// Revision of the newest fallback copy seen; every secure write records
  /// it, so that copy can never win over the secure one again (GS-123).
  int _fallbackSeen = 0;

  ConsentState _seen(ConsentState state) {
    if (state.revision > _revision) _revision = state.revision;
    if (state.supersedesSecure && state.revision > _fallbackSeen) {
      _fallbackSeen = state.revision;
    }
    return state;
  }

  /// Writes [state] to the credential store and mirrors its hashes into the
  /// prefs. Throws when the credential store fails.
  Future<void> _writeSecure(SharedPreferences prefs, ConsentState state) async {
    await _secure.writeKey(
      kSecureConsentStateKey,
      state.encode(revision: _nextRevision(), replacesFallback: _fallbackSeen),
    );
    await _writeMirror(prefs, state.references);
  }

  Future<void> _writeMirror(
    SharedPreferences prefs,
    List<ConsentReference> refs,
  ) async {
    try {
      final now = DateTime.fromMillisecondsSinceEpoch(_clock());
      final kept = [
        for (final r in refs)
          if (!_mirrorExpired(r, now)) r,
      ];
      if (kept.isEmpty) {
        await prefs.remove(kConsentMirrorKey);
      } else {
        await prefs.setString(
          kConsentMirrorKey,
          jsonEncode([for (final r in kept) r.toJson()]),
        );
      }
    } on Object catch (e) {
      _log.warning('Could not update the consent mirror: ${e.runtimeType}');
    }
  }

  /// The mirror keeps the hash of a withdrawn or failed consent for at most
  /// [kFailedWithdrawalRetention] after the withdrawal, the period after
  /// which the server has deleted the entry as well (GS-141). One without a
  /// withdrawal time, from an older build, counts as expired. An active
  /// consent stays for as long as it is active: without its hash the locked
  /// notice and the prepared e-mail could not name it (BIZ-114).
  bool _mirrorExpired(ConsentReference r, DateTime now) {
    if (!r.withdrawn && !r.failed) return false;
    final since = r.since;
    return since == null || now.difference(since) > kFailedWithdrawalRetention;
  }

  List<ConsentReference> _readMirror(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(kConsentMirrorKey);
      if (raw == null) return const [];
      final now = DateTime.fromMillisecondsSinceEpoch(_clock());
      return [
        for (final r in jsonDecode(raw) as List)
          ConsentReference.fromJson(r as Map<String, dynamic>),
      ].where((r) => !_mirrorExpired(r, now)).toList();
    } on Object {
      return const [];
    }
  }

  /// A failed clean-up of the prefs must not fail the write that succeeded
  /// in the credential store; the revisions keep the stale copy out.
  Future<void> _clearPrefsSafely(SharedPreferences prefs) async {
    try {
      await _clearPrefs(prefs);
    } on Object catch (e) {
      _log.warning('Could not clear consent prefs: ${e.runtimeType}');
    }
  }

  @override
  Future<ConsentState> read() async {
    final prefs = await _prefs();
    final fromPrefs = _decodeOrNull(prefs.getString(kConsentStateKey));
    final legacy = _legacyFromPrefs(prefs);
    ConsentState withLegacy(ConsentState state) =>
        legacy == null ? state : state.merge(legacy);

    final ConsentState? fromSecure;
    try {
      fromSecure = _decodeOrNull(await _secure.readKey(kSecureConsentStateKey));
    } on Object catch (e) {
      _logFallback(e);
      final state = _seen(withLegacy(fromPrefs ?? const ConsentState()));
      final known = {for (final r in state.references) r.hash};
      return state.withLocked([
        for (final r in _readMirror(prefs))
          if (!known.contains(r.hash)) r,
      ]);
    }
    // The newer copy wins. A secure copy can be stale: a fallback write
    // could not delete it while the credential store was failing. A fallback
    // copy the secure copy does not know of wins whatever the revisions say,
    // as the revision of a secure copy that could not be read is unknown
    // (GS-109). One the secure copy was written over is stale, as when its
    // deletion from the prefs failed (GS-123). On a tie the credential store
    // wins, as the primary store. A tie only happens with two unrevisioned
    // copies (revision 0), which no released build writes; the move below
    // then stamps a revision, so it happens once.
    bool prefsWin(ConsentState prefs, ConsentState secure) =>
        prefs.supersedesSecure
        ? secure.replacesFallback < prefs.revision
        : prefs.revision > secure.revision;
    final newest =
        fromPrefs != null &&
            (fromSecure == null || prefsWin(fromPrefs, fromSecure))
        ? fromPrefs
        : fromSecure ?? const ConsentState();
    if (fromPrefs != null) _seen(fromPrefs);
    if (fromSecure != null) _seen(fromSecure);
    if (fromPrefs == null && legacy == null) return newest;

    // One-off move: credential store first, then delete from the prefs.
    final merged = withLegacy(newest);
    try {
      await _writeSecure(prefs, merged);
    } on Object catch (e) {
      _logFallback(e);
      return merged;
    }
    await _clearPrefsSafely(prefs);
    return merged;
  }

  @override
  Future<void> write(ConsentState state) async {
    // Read first: the next revision must beat both stored copies, also when
    // this storage has not read them yet.
    await read();
    final prefs = await _prefs();
    try {
      await _writeSecure(prefs, state);
    } on Object catch (e) {
      _logFallback(e);
      // The legacy keys were merged into this state, so they go too: left
      // behind they would bring a deleted secret back on the next read. An
      // empty state is stored as well, as its newer revision is what beats
      // a stale secure copy.
      await _clearPrefs(prefs);
      final revision = _fallbackSeen = _nextRevision();
      await prefs.setString(
        kConsentStateKey,
        state.encode(revision: revision, supersedesSecure: true),
      );
      try {
        await _secure.deleteKey(kSecureConsentStateKey);
        // Nothing left in the credential store to mirror.
        await _writeMirror(prefs, const []);
      } on Object catch (e) {
        // Still failing; the marker settles it once it works again. The
        // mirror keeps describing the stale secure copy meanwhile.
        _log.debug('Stale secure consent copy kept: ${e.runtimeType}');
      }
      return;
    }
    await _clearPrefsSafely(prefs);
  }
}

/// Tail of the queue that serializes every change of the consent state. It
/// is shared by all store instances, so a flush cannot write back a stale
/// state over a withdrawal made meanwhile (GS-064). Only reads and writes of
/// the state run in it, never a network call (DEV-249).
///
/// Null while idle: a completed future notifies late listeners in the zone it
/// completed in, so keeping one would tie later callers to a zone that may be
/// gone.
Future<void>? _tail;

/// Secrets with a withdrawal request on the way, so two overlapping flushes
/// do not send the same one twice.
final _inFlight = <String>{};

Future<T> _serialized<T>(Future<T> Function() action) {
  final previous = _tail;
  final result = previous == null ? action() : previous.then((_) => action());
  final tail = result.then<void>((_) {}, onError: (Object _) {});
  _tail = tail;
  unawaited(
    tail.whenComplete(() {
      if (identical(_tail, tail)) _tail = null;
    }),
  );
  return result;
}

/// Forgets queued work and in-flight markers left by an earlier test.
@visibleForTesting
void resetConsentStoreQueueForTesting() {
  _tail = null;
  _inFlight.clear();
}

final class FeedbackConsentStore {
  FeedbackConsentStore({ConsentStateStorage? storage, DateTime Function()? now})
    : _storage = storage ?? SecureConsentStateStorage(),
      _now = now ?? DateTime.now;

  final ConsentStateStorage _storage;
  final DateTime Function() _now;

  Future<ConsentState> state() => _storage.read();

  /// Secrets of active consents.
  Future<List<String>> activeTokens() async => (await state()).active;

  /// Keeps the secret of a consent that was just accepted by the server. No
  /// cap: dropping an active secret would make that consent unwithdrawable on
  /// the device (DEV-213). Never waits on the network (DEV-249).
  Future<void> addConsent(String token) => _serialized(() async {
    final current = await _storage.read();
    await _storage.write(
      ConsentState(
        active: [...current.active, token],
        pending: current.pending,
      ),
    );
  });

  /// One click: moves all active secrets to the pending list in one write,
  /// then tries to send them. Returns true when nothing is left to retry.
  Future<bool> withdrawAll(FeedbackSubmissionService service) async {
    await _serialized(() async {
      final current = await _storage.read();
      if (current.active.isEmpty) return;
      final since = _now();
      await _storage.write(
        ConsentState(
          pending: [
            ...current.pending,
            for (final t in current.active)
              PendingWithdrawal(token: t, since: since),
          ],
        ),
      );
    });
    return flushPending(service);
  }

  /// Deletes failed withdrawals and their secrets: the user took the e-mail
  /// route, so the device has nothing left to do with them.
  Future<void> acknowledgeFailed() => _serialized(() async {
    final current = await _storage.read();
    if (!current.pending.any((p) => p.failed)) return;
    await _storage.write(
      ConsentState(
        active: current.active,
        pending: [
          for (final p in current.pending)
            if (!p.failed) p,
        ],
      ),
    );
  });

  /// Deletes failed withdrawals older than [kFailedWithdrawalRetention].
  Future<void> _purgeExpired() => _serialized(() async {
    final current = await _storage.read();
    final now = _now();
    bool expired(PendingWithdrawal p) =>
        p.failed && now.difference(p.since) >= kFailedWithdrawalRetention;
    if (!current.pending.any(expired)) return;
    await _storage.write(
      ConsentState(
        active: current.active,
        pending: [
          for (final p in current.pending)
            if (!expired(p)) p,
        ],
      ),
    );
  });

  /// Sends every withdrawal that is still worth a try once. The requests run
  /// outside the queue; their results are applied to the state as it is then.
  /// Returns true when nothing is left to retry.
  Future<bool> flushPending(FeedbackSubmissionService service) async {
    await _purgeExpired();
    if (!service.isConfigured) {
      return !(await state()).pending.any((p) => !p.failed);
    }
    final toSend = await _serialized(() async {
      final current = await _storage.read();
      final due = [
        for (final p in current.pending)
          if (!p.failed && !_inFlight.contains(p.token)) p.token,
      ];
      _inFlight.addAll(due);
      return due;
    });

    final outcomes = <String, WithdrawalOutcome>{};
    try {
      for (final token in toSend) {
        outcomes[token] = await service.withdrawPublishConsent(token);
      }
    } finally {
      _inFlight.removeAll(toSend);
    }

    return _serialized(() async {
      final current = await _storage.read();
      final now = _now();
      final pending = <PendingWithdrawal>[];
      for (final p in current.pending) {
        final outcome = outcomes[p.token];
        if (outcome == WithdrawalOutcome.confirmed) continue;
        if (outcome == null) {
          pending.add(p);
          continue;
        }
        final attempts = p.attempts + 1;
        pending.add(
          p.copyWith(
            attempts: attempts,
            failed:
                outcome == WithdrawalOutcome.rejected ||
                now.difference(p.since) >= kMaxWithdrawalAge,
          ),
        );
      }
      final confirmed = {
        for (final e in outcomes.entries)
          if (e.value == WithdrawalOutcome.confirmed) e.key,
      };
      await _storage.write(
        ConsentState(
          active: [
            for (final t in current.active)
              if (!confirmed.contains(t)) t,
          ],
          pending: pending,
        ),
      );
      return !pending.any((p) => !p.failed);
    });
  }
}

/// Sends pending withdrawals until the server confirmed them: once at app
/// start, and again with growing pauses while anything is worth a retry, so
/// the "sent as soon as you are online" promise holds without the feedback
/// screen being open (BIZ-63).
final class FeedbackWithdrawalRetry {
  FeedbackWithdrawalRetry({
    FeedbackConsentStore? store,
    this.initialDelay = const Duration(seconds: 15),
    this.maxDelay = const Duration(hours: 1),
  }) : _store = store ?? FeedbackConsentStore();

  final FeedbackConsentStore _store;
  final Duration initialDelay;
  final Duration maxDelay;

  FeedbackSubmissionService? _service;
  Timer? _timer;
  late Duration _delay = initialDelay;

  /// True while a retry is scheduled.
  bool get isScheduled => _timer?.isActive ?? false;

  /// Starts with [service] (or keeps the one already set) and tries now. The
  /// backoff starts over, also at every app start; that is intended, as a
  /// fresh start is a good moment to try again and there is no attempt cap
  /// it could wear down.
  Future<void> kick([FeedbackSubmissionService? service]) {
    _service = service ?? _service;
    _timer?.cancel();
    _delay = initialDelay;
    return _attempt();
  }

  /// Schedules the next attempt with a fresh backoff, without trying now.
  /// Used after a withdrawal on the feedback screen stayed pending. Does
  /// nothing before [kick] set a configured service.
  void retryLater() {
    if (!(_service?.isConfigured ?? false)) return;
    _timer?.cancel();
    _delay = initialDelay;
    _schedule();
  }

  void _schedule() {
    _timer = Timer(_delay, () => unawaited(_attempt()));
    final next = _delay * 2;
    _delay = next > maxDelay ? maxDelay : next;
  }

  Future<void> _attempt() async {
    final service = _service;
    // Without a backend a retry can never succeed.
    if (service == null || !service.isConfigured) return;
    bool done;
    try {
      done = await _store.flushPending(service);
    } on Object catch (e) {
      // Storage unavailable for now: keep the loop alive.
      _log.warning('Withdrawal retry could not read the state: $e');
      done = false;
    }
    if (done) return;
    _timer?.cancel();
    _schedule();
  }

  void cancel() => _timer?.cancel();
}

/// The app-wide retry. The bootstrap starts it, the feedback screen asks for
/// another round after a withdrawal stayed pending.
final feedbackWithdrawalRetry = FeedbackWithdrawalRetry();

/// `mailto:` link to the withdrawal contact. [subject] and [body] are already
/// localized; the caller adds the feedback date to the body when known.
Uri consentWithdrawalMailUri({required String subject, required String body}) =>
    Uri(
      scheme: 'mailto',
      path: kConsentWithdrawalContact,
      query:
          'subject=${Uri.encodeComponent(subject)}'
          '&body=${Uri.encodeComponent(body)}',
    );
