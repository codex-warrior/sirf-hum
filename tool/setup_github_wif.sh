#!/usr/bin/env bash
# Sets up GitHub Actions -> Google Cloud Workload Identity Federation for ONE
# environment. Idempotent. Requires gcloud authenticated as a project owner.
#
#   tool/setup_github_wif.sh development|staging|production
#
# Creates, in that environment's project only:
#   - service account  github-deployer@<project>.iam.gserviceaccount.com
#   - pool "github" with OIDC provider "sirf-hum" trusting GitHub's issuer,
#     restricted to this repository (by immutable numeric ID), the matching
#     GitHub Environment, and for production also refs/heads/main
#   - least-privilege deploy roles (no Owner/Editor); see ENVIRONMENTS.md
# No service-account keys are created.
set -euo pipefail

REPO_ID=1420599703      # codex-warrior/sirf-hum
OWNER_ID=148367546      # codex-warrior
POOL=github
PROVIDER=sirf-hum
SA_NAME=github-deployer

ENV="${1:-}"
case "$ENV" in
  development) PROJECT=sirf-hum-dev ;;
  staging)     PROJECT=sirf-hum-staging ;;
  production)  PROJECT=sirf-hum-prod ;;
  *) echo "usage: $0 development|staging|production" >&2; exit 2 ;;
esac

CONDITION="assertion.repository_id=='${REPO_ID}' && assertion.repository_owner_id=='${OWNER_ID}' && assertion.environment=='${ENV}'"
if [[ "$ENV" == production ]]; then
  CONDITION+=" && assertion.ref=='refs/heads/main'"
fi

# Deploy roles. Functions roles are added in the phase that deploys Functions.
ROLES=(
  roles/firebaserules.admin              # Firestore + Storage rules releases
  roles/datastore.indexAdmin             # Firestore indexes
  roles/firebasehosting.admin            # Hosting releases
  roles/serviceusage.serviceUsageConsumer # CLI API checks
  roles/serviceusage.serviceUsageViewer
)

step() { printf '\n==> [%s] %s\n' "$PROJECT" "$1"; }

NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
SA="${SA_NAME}@${PROJECT}.iam.gserviceaccount.com"

step 'Enable IAM / STS APIs'
gcloud services enable iam.googleapis.com iamcredentials.googleapis.com \
  sts.googleapis.com cloudresourcemanager.googleapis.com \
  firebaserules.googleapis.com firebasehosting.googleapis.com \
  --project "$PROJECT"

step "Service account $SA"
gcloud iam service-accounts describe "$SA" --project "$PROJECT" >/dev/null 2>&1 ||
  gcloud iam service-accounts create "$SA_NAME" --project "$PROJECT" \
    --display-name "GitHub Actions deployer (${ENV})" \
    --description "Deploys from codex-warrior/sirf-hum, GitHub Environment ${ENV}. No keys."

step 'Workload identity pool'
gcloud iam workload-identity-pools describe "$POOL" --location global --project "$PROJECT" >/dev/null 2>&1 ||
  gcloud iam workload-identity-pools create "$POOL" --location global --project "$PROJECT" \
    --display-name 'GitHub Actions'

step 'OIDC provider (repository + environment condition)'
PROVIDER_ARGS=(
  --location global --workload-identity-pool "$POOL" --project "$PROJECT"
  --attribute-mapping 'google.subject=assertion.sub,attribute.repository_id=assertion.repository_id,attribute.environment=assertion.environment,attribute.ref=assertion.ref'
  --attribute-condition "$CONDITION"
)
if gcloud iam workload-identity-pools providers describe "$PROVIDER" --location global \
    --workload-identity-pool "$POOL" --project "$PROJECT" >/dev/null 2>&1; then
  gcloud iam workload-identity-pools providers update-oidc "$PROVIDER" "${PROVIDER_ARGS[@]}"
else
  gcloud iam workload-identity-pools providers create-oidc "$PROVIDER" "${PROVIDER_ARGS[@]}" \
    --issuer-uri 'https://token.actions.githubusercontent.com' --display-name 'sirf-hum repo'
fi

step 'Allow only this environment to impersonate the service account'
gcloud iam service-accounts add-iam-policy-binding "$SA" --project "$PROJECT" \
  --role roles/iam.workloadIdentityUser \
  --member "principalSet://iam.googleapis.com/projects/${NUMBER}/locations/global/workloadIdentityPools/${POOL}/attribute.environment/${ENV}" \
  --condition None >/dev/null

step 'Grant deploy roles'
for role in "${ROLES[@]}"; do
  gcloud projects add-iam-policy-binding "$PROJECT" --member "serviceAccount:${SA}" \
    --role "$role" --condition None >/dev/null
  echo "  $role"
done

step 'GitHub Environment variables to set'
echo "GCP_WORKLOAD_IDENTITY_PROVIDER=projects/${NUMBER}/locations/global/workloadIdentityPools/${POOL}/providers/${PROVIDER}"
echo "GCP_DEPLOY_SERVICE_ACCOUNT=${SA}"
