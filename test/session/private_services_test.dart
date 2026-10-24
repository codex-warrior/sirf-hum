import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/features/moments/application/moments_controller.dart';
import 'package:sirf_hum/features/moments/domain/moments_state.dart';
import 'package:sirf_hum/features/notebook/application/notebook_controller.dart';
import 'package:sirf_hum/features/notebook/domain/notebook_state.dart';
import 'package:sirf_hum/features/verification/application/verification_controller.dart';
import 'package:sirf_hum/features/verification/domain/verification_state.dart';
import 'package:sirf_hum/infrastructure/firebase/firestore_couple_conversation_locator.dart';
import 'package:sirf_hum/security/couple/pairing.dart';
import 'package:sirf_hum/session/private_services.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

import '../support/session_fakes.dart';

/// An opener the test drives. Opening real services needs the native core
/// (covered on device by the integration tests); here it never succeeds,
/// which is all the gating needs.
class _Opener implements PrivateServicesOpener {
  final requests = <Completer<PrivateServices>>[];
  final accounts = <AccountId>[];

  @override
  Future<PrivateServices> open(AccountId account) {
    accounts.add(account);
    final c = Completer<PrivateServices>();
    requests.add(c);
    return c.future;
  }
}

void main() {
  // The moments controller evicts decoded photos from the image cache.
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer container({
    PrivateServicesOpener? opener,
    PairingState answer = paired,
    bool privateContent = true,
  }) {
    final c = ProviderContainer(
      overrides: sessionOverrides(
        session: FakeAccountSession(alice),
        backend: FakePairingBackend.returning(answer),
        profiles: FakeCoupleProfiles(names),
        privateContent: privateContent,
        extra: [privateServicesOpenerProvider.overrideWithValue(opener)],
      ),
    );
    addTearDown(c.dispose);
    c
      ..listen(privateServicesStatusProvider, (_, _) {})
      ..listen(momentsProvider, (_, _) {})
      ..listen(notebookProvider, (_, _) {})
      ..listen(partnerVerificationProvider, (_, _) {});
    return c;
  }

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  group('status', () {
    test('no opener: nothing is wired and the features say so', () async {
      final c = container();
      await settle();
      expect(
        c.read(privateServicesStatusProvider),
        PrivateServicesStatus.notWired,
      );
      expect(c.read(momentsProvider), isA<MomentsUnavailable>());
      expect(c.read(notebookProvider), isA<NotebookUnavailable>());
      expect(
        c.read(partnerVerificationProvider),
        isA<VerificationUnavailable>(),
      );
    });

    test('not paired: the opener is never asked', () async {
      final opener = _Opener();
      final c = container(opener: opener, answer: const PairingNone());
      await settle();
      expect(opener.accounts, isEmpty);
      expect(
        c.read(privateServicesStatusProvider),
        PrivateServicesStatus.notWired,
      );
    });

    test('web: the opener is never asked', () async {
      final opener = _Opener();
      final c = container(opener: opener, privateContent: false);
      await settle();
      expect(opener.accounts, isEmpty);
      expect(
        c.read(privateServicesStatusProvider),
        PrivateServicesStatus.notWired,
      );
    });

    test('paired on a phone: opens for exactly the signed-in account, and '
        'the features load instead of saying "not yet"', () async {
      final opener = _Opener();
      final c = container(opener: opener);
      await settle();
      expect(opener.accounts, [alice]);
      expect(
        c.read(privateServicesStatusProvider),
        PrivateServicesStatus.starting,
      );
      expect(c.read(momentsProvider), isA<MomentsLoading>());
      expect(c.read(notebookProvider), isA<NotebookLoading>());
      expect(c.read(partnerVerificationProvider), isA<VerificationLoading>());
    });

    test('a failed open is a failure with a retry that opens again', () async {
      final opener = _Opener();
      final c = container(opener: opener);
      await settle();
      opener.requests.single.completeError(
        const PrivateServicesException(PrivateServicesProblem.unreadable),
      );
      await settle();
      expect(
        c.read(privateServicesStatusProvider),
        PrivateServicesStatus.failed,
      );
      expect(c.read(momentsProvider), isA<MomentsFailed>());
      expect(c.read(notebookProvider), isA<NotebookFailed>());
      expect(c.read(partnerVerificationProvider), isA<VerificationFailed>());
      expect(c.read(currentPrivateServicesProvider), isNull);

      c.read(momentsProvider.notifier).retry();
      await settle();
      expect(opener.accounts, [alice, alice]);
      expect(c.read(momentsProvider), isA<MomentsLoading>());
    });
  });

  group('couple record', () {
    const conversationHex = 'fedcba9876543210fedcba9876543210';

    test('reads the partner and the conversation', () {
      final couple = FirestoreCoupleConversationLocator.parse(alice, {
        'partnerAccountId': 'uidBob',
        'conversationId': conversationHex,
      });
      expect(couple?.partner.value, 'uidBob');
      expect(couple?.conversation.bytes.length, 16);
    });

    test('anything else is no couple', () {
      for (final data in <Map<String, dynamic>?>[
        null,
        {},
        {'partnerAccountId': 'uidBob'},
        {'conversationId': conversationHex},
        {'partnerAccountId': alice.value, 'conversationId': conversationHex},
        {'partnerAccountId': 'uid/Bob', 'conversationId': conversationHex},
        {'partnerAccountId': 'uidBob', 'conversationId': 'FEDCBA'},
        {'partnerAccountId': 7, 'conversationId': conversationHex},
      ]) {
        expect(
          FirestoreCoupleConversationLocator.parse(alice, data),
          isNull,
          reason: '$data',
        );
      }
    });
  });
}
