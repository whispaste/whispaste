/// Sample history data for preview mode.
///
/// Used until real recording + transcription is connected.
/// Provides realistic entries that showcase search, filtering, and grouping.
library;

import 'database.dart';

/// Sample entries spanning multiple days to demonstrate date grouping.
List<HistoryEntry> generateSampleEntries() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  return [
    // Today
    _entry(
      id: 'sample-1',
      title: 'Meeting notes — Product roadmap Q3',
      content:
          'We discussed the upcoming features for Q3. The team agreed on '
          'prioritizing the mobile app launch and improving the onboarding '
          'experience. Key milestones: beta by June, public launch by August. '
          'Need to align design and engineering on the timeline.',
      timestamp: today.add(const Duration(hours: 14, minutes: 23)),
      durationSec: 185.0,
      language: 'en',
      model: 'large-v3',
      isLocal: true,
      tags: '["meeting","product"]',
      pinned: true,
    ),
    _entry(
      id: 'sample-2',
      title: 'Quick reminder',
      content: 'Pick up groceries on the way home. Milk, bread, avocados, '
          'and that new pasta sauce Sarah recommended.',
      timestamp: today.add(const Duration(hours: 10, minutes: 5)),
      durationSec: 12.0,
      language: 'en',
      model: 'large-v3',
      isLocal: true,
      tags: '["personal"]',
    ),
    _entry(
      id: 'sample-3',
      title: 'Client email — Proposal follow-up',
      content:
          'Hi Marcus, thank you for taking the time to review our proposal. '
          'I wanted to follow up on the timeline we discussed. We can '
          'definitely accommodate the earlier deadline if we adjust the '
          'scope of phase two. Let me know if Thursday works for a quick call.',
      timestamp: today.add(const Duration(hours: 9, minutes: 15)),
      durationSec: 45.0,
      language: 'en',
      model: 'base',
      isLocal: false,
      tags: '["work","email"]',
    ),
    // Yesterday
    _entry(
      id: 'sample-4',
      title: 'Blog draft — Privacy in AI tools',
      content:
          'Privacy is not a feature — it is a fundamental right. When we '
          'build AI tools that process sensitive information like voice '
          'recordings and personal notes, we have a responsibility to ensure '
          'that data stays where users expect it. Local-first processing '
          'is not just a technical choice, it is an ethical one.',
      timestamp:
          today.subtract(const Duration(days: 1, hours: -16, minutes: -30)),
      durationSec: 240.0,
      processingDurationSec: 3.2,
      language: 'en',
      model: 'large-v3',
      isLocal: true,
      tags: '["blog","writing"]',
      pinned: true,
    ),
    _entry(
      id: 'sample-5',
      title: 'Feedback for design review',
      content:
          'The new dashboard layout looks great overall. Two suggestions: '
          'the chart colors could use more contrast for accessibility, and '
          'the export button should be more prominent — it took me a while '
          'to find it.',
      timestamp:
          today.subtract(const Duration(days: 1, hours: -11, minutes: -45)),
      durationSec: 38.0,
      language: 'en',
      model: 'large-v3',
      isLocal: true,
      tags: '["feedback"]',
    ),
    // This week
    _entry(
      id: 'sample-6',
      title: 'Standup notes — Sprint 14',
      content:
          'Yesterday I finished the API integration for the new export '
          'feature. Today I will work on the unit tests and start the '
          'documentation. No blockers.',
      timestamp: today.subtract(const Duration(days: 3, hours: -9)),
      durationSec: 22.0,
      language: 'en',
      model: 'base',
      isLocal: true,
      tags: '["standup","work"]',
    ),
    _entry(
      id: 'sample-7',
      title: 'Gedanken zum Teamausflug',
      content:
          'Ich denke wir sollten dieses Jahr etwas anderes machen. Vielleicht '
          'eine Kanufahrt auf der Spree oder ein Escape Room. Letztes Jahr '
          'war das Bowling ganz nett aber es wäre schön, mal was Neues '
          'auszuprobieren.',
      timestamp: today.subtract(const Duration(days: 4, hours: -14)),
      durationSec: 35.0,
      language: 'de',
      model: 'large-v3',
      isLocal: true,
      tags: '["team","ideas"]',
    ),
    // Older
    _entry(
      id: 'sample-8',
      title: 'Project brief — Website redesign',
      content:
          'The current website does not reflect our brand anymore. We need '
          'a complete redesign focusing on three areas: modern visual identity, '
          'better onboarding for new users, and improved documentation. '
          'Budget: 25k, timeline: 8 weeks.',
      timestamp: today.subtract(const Duration(days: 12)),
      durationSec: 95.0,
      processingDurationSec: 2.1,
      language: 'en',
      model: 'large-v3',
      isLocal: true,
      tags: '["project","design"]',
    ),
    _entry(
      id: 'sample-9',
      title: 'Rezeptidee — Pasta al limone',
      content:
          'Spaghetti kochen, in der Zwischenzeit Zitronensaft und Schale '
          'mit Butter und Parmesan verrühren. Pasta abgießen, etwas '
          'Kochwasser aufheben. Alles zusammen schwenken bis eine cremige '
          'Sauce entsteht. Mit Pfeffer und frischer Petersilie servieren.',
      timestamp: today.subtract(const Duration(days: 18)),
      durationSec: 28.0,
      language: 'de',
      model: 'base',
      isLocal: true,
      tags: '["personal","recipe"]',
    ),
    _entry(
      id: 'sample-10',
      title: 'Quarterly review talking points',
      content:
          'Key achievements: launched v2.0, onboarded 3 enterprise clients, '
          'reduced churn by 15 percent. Challenges: hiring took longer than '
          'expected, infrastructure costs increased. Next quarter focus: '
          'series A preparation, mobile app beta, partnerships.',
      timestamp: today.subtract(const Duration(days: 25)),
      durationSec: 150.0,
      processingDurationSec: 4.5,
      language: 'en',
      model: 'large-v3',
      isLocal: true,
      tags: '["review","leadership"]',
      pinned: true,
    ),
  ];
}

HistoryEntry _entry({
  required String id,
  required String title,
  required String content,
  required DateTime timestamp,
  required double durationSec,
  double processingDurationSec = 0.0,
  required String language,
  required String model,
  required bool isLocal,
  String tags = '[]',
  bool pinned = false,
  String source = 'dictation',
}) {
  // Build the entry via Companion → toColumns → HistoryEntry
  // Since HistoryEntry is a DataClass, we construct it directly.
  return HistoryEntry(
    id: id,
    content: content,
    title: title,
    timestamp: timestamp,
    durationSec: durationSec,
    processingDurationSec: processingDurationSec,
    language: language,
    languageHint: '',
    tags: tags,
    pinned: pinned,
    source: source,
    model: model,
    isLocal: isLocal,
    costUsd: 0.0,
    projectId: '',
    archived: false,
    titleEdited: false,
    deletedAt: null,
  );
}
