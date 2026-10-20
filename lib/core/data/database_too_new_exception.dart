/// Thrown when a database file was written by a newer app version than this
/// build supports (see HistoryDatabase.migration).
library;

/// The file was written by a newer app version than this build supports. It is
/// not opened, so nothing in it is changed or lost.
class DatabaseTooNewException implements Exception {
  const DatabaseTooNewException({
    required this.storedVersion,
    required this.supportedVersion,
  });

  final int storedVersion;
  final int supportedVersion;

  @override
  String toString() =>
      'DatabaseTooNewException: the database is schema version $storedVersion, '
      'this build supports up to $supportedVersion. Update WhisPaste to open it.';
}
