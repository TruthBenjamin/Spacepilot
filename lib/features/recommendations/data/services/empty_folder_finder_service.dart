import 'dart:io';

final class EmptyFolderFinderService {
  const EmptyFolderFinderService();

  Future<List<Directory>> findEmptyFolders(
    Iterable<Directory> roots, {
    bool recursive = true,
    bool followLinks = false,
  }) async {
    final emptyFolders = <Directory>[];

    for (final root in roots) {
      await _collectEmptyFolders(
        root,
        emptyFolders,
        recursive: recursive,
        followLinks: followLinks,
      );
    }

    emptyFolders.sort((a, b) => a.path.compareTo(b.path));
    return emptyFolders;
  }

  Future<bool> _collectEmptyFolders(
    Directory directory,
    List<Directory> emptyFolders, {
    required bool recursive,
    required bool followLinks,
  }) async {
    try {
      final type = await FileSystemEntity.type(
        directory.path,
        followLinks: followLinks,
      );
      if (type != FileSystemEntityType.directory) return false;

      var hasContents = false;
      await for (final entity in directory.list(followLinks: followLinks)) {
        hasContents = true;
        if (recursive && entity is Directory) {
          final childEmpty = await _collectEmptyFolders(
            entity,
            emptyFolders,
            recursive: recursive,
            followLinks: followLinks,
          );
          if (childEmpty) {
            hasContents = false;
          }
        }
      }

      if (!hasContents) {
        emptyFolders.add(directory);
        return true;
      }

      return false;
    } on FileSystemException {
      return false;
    }
  }
}
