# Analytics Policy

Status: **Policy established (Prompt 01). No analytics SDK is integrated.**

## Principle

Measure how the product is used, never what couples say or share.

## Allowed (behavioural) events — examples

```text
app_opened
together_started
call_started
moment_created
future_plan_created
feature_used
```

Events may carry coarse, non-content properties (platform, app version,
feature name, duration bucket, success/failure). Each new event is listed
in this document before it ships.

## Never collected

- Message contents, letter contents, captions, plan details
- Photo, video or voice contents (or derived data such as image labels)
- Keys, tokens, ciphertext
- Contact lists, precise location
- Free-text fields of any kind

…unless a future, explicitly reviewed feature requires it **and** the
privacy architecture permits it (Decision Log entry required).

## Rules

1. **Opt-in posture to be decided** with legal review; default to the most
   privacy-protective option allowed by product needs.
2. **Pseudonymous identifiers only.** No names, emails or phone numbers in
   analytics. Do not join analytics identity with the partner's identity
   unless needed for a reviewed couple-level metric.
3. **No advertising identifiers.** No ad SDKs; no sharing with ad networks.
4. **Vendor review.** The analytics vendor (Firebase Analytics or other)
   is chosen in a dedicated decision, with automatic collection reviewed
   (e.g. disable auto screen-view of routes that embed IDs).
5. **Retention limits** set at integration time.
6. **Event review** is part of the Definition of Done for every feature.
