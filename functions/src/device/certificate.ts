/**
 * Device certificate v1 (D-064), server-side decoder and verifier.
 *
 * Mirrors `DeviceCertificate::decode` / `verify_signature` in
 * packages/sirf_hum_crypto/native/src/identity.rs byte for byte. Encoding:
 *
 *   version u8 = 1 | u32 len | person key (32) | device id (16)
 *   | u32 len | device signature key (32) | issued-at u64 BE | u32 len | signature (64)
 *
 * The person key signs:
 *   "SirfHum-DeviceCertificate-v1" | version | u32 len | person key | device id
 *   | u32 len | device signature key | issued-at u64 BE
 *
 * Ed25519 (RFC 8032) via node:crypto; no primitive is implemented here.
 */
import { createPublicKey, verify, type KeyObject } from 'node:crypto';

export const MAX_CERTIFICATE_BYTES = 512;
export const DEVICE_ID_BYTES = 16;
const CERT_VERSION = 1;
const ED25519_PUBLIC_BYTES = 32;
const ED25519_SIGNATURE_BYTES = 64;
const CERT_CONTEXT = Buffer.from('SirfHum-DeviceCertificate-v1', 'ascii');
// DER SubjectPublicKeyInfo prefix for a raw Ed25519 key (RFC 8410).
const ED25519_SPKI_PREFIX = Buffer.from('302a300506032b6570032100', 'hex');

export interface DeviceCertificate {
  readonly personKey: Buffer;
  readonly deviceId: Buffer;
  readonly deviceSignatureKey: Buffer;
  readonly issuedAtUnix: bigint;
  readonly signature: Buffer;
}

/** Raised for any malformed or unauthentic certificate. Carries no bytes. */
export class InvalidCertificateError extends Error {
  constructor() {
    super('invalid_certificate');
  }
}

class Reader {
  private offset = 0;
  constructor(private readonly bytes: Buffer) {}

  u8(): number {
    return this.take(1).readUInt8(0);
  }

  fixed(length: number): Buffer {
    return this.take(length);
  }

  variable(): Buffer {
    const length = this.take(4).readUInt32BE(0);
    return this.take(length);
  }

  get done(): boolean {
    return this.offset === this.bytes.length;
  }

  private take(length: number): Buffer {
    if (this.offset + length > this.bytes.length) throw new InvalidCertificateError();
    const out = this.bytes.subarray(this.offset, this.offset + length);
    this.offset += length;
    return out;
  }
}

export function lengthPrefixed(value: Buffer): Buffer {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(value.length, 0);
  return Buffer.concat([length, value]);
}

/** Strict decoder: exact lengths, known version, no trailing bytes. */
export function decodeCertificate(bytes: Uint8Array): DeviceCertificate {
  if (bytes.length > MAX_CERTIFICATE_BYTES) throw new InvalidCertificateError();
  const reader = new Reader(Buffer.from(bytes));
  if (reader.u8() !== CERT_VERSION) throw new InvalidCertificateError();
  const personKey = reader.variable();
  const deviceId = reader.fixed(DEVICE_ID_BYTES);
  const deviceSignatureKey = reader.variable();
  const issuedAtUnix = reader.fixed(8).readBigUInt64BE(0);
  const signature = reader.variable();
  if (
    !reader.done ||
    personKey.length !== ED25519_PUBLIC_BYTES ||
    deviceSignatureKey.length !== ED25519_PUBLIC_BYTES ||
    signature.length !== ED25519_SIGNATURE_BYTES
  ) {
    throw new InvalidCertificateError();
  }
  return { personKey, deviceId, deviceSignatureKey, issuedAtUnix, signature };
}

export function certificateSignedPayload(cert: DeviceCertificate): Buffer {
  const issuedAt = Buffer.alloc(8);
  issuedAt.writeBigUInt64BE(cert.issuedAtUnix, 0);
  return Buffer.concat([
    CERT_CONTEXT,
    Buffer.from([CERT_VERSION]),
    lengthPrefixed(cert.personKey),
    cert.deviceId,
    lengthPrefixed(cert.deviceSignatureKey),
    issuedAt,
  ]);
}

export function ed25519PublicKey(raw: Buffer): KeyObject {
  if (raw.length !== ED25519_PUBLIC_BYTES) throw new InvalidCertificateError();
  return createPublicKey({
    key: Buffer.concat([ED25519_SPKI_PREFIX, raw]),
    format: 'der',
    type: 'spki',
  });
}

/** Ed25519 verification; false (never throws) for any bad input. */
export function ed25519Verify(publicKey: Buffer, message: Buffer, signature: Buffer): boolean {
  if (signature.length !== ED25519_SIGNATURE_BYTES) return false;
  try {
    return verify(null, message, ed25519PublicKey(publicKey), signature);
  } catch {
    return false;
  }
}

/** Decodes and checks the person-key signature. Throws on any failure. */
export function verifyCertificate(bytes: Uint8Array): DeviceCertificate {
  const cert = decodeCertificate(bytes);
  if (!ed25519Verify(cert.personKey, certificateSignedPayload(cert), cert.signature)) {
    throw new InvalidCertificateError();
  }
  return cert;
}
