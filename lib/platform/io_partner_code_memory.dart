import 'dart:io';

import 'package:sirf_hum/security/verification/partner_code_memory.dart';

/// [PartnerCodeMemory] as two small files in the account's slot directory
/// (backup-excluded, removed with the account).
class IoPartnerCodeMemory implements PartnerCodeMemory {
  IoPartnerCodeMemory(String slotDirectory)
    : _trusted = File('$slotDirectory/partner_code_trusted'),
      _compared = File('$slotDirectory/partner_code_compared');

  final File _trusted;
  final File _compared;

  static Future<String?> _read(File f) async {
    try {
      final value = (await f.readAsString()).trim();
      return value.isEmpty ? null : value;
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<String?> lastTrusted() => _read(_trusted);

  @override
  Future<void> setLastTrusted(String code) =>
      _trusted.writeAsString(code, flush: true);

  @override
  Future<String?> compared() => _read(_compared);

  @override
  Future<void> setCompared(String code) =>
      _compared.writeAsString(code, flush: true);
}
