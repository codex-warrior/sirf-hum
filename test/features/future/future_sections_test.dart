import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/features/future/domain/future_sections.dart';
import 'package:sirf_hum/security/moments/moment_payload.dart';
import 'package:sirf_hum/security/notebook/notebook_payload.dart';

import '../../support/notebook_fakes.dart';

void main() {
  final today = MomentDate(2026, 10, 20);

  test('coming up: dated plans from today on, soonest first', () {
    final s = FutureSections.of([
      fakeEntry(1, plan('later', date: MomentDate(2026, 12, 1))),
      fakeEntry(2, plan('today', date: today)),
      fakeEntry(
        3,
        plan(
          'place soon',
          category: FutureCategory.place,
          date: MomentDate(2026, 11, 1),
        ),
      ),
    ], today);
    expect(s.comingUp.map((e) => e.title), ['today', 'place soon', 'later']);
    expect(s.next!.title, 'today');
  });

  test('a day that passed is never "missed": the plan stays with its kind', () {
    final s = FutureSections.of([
      fakeEntry(1, plan('last month', date: MomentDate(2026, 9, 1))),
      fakeEntry(2, plan('someday')),
    ], today);
    expect(s.comingUp, isEmpty);
    expect(s.next, isNull);
    expect(
      s.byCategory[FutureCategory.plan]!.map((e) => e.title),
      ['someday', 'last month'],
      reason: 'newest first',
    );
  });

  test('categories, important dates and done are filed apart', () {
    final s = FutureSections.of([
      fakeEntry(1, plan('Goa', category: FutureCategory.place)),
      fakeEntry(2, plan('Pottery', category: FutureCategory.tryThing)),
      fakeEntry(
        3,
        plan(
          'Anniversary',
          category: FutureCategory.importantDate,
          date: MomentDate(2027, 3, 12),
        ),
      ),
      fakeEntry(
        4,
        plan(
          'Birthday',
          category: FutureCategory.importantDate,
          date: MomentDate(2026, 11, 2),
        ),
      ),
      fakeEntry(5, plan('Manali', category: FutureCategory.place, done: true)),
    ], today);
    expect(s.byCategory[FutureCategory.place]!.single.title, 'Goa');
    expect(s.byCategory[FutureCategory.tryThing]!.single.title, 'Pottery');
    expect(s.importantDates.map((e) => e.title), ['Birthday', 'Anniversary']);
    expect(s.done.single.title, 'Manali');
    expect(s.comingUp, isEmpty, reason: 'important dates are not plans');
    expect(s.byCategory.keys, isNot(contains(FutureCategory.importantDate)));
  });

  test('empty is empty; other sections are ignored', () {
    expect(FutureSections.of(const [], today).isEmpty, isTrue);
    final ritual = NotebookFields(section: NotebookSection.ritual, title: 'x');
    expect(FutureSections.of([fakeEntry(1, ritual)], today).isEmpty, isTrue);
  });
}
