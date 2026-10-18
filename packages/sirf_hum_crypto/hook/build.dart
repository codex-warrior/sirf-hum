// Builds the Rust crypto core (native/) with cargo and bundles it as a code
// asset (D-063: hand-written C ABI + first-party Flutter/Dart native assets).
//
// Fails closed: a supported target that cannot be built fails the app build.
// Targets without a native crypto core (Windows, Web, unknown) emit no asset;
// the Dart API then reports the core as unavailable instead of degrading.
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

const _crate = 'sirf_hum_crypto';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;
    final triple = _rustTarget(code);
    if (triple == null) return;

    final native = input.packageRoot.resolve('native/');
    final targetDir = input.outputDirectoryShared.resolve('cargo/');
    // The hook runner passes only an allowlisted environment (PATH, HOME, …),
    // so RUSTFLAGS and friends from the developer's shell never reach cargo.
    final env = <String, String>{
      'CARGO_TARGET_DIR': targetDir.toFilePath(),
      ..._targetEnvironment(code, triple),
    };

    // --locked: Cargo.lock is authoritative (no silent dependency changes).
    // Release always: debug builds of the crypto stack are too slow on devices.
    final result = await Process.run(
      'cargo',
      ['build', '--locked', '--release', '--lib', '--target', triple],
      workingDirectory: native.toFilePath(),
      environment: env,
    );
    if (result.exitCode != 0) {
      throw Exception(
        'cargo build for $triple failed (${result.exitCode}):\n'
        '${result.stdout}\n${result.stderr}',
      );
    }

    final fileName = code.targetOS.dylibFileName(_crate);
    final built = targetDir.resolve('$triple/release/$fileName');
    final bundled = input.outputDirectory.resolve(fileName);
    await File.fromUri(built).copy(bundled.toFilePath());

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: _crate,
        linkMode: DynamicLoadingBundled(),
        file: bundled,
      ),
    );
    output.dependencies.addAll([
      native.resolve('Cargo.toml'),
      native.resolve('Cargo.lock'),
      native.resolve('rust-toolchain.toml'),
      ...Directory.fromUri(
        native.resolve('src/'),
      ).listSync(recursive: true).whereType<File>().map((f) => f.uri),
    ]);
  });
}

/// Rust target triple for the hook's target, or null where no native crypto
/// core is provided.
String? _rustTarget(CodeConfig code) {
  final arch = code.targetArchitecture;
  switch (code.targetOS) {
    case OS.android:
      return switch (arch) {
        Architecture.arm64 => 'aarch64-linux-android',
        Architecture.arm => 'armv7-linux-androideabi',
        Architecture.x64 => 'x86_64-linux-android',
        _ => throw UnsupportedError('Android $arch is not supported'),
      };
    case OS.iOS:
      final simulator = code.iOS.targetSdk == IOSSdk.iPhoneSimulator;
      return switch (arch) {
        Architecture.arm64 when simulator => 'aarch64-apple-ios-sim',
        Architecture.arm64 => 'aarch64-apple-ios',
        Architecture.x64 when simulator => 'x86_64-apple-ios',
        _ => throw UnsupportedError('iOS $arch is not supported'),
      };
    // Hosts for `dart test` / `flutter test` (CI runs Linux and macOS).
    case OS.linux when arch == Architecture.x64:
      return 'x86_64-unknown-linux-gnu';
    case OS.linux when arch == Architecture.arm64:
      return 'aarch64-unknown-linux-gnu';
    case OS.macOS when arch == Architecture.arm64:
      return 'aarch64-apple-darwin';
    case OS.macOS when arch == Architecture.x64:
      return 'x86_64-apple-darwin';
    default:
      return null;
  }
}

Map<String, String> _targetEnvironment(CodeConfig code, String triple) {
  final upper = triple.toUpperCase().replaceAll('-', '_');
  switch (code.targetOS) {
    case OS.android:
      final clang = code.cCompiler?.compiler;
      if (clang == null) {
        throw Exception('Android build needs the NDK C compiler from Flutter');
      }
      final api = code.android.targetNdkApi;
      final clangTriple = triple.replaceFirst('armv7-', 'armv7a-');
      // CARGO_ENCODED_RUSTFLAGS separates flags with 0x1f. 16 KB page
      // alignment is required for recent Android releases.
      return {
        'CARGO_TARGET_${upper}_LINKER': clang.toFilePath(),
        'CARGO_ENCODED_RUSTFLAGS': [
          '-Clink-arg=--target=$clangTriple$api',
          '-Clink-arg=-Wl,-z,max-page-size=16384',
        ].join('\x1f'),
      };
    case OS.iOS:
      return {'IPHONEOS_DEPLOYMENT_TARGET': '${code.iOS.targetVersion}'};
    case OS.macOS:
      return {'MACOSX_DEPLOYMENT_TARGET': '${code.macOS.targetVersion}'};
    default:
      return const {};
  }
}
