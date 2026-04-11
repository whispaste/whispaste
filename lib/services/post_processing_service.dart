/// Unified post-processing facade.
///
/// Routes [process], [suggestTags], and [suggestTitle] to either the local
/// llama-server ([LlmServiceNotifier]) or a cloud provider
/// ([CloudLlmProvider]) based on the user's [postProcessProvider] setting.
///
/// Consumers call this facade instead of reaching into LLM/cloud directly.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/settings_enums.dart';
import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart';
import 'llm_cloud_providers.dart';
import 'llm_service.dart';
import 'model_download_service.dart';

// ---------------------------------------------------------------------------
// Status
// ---------------------------------------------------------------------------

/// Lightweight status for the post-processing facade.
enum PostProcessingState { idle, starting, processing, error }

class PostProcessingStatus {
  const PostProcessingStatus({
    this.state = PostProcessingState.idle,
    this.errorMessage,
  });

  final PostProcessingState state;
  final String? errorMessage;

  bool get isBusy =>
      state == PostProcessingState.starting ||
      state == PostProcessingState.processing;
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Facade that dispatches post-processing requests to local or cloud LLM.
///
/// Usage:
/// ```dart
/// final pp = ref.read(postProcessingProvider.notifier);
/// final cleaned = await pp.process(text, PostProcessPreset.cleanup);
/// ```
class PostProcessingNotifier extends Notifier<PostProcessingStatus> {
  static final _log = AppLogger('PostProcessing');

  @override
  PostProcessingStatus build() {
    return const PostProcessingStatus();
  }

  // -----------------------------------------------------------------------
  // Public API
  // -----------------------------------------------------------------------

  /// Processes [text] using the configured LLM backend and [preset].
  ///
  /// For [PostProcessPreset.translate], pass [targetLang] (e.g. "German").
  /// Returns the processed text.
  Future<String> process(
    String text,
    PostProcessPreset preset, {
    String? targetLang,
  }) async {
    if (state.isBusy) {
      throw StateError('Post-processing already in progress');
    }

    final settings =
        ref.read(settingsProvider).value ?? AppSettings.defaults;
    final provider = settings.postProcessProviderType;

    _log.info(
      'Post-processing: preset=${preset.name} provider=${provider.value} '
      'textLen=${text.length}',
    );

    state = const PostProcessingStatus(
      state: PostProcessingState.starting,
    );

    try {
      final String result;

      if (provider.isLocal) {
        result = await _processLocal(text, preset, targetLang: targetLang);
      } else {
        result = await _processCloud(
          text,
          preset,
          settings: settings,
          provider: provider,
          targetLang: targetLang,
        );
      }

      state = const PostProcessingStatus();
      _log.info('Post-processing complete (${result.length} chars)');
      return result;
    } on Exception catch (e) {
      final msg = _friendlyError(e);
      _log.error('Post-processing failed: $msg');
      state = PostProcessingStatus(
        state: PostProcessingState.error,
        errorMessage: msg,
      );
      rethrow;
    }
  }

  /// Suggests tags for [text] using the configured LLM backend.
  Future<List<String>> suggestTags(String text) async {
    if (state.isBusy) {
      throw StateError('Post-processing already in progress');
    }

    final settings =
        ref.read(settingsProvider).value ?? AppSettings.defaults;
    final provider = settings.postProcessProviderType;

    state = const PostProcessingStatus(
      state: PostProcessingState.processing,
    );

    try {
      final List<String> tags;

      if (provider.isLocal) {
        tags = await _suggestTagsLocal(text);
      } else {
        tags = await _suggestTagsCloud(text, settings: settings, provider: provider);
      }

      state = const PostProcessingStatus();
      return tags;
    } on Exception catch (e) {
      final msg = _friendlyError(e);
      _log.error('Tag suggestion failed: $msg');
      state = PostProcessingStatus(
        state: PostProcessingState.error,
        errorMessage: msg,
      );
      rethrow;
    }
  }

  /// Suggests a title for [text] using the configured LLM backend.
  Future<String> suggestTitle(String text) async {
    if (state.isBusy) {
      throw StateError('Post-processing already in progress');
    }

    final settings =
        ref.read(settingsProvider).value ?? AppSettings.defaults;
    final provider = settings.postProcessProviderType;

    state = const PostProcessingStatus(
      state: PostProcessingState.processing,
    );

    try {
      final String title;

      if (provider.isLocal) {
        title = await _suggestTitleLocal(text);
      } else {
        title = await _suggestTitleCloud(text, settings: settings, provider: provider);
      }

      state = const PostProcessingStatus();
      return title;
    } on Exception catch (e) {
      final msg = _friendlyError(e);
      _log.error('Title suggestion failed: $msg');
      state = PostProcessingStatus(
        state: PostProcessingState.error,
        errorMessage: msg,
      );
      rethrow;
    }
  }

  // -----------------------------------------------------------------------
  // Private — local
  // -----------------------------------------------------------------------

  Future<String> _processLocal(
    String text,
    PostProcessPreset preset, {
    String? targetLang,
  }) async {
    _ensureLocalModelDownloaded();

    state = const PostProcessingStatus(
      state: PostProcessingState.starting,
    );

    final llm = ref.read(llmServiceProvider.notifier);
    await llm.ensureRunning();

    state = const PostProcessingStatus(
      state: PostProcessingState.processing,
    );

    return llm.complete(text, preset, targetLang: targetLang);
  }

  Future<List<String>> _suggestTagsLocal(String text) async {
    _ensureLocalModelDownloaded();

    final llm = ref.read(llmServiceProvider.notifier);
    await llm.ensureRunning();

    return llm.suggestTags(text);
  }

  Future<String> _suggestTitleLocal(String text) async {
    _ensureLocalModelDownloaded();

    final llm = ref.read(llmServiceProvider.notifier);
    await llm.ensureRunning();

    return llm.suggestTitle(text);
  }

  void _ensureLocalModelDownloaded() {
    final downloadState = ref.read(modelDownloadProvider);
    if (!downloadState.downloadedLlmModels.contains('qwen3-1.7b')) {
      throw StateError(
        'Local LLM model not downloaded. '
        'Please download the model in Settings → Models first.',
      );
    }
    if (!downloadState.llmServerReady) {
      throw StateError(
        'LLM engine binary not found. '
        'Please download the engine in Settings → Models first.',
      );
    }
  }

  // -----------------------------------------------------------------------
  // Private — cloud
  // -----------------------------------------------------------------------

  Future<String> _processCloud(
    String text,
    PostProcessPreset preset, {
    required AppSettings settings,
    required PostProcessProviderType provider,
    String? targetLang,
  }) async {
    state = const PostProcessingStatus(
      state: PostProcessingState.processing,
    );

    final cloud = _createCloudProvider(settings, provider);
    return cloud.complete(text, preset, targetLang: targetLang);
  }

  Future<List<String>> _suggestTagsCloud(
    String text, {
    required AppSettings settings,
    required PostProcessProviderType provider,
  }) async {
    final cloud = _createCloudProvider(settings, provider);
    return cloud.suggestTags(text);
  }

  Future<String> _suggestTitleCloud(
    String text, {
    required AppSettings settings,
    required PostProcessProviderType provider,
  }) async {
    final cloud = _createCloudProvider(settings, provider);
    return cloud.suggestTitle(text);
  }

  CloudLlmProvider _createCloudProvider(
    AppSettings settings,
    PostProcessProviderType provider,
  ) {
    final apiKey = switch (provider) {
      PostProcessProviderType.openAI => settings.openAiApiKey,
      PostProcessProviderType.anthropic => settings.anthropicApiKey,
      PostProcessProviderType.groq => settings.groqApiKey,
      PostProcessProviderType.gemini => settings.geminiApiKey,
      PostProcessProviderType.local =>
        throw ArgumentError('Local provider does not use cloud API'),
    };

    return createCloudProvider(
      provider: provider,
      apiKey: apiKey,
      model: settings.cloudLlmModel,
    );
  }

  // -----------------------------------------------------------------------
  // Private — error messages
  // -----------------------------------------------------------------------

  static String _friendlyError(Exception e) {
    final msg = e.toString();

    if (msg.contains('API key') || msg.contains('401') || msg.contains('403')) {
      return 'Invalid or missing API key. Check your settings.';
    }
    if (msg.contains('429') || msg.contains('rate limit')) {
      return 'Rate limit reached. Please wait a moment and try again.';
    }
    if (msg.contains('timeout') || msg.contains('TimeoutException')) {
      return 'Request timed out. The model may be overloaded.';
    }
    if (msg.contains('SocketException') || msg.contains('Connection refused')) {
      return 'Cannot reach the LLM server. Check your connection.';
    }
    if (msg.contains('not downloaded') || msg.contains('not found')) {
      return msg;
    }

    // Truncate long error messages.
    return msg.length > 120 ? '${msg.substring(0, 120)}…' : msg;
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Global post-processing provider.
final postProcessingProvider =
    NotifierProvider<PostProcessingNotifier, PostProcessingStatus>(
  PostProcessingNotifier.new,
);
