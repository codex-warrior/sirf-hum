/**
 * Environment identity for Cloud Functions.
 *
 * `SH_ENV` comes from `functions/.env.<alias>` at deploy time. At instance
 * start-up we verify it matches the project the code is actually running in,
 * so a mis-targeted deploy fails loudly instead of serving the wrong data.
 */
export const ENVIRONMENTS = ['development', 'staging', 'production'] as const;
export type Environment = (typeof ENVIRONMENTS)[number];

/** Primary region for all functions (D-016). Must match Firestore. */
export const REGION = 'asia-south1';

const PROJECT_FOR: Record<Environment, string> = {
  development: 'sirf-hum-dev',
  staging: 'sirf-hum-staging',
  production: 'sirf-hum-prod',
};

export function parseEnvironment(value: string | undefined): Environment {
  const match = ENVIRONMENTS.find((env) => env === value);
  if (match === undefined) {
    throw new Error(
      `SH_ENV must be one of ${ENVIRONMENTS.join(', ')}; got "${value ?? ''}".`,
    );
  }
  return match;
}

export function expectedProjectFor(env: Environment): string {
  return PROJECT_FOR[env];
}

/**
 * Throws unless `projectId` is the project assigned to `env`. The emulator
 * (`demo-*` projects) is always allowed so local runs need no real project.
 */
export function assertProjectMatches(
  env: Environment,
  projectId: string | undefined,
): void {
  if (projectId?.startsWith('demo-')) return;
  const expected = expectedProjectFor(env);
  if (projectId !== expected) {
    throw new Error(
      `Environment "${env}" must run in project "${expected}", not "${projectId ?? 'unknown'}".`,
    );
  }
}
