// Cross-checks every place an environment is wired, so a typo in one file
// (e.g. a staging alias pointing at the production project) fails CI.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/core/config/app_environment.dart';

const _appIds = {
  AppEnvironment.development: 'com.sirfhum.app.dev',
  AppEnvironment.staging: 'com.sirfhum.app.staging',
  AppEnvironment.production: 'com.sirfhum.app',
};

const _iosSchemes = {
  AppEnvironment.development: 'Development',
  AppEnvironment.staging: 'Staging',
  AppEnvironment.production: 'Production',
};

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('.firebaserc maps each alias and hosting target to its own project', () {
    final rc = jsonDecode(_read('.firebaserc')) as Map<String, dynamic>;
    final projects = rc['projects'] as Map<String, dynamic>;
    final targets = rc['targets'] as Map<String, dynamic>;

    expect(
      projects.containsKey('default'),
      isFalse,
      reason: 'A default project would make bare `firebase deploy` work.',
    );
    for (final env in AppEnvironment.values) {
      expect(projects[env.name], env.firebaseProjectId);
      final hosting =
          (targets[env.firebaseProjectId] as Map<String, dynamic>)['hosting']
              as Map<String, dynamic>;
      expect(hosting['app'], [env.firebaseProjectId]);
    }
  });

  test('client config examples name their own environment and project', () {
    for (final env in AppEnvironment.values) {
      final config =
          jsonDecode(_read('config/env/${env.name}.example.json'))
              as Map<String, dynamic>;
      expect(config['SH_ENV'], env.name);
      expect(config['SH_FIREBASE_PROJECT_ID'], env.firebaseProjectId);
      expect(config['SH_FIREBASE_IOS_BUNDLE_ID'], _appIds[env]);
      if (env.isProduction) {
        expect(config['SH_APPCHECK_PROVIDER'], 'attestation');
      }
    }
  });

  test('Functions .env files declare the matching environment', () {
    for (final env in AppEnvironment.values) {
      expect(
        _read('functions/.env.${env.name}'),
        contains('SH_ENV=${env.name}\n'),
      );
    }
  });

  test('Android flavors produce the expected application IDs', () {
    final gradle = _read('android/app/build.gradle.kts');
    expect(gradle, contains('applicationId = "com.sirfhum.app"'));
    expect(gradle, contains('namespace = "com.sirfhum.app"'));
    for (final env in AppEnvironment.values) {
      final block = RegExp(
        'create\\("${env.name}"\\) \\{(.*?)\\n        \\}',
        dotAll: true,
      ).firstMatch(gradle);
      expect(block, isNotNull, reason: 'missing flavor ${env.name}');
      final suffix = RegExp(
        r'applicationIdSuffix = "([^"]*)"',
      ).firstMatch(block!.group(1)!)?.group(1);
      expect('com.sirfhum.app${suffix ?? ''}', _appIds[env]);
    }
  });

  test('iOS configurations use the expected bundle IDs', () {
    final pbx = _read('ios/Runner.xcodeproj/project.pbxproj');
    for (final env in AppEnvironment.values) {
      final scheme = _iosSchemes[env]!;
      expect(
        File(
          'ios/Runner.xcodeproj/xcshareddata/xcschemes/$scheme.xcscheme',
        ).existsSync(),
        isTrue,
      );
      for (final mode in ['Debug', 'Release', 'Profile']) {
        final name = '$mode-$scheme';
        // The Runner target's block for this configuration.
        final block = RegExp(
          '/\\* $name \\*/ = \\{\\n\\t\\t\\tisa = XCBuildConfiguration;\\n'
          '\\t\\t\\tbaseConfigurationReference = [0-9A-F]+ /\\* $name\\.xcconfig'
          r' \*/;(.*?)name = "',
          dotAll: true,
        ).firstMatch(pbx);
        expect(block, isNotNull, reason: 'missing Runner config $name');
        expect(
          block!.group(1),
          contains('PRODUCT_BUNDLE_IDENTIFIER = ${_appIds[env]};'),
          reason: name,
        );
      }
    }
  });
}
