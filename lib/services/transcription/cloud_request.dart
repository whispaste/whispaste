import 'package:http/http.dart' as http;

/// Sends [request] for a cloud speech-to-text adapter and reads the whole
/// response body.
///
/// Without a [client] the request gets its own, closed right after. The
/// transcriber provider caches an adapter for the whole session, so it holds
/// no connection between requests and `release()` has nothing to close.
Future<(int, String)> sendCloudSttRequest(
  http.BaseRequest request, {
  required Duration timeout,
  http.Client? client,
}) async {
  final effective = client ?? http.Client();
  try {
    final streamed = await effective.send(request).timeout(timeout);
    return (streamed.statusCode, await streamed.stream.bytesToString());
  } finally {
    if (client == null) effective.close();
  }
}
