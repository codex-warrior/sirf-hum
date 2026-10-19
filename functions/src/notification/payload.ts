/**
 * Content-free push payloads (Prompt 11, D-097;
 * docs/security/E2EE-MEDIA-AND-NOTIFICATIONS.md §8).
 *
 * FCM is outside the trust boundary. A push is a wake-up: the device syncs
 * and decrypts locally. Payloads are CONSTANT except for the device token
 * and the kind: no conversation, message, media, device or account IDs, no
 * names, counts, encrypted bodies or previews, no topics.
 */
import type { TokenMessage } from 'firebase-admin/messaging';

/**
 * `message`: something new from the partner (visible, generic text).
 * `sync`: silent wake-up (own device sent something, a commit, a revocation).
 */
export type PushKind = 'message' | 'sync';

export const NOTIFICATION_TITLE = 'Sirf Hum';
export const NOTIFICATION_BODY = 'You have a new message';

/** Wire value of the kind in `data.k`. */
export const KIND_CODES: Record<PushKind, string> = { message: 'm', sync: 's' };

const HOUR_MS = 60 * 60 * 1000;

/** The whole FCM message for one device token. Nothing else is ever sent. */
export function pushMessage(token: string, kind: PushKind): TokenMessage {
  const k = KIND_CODES[kind];
  if (kind === 'sync') {
    return {
      token,
      data: { v: '1', k },
      android: { priority: 'normal', collapseKey: `sh_${k}`, ttl: HOUR_MS },
    };
  }
  return {
    token,
    data: { v: '1', k },
    android: {
      priority: 'high',
      collapseKey: `sh_${k}`,
      ttl: 24 * HOUR_MS,
      notification: {
        title: NOTIFICATION_TITLE,
        body: NOTIFICATION_BODY,
        // One notification at a time: a new one replaces the old.
        tag: 'sh',
        // Hidden on a secure lock screen, although it is generic anyway.
        visibility: 'private',
      },
    },
  };
}
