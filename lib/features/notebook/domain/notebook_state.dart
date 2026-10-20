import 'package:sirf_hum/security/notebook/notebook.dart';
import 'package:sirf_hum/security/notebook/notebook_service.dart';

/// What Future and Us show of the couple's notebook (D-121). A finite set of
/// states; no account, couple, conversation or device identifiers. Entries
/// carry only opaque handles that are never rendered. The only producer is
/// `NotebookController`.
sealed class NotebookState {
  const NotebookState();
}

enum NotebookUnavailableReason {
  /// No couple (or the session is still being established).
  notPaired,

  /// Web never holds private content (D-046).
  needsPhone,

  /// No notebook backend is wired in this build yet (D-121).
  notYetAvailable,
}

final class NotebookUnavailable extends NotebookState {
  const NotebookUnavailable(this.reason);

  final NotebookUnavailableReason reason;
}

/// Reading this phone's notebook.
final class NotebookLoading extends NotebookState {
  const NotebookLoading();
}

/// Why the newest changes might not be here.
enum NotebookNotice {
  /// The last check did not reach the server.
  offline,

  /// The two phones are not connected yet.
  connecting,
}

/// The notebook. Empty is a normal, honest state.
final class NotebookReady extends NotebookState {
  const NotebookReady({
    required this.snapshot,
    this.refreshing = false,
    this.notice,
  });

  final NotebookSnapshot snapshot;

  /// A check for changes is running; what is shown stays.
  final bool refreshing;
  final NotebookNotice? notice;

  List<NotebookEntry> get entries => snapshot.entries;
}

/// This phone is not a trusted device any more. Nothing private is shown
/// and nothing can be written.
final class NotebookBlocked extends NotebookState {
  const NotebookBlocked();
}

/// The notebook could not be read at all.
final class NotebookFailed extends NotebookState {
  const NotebookFailed(this.failure);

  /// Null for a local problem that is not a notebook category.
  final NotebookFailure? failure;
}
