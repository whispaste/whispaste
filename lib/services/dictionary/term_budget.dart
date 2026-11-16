import 'dart:convert' show utf8;

import '../../core/config/settings_enums.dart';
import '../stt/stt_server_state_notifier.dart' show SttServerStateNotifier;
import '../transcription/deepgram_transcriber.dart'
    show kDeepgramKeytermByteBudget, kDeepgramKeytermMaxCount;
import 'vocabulary_terms.dart';

/// Exact token count of a text with the loaded on-device model, or null when
/// no model is loaded (the real count is then unknown).
typedef TermTokenCounter = Future<int?> Function(String text);

/// Index of the first term the active recognition no longer uses, or null
/// when it uses all of them (or the limit cannot be told).
///
/// The terms keep their order of priority: what comes first is used first.
/// - On-device Whisper: the terms go in as one prompt of
///   [SttServerStateNotifier.promptTokenBudget] real tokens; the rest is cut.
///   Each prefix is written with [encodeVocabulary] in the style of [style]
///   (the stored vocabulary), the same text [vocabularyPrompt] hands to the
///   recognition, so the list and the engine count alike (#145).
///   Only the exact count of the loaded model is trusted, so without
///   [countTokens] (no model loaded) nothing is claimed.
/// - Deepgram: at most [kDeepgramKeytermMaxCount] terms and
///   [kDeepgramKeytermByteBudget] bytes (the first term that does not fit).
/// - Engines without a prompt channel and the OpenAI-style endpoints have no
///   limit known to the app, so no term is reported as left out.
Future<int?> firstLeftOutTerm(
  List<String> terms, {
  required SttProviderType provider,
  required OnDeviceEngine engine,
  String style = '',
  TermTokenCounter? countTokens,
}) async {
  switch (provider) {
    case SttProviderType.deepgram:
      // The same choice as `deepgramKeyterms`: a repeated term is not sent
      // twice, a term past the count limit ends the list, one past the byte
      // budget is skipped. The line goes before the first term it affects.
      final seen = <String>{};
      var sent = 0;
      var bytes = 0;
      for (var i = 0; i < terms.length; i++) {
        if (!seen.add(terms[i].toLowerCase())) continue;
        if (sent >= kDeepgramKeytermMaxCount) return i;
        final termBytes = utf8.encode(terms[i]).length;
        if (bytes + termBytes > kDeepgramKeytermByteBudget) return i;
        sent++;
        bytes += termBytes;
      }
      return null;
    case SttProviderType.onDevice when engine == OnDeviceEngine.whisper:
      if (countTokens == null || terms.isEmpty) return null;
      const budget = SttServerStateNotifier.promptTokenBudget;
      // null: the model went away mid-count, so nothing is claimed.
      Future<bool?> fits(int n) async {
        final count = await countTokens(
          encodeVocabulary(terms.take(n), style: style),
        );
        return count == null ? null : count <= budget;
      }

      final all = await fits(terms.length);
      if (all == null || all) return null;
      // The prefix length that still fits is monotone: bisect it.
      var lo = 0; // fits
      var hi = terms.length; // does not fit
      while (hi - lo > 1) {
        final mid = (lo + hi) ~/ 2;
        final ok = await fits(mid);
        if (ok == null) return null;
        if (ok) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      // The term at [lo] is cut or dropped.
      return lo;
    case _:
      return null;
  }
}
