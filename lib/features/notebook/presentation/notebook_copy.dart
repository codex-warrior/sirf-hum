import 'package:flutter/material.dart';
import 'package:sirf_hum/security/moments/moment_payload.dart';
import 'package:sirf_hum/security/notebook/notebook_payload.dart';
import 'package:sirf_hum/security/notebook/notebook_service.dart';

/// Human words for the notebook's fixed sets, shared by Future and Us.
extension FutureCategoryCopy on FutureCategory {
  /// A section heading.
  String get plural => switch (this) {
    FutureCategory.plan => 'Plans',
    FutureCategory.place => 'Places',
    FutureCategory.tryThing => 'Things to try',
    FutureCategory.importantDate => 'Important dates',
  };

  /// A choice in the editor.
  String get label => switch (this) {
    FutureCategory.plan => 'Plan',
    FutureCategory.place => 'Place',
    FutureCategory.tryThing => 'Something to try',
    FutureCategory.importantDate => 'Important date',
  };

  String get titleLabel => switch (this) {
    FutureCategory.plan => 'What do you want to do?',
    FutureCategory.place => 'Where do you want to go?',
    FutureCategory.tryThing => 'What do you want to try?',
    FutureCategory.importantDate => 'What’s the day?',
  };

  String get titleHint => switch (this) {
    FutureCategory.plan => 'A weekend in Udaipur',
    FutureCategory.place => 'Manali',
    FutureCategory.tryThing => 'That new café',
    FutureCategory.importantDate => 'Our anniversary',
  };

  IconData get icon => switch (this) {
    FutureCategory.plan => Icons.flag_outlined,
    FutureCategory.place => Icons.place_outlined,
    FutureCategory.tryThing => Icons.auto_awesome_outlined,
    FutureCategory.importantDate => Icons.event_outlined,
  };
}

extension LittleThingCopy on LittleThingKind {
  String get label => switch (this) {
    LittleThingKind.favouriteFood => 'Favourite food',
    LittleThingKind.comfortFood => 'Comfort food',
    LittleThingKind.favouriteMovie => 'Favourite movie',
    LittleThingKind.ourSong => 'Our song',
    LittleThingKind.favouritePlace => 'Favourite place',
    LittleThingKind.insideJoke => 'Inside joke',
    LittleThingKind.alwaysDo => 'Something we always do',
    LittleThingKind.other => 'Another little thing',
  };
}

/// A day as people read it, in the device's locale ("28 Oct 2026").
String formatDay(BuildContext context, MomentDate date) =>
    MaterialLocalizations.of(context).formatMediumDate(date.toLocal());

/// Human copy for a failed change. Every failure means nothing was changed
/// or shared (the service seals nothing it cannot send), so it says so.
String notebookFailureMessage(NotebookFailure? failure) => switch (failure) {
  NotebookFailure.missingTitle => 'Give it a name first.',
  NotebookFailure.titleTooLong ||
  NotebookFailure.noteTooLong ||
  NotebookFailure.detailTooLong =>
    'That’s a little long. Try something shorter.',
  NotebookFailure.invalidText => 'Some characters can’t be used here.',
  NotebookFailure.invalidDate => 'That day hasn’t happened yet.',
  NotebookFailure.limitReached =>
    'There’s no room for more here yet. Nothing was saved.',
  NotebookFailure.notFound =>
    'This was changed or removed on the other phone. Nothing was saved.',
  NotebookFailure.deviceNotTrusted =>
    'This phone can’t make changes any more. Nothing was saved.',
  NotebookFailure.notPaired =>
    'Saving needs your couple to be connected. Nothing was saved.',
  NotebookFailure.notReady =>
    'Your phones are still connecting. Try again in a moment. Nothing was '
        'saved.',
  NotebookFailure.outboxFull =>
    'A lot is still waiting to upload. Try again once you’re online. '
        'Nothing was saved.',
  NotebookFailure.unavailable =>
    'You seem to be offline, so this phone couldn’t check it’s still '
        'trusted. Nothing was saved. Try again when you’re online.',
  _ => 'That couldn’t be saved. Nothing was shared. Try again.',
};

String saveOutcomeMessage(NotebookSaveOutcome outcome) => switch (outcome) {
  NotebookSaveOutcome.saved => 'Saved. It’s here for both of you.',
  NotebookSaveOutcome.savedOnPhone =>
    'Saved on this phone. It will finish when you’re back online.',
};
