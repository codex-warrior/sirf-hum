/// What a couple can do in Together (D-111).
///
/// Every kind is listed so the hub can show what is coming, but only a kind
/// the backend reports as supported can ever be started. Call, Watch and
/// Listen need realtime media and their own security design (LiveKit token
/// minting, media E2EE), so no backend supports them yet.
enum TogetherActivity {
  /// Both of you, in the same moment: a shared, content-free session with a
  /// running clock. Proves the session flow without media or private content.
  timeTogether(
    label: 'Time together',
    description: 'Be together for a while, wherever you are.',
  ),
  call(label: 'Call', description: 'Hear each other.'),
  watch(label: 'Watch', description: 'Watch the same thing, together.'),
  listen(label: 'Listen', description: 'Listen to the same thing, together.');

  const TogetherActivity({required this.label, required this.description});

  final String label;
  final String description;
}
