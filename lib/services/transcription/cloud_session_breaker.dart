import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'transcriber_exception.dart';

/// Failed requests in a row that open the breaker for a target.
const int kCloudBreakerThreshold = 3;

/// Pause before the first probe request after the breaker opened.
const Duration kCloudBreakerBasePause = Duration(minutes: 1);

/// Longest pause between two probes; a failed probe doubles the pause up to
/// this.
const Duration kCloudBreakerMaxPause = Duration(minutes: 10);

/// Whether a failure says the service itself cannot be reached or is failing
/// right now. A wrong key, a used-up quota, a rejected request or a wrong
/// answer format of an own endpoint come from a service that responded, so
/// they never open the breaker.
bool isOutageFailure(TranscriberFailureReason reason) => switch (reason) {
  TranscriberFailureReason.networkError ||
  TranscriberFailureReason.timeout ||
  TranscriberFailureReason.serverError ||
  TranscriberFailureReason.rateLimited ||
  TranscriberFailureReason.endpointUnreachable => true,
  _ => false,
};

/// Stable identity of one cloud destination: provider, address and key. A
/// different key or provider is a different target and starts fresh. Only a
/// SHA-256 digest of the key is kept, never the key itself.
String cloudBreakerTarget({
  required String provider,
  required String address,
  String? key,
}) {
  final keyDigest = key == null || key.isEmpty
      ? ''
      : sha256.convert(utf8.encode(key)).toString();
  return '$provider|$address|$keyDigest';
}

class _TargetState {
  int failures = 0;
  DateTime? openedAt;
  Duration pause = kCloudBreakerBasePause;
  bool probing = false;
  TranscriberFailureReason lastReason = TranscriberFailureReason.networkError;
}

/// Session circuit breaker for cloud speech services.
///
/// After [kCloudBreakerThreshold] outage failures in a row at one target,
/// new requests to it fail at once instead of running the whole retry chain.
/// After the pause exactly one probe request goes out: success closes the
/// breaker, failure doubles the pause (at most [kCloudBreakerMaxPause]).
/// State lives in memory only and is gone after an app restart.
class CloudSessionBreaker {
  CloudSessionBreaker({this._now = DateTime.now});

  final DateTime Function() _now;
  final Map<String, _TargetState> _targets = {};

  /// Throws a [TranscriberException] when [target] is blocked; otherwise the
  /// request may go out. In the half-open state this lets exactly one caller
  /// through, and that caller must report [onSuccess], [onFailure] or
  /// [onAborted].
  void acquire(String target) {
    final s = _targets[target];
    if (s == null || s.openedAt == null) return;
    final remaining = s.openedAt!.add(s.pause).difference(_now());
    if (remaining <= Duration.zero && !s.probing) {
      s.probing = true;
      return;
    }
    throw TranscriberException(
      'Cloud service paused after repeated failures; trying again later.',
      reason: s.lastReason,
      retryAfter: remaining > Duration.zero ? remaining : null,
    );
  }

  /// The request got an answer that proves the service works.
  void onSuccess(String target) => _targets.remove(target);

  /// The request failed with [reason].
  void onFailure(String target, TranscriberFailureReason reason) {
    if (!isOutageFailure(reason)) {
      // The service answered, so it is reachable; the failure is not an outage.
      onSuccess(target);
      return;
    }
    final s = _targets.putIfAbsent(target, _TargetState.new);
    s.lastReason = reason;
    if (s.probing) {
      s.probing = false;
      s.pause = s.pause * 2 > kCloudBreakerMaxPause
          ? kCloudBreakerMaxPause
          : s.pause * 2;
      s.openedAt = _now();
      return;
    }
    if (s.openedAt != null) return;
    if (++s.failures >= kCloudBreakerThreshold) s.openedAt = _now();
  }

  /// The request ended without a verdict (cancelled): free a probe slot.
  void onAborted(String target) => _targets[target]?.probing = false;
}

/// The breaker of the running app session. One instance, so every adapter and
/// settings change shares it.
final cloudSessionBreakerProvider = Provider<CloudSessionBreaker>(
  (ref) => CloudSessionBreaker(),
);
