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
import 'package:sirf_hum/security/verification/partner_code_memory.dart';
import 'package:sirf_hum/security/verification/partner_verification.dart';
import 'package:sirf_hum/session/phone_setup.dart';
import 'package:sirf_hum/session/session_controller.dart';
import 'package:sirf_hum/session/session_state.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// The couple's private services on this phone: one device identity (the
/// platform key store, D-066), one conversation (D-086) and the features
/// that share it — Moments, the notebook (Future + Us) and partner
/// verification. Lives while the session is paired; closing it closes the
/// core.
///
/// Trust is WhatsApp-style (D-160): the partner's identity is trusted the
/// first time it is seen and again whenever it changes, and a change is
/// announced ("security code changed"). Comparing safety numbers stays
/// available, and only a comparison makes the partner "verified".
class PrivateServices {
  PrivateServices({
    required CryptoCore core,
    required this.messaging,
    required AccountId partner,
    required DeviceRegistry registry,
    PartnerCodeMemory? codes,
  }) : _core = core,
       _codes = codes ?? InMemoryPartnerCodeMemory(),
       moments = MomentsService(messaging: messaging),
       notebook = NotebookService(messaging: messaging) {
    _partnerTrust = PartnerVerificationService(
      core: core,
      account: messaging.account,
      partner: partner,
      registry: registry,
    );
    verification = _ConnectingVerification(_partnerTrust, this);
  }

  final CryptoCore _core;
  final PartnerCodeMemory _codes;
  final MessagingService messaging;
  final MomentsService moments;
  final NotebookService notebook;
  late final PartnerVerificationService _partnerTrust;
  late final PartnerVerificationBackend verification;

  /// Called when the partner's security code differs from the one this
  /// phone trusted before (a reinstall or a new phone on their side).
  void Function()? onPartnerCodeChanged;

  bool _closed = false;

  /// Trusts the partner as they are now (first use, or after their code
  /// changed), then joins or creates the couple's group and brings in
  /// newly trusted devices. Never throws: the features report their own
  /// state on their next refresh.
  Future<void> connect() async {
    if (_closed) return;
    try {
      await messaging.exclusive(_trustPartner);
      final report = await messaging.exclusive(messaging.connect);
      AppLogger.info(
        'private_services_connected',
        fields: {'epoch': report.epoch, 'joined': report.joined},
      );
    } on Object catch (e) {
      AppLogger.warning('private_services_connect_failed', error: e);
    }
  }

  /// Trust on first use (D-160). A partner who has no identity yet, or an
  /// identity that contradicts what this phone holds ("changed"), is left
  /// as it is: nothing is trusted that the core would refuse.
  Future<void> _trustPartner() async {
    PartnerVerification shown;
    try {
      shown = await _partnerTrust.load();
      if (shown.status == VerificationStatus.notVerified) {
        shown = await _partnerTrust.confirmCompared(shown);
      }
    } on VerificationException catch (e) {
      AppLogger.info(
        'partner_trust_skipped',
        fields: {'reason': SafeLogString(e.failure.name)},
      );
      return;
    }
    if (shown.status != VerificationStatus.verified) return;
    final before = await _codes.lastTrusted();
    if (before != null && before != shown.code) {
      AppLogger.info('partner_code_changed');
      onPartnerCodeChanged?.call();
    }
    await _codes.setLastTrusted(shown.code);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _core.close();
  }
}

/// What the safety-number page sees (D-128, D-160). The partner is trusted
/// automatically, but shown as "verified" only once the person compared
/// this exact code; a comparison is remembered on this phone. Every step
/// runs in the conversation's exclusive lane: trust never changes in the
/// middle of a sync.
class _ConnectingVerification implements PartnerVerificationBackend {
  _ConnectingVerification(this._inner, this._services);

  final PartnerVerificationBackend _inner;
  final PrivateServices _services;

  @override
  Future<PartnerVerification> load() async =>
      _asCompared(await _services.messaging.exclusive(_inner.load));

  @override
  Future<PartnerVerification> confirmCompared(PartnerVerification shown) =>
      _confirm(() => _inner.confirmCompared(shown));

  @override
  Future<PartnerVerification> confirmScanned(
    PartnerVerification shown,
    Uint8List scanned,
  ) => _confirm(() => _inner.confirmScanned(shown, scanned));

  Future<PartnerVerification> _confirm(
    Future<PartnerVerification> Function() action,
  ) async {
    final after = await _services.messaging.exclusive(action);
    if (after.status == VerificationStatus.verified) {
      await _services._codes.setCompared(after.code);
      unawaited(_services.connect());
    }
    return _asCompared(after);
  }

  Future<PartnerVerification> _asCompared(PartnerVerification v) async {
    if (v.status != VerificationStatus.verified) return v;
    return await _services._codes.compared() == v.code
        ? v
        : v.withStatus(VerificationStatus.notVerified);
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
    PhoneSetup Function(AccountId account)? setup,
    Future<PartnerCodeMemory> Function(AccountId account)? partnerCodes,
  }) : _identities = identities,
       _locator = locator,
       _registry = registry,
       _transport = transport,
       _storage = storage,
       _files = files,
       _mediaDirectory = mediaDirectory,
       _setup = setup,
       _partnerCodes = partnerCodes;

  final LocalDeviceIdentityService _identities;
  final CoupleConversationLocator _locator;
  final DeviceRegistry _registry;
  final ConversationTransport _transport;
  final MediaStorage _storage;
  final MediaFiles _files;
  final Future<String> Function(AccountId account) _mediaDirectory;
  final PhoneSetup Function(AccountId account)? _setup;
  final Future<PartnerCodeMemory> Function(AccountId account)? _partnerCodes;

  @override
  Future<PrivateServices> open(AccountId account) async {
    final couple = await _locator.locate(account);
    if (couple == null) {
      throw const PrivateServicesException(PrivateServicesProblem.notPaired);
    }
    var core = await _openIdentity(account);
    try {
      // Only an active device opens private services. A phone that is not
      // (reinstalled, data cleared) re-registers itself, WhatsApp-style
      // (D-160); only a configured wait leaves "Set up this phone".
      if (!await _isActive(account, core)) {
        core.close();
        await _registerAgain(account);
        core = await _openIdentity(account);
        if (!await _isActive(account, core)) {
          throw const PrivateServicesException(
            PrivateServicesProblem.needsSetup,
          );
        }
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
        codes: await _partnerCodes?.call(account),
      );
    } on Object {
      core.close();
      rethrow;
    }
  }

  Future<CryptoCore> _openIdentity(AccountId account) async {
    switch (await _identities.open(account)) {
      case LocalIdentityUnavailable():
        throw const PrivateServicesException(PrivateServicesProblem.needsPhone);
      case LocalIdentityCorrupted():
        throw const PrivateServicesException(PrivateServicesProblem.unreadable);
      case LocalIdentityReady(:final core):
        return core;
    }
  }

  Future<bool> _isActive(AccountId account, CryptoCore core) async =>
      await _registry.status(
        account,
        PendingDeviceRegistration.hexOf(core.publicIdentity().deviceId),
      ) ==
      DeviceStatus.active;

  /// Runs "set this phone up" by itself: register, re-register the account
  /// on this phone if it holds another identity, finish. Stops (leaving the
  /// page to the person) when a wait is configured or a step fails.
  Future<void> _registerAgain(AccountId account) async {
    final factory = _setup;
    if (factory == null) {
      throw const PrivateServicesException(PrivateServicesProblem.needsSetup);
    }
    final setup = factory(account);
    try {
      var step = await setup.check();
      if (step is PhoneSetupNeedsApproval) step = await setup.requestReset();
      if (step is PhoneSetupResetReady) step = await setup.finishReset();
      if (step is! PhoneSetupDone) {
        throw const PrivateServicesException(PrivateServicesProblem.needsSetup);
      }
      AppLogger.info(
        'phone_registered_again',
        fields: {'new_identity': step.newIdentity},
      );
    } on PhoneSetupException catch (e) {
      AppLogger.warning(
        'phone_register_again_failed',
        fields: {'reason': SafeLogString(e.failure.name)},
      );
      throw const PrivateServicesException(PrivateServicesProblem.needsSetup);
    } finally {
      setup.close();
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
  services.onPartnerCodeChanged = () {
    if (!disposed) ref.read(partnerCodeChangedProvider.notifier).changed();
  };
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

/// The partner's security code changed since this phone last trusted it
/// (D-160), until the person opens the safety-number page.
final partnerCodeChangedProvider = NotifierProvider<PartnerCodeChanged, bool>(
  PartnerCodeChanged.new,
);

class PartnerCodeChanged extends Notifier<bool> {
  @override
  bool build() {
    // A different session (account, couple) starts with nothing to say.
    ref.watch(sessionProvider.select((s) => s is SessionPaired));
    return false;
  }

  void changed() => state = true;

  void seen() => state = false;
}

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
