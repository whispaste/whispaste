import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/feedback/feedback_page.dart';
import 'package:whispaste/services/feedback_consent_store.dart';
import 'package:whispaste/services/feedback_submission_service.dart';
import 'package:whispaste/widgets/wp_button.dart';

import '../../fixtures/test_helpers.dart';

/// Consent state kept in memory, so the page never touches the platform
/// credential store in a widget test.
final class _MemoryStorage implements ConsentStateStorage {
  _MemoryStorage([this.state = const ConsentState()]);

  ConsentState state;

  @override
  Future<ConsentState> read() async => state;

  @override
  Future<void> write(ConsentState next) async => state = next;
}

/// Credential store that can turn unreadable.
final class _SwitchableSecureKeyStore implements SecureKeyStore {
  final values = <String, String>{};
  bool unavailable = false;

  @override
  Future<String?> readKey(String key) async {
    if (unavailable) throw StateError('locked keyring');
    return values[key];
  }

  @override
  Future<void> writeKey(String key, String value) async {
    if (unavailable) throw StateError('locked keyring');
    values[key] = value;
  }

  @override
  Future<void> deleteKey(String key) async {
    if (unavailable) throw StateError('locked keyring');
    values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _since = DateTime(2026, 10, 17);

void main() {
  late L10n l10n;
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  setUp(() {
    resetConsentStoreQueueForTesting();
    SharedPreferences.setMockInitialValues({});
  });

  Future<List<http.Request>> pumpWith(
    WidgetTester tester, {
    required int status,
    required ConsentStateStorage storage,
    bool configured = true,
  }) async {
    final requests = <http.Request>[];
    final service = FeedbackSubmissionService(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(status == 200 ? '' : 'boom', status);
      }),
      supabaseUrl: configured ? 'https://example.supabase.co' : '',
      supabasePublishableKey: 'test-key',
      breadcrumbSink: (_) {},
    );
    await tester.pumpWidget(
      makeTestable(
        FeedbackPage(
          submissionService: service,
          consentStore: FeedbackConsentStore(storage: storage),
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    return requests;
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  ConsentState pendingOne({bool failed = false}) => ConsentState(
    pending: [
      PendingWithdrawal(
        token: 'secret-pending-long-enough',
        since: _since,
        failed: failed,
      ),
    ],
  );

  testWidgets('no one-click button without a stored consent code', (
    tester,
  ) async {
    await pumpWith(tester, status: 204, storage: _MemoryStorage());
    expect(find.byKey(const Key('feedback-withdraw-consent')), findsNothing);
  });

  testWidgets('the e-mail route is always visible', (tester) async {
    await pumpWith(tester, status: 204, storage: _MemoryStorage());
    expect(find.byKey(const Key('feedback-withdraw-email')), findsOneWidget);
    expect(find.text(l10n.feedbackWithdrawEmailLabel), findsOneWidget);
  });

  testWidgets(
    'one tap withdraws with the stored secret and says when it leaves',
    (tester) async {
      final storage = _MemoryStorage(
        const ConsentState(active: ['secret-one-long-enough']),
      );
      final requests = await pumpWith(tester, status: 204, storage: storage);

      await tapKey(tester, 'feedback-withdraw-consent');

      expect(requests, hasLength(1));
      expect(jsonDecode(requests.single.body), {
        'p_token': 'secret-one-long-enough',
      });
      expect(find.text(l10n.feedbackWithdrawConsentDone), findsOneWidget);
      expect(find.byKey(const Key('feedback-withdraw-consent')), findsNothing);
      expect(storage.state.isEmpty, isTrue);
    },
  );

  testWidgets('an offline withdrawal is shown as being sent', (tester) async {
    final storage = _MemoryStorage(
      const ConsentState(active: ['secret-one-long-enough']),
    );
    await pumpWith(tester, status: 500, storage: storage);

    await tapKey(tester, 'feedback-withdraw-consent');

    expect(find.text(l10n.feedbackWithdrawConsentPending), findsOneWidget);
    expect(
      find.byKey(const Key('feedback-withdraw-entry-sending-0')),
      findsOneWidget,
    );
    expect(storage.state.pending.single.token, 'secret-one-long-enough');
  });

  testWidgets('a rejected withdrawal points to the e-mail route', (
    tester,
  ) async {
    final storage = _MemoryStorage(
      const ConsentState(active: ['secret-one-long-enough']),
    );
    await pumpWith(tester, status: 422, storage: storage);

    await tapKey(tester, 'feedback-withdraw-consent');

    expect(find.text(l10n.feedbackWithdrawConsentUndelivered), findsOneWidget);
    expect(find.text(l10n.feedbackWithdrawConsentPending), findsNothing);
    expect(
      find.byKey(const Key('feedback-withdraw-entry-failed-0')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('feedback-withdraw-email')), findsOneWidget);
  });

  testWidgets('without a backend nothing promises a later delivery', (
    tester,
  ) async {
    final storage = _MemoryStorage(
      const ConsentState(active: ['secret-one-long-enough']),
    );
    final requests = await pumpWith(
      tester,
      status: 204,
      storage: storage,
      configured: false,
    );

    await tapKey(tester, 'feedback-withdraw-consent');

    expect(requests, isEmpty);
    expect(find.text(l10n.feedbackWithdrawConsentUndelivered), findsOneWidget);
    expect(find.text(l10n.feedbackWithdrawConsentPending), findsNothing);
    expect(
      find.byKey(const Key('feedback-withdraw-entry-failed-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('feedback-withdraw-entry-sending-0')),
      findsNothing,
    );
  });

  testWidgets('a pending entry shows its date while it is being sent', (
    tester,
  ) async {
    await pumpWith(tester, status: 500, storage: _MemoryStorage(pendingOne()));

    expect(
      find.text(l10n.feedbackWithdrawEntrySending('2026-10-17')),
      findsOneWidget,
    );
  });

  testWidgets('a failed entry shows the e-mail route', (tester) async {
    await pumpWith(
      tester,
      status: 204,
      storage: _MemoryStorage(pendingOne(failed: true)),
    );

    expect(
      find.text(l10n.feedbackWithdrawEntryFailed('2026-10-17')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('feedback-withdraw-email')), findsOneWidget);
  });

  /// Fakes the url_launcher channel; returns the links that were opened.
  List<String> fakeLauncher(WidgetTester tester, {required bool opens}) {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final launched = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'launch') {
        launched.add((call.arguments as Map)['url'] as String);
      }
      return opens;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    return launched;
  }

  const secret = 'secret-pending-long-enough';
  final reference = consentTokenHash(secret);

  testWidgets('an opened mail keeps the failed entry until confirmed', (
    tester,
  ) async {
    final launched = fakeLauncher(tester, opens: true);
    final storage = _MemoryStorage(pendingOne(failed: true));
    await pumpWith(tester, status: 204, storage: storage);

    await tapKey(tester, 'feedback-withdraw-email');

    final mail = Uri.decodeComponent(launched.single);
    expect(mail, contains(reference));
    expect(mail, isNot(contains(secret)));
    // Opening a draft is not sending it.
    expect(storage.state.pending.single.failed, isTrue);
    expect(
      find.byKey(const Key('feedback-withdraw-entry-failed-0')),
      findsOneWidget,
    );

    await tapKey(tester, 'feedback-withdraw-email-sent');

    expect(storage.state.isEmpty, isTrue);
    expect(
      find.byKey(const Key('feedback-withdraw-entry-failed-0')),
      findsNothing,
    );
    expect(find.byKey(const Key('feedback-withdraw-email-sent')), findsNothing);
  });

  testWidgets('without a mail app the address can be copied', (tester) async {
    fakeLauncher(tester, opens: false);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final storage = _MemoryStorage(pendingOne(failed: true));
    await pumpWith(tester, status: 204, storage: storage);

    await tapKey(tester, 'feedback-withdraw-email');

    expect(storage.state.pending.single.failed, isTrue);
    expect(
      find.byKey(const Key('feedback-withdraw-email-address')),
      findsOneWidget,
    );
    expect(find.text(kConsentWithdrawalContact), findsOneWidget);

    await tapKey(tester, 'feedback-withdraw-email-copy');

    expect(copied, startsWith(kConsentWithdrawalContact));
    expect(copied, contains(reference));
    expect(copied, isNot(contains(secret)));
    expect(storage.state.pending.single.failed, isTrue);
  });

  testWidgets('an unreadable credential store points to the e-mail route '
      'with the mirrored hash', (tester) async {
    final launched = fakeLauncher(tester, opens: true);
    final secure = _SwitchableSecureKeyStore();
    final storage = SecureConsentStateStorage(secure: secure);
    await tester.runAsync(() async {
      await storage.write(pendingOne());
    });
    secure.unavailable = true;

    await pumpWith(tester, status: 500, storage: storage);

    expect(find.byKey(const Key('feedback-withdraw-locked')), findsOneWidget);
    expect(find.text(l10n.feedbackWithdrawLocked), findsOneWidget);

    await tapKey(tester, 'feedback-withdraw-email');

    final mail = Uri.decodeComponent(launched.single);
    expect(mail, contains(reference));
    expect(mail, isNot(contains(secret)));
  });

  testWidgets('a pending withdrawal is retried when the screen opens', (
    tester,
  ) async {
    final storage = _MemoryStorage(pendingOne());
    final requests = await pumpWith(tester, status: 204, storage: storage);

    expect(requests, hasLength(1));
    expect(jsonDecode(requests.single.body), {
      'p_token': 'secret-pending-long-enough',
    });
    expect(storage.state.isEmpty, isTrue);
    expect(
      find.byKey(const Key('feedback-withdraw-entry-sending-0')),
      findsNothing,
    );
  });

  Future<void> fillForm(WidgetTester tester, {required bool consent}) async {
    await tester.tap(find.text(l10n.feedbackTypeQuestion));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('feedbackCommentField')),
      'How does it work?',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('feedback-rating-5'));
    await tester.pumpAndSettle();
    if (consent) await tapKey(tester, 'feedbackPublishConsent');
    final submit = find.widgetWithText(WpButton, l10n.feedbackSubmit);
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
  }

  testWidgets('consent is off by default: nothing about a secret is sent', (
    tester,
  ) async {
    final storage = _MemoryStorage();
    final requests = await pumpWith(tester, status: 204, storage: storage);

    await fillForm(tester, consent: false);

    expect(requests, hasLength(1));
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['publish_consent'], isFalse);
    expect(body.containsKey('withdraw_token_hash'), isFalse);
    expect(storage.state.isEmpty, isTrue);
  });

  testWidgets(
    'a consented submission sends only the hash and keeps the secret',
    (tester) async {
      final storage = _MemoryStorage();
      final requests = await pumpWith(tester, status: 204, storage: storage);

      await fillForm(tester, consent: true);

      expect(requests, hasLength(1));
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['publish_consent'], isTrue);
      expect(body['consent_text_version'], kFeedbackConsentTextVersion);
      final secret = storage.state.active.single;
      expect(body['withdraw_token_hash'], consentTokenHash(secret));
      expect(requests.single.body, isNot(contains(secret)));
    },
  );
}
