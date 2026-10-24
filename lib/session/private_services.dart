import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/core/logging/log_value.dart';
import 'package:sirf_hum/security/couple/couple_conversation.dart';
import 'package:sirf_hum/security/device/device_registration.dart';
import 'package:sirf_hum/security/device/device_status.dart';
import 'package:sirf_hum/security/device/local_device_identity.dart';
import 'package:sirf_hum/security/media/media_storage.dart';
import 'package:sirf_hum/security/messaging/conversation_transport.dart';
import 'package:sirf_hum/security/messaging/messaging_service.dart';
import 'package:sirf_hum/security/moments/moments_service.dart';
import 'package:sirf_hum/security/notebook/notebook_service.dart';
import 'package:sirf_hum/security/verification/partner_verification.dart';
import 'package:sirf_hum/session/session_controller.dart';
import 'package:sirf_hum/session/session_state.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// The couple's private services on this phone: one device identity (the
/// platform key store, D-066), one conversation (D-086) and the features
/// that share it — Moments, the notebook (Future + Us) and partner
/// verification. Lives while the session is paired; closing it closes the
/// core.
class PrivateServices {
  PrivateServices({
    required CryptoCore core,
    required this.messaging,
    required AccountId partner,
    required DeviceRegistry registry,
  }) : _core = core,
       moments = MomentsService(messaging: messaging),
       notebook = NotebookService(messaging: messaging) {
    verification = _ConnectingVerification(
      PartnerVerificationService(
        core: core,
        account: messaging.account,
        partner: partner,
        registry: registry,
      ),
      this,
    );
  }

  final CryptoCore _core;
  final MessagingService messaging;
  final MomentsService moments;
  final NotebookService notebook;
  late final PartnerVerificationBackend verification;

  bool _closed = false;

  /// Joins (or creates) the couple's group when both sides have verified
  /// each other; otherwise just makes this phone reachable. Never throws:
  /// the features report their own state on their next refresh.
  Future<void> connect() async {
    if (_closed) return;
    try {
      final report = await messaging.exclusive(messaging.connect);
      AppLogger.info(
        'private_services_connected',
        fields: {'epoch': report.epoch, 'joined': report.joined},
      );
    } on Object catch (e) {
      AppLogger.warning('private_services_connect_failed', error: e);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _core.close();
  }
}

/// Verification that reconnects after trust changes, so the group forms as
/// soon as the second partner confirms the number. Every step runs in the
/// conversation's exclusive lane: trust never changes in the middle of a
/// sync.
class _ConnectingVerification implements PartnerVerificationBackend {
  _ConnectingVerification(this._inner, this._services);

  final PartnerVerificationBackend _inner;
  final PrivateServices _services;

  @override
  Future<PartnerVerification> load() =>
      _services.messaging.exclusive(_inner.load);

  @override
  Future<PartnerVerification> confirmCompared(PartnerVerification shown) =>
      _thenConnect(() => _inner.confirmCompared(shown));

  @override
  Future<PartnerVerification> confirmScanned(
    PartnerVerification shown,
    Uint8List scanned,
  ) => _thenConnect(() => _inner.confirmScanned(shown, scanned));

  Future<PartnerVerification> _thenConnect(
    Future<PartnerVerification> Function() action,
  ) async {
    final after = await _services.messaging.exclusive(action);
    if (after.status == VerificationStatus.verified) {
      unawaited(_services.connect());
    }
    return after;
  }
}

enum PrivateServicesProblem {
  /// The server has no couple conversation for this account.
  notPaired,

  /// This platform cannot hold the device identity.
  needsPhone,

  /// This phone's sealed state could not be opened.
  unreadable,

  /// This phone does not hold the account's trusted identity (reinstalled,
  /// data cleared, revoked): it must be set up again (D-159).
  needsSetup,
}

class PrivateServicesException implements Exception {
  const PrivateServicesException(this.problem);

  final PrivateServicesProblem problem;

  @override
  String toString() => 'PrivateServicesException(${problem.name})';
}

/// Opens the couple's private services for [account]. Throws
/// [PrivateServicesException] or a network/backend failure.
abstract interface class PrivateServicesOpener {
  Future<PrivateServices> open(AccountId account);
}

/// The production opener: the account's device identity from the platform
/// key store, the couple conversation the server provisioned, and ciphertext
/// transport, registry and media storage. Platform pieces come from the
/// composition root, so this stays free of Firebase and `dart:io`.
class LocalPrivateServicesOpener implements PrivateServicesOpener {
  LocalPrivateServicesOpener({
    required LocalDeviceIdentityService identities,
    required CoupleConversationLocator locator,
    required DeviceRegistry registry,
    required ConversationTransport transport,
    required MediaStorage storage,
    required MediaFiles files,
    required Future<String> Function(AccountId account) mediaDirectory,
  }) : _identities = identities,
       _locator = locator,
       _registry = registry,
       _transport = transport,
       _storage = storage,
       _files = files,
       _mediaDirectory = mediaDirectory;

  final LocalDeviceIdentityService _identities;
  final CoupleConversationLocator _locator;
  final DeviceRegistry _registry;
  final ConversationTransport _transport;
  final MediaStorage _storage;
  final MediaFiles _files;
  final Future<String> Function(AccountId account) _mediaDirectory;

  @override
  Future<PrivateServices> open(AccountId account) async {
    final couple = await _locator.locate(account);
    if (couple == null) {
      throw const PrivateServicesException(PrivateServicesProblem.notPaired);
    }
    final CryptoCore core;
    switch (await _identities.open(account)) {
      case LocalIdentityUnavailable():
        throw const PrivateServicesException(PrivateServicesProblem.needsPhone);
      case LocalIdentityCorrupted():
        throw const PrivateServicesException(PrivateServicesProblem.unreadable);
      case LocalIdentityReady(core: final ready):
        core = ready;
    }
    try {
      // Only an active device opens private services. Anything else is
      // "set this phone up again", never "you are no longer trusted".
      final own = PendingDeviceRegistration.hexOf(
        core.publicIdentity().deviceId,
      );
      if (await _registry.status(account, own) != DeviceStatus.active) {
        throw const PrivateServicesException(PrivateServicesProblem.needsSetup);
      }
      final messaging = MessagingService(
        core: core,
        account: account,
        conversation: couple.conversation,
        transport: _transport,
        registry: _registry,
        media: MediaSupport(
          storage: _storage,
          files: _files,
          directory: await _mediaDirectory(account),
        ),
      );
      return PrivateServices(
        core: core,
        messaging: messaging,
        partner: couple.partner,
        registry: _registry,
      );
    } on Object {
      core.close();
      rethrow;
    }
  }
}

/// `null` — builds without Firebase, web and tests — means nothing private
/// is wired, and the features say so.
final privateServicesOpenerProvider = Provider<PrivateServicesOpener?>(
  (ref) => null,
);

/// The couple's private services while the session is paired on a phone.
/// Any session change (sign-out, another account, unpairing) closes them.
/// A failed open is not retried by itself (a sealed state that cannot be
/// read will not heal): the features offer [retryPrivateServices].
final privateServicesProvider = FutureProvider<PrivateServices?>((ref) async {
  final paired = ref.watch(sessionProvider.select((s) => s is SessionPaired));
  if (!paired || !ref.watch(privateContentAvailableProvider)) return null;
  final opener = ref.watch(privateServicesOpenerProvider);
  if (opener == null) return null;

  // Registered before any await, so services opened after this build was
  // replaced are still closed.
  PrivateServices? opened;
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    opened?.close();
  });

  final account = await ref.read(accountSessionProvider).accountChanges.first;
  if (account == null || disposed) return null;
  final PrivateServices services;
  try {
    services = await opener.open(account);
  } on Object catch (e) {
    AppLogger.warning('private_services_open_failed', error: e);
    rethrow;
  }
  if (disposed) {
    services.close();
    return null;
  }
  opened = services;
  AppLogger.info(
    'private_services_opened',
    fields: {'state': const SafeLogString('ready')},
  );
  unawaited(services.connect());
  return services;
}, retry: (_, _) => null);

/// The services the features may use: only a settled, current value. While
/// [privateServicesProvider] reloads (another account, a retry) Riverpod
/// keeps the previous value, whose core is already closed — never handed
/// out.
final currentPrivateServicesProvider = Provider<PrivateServices?>((ref) {
  final services = ref.watch(privateServicesProvider);
  if (services.isLoading || services.hasError) return null;
  return services.value;
});

enum PrivateServicesStatus {
  /// Nothing private is wired here (web, no backend, not paired).
  notWired,

  /// Opening this phone's keys and finding the couple's conversation.
  starting,

  ready,

  /// Opening failed; [retryPrivateServices] starts over.
  failed,

  /// This phone must be set up again before anything private opens.
  needsSetup,
}

final privateServicesStatusProvider = Provider<PrivateServicesStatus>((ref) {
  final services = ref.watch(privateServicesProvider);
  // A retry keeps the previous error while it loads again.
  if (services.isLoading) return PrivateServicesStatus.starting;
  return switch (services) {
    AsyncData(value: null) => PrivateServicesStatus.notWired,
    AsyncData() => PrivateServicesStatus.ready,
    AsyncError(
      error: PrivateServicesException(
        problem: PrivateServicesProblem.needsSetup,
      ),
    ) =>
      PrivateServicesStatus.needsSetup,
    AsyncError() => PrivateServicesStatus.failed,
    _ => PrivateServicesStatus.starting,
  };
});

/// Starts opening the private services again after a failure.
void retryPrivateServices(Ref ref) => ref.invalidate(privateServicesProvider);
