#!/usr/bin/env bash
# Simulate one unreachable target via CloudFormation / Simuler une cible inaccessible via CloudFormation.
set -euo pipefail
export AWS_CLI_OUTPUT_ENCODING=UTF-8
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

aws_lab() { aws "$@" --region us-east-2 --no-cli-pager; }
stack_output() {
  aws_lab cloudformation describe-stacks --stack-name "$1" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue | [0]" --output text
}
fail() { printf 'ERROR / ERREUR: %s\n' "$1" >&2; exit 1; }

LAB_GROUP="$(stack_output lab6-alb TargetGroupArn)"
LAB_URL="$(stack_output lab6-alb ApplicationUrl)"
LAB_WEB_A="$(stack_output lab6-ec2 WebAInstanceId)"
LAB_WEB_B="$(stack_output lab6-ec2 WebBInstanceId)"
[[ "$LAB_GROUP" =~ ^arn:aws:elasticloadbalancing:us-east-2:[0-9]{12}:targetgroup/ &&
   "$LAB_URL" =~ ^http://[a-zA-Z0-9.-]+\.us-east-2\.elb\.amazonaws\.com$ &&
   "$LAB_WEB_A" =~ ^i-[0-9a-f]+$ && "$LAB_WEB_B" =~ ^i-[0-9a-f]+$ && "$LAB_WEB_A" != "$LAB_WEB_B" ]] || \
  fail 'Unexpected lab stack outputs / sorties des stacks inattendues.'

target_state() {
  aws_lab elbv2 describe-target-health --target-group-arn "$LAB_GROUP" --targets "Id=$1,Port=$2" \
    --query 'TargetHealthDescriptions[0].TargetHealth.State' --output text
}
restore_alb() {
  local result=$?
  trap - EXIT
  if [[ "$LAB_RESTORE_NEEDED" == true ]]; then
    printf '\nRestoring both targets / Rétablissement des deux cibles sur 8080\n'
    if ! bash scripts/deploy-alb.sh; then
      printf 'Restoration failed. Retry: bash scripts/deploy-alb.sh\nRétablissement en échec. Relance cette commande.\n' >&2
      exit 1
    fi
  fi
  exit "$result"
}

printf 'Baseline / État initial\n'
bash scripts/check-alb.sh
LAB_RESTORE_NEEDED=true
trap restore_alb EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
bash scripts/deploy-alb.sh --simulate-web-a-failure

# Check the exact instance and port registered by the stack update.
# Vérifier l’instance et le port exacts enregistrés par la mise à jour.
LAB_FAILOVER_READY=false
for ((attempt=1; attempt<=24; attempt++)); do
  LAB_A_STATE="$(target_state "$LAB_WEB_A" 8081)"
  LAB_A_OLD_STATE="$(target_state "$LAB_WEB_A" 8080)"
  LAB_B_STATE="$(target_state "$LAB_WEB_B" 8080)"
  if [[ "$LAB_A_STATE" == unhealthy && "$LAB_B_STATE" == healthy &&
        ( "$LAB_A_OLD_STATE" == draining || "$LAB_A_OLD_STATE" == unused ) ]]; then
    LAB_FAILOVER_READY=true
    break
  fi
  sleep 5
done
printf 'WebA:8081 %s | WebA:8080 %s | WebB:8080 %s\n' "$LAB_A_STATE" "$LAB_A_OLD_STATE" "$LAB_B_STATE"
[[ "$LAB_FAILOVER_READY" == true ]] || fail 'Expected WebA unhealthy and WebB healthy / états attendus non atteints.'

for ((request=1; request<=10; request++)); do
  LAB_RESPONSE="$(curl --silent --show-error --max-time 15 --write-out $'\n%{http_code}' "$LAB_URL/health?strict=1")"
  LAB_CODE="${LAB_RESPONSE##*$'\n'}"
  LAB_BODY="${LAB_RESPONSE%$'\n'*}"
  [[ "$LAB_CODE" == 200 &&
     "$LAB_BODY" =~ \"served_by\"[[:space:]]*:[[:space:]]*\"$LAB_WEB_B\" &&
     "$LAB_BODY" =~ \"db_tls\"[[:space:]]*:[[:space:]]*\"[A-Za-z0-9_-]+\" ]] || \
    fail "Expected HTTP 200 from WebB with TLS / HTTP 200 de WebB avec TLS attendu: $request"
  printf '%02d HTTP %s %s\n' "$request" "$LAB_CODE" "$LAB_BODY"
done

bash scripts/deploy-alb.sh
LAB_RESTORE_NEEDED=false
bash scripts/check-alb.sh
printf 'FAILOVER_OK WebB=10/10 recovery=both-healthy\n'
