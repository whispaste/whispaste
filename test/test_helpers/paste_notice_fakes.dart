import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whispaste/services/sound_feedback_service.dart';
import 'package:whispaste/services/system_attention_service.dart';
import 'package:whispaste/services/tray_service.dart';

/// One attention request that reached the (fake) OS layer. [notification] is
/// false when the caller asked to skip the native notification (#1672).
typedef AttentionRequest = ({
  AttentionKind kind,
  String title,
  String body,
  bool notification,
});

/// Records every [requestAttention] and [clearAttention] instead of posting a
/// notification, so tests can assert which paste notice the user would see.
class RecordingSystemAttention extends SystemAttentionService {
  // The base class keeps its Ref private, so it cannot be a super parameter.
  // ignore: use_super_parameters
  RecordingSystemAttention(Ref ref) : super(ref);

  final List<AttentionRequest> requests = [];
  int clearCalls = 0;

  /// What [requestAttention] reports: false stands for a notice the OS did
  /// not show (switched off, no notification server, delivery failed).
  bool delivers = true;

  @override
  Future<bool> requestAttention({
    required AttentionKind kind,
    required String title,
    required String body,
    void Function()? onClick,
    bool showNotification = true,
  }) async {
    requests.add((
      kind: kind,
      title: title,
      body: body,
      notification: showNotification,
    ));
    return delivers;
  }

  @override
  Future<void> clearAttention() async {
    clearCalls++;
  }
}

/// Tray double that records the action-needed entries without touching
/// tray_manager.
class FakeNoticeTray extends TrayService {
  final setActionNeededLabels = <String>[];
  int clearActionNeededCalls = 0;
  final openedActionNeededKeys = <String>[];

  @override
  void build() {
    // No-op: skip the real tray_manager setup.
  }

  @override
  void setActionNeeded({
    required String label,
    required String tooltip,
    String? menuItemKey,
  }) {
    setActionNeededLabels.add(label);
  }

  @override
  void clearActionNeeded({String? ifKey}) {
    clearActionNeededCalls++;
  }

  @override
  void openActionNeeded(String key) => openedActionNeededKeys.add(key);
}

/// Sound double that counts error sounds.
class FakeNoticeSound extends SoundFeedbackService {
  int playErrorCalls = 0;

  @override
  void build() {
    // No-op: skip the real audio engine.
  }

  @override
  Future<void> playError() async {
    playErrorCalls++;
  }
}
