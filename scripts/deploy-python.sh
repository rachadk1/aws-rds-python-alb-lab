#!/usr/bin/env bash
# Deploy the app and run local health checks via SSM / déployer et vérifier l'application avec SSM.
set -euo pipefail
umask 077
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

LAB_REGION=us-east-2
LAB_STACK=lab6-python
fail() { printf 'ERROR / ERREUR: %s\n' "$1" >&2; exit 1; }

[[ $# -eq 0 || ( $# -eq 1 && "$1" == --retry ) ]] || fail 'Usage: bash scripts/deploy-python.sh [--retry]'
for TOOL in aws tar base64 sha256sum sed tr; do
  command -v "$TOOL" >/dev/null || fail "Missing command / commande manquante: $TOOL"
done

stack_output() {
  aws cloudformation describe-stacks --stack-name "$1" --region "$LAB_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue | [0]" --output text --no-cli-pager
}

[[ "$(stack_output lab6-network NatGatewayEnabled)" == true ]] || fail 'NAT required for package downloads / NAT requis pour les paquets.'
LAB_DB_ID="$(stack_output lab6-rds DbInstanceIdentifier)"
LAB_DB_STATUS="$(aws rds describe-db-instances --db-instance-identifier "$LAB_DB_ID" --region "$LAB_REGION" \
  --query 'DBInstances[0].DBInstanceStatus' --output text --no-cli-pager)"
[[ "$LAB_DB_STATUS" == available ]] || fail 'RDS must be available / RDS doit être disponible.'
LAB_ENDPOINT="$(stack_output lab6-rds DbEndpoint)"
LAB_SECRET_ARN="$(stack_output lab6-sql-bootstrap AppSecretArn)"
LAB_WEB_A="$(stack_output lab6-ec2 WebAInstanceId)"
LAB_WEB_B="$(stack_output lab6-ec2 WebBInstanceId)"
[[ "$LAB_ENDPOINT" =~ ^[a-zA-Z0-9.-]+\.us-east-2\.rds\.amazonaws\.com$ ]] || fail 'Invalid RDS endpoint / endpoint RDS invalide.'
[[ "$LAB_SECRET_ARN" =~ ^arn:aws:secretsmanager:us-east-2:[0-9]{12}:secret:[a-zA-Z0-9/_+=.@-]+$ ]] || \
  fail 'Invalid application secret ARN / ARN du secret applicatif invalide.'
for LAB_ID in "$LAB_WEB_A" "$LAB_WEB_B"; do
  [[ "$LAB_ID" =~ ^i-([0-9a-f]{8}|[0-9a-f]{17})$ ]] || fail 'Invalid web instance / instance web invalide.'
  LAB_PING="$(aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$LAB_ID" \
    --query 'InstanceInformationList[0].PingStatus' --output text --region "$LAB_REGION" --no-cli-pager)"
  [[ "$LAB_PING" == Online ]] || fail "SSM is not online / SSM indisponible: $LAB_ID"
  printf 'SSM Online: %s\n' "$LAB_ID"
done
[[ "$LAB_WEB_A" != "$LAB_WEB_B" ]] || fail 'Expected two distinct web instances / deux instances distinctes requises.'

# Local render avoids an artifact bucket or a public download of the app.
# Le rendu local évite un bucket de déploiement et le téléchargement public de l'app.
LAB_TMP="$(mktemp -d)"
trap 'rm -rf -- "$LAB_TMP"' EXIT
tar --mtime=@0 --owner=0 --group=0 --mode=0644 -C app -czf "$LAB_TMP/application.tar.gz" install.sh labapp.py labapp.service requirements.txt templates/index.html
LAB_BUNDLE="$(base64 < "$LAB_TMP/application.tar.gz" | tr -d '\r\n')"
LAB_TEMPLATE="$LAB_TMP/05-python.yaml"
sed "s|__LAB_APP_BUNDLE__|$LAB_BUNDLE|" cloudformation/05-python.yaml > "$LAB_TEMPLATE"
[[ "$(wc -c < "$LAB_TEMPLATE")" -le 51200 ]] || fail 'Rendered template exceeds 51,200 bytes / template supérieur à 51 200 octets.'
LAB_REVISION="$( { cat "$LAB_TEMPLATE"; if [[ $# -eq 1 ]]; then date -u '+%Y%m%d%H%M%S'; fi; } | sha256sum )"
LAB_REVISION="${LAB_REVISION%% *}"
# file:// needs a Windows-native path with AWS CLI on Git Bash.
# file:// requiert un chemin Windows natif avec AWS CLI sous Git Bash.
LAB_AWS_PATH="$LAB_TEMPLATE"
if [[ -n "${MSYSTEM:-}" ]]; then
  LAB_AWS_PATH="$(cygpath -m "$LAB_TEMPLATE")"
  export MSYS2_ARG_CONV_EXCL='file://'
fi
aws cloudformation validate-template --template-body "file://$LAB_AWS_PATH" \
  --query Description --output text --region "$LAB_REGION" --no-cli-pager

aws cloudformation deploy --template-file "$LAB_AWS_PATH" --stack-name "$LAB_STACK" \
  --parameter-overrides RdsEndpoint="$LAB_ENDPOINT" AppSecretArn="$LAB_SECRET_ARN" \
    WebAInstanceId="$LAB_WEB_A" WebBInstanceId="$LAB_WEB_B" DeploymentRevision="$LAB_REVISION" \
  --tags Project=lab6 Purpose=Learning --region "$LAB_REGION" --no-fail-on-empty-changeset --no-cli-pager
bash scripts/show-python-results.sh
