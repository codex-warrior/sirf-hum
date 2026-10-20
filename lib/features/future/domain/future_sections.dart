import 'package:sirf_hum/security/moments/moment_payload.dart';
import 'package:sirf_hum/security/notebook/notebook.dart';
import 'package:sirf_hum/security/notebook/notebook_payload.dart';

/// How Future files the couple's plans (D-120). Pure, so the rules are
/// testable without widgets:
///
/// - **Coming up:** plans with a day from today on, soonest first.
/// - **Plans / Places / Things to try:** the rest of what is still planned
///   — no date, or a day that has passed (never "missed") — newest first.
/// - **Important dates:** anniversaries, birthdays and other days, by day.
/// - **Done:** what you have done together, most recent first.
class FutureSections {
  FutureSections._(
    this.comingUp,
    this.byCategory,
    this.importantDates,
    this.done,
  );

  factory FutureSections.of(Iterable<NotebookEntry> entries, MomentDate today) {
    final comingUp = <NotebookEntry>[];
    final byCategory = {
      for (final c in FutureCategory.values)
        if (c != FutureCategory.importantDate) c: <NotebookEntry>[],
    };
    final dates = <NotebookEntry>[];
    final done = <NotebookEntry>[];
    for (final e in entries) {
      final category = e.futureCategory;
      if (category == null) continue;
      if (category == FutureCategory.importantDate) {
        dates.add(e);
      } else if (e.done) {
        done.add(e);
      } else if (e.date != null && e.date!.compareTo(today) >= 0) {
        comingUp.add(e);
      } else {
        byCategory[category]!.add(e);
      }
    }
    int newest(NotebookEntry a, NotebookEntry b) =>
        b.addedAt.compareTo(a.addedAt);
    int byDay(NotebookEntry a, NotebookEntry b) {
      final ad = a.date;
      final bd = b.date;
      if (ad == null || bd == null) {
        return ad == bd ? newest(a, b) : (ad == null ? 1 : -1);
      }
      final d = ad.compareTo(bd);
      return d != 0 ? d : a.addedAt.compareTo(b.addedAt);
    }

    comingUp.sort(byDay);
    dates.sort(byDay);
    done.sort((a, b) => b.changedAt.compareTo(a.changedAt));
    for (final list in byCategory.values) {
      list.sort(newest);
    }
    return FutureSections._(
      List.unmodifiable(comingUp),
      Map.unmodifiable({
        for (final MapEntry(:key, :value) in byCategory.entries)
          key: List<NotebookEntry>.unmodifiable(value),
      }),
      List.unmodifiable(dates),
      List.unmodifiable(done),
    );
  }

  final List<NotebookEntry> comingUp;

  /// Plans, places and things to try, in that order.
  final Map<FutureCategory, List<NotebookEntry>> byCategory;
  final List<NotebookEntry> importantDates;
  final List<NotebookEntry> done;

  bool get isEmpty =>
      comingUp.isEmpty &&
      importantDates.isEmpty &&
      done.isEmpty &&
      byCategory.values.every((l) => l.isEmpty);

  /// The soonest plan ahead, for Home.
  NotebookEntry? get next => comingUp.isEmpty ? null : comingUp.first;
}
