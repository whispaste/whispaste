/// Pure folder-tree logic for the Notizen page (#659, ADR 0034): at most two
/// levels, a note sits in at most one folder, and a folder id without its
/// folder counts as the top level.
library;

import 'package:whispaste/core/data/database.dart';

/// One top-level folder with its subfolders, both alphabetical as the
/// database delivers them.
class NoteFolderNode {
  const NoteFolderNode({required this.folder, this.children = const []});

  final NoteFolder folder;
  final List<NoteFolder> children;
}

/// The folders as a two-level tree. A subfolder whose parent is gone, or
/// whose parent is itself a subfolder, is shown at the top level so it never
/// disappears from view.
List<NoteFolderNode> buildNoteFolderTree(List<NoteFolder> folders) {
  final byId = {for (final f in folders) f.id: f};
  bool isTop(NoteFolder f) {
    final parent = f.parentId == null ? null : byId[f.parentId];
    return parent == null || parent.parentId != null;
  }

  return [
    for (final top in folders)
      if (isTop(top))
        NoteFolderNode(
          folder: top,
          children: [
            for (final child in folders)
              if (child.parentId == top.id && !isTop(child)) child,
          ],
        ),
  ];
}

/// The folder a note with [folderId] effectively sits in: null (top level)
/// when the id names no existing folder.
String? effectiveNoteFolderId(String? folderId, Map<String, NoteFolder> byId) =>
    folderId != null && byId.containsKey(folderId) ? folderId : null;

/// [folderId] with its parent, as saved views and the folder filter read it:
/// a rule or filter on a parent also covers its subfolders.
Set<String> noteFolderAncestry(String? folderId, Map<String, NoteFolder> byId) {
  final id = effectiveNoteFolderId(folderId, byId);
  if (id == null) return const {};
  final parent = byId[id]!.parentId;
  return {id, if (parent != null && byId.containsKey(parent)) parent};
}

/// Whether a note in [noteFolderId] shows while [filterId] is the chosen
/// folder: the folder itself and its subfolders. A null filter shows all.
bool noteInFolder(
  String? noteFolderId,
  String? filterId,
  Map<String, NoteFolder> byId,
) =>
    filterId == null ||
    noteFolderAncestry(noteFolderId, byId).contains(filterId);

/// Number of [notes] per folder, a parent counting its subfolders' notes
/// too, as the tree announces it.
Map<String, int> noteCountsByFolder(
  Iterable<Note> notes,
  Map<String, NoteFolder> byId,
) {
  final counts = <String, int>{};
  for (final n in notes) {
    for (final id in noteFolderAncestry(n.folderId, byId)) {
      counts[id] = (counts[id] ?? 0) + 1;
    }
  }
  return counts;
}

/// Whether a new folder may go under [parentId]: the top level always, an
/// existing top-level folder too, a subfolder never (two levels at most).
bool canHoldSubfolder(String? parentId, Map<String, NoteFolder> byId) {
  if (parentId == null) return true;
  final parent = byId[parentId];
  return parent != null && parent.parentId == null;
}
