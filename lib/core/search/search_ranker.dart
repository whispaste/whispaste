/// The one search ranking of the app: every list search, the snippet picker,
/// the settings search, the history (over its full-text candidates) and the
/// global search rank through [rankSearch], so a query finds and orders
/// things the same way everywhere.
///
/// Pure Dart without Flutter, so large lists can be ranked off the UI
/// isolate ([rankSearchAsync]).
library;

import 'dart:isolate';
import 'dart:math' as math;

import '../utils/search_fold.dart';
import 'bounded_edit_distance.dart';

/// Field weights shared by every search, so a title counts the same
/// everywhere.
abstract final class SearchWeight {
  static const title = 3.0;
  static const body = 1.0;
}

/// One searchable text of an item with its weight, e.g. a snippet's title
/// (3) and body (1). A word found in a heavier field ranks higher.
class SearchField {
  const SearchField(this.text, this.weight);

  final String text;
  final double weight;
}

/// An item as the ranker sees it: a stable [id] (used for what was learned)
/// and its weighted [fields].
class SearchDoc {
  const SearchDoc(this.id, this.fields);

  final String id;
  final List<SearchField> fields;
}

/// How often an item was picked after a search that matched one of its
/// words, and when last. [lastPickedUtc] is in UTC.
class SearchPickStat {
  const SearchPickStat(this.count, this.lastPickedUtc);

  final int count;
  final DateTime lastPickedUtc;
}

/// What the user picked from earlier result lists: per item id, per word of
/// that item that the query matched. It never holds the typed query, only
/// words that are part of the item anyway.
class SearchMemory {
  const SearchMemory([this.byItem = const {}]);

  final Map<String, Map<String, SearchPickStat>> byItem;

  static const empty = SearchMemory();
}

/// A ranked match: [index] into the ranked docs, its [score], the item's
/// own words the query matched ([matchedWords], which is what a pick of
/// this hit records), and whether a query word only matched with a typo.
class SearchHit {
  const SearchHit(
    this.index,
    this.score,
    this.matchedWords, {
    this.viaTypo = false,
  });

  final int index;
  final double score;
  final Set<String> matchedWords;
  final bool viaTypo;
}

/// Tuning of the ranking, in one place.
abstract final class SearchScoring {
  /// Match quality per query word, multiplied by the field weight.
  static const exactWord = 1.0;
  static const wordStart = 0.8;
  static const inWord = 0.5;
  static const typo = 0.3;

  /// Extra share for a match in the field's first word: "Workflow
  /// review" before "Review of the workflow".
  static const firstWordBonus = 0.1;

  /// Typo tolerance only for query words of this length or more; one edit
  /// up to [twoEditsFrom] characters, two from there.
  static const typoFrom = 4;
  static const twoEditsFrom = 9;

  /// Learned boost: grows with the log of the decayed pick count, halves
  /// every [halfLife] and never exceeds [maxLearned]. The cap stays below
  /// the gap between a whole word or word start in a title (weight 3) and
  /// a whole word in a body (weight 1), so picks reorder hits of the same
  /// kind but never bury such a title hit below a body-only one.
  static const learnedPerLog = 0.5;
  static const maxLearned = 1.0;
  static const halfLife = Duration(days: 30);
}

/// Splits folded text into words (letters and digits).
List<String> searchWords(String text) => foldForSearch(
  text,
).split(_nonWord).where((w) => w.isNotEmpty).toList(growable: false);

final _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Ranks [docs] for [query]. Every query word must match somewhere in a doc
/// (order free); the doc's score adds the best weighted match of each word
/// and the learned boost. Docs found only through a typo follow all others. Ties keep the docs' given order, which is the
/// caller's base order (newest, last used …). An empty query returns every
/// doc in that order.
List<SearchHit> rankSearch(
  List<SearchDoc> docs,
  String query, {
  SearchMemory memory = SearchMemory.empty,
  DateTime? nowUtc,
}) {
  final queryWords = searchWords(query);
  if (queryWords.isEmpty) {
    return [for (var i = 0; i < docs.length; i++) SearchHit(i, 0, const {})];
  }
  final now = nowUtc ?? DateTime.now().toUtc();
  final hits = <SearchHit>[];
  for (var i = 0; i < docs.length; i++) {
    final hit = _score(i, docs[i], queryWords, memory, now);
    if (hit != null) hits.add(hit);
  }
  // Hits that needed a typo come after every exact hit, whatever their
  // fields. List.sort is not stable; the index keeps ties in base order.
  hits.sort((a, b) {
    if (a.viaTypo != b.viaTypo) return a.viaTypo ? 1 : -1;
    final byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : a.index.compareTo(b.index);
  });
  return hits;
}

/// [rankSearch] on a background isolate once the list is large enough that
/// ranking it could stall a keystroke (many notes or history candidates).
Future<List<SearchHit>> rankSearchAsync(
  List<SearchDoc> docs,
  String query, {
  SearchMemory memory = SearchMemory.empty,
  DateTime? nowUtc,
  int isolateFrom = 2000,
}) {
  if (docs.length < isolateFrom) {
    return Future.value(
      rankSearch(docs, query, memory: memory, nowUtc: nowUtc),
    );
  }
  final now = nowUtc ?? DateTime.now().toUtc();
  return Isolate.run(
    () => rankSearch(docs, query, memory: memory, nowUtc: now),
  );
}

SearchHit? _score(
  int index,
  SearchDoc doc,
  List<String> queryWords,
  SearchMemory memory,
  DateTime now,
) {
  final fieldWords = [for (final f in doc.fields) searchWords(f.text)];
  var score = 0.0;
  var viaTypo = false;
  final matched = <String>{};
  for (final q in queryWords) {
    var best = 0.0;
    var bestIsTypo = false;
    String? bestWord;
    for (var f = 0; f < doc.fields.length; f++) {
      final words = fieldWords[f];
      for (var w = 0; w < words.length; w++) {
        final base = _quality(q, words[w]);
        if (base == 0) continue;
        final isTypo = base == SearchScoring.typo;
        // An exact match of this word always wins over a typo match.
        if (bestWord != null && isTypo && !bestIsTypo) continue;
        final quality = w == 0 ? base + SearchScoring.firstWordBonus : base;
        final weighted = quality * doc.fields[f].weight;
        if (weighted > best || (bestIsTypo && !isTypo)) {
          best = weighted;
          bestIsTypo = isTypo;
          bestWord = words[w];
        }
      }
    }
    if (bestWord == null) return null;
    score += best;
    if (bestIsTypo) viaTypo = true;
    matched.add(bestWord);
  }
  score += _learned(memory.byItem[doc.id], matched, now);
  return SearchHit(index, score, matched, viaTypo: viaTypo);
}

double _quality(String query, String word) {
  if (word == query) return SearchScoring.exactWord;
  if (word.startsWith(query)) return SearchScoring.wordStart;
  if (word.contains(query)) return SearchScoring.inWord;
  if (query.length < SearchScoring.typoFrom) return 0;
  final max = query.length >= SearchScoring.twoEditsFrom ? 2 : 1;
  // Against the word's starts around the query's length, so "wrkflow"
  // finds "workflows" while the user is still typing.
  final from = math.max(1, query.length - max);
  final to = math.min(word.length, query.length + max);
  for (var len = from; len <= to; len++) {
    if (boundedEditDistance(query, word.substring(0, len), max) != null) {
      return SearchScoring.typo;
    }
  }
  return 0;
}

double _learned(
  Map<String, SearchPickStat>? picks,
  Set<String> matched,
  DateTime now,
) {
  if (picks == null) return 0;
  var decayed = 0.0;
  for (final word in matched) {
    final stat = picks[word];
    if (stat == null) continue;
    final age = now.difference(stat.lastPickedUtc);
    final halves = age.inMinutes / SearchScoring.halfLife.inMinutes;
    decayed += stat.count * math.pow(0.5, halves.clamp(0, 64));
  }
  if (decayed <= 0) return 0;
  return math.min(
    SearchScoring.maxLearned,
    SearchScoring.learnedPerLog * math.log(1 + decayed) / math.ln2,
  );
}
