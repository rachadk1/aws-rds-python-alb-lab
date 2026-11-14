#!/usr/bin/env bash
# Deploy stage 02 from Git Bash / deployer l'etape 02 depuis Git Bash.
# Usage: bash scripts/deploy-security-groups.sh [network-stack-name]
# Optional override / remplacement optionnel: LAB_ADMIN_CIDR=203.0.113.10/32
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
LAB_REGION=us-east-2
LAB_NETWORK_STACK="${1:-lab6-network}"
LAB_SECURITY_STACK=lab6-security

fail() {
  printf 'ERROR / ERREUR: %s\n' "$1" >&2
  exit 1
}

[[ $# -le 1 ]] || fail 'Use zero or one network stack name / indiquer au plus un nom de stack reseau.'
command -v aws >/dev/null 2>&1 || fail 'AWS CLI is required / AWS CLI est requis.'
[[ "$LAB_NETWORK_STACK" =~ ^[a-zA-Z][a-zA-Z0-9-]{0,127}$ ]] || fail 'Invalid stack name / nom de stack invalide.'

# Read the deployed network before creating anything / lire le reseau avant toute creation.
if ! LAB_NETWORK_STATUS="$(aws cloudformation describe-stacks \
  --stack-name "$LAB_NETWORK_STACK" --region "$LAB_REGION" \
  --query 'Stacks[0].StackStatus' --output text --no-cli-pager)"; then
  fail 'Cannot read network stack. Check its exact name and AWS login / verifier le nom exact et la connexion AWS.'
fi
case "$LAB_NETWORK_STATUS" in
  CREATE_COMPLETE|UPDATE_COMPLETE|UPDATE_ROLLBACK_COMPLETE) ;;
  *) fail "Network stack is not ready / stack reseau non prete: $LAB_NETWORK_STATUS" ;;
esac

LAB_VPC_ID="$(aws cloudformation describe-stacks \
  --stack-name "$LAB_NETWORK_STACK" --region "$LAB_REGION" \
  --query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue | [0]' \
  --output text --no-cli-pager)"
[[ "$LAB_VPC_ID" =~ ^vpc-([0-9a-f]{8}|[0-9a-f]{17})$ ]] || fail 'VpcId output missing or invalid / sortie VpcId absente ou invalide.'

# No IP is committed; detect current public IPv4 / aucune IP dans Git, detection IPv4 actuelle.
if [[ -z "${LAB_ADMIN_CIDR:-}" ]]; then
  command -v curl >/dev/null 2>&1 || fail 'curl is required for IP detection / curl est requis pour detecter IP.'
  LAB_PUBLIC_IPV4="$(curl -4 --fail --silent --show-error \
    --connect-timeout 10 --max-time 20 https://checkip.amazonaws.com)"
  LAB_PUBLIC_IPV4="${LAB_PUBLIC_IPV4//$'\r'/}"
  LAB_ADMIN_CIDR="${LAB_PUBLIC_IPV4}/32"
fi
LAB_IPV4_OCTET='(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])'
[[ "$LAB_ADMIN_CIDR" =~ ^${LAB_IPV4_OCTET}\.${LAB_IPV4_OCTET}\.${LAB_IPV4_OCTET}\.${LAB_IPV4_OCTET}/32$ ]] || \
  fail 'Admin source must be one valid IPv4 /32 / la source admin doit etre une IPv4 valide en /32.'

printf 'Region: %s\nNetwork stack / stack reseau: %s\nVPC: %s\nSSH source: %s\n' \
  "$LAB_REGION" "$LAB_NETWORK_STACK" "$LAB_VPC_ID" "$LAB_ADMIN_CIDR"

aws cloudformation validate-template \
  --template-body file://cloudformation/02-security-groups.yaml \
  --query Description --output text --region "$LAB_REGION" --no-cli-pager

aws cloudformation deploy \
  --template-file cloudformation/02-security-groups.yaml \
  --stack-name "$LAB_SECURITY_STACK" \
  --parameter-overrides ProjectName=lab6 VpcId="$LAB_VPC_ID" AdminCidr="$LAB_ADMIN_CIDR" \
  --tags Project=lab6 Purpose=Learning \
  --region "$LAB_REGION" --no-fail-on-empty-changeset

aws cloudformation describe-stacks \
  --stack-name "$LAB_SECURITY_STACK" --region "$LAB_REGION" \
  --query 'Stacks[0].{Status:StackStatus,Outputs:Outputs}' \
  --output table --no-cli-pager

# Keep actual rules locally for review / conserver les regles reelles localement pour verification.
mkdir -p local
aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$LAB_VPC_ID" \
    'Name=group-name,Values=lab6-alb-sg,lab6-bastion-sg,lab6-web-sg,lab6-rds-sg' \
  --query 'SecurityGroups[].{Name:GroupName,Id:GroupId,Vpc:VpcId,Inbound:IpPermissions,Outbound:IpPermissionsEgress}' \
  --output json --region "$LAB_REGION" --no-cli-pager > local/security-group-rules.json

printf '\nRules saved locally / regles enregistrees localement: local/security-group-rules.json\n'
