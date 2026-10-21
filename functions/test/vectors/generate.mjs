// Regenerates device_proof_v1.json, device_trust_v1.json, device_trust_v2.json commit_authorization_v1.json and lifecycle_authorization_v1.json. Deterministic (Ed25519 from fixed seeds):
// rerunning must produce the identical file; a test enforces that.
// Usage: npm run build && node test/vectors/generate.mjs
import { URL } from 'node:url';
import { writeFileSync } from 'node:fs';
import { commitAuthorizationVectors, goldenVector, lifecycleAuthorizationVectors, trustVectors, trustVectorsV2 } from '../support.mjs';

writeFileSync(
  new URL('./device_proof_v1.json', import.meta.url),
  `${JSON.stringify(goldenVector(), null, 2)}\n`,
);
writeFileSync(
  new URL('./device_trust_v1.json', import.meta.url),
  `${JSON.stringify(trustVectors(), null, 2)}
`,
);
writeFileSync(
  new URL('./device_trust_v2.json', import.meta.url),
  `${JSON.stringify(trustVectorsV2(), null, 2)}\n`,
);
writeFileSync(
  new URL('./commit_authorization_v1.json', import.meta.url),
  `${JSON.stringify(await commitAuthorizationVectors(), null, 2)}
`,
);
writeFileSync(
  new URL('./lifecycle_authorization_v1.json', import.meta.url),
  `${JSON.stringify(await lifecycleAuthorizationVectors(), null, 2)}
`,
);
