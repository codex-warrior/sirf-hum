#!/usr/bin/env bash
# Provisions ONE Sirf Hum Firebase environment. Safe to re-run: each step
# tolerates "already exists". Requires `firebase login` with an account
# allowed to create projects.
#
#   tool/provision_firebase.sh development|staging|production
#
# Does NOT link billing. Cloud Storage default buckets and Cloud Functions
# require the Blaze plan; see docs/architecture/DEVELOPMENT-ENVIRONMENT.md.
set -uo pipefail

case "${1:-}" in
  development) PROJECT=sirf-hum-dev;     NAME='Sirf Hum Development'; BUNDLE=com.sirfhum.app.dev ;;
  staging)     PROJECT=sirf-hum-staging; NAME='Sirf Hum Staging';     BUNDLE=com.sirfhum.app.staging ;;
  production)  PROJECT=sirf-hum-prod;    NAME='Sirf Hum Production';  BUNDLE=com.sirfhum.app ;;
  *) echo "usage: $0 development|staging|production" >&2; exit 2 ;;
esac
REGION=asia-south1

step() { printf '\n==> [%s] %s\n' "$PROJECT" "$1"; }
run() { "$@" 2>&1 | tail -n 4; }

step 'Create project'
run firebase projects:create "$PROJECT" --display-name "$NAME" --non-interactive

step 'Register Android app'
run firebase apps:create ANDROID "$NAME Android" --package-name "$BUNDLE" --project "$PROJECT" --non-interactive

step 'Register iOS app'
run firebase apps:create IOS "$NAME iOS" --bundle-id "$BUNDLE" --project "$PROJECT" --non-interactive

step 'Register Web app'
run firebase apps:create WEB "$NAME Web" --project "$PROJECT" --non-interactive

# Only APIs the architecture uses (docs/architecture/FIREBASE-ARCHITECTURE.md).
# None of these require billing. Auth sign-in providers are deliberately NOT
# enabled: an enabled provider lets anyone with the public API key create
# accounts. They are enabled in the identity phase.
step 'Enable required APIs (requires gcloud)'
run gcloud services enable \
  firestore.googleapis.com \
  firebaseappcheck.googleapis.com \
  identitytoolkit.googleapis.com \
  firebasecrashlytics.googleapis.com \
  fcm.googleapis.com \
  --project "$PROJECT"

step "Create Firestore (default) database in $REGION"
run firebase firestore:databases:create '(default)' --location "$REGION" --project "$PROJECT" --non-interactive

step 'Done. Apps registered:'
run firebase apps:list --project "$PROJECT" --non-interactive
