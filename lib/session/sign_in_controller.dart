import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/core/logging/log_value.dart';
import 'package:sirf_hum/security/account/email_link_sign_in.dart';

/// Ports, overridden in `main.dart` for a configured Android build. The
/// defaults are those of a build that cannot sign in.
final emailLinkSignInProvider = Provider<EmailLinkSignIn>(
  (ref) => const UnavailableEmailLinkSignIn(),
);

/// The Hosting domain sign-in links open on (the Firebase auth domain);
/// null where sign-in is not offered.
final authLinkDomainProvider = Provider<String?>((ref) => null);

final signInProvider = NotifierProvider<SignInController, SignInState>(
  SignInController.new,
);

sealed class SignInState {
  const SignInState();
}

/// Asking for the address. [failure] explains the last attempt, if any.
class SignInEnterEmail extends SignInState {
  const SignInEnterEmail({this.failure});
  final EmailLinkFailure? failure;
}

class SignInSending extends SignInState {
  const SignInSending();
}

/// The link is on its way; waiting for it to come back (App Link or paste).
class SignInLinkSent extends SignInState {
  const SignInLinkSent({this.failure});
  final EmailLinkFailure? failure;
}

class SignInCompleting extends SignInState {
  const SignInCompleting();
}

/// A link arrived but this run of the app does not know the address (it was
/// restarted, or the link was opened on another phone): ask again (D-138).
class SignInNeedsEmail extends SignInState {
  const SignInNeedsEmail({this.failure});
  final EmailLinkFailure? failure;
}

/// The email-link round trip (D-138). Success is not a state here: the
/// account arrives through `AccountSession` and the session moves on.
///
/// The address lives only in this controller's memory until the link
/// returns; it is never persisted, logged or shown in an error.
class SignInController extends Notifier<SignInState> {
  String? _email;
  String? _pendingLink;

  @override
  SignInState build() => const SignInEnterEmail();

  Future<void> send(String input) async {
    final email = normalizeEmail(input);
    if (email == null) {
      state = const SignInEnterEmail(failure: EmailLinkFailure.invalidEmail);
      return;
    }
    state = const SignInSending();
    try {
      await ref.read(emailLinkSignInProvider).sendLink(email);
      _email = email;
      state = const SignInLinkSent();
      AppLogger.info('sign_in_link_sent');
    } on EmailLinkException catch (e) {
      state = SignInEnterEmail(failure: e.failure);
    }
  }

  /// A link from an App Link or pasted by the user. Anything that is not a
  /// sign-in link for this app's domain is refused locally.
  Future<void> receiveLink(String raw) async {
    final domain = ref.read(authLinkDomainProvider);
    final uri = Uri.tryParse(raw.trim());
    final link = (uri == null || domain == null)
        ? null
        : signInLinkFrom(uri, linkDomain: domain);
    if (link == null) {
      state = _email == null
          ? const SignInEnterEmail(failure: EmailLinkFailure.invalidLink)
          : const SignInLinkSent(failure: EmailLinkFailure.invalidLink);
      return;
    }
    final email = _email;
    if (email == null) {
      _pendingLink = link;
      state = const SignInNeedsEmail();
      return;
    }
    await _complete(email, link);
  }

  /// The address for a link that arrived without one ([SignInNeedsEmail]).
  Future<void> confirmEmail(String input) async {
    final link = _pendingLink;
    if (link == null) {
      state = const SignInEnterEmail();
      return;
    }
    final email = normalizeEmail(input);
    if (email == null) {
      state = const SignInNeedsEmail(failure: EmailLinkFailure.invalidEmail);
      return;
    }
    await _complete(email, link);
  }

  /// Back to the start (wrong address, or a fresh link is needed).
  void restart() {
    _email = null;
    _pendingLink = null;
    state = const SignInEnterEmail();
  }

  Future<void> _complete(String email, String link) async {
    state = const SignInCompleting();
    try {
      await ref
          .read(emailLinkSignInProvider)
          .completeSignIn(email: email, link: link);
      // Signed in: forget everything; the session takes over.
      _email = null;
      _pendingLink = null;
      // Ready for a later sign-out, which returns to this screen.
      state = const SignInEnterEmail();
      AppLogger.info('sign_in_completed');
    } on EmailLinkException catch (e) {
      AppLogger.info(
        'sign_in_link_refused',
        fields: {'failure': SafeLogString(e.failure.name)},
      );
      if (e.failure == EmailLinkFailure.emailMismatch) {
        _pendingLink = link;
        state = SignInNeedsEmail(failure: e.failure);
      } else {
        _pendingLink = null;
        state = _email == null
            ? SignInEnterEmail(failure: e.failure)
            : SignInLinkSent(failure: e.failure);
      }
    }
  }
}
