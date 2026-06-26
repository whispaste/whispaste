import 'dart:async';

import 'package:http/http.dart' as http;

final class AnalyticsService {
  AnalyticsService({
    required this.client,
    required this.endpointUrl,
    required this.siteId,
    required this.consentGranted,
    required this.dntActive,
  });

  final http.Client client;
  final String endpointUrl;
  final int siteId;
  final bool consentGranted;
  final bool dntActive;

  final List<Future<http.Response>> _pending = [];

  bool get _isConfigured => endpointUrl.isNotEmpty && siteId > 0;

  bool get _shouldDispatch => _isConfigured && consentGranted && !dntActive;

  void trackPageView(String path) {
    if (!_shouldDispatch) return;
    _pending.add(_sendPageView(path));
  }

  Future<void> flush() async {
    if (_pending.isNotEmpty) {
      await Future.wait(_pending, eagerError: false);
      _pending.clear();
    }
  }

  Future<http.Response> _sendPageView(String path) {
    final url = Uri.parse(
      '$endpointUrl/matomo.php',
    ).replace(queryParameters: {'idsite': '$siteId', 'rec': '1'});

    return client.post(
      url,
      headers: {'User-Agent': 'WhisPaste/1.0'},
      body: {
        'url': 'app://whispaste$path',
        'action_name': 'pageView',
        'apiv': '1',
        'send_image': '0',
        'rand': DateTime.now().microsecondsSinceEpoch.toString(),
      },
    );
  }
}
