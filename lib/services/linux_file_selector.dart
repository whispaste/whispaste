import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/services.dart';

import '../core/l10n/generated/app_localizations.dart';

/// Linux file dialogs with title and buttons in the app language (XP-5-13).
///
/// file_selector_linux shows "Open File", "Open" and "Cancel" in English and
/// takes no title. This implementation sends the same options to the
/// runner's com.whispaste.file_dialog channel (linux/runner/file_dialog_host)
/// together with localized texts. A label the caller passes as
/// `confirmButtonText` still wins.
class LinuxFileSelector extends FileSelectorPlatform {
  LinuxFileSelector(this.l10n, {MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.whispaste.file_dialog');

  /// Texts of the current app language; replaced on every language change.
  L10n l10n;

  final MethodChannel _channel;

  /// Makes this the file_selector implementation, or relabels the installed
  /// one for a new app language.
  static void install(L10n l10n) {
    final current = FileSelectorPlatform.instance;
    if (current is LinuxFileSelector) {
      current.l10n = l10n;
    } else {
      FileSelectorPlatform.instance = LinuxFileSelector(l10n);
    }
  }

  Future<List<String>> _show({
    required String action,
    required String title,
    required String accept,
    bool multiple = false,
    List<XTypeGroup>? typeGroups,
    String? folder,
    String? name,
    bool createFolders = false,
  }) async {
    final paths = await _channel.invokeListMethod<String>('show', {
      'action': action,
      'title': title,
      'accept': accept,
      'cancel': l10n.actionCancel,
      'multiple': multiple,
      'filters': ?typeGroups?.map(_filter).toList(),
      'folder': ?folder,
      'name': ?name,
      'createFolders': createFolders,
    });
    return paths ?? const [];
  }

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    final paths = await _show(
      action: 'open',
      title: l10n.fileDialogOpenTitle,
      accept: confirmButtonText ?? l10n.actionOpen,
      typeGroups: acceptedTypeGroups,
      folder: initialDirectory,
    );
    return paths.isEmpty ? null : XFile(paths.first);
  }

  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    final paths = await _show(
      action: 'open',
      title: l10n.fileDialogOpenFilesTitle,
      accept: confirmButtonText ?? l10n.actionOpen,
      multiple: true,
      typeGroups: acceptedTypeGroups,
      folder: initialDirectory,
    );
    return [for (final path in paths) XFile(path)];
  }

  @override
  Future<String?> getSavePath({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? suggestedName,
    String? confirmButtonText,
  }) async {
    final location = await getSaveLocation(
      acceptedTypeGroups: acceptedTypeGroups,
      options: SaveDialogOptions(
        initialDirectory: initialDirectory,
        suggestedName: suggestedName,
        confirmButtonText: confirmButtonText,
      ),
    );
    return location?.path;
  }

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    final paths = await _show(
      action: 'save',
      title: l10n.fileDialogSaveTitle,
      accept: options.confirmButtonText ?? l10n.actionSave,
      typeGroups: acceptedTypeGroups,
      folder: options.initialDirectory,
      name: options.suggestedName,
      createFolders: options.canCreateDirectories ?? true,
    );
    return paths.isEmpty ? null : FileSaveLocation(paths.first);
  }

  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) => getDirectoryPathWithOptions(
    FileDialogOptions(
      initialDirectory: initialDirectory,
      confirmButtonText: confirmButtonText,
    ),
  );

  @override
  Future<String?> getDirectoryPathWithOptions(FileDialogOptions options) async {
    final paths = await _folders(options, multiple: false);
    return paths.isEmpty ? null : paths.first;
  }

  @override
  Future<List<String>> getDirectoryPaths({
    String? initialDirectory,
    String? confirmButtonText,
  }) => getDirectoryPathsWithOptions(
    FileDialogOptions(
      initialDirectory: initialDirectory,
      confirmButtonText: confirmButtonText,
    ),
  );

  @override
  Future<List<String>> getDirectoryPathsWithOptions(
    FileDialogOptions options,
  ) => _folders(options, multiple: true);

  Future<List<String>> _folders(
    FileDialogOptions options, {
    required bool multiple,
  }) => _show(
    action: 'folder',
    title: l10n.fileDialogFolderTitle,
    accept: options.confirmButtonText ?? l10n.fileDialogSelectFolder,
    multiple: multiple,
    folder: options.initialDirectory,
    createFolders: options.canCreateDirectories ?? true,
  );
}

/// The filter the runner builds a GtkFileFilter from; same rules as
/// file_selector_linux (extensions become "*.ext" globs, "any" is "*").
Map<String, Object> _filter(XTypeGroup group) {
  final label = group.label ?? '';
  if (group.allowsAny) {
    return {
      'label': label,
      'patterns': ['*'],
    };
  }
  if ((group.extensions?.isEmpty ?? true) &&
      (group.mimeTypes?.isEmpty ?? true)) {
    throw ArgumentError(
      'Type group $group allows neither extensions nor MIME types, which '
      'Linux needs to filter by.',
    );
  }
  return {
    'label': label,
    'patterns': [for (final ext in group.extensions ?? <String>[]) '*.$ext'],
    'mimeTypes': group.mimeTypes ?? <String>[],
  };
}
