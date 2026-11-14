#!/usr/bin/env bash
# Check AWS target health and the public HTTP path / Vérifier les cibles et le chemin HTTP public.
set -euo pipefail
export AWS_CLI_OUTPUT_ENCODING=UTF-8

LAB_REGION=us-east-2
LAB_STACK=lab6-alb
fail() { printf 'ERROR / ERREUR: %s\n' "$1" >&2; exit 1; }
command -v aws >/dev/null || fail 'AWS CLI is required / AWS CLI est requis.'
command -v curl >/dev/null || fail 'curl is required / curl est requis.'

aws_lab() { aws "$@" --region "$LAB_REGION" --no-cli-pager; }
stack_output() {
  aws_lab cloudformation describe-stacks --stack-name "$1" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue | [0]" --output text
}
LAB_URL="$(stack_output "$LAB_STACK" ApplicationUrl)"
LAB_GROUP="$(stack_output "$LAB_STACK" TargetGroupArn)"
LAB_WEB_A="$(stack_output lab6-ec2 WebAInstanceId)"
LAB_WEB_B="$(stack_output lab6-ec2 WebBInstanceId)"
LAB_AZ_A="$(stack_output lab6-network AvailabilityZoneA)"
LAB_AZ_B="$(stack_output lab6-network AvailabilityZoneB)"
[[ "$LAB_URL" =~ ^http://[a-zA-Z0-9.-]+\.us-east-2\.elb\.amazonaws\.com$ &&
   "$LAB_GROUP" =~ ^arn:aws:elasticloadbalancing:us-east-2:[0-9]{12}:targetgroup/ &&
   "$LAB_WEB_A" =~ ^i-[0-9a-f]+$ && "$LAB_WEB_B" =~ ^i-[0-9a-f]+$ && "$LAB_WEB_A" != "$LAB_WEB_B" &&
   "$LAB_AZ_A" =~ ^us-east-2[a-z]$ && "$LAB_AZ_B" =~ ^us-east-2[a-z]$ && "$LAB_AZ_A" != "$LAB_AZ_B" ]] || \
  fail 'Unexpected stack outputs / sorties des stacks inattendues.'

LAB_TARGET_A="Id=$LAB_WEB_A,Port=8080"
LAB_TARGET_B="Id=$LAB_WEB_B,Port=8080"
printf 'Waiting for both targets / Attente des deux cibles (max. 10 min)\n'
LAB_HEALTHY=true
aws_lab elbv2 wait target-in-service --target-group-arn "$LAB_GROUP" \
  --targets "$LAB_TARGET_A" "$LAB_TARGET_B" || LAB_HEALTHY=false
aws_lab elbv2 describe-target-health --target-group-arn "$LAB_GROUP" \
  --targets "$LAB_TARGET_A" "$LAB_TARGET_B" \
  --query 'TargetHealthDescriptions[].{Instance:Target.Id,Port:Target.Port,State:TargetHealth.State,Reason:TargetHealth.Reason}' \
  --output table
[[ "$LAB_HEALTHY" == true ]] || fail 'Both targets must be healthy / les deux cibles doivent être healthy.'

LAB_CODE="$(curl --silent --show-error --max-time 15 --output /dev/null --write-out '%{http_code}' "$LAB_URL/")"
[[ "$LAB_CODE" == 200 ]] || fail "Home page / page d’accueil: HTTP $LAB_CODE"
printf '\n%s/ -> HTTP %s\n' "$LAB_URL" "$LAB_CODE"

LAB_A_COUNT=0
LAB_B_COUNT=0
LAB_PROBE_COUNT=20
for ((request=1; request<=LAB_PROBE_COUNT; request++)); do
  LAB_RESPONSE="$(curl --fail --silent --show-error --max-time 15 "$LAB_URL/health?strict=1")" || \
    fail "Readiness request failed / requête readiness en échec: $request"
  printf '%02d %s\n' "$request" "$LAB_RESPONSE"
  [[ "$LAB_RESPONSE" =~ \"db\"[[:space:]]*:[[:space:]]*\"reachable\" &&
     "$LAB_RESPONSE" =~ \"db_tls\"[[:space:]]*:[[:space:]]*\"[A-Za-z0-9_-]+\" &&
     "$LAB_RESPONSE" =~ \"students\"[[:space:]]*:[[:space:]]*[0-9]+ ]] || \
    fail 'Missing database readiness, TLS or student count / readiness RDS, TLS ou nombre d’élèves manquant.'
  [[ "$LAB_RESPONSE" =~ \"served_by\"[[:space:]]*:[[:space:]]*\"(i-[0-9a-f]+)\" ]] || \
    fail 'Missing instance ID / identifiant de l’instance absent.'
  LAB_SERVED_BY="${BASH_REMATCH[1]}"
  [[ "$LAB_RESPONSE" =~ \"az\"[[:space:]]*:[[:space:]]*\"(us-east-2[a-z])\" ]] || \
    fail 'Missing Availability Zone / zone de disponibilité absente.'
  case "$LAB_SERVED_BY:${BASH_REMATCH[1]}" in
    "$LAB_WEB_A:$LAB_AZ_A") LAB_A_COUNT=$((LAB_A_COUNT + 1)) ;;
    "$LAB_WEB_B:$LAB_AZ_B") LAB_B_COUNT=$((LAB_B_COUNT + 1)) ;;
    *) fail "Unexpected server or zone / serveur ou zone inattendus: $LAB_SERVED_BY ${BASH_REMATCH[1]}" ;;
  esac
done

printf '\nWebA (%s): %d | WebB (%s): %d\n' "$LAB_AZ_A" "$LAB_A_COUNT" "$LAB_AZ_B" "$LAB_B_COUNT"
((LAB_A_COUNT > 0 && LAB_B_COUNT > 0)) || fail 'Both instances must answer / les deux instances doivent répondre.'
printf 'ALB_OK url=%s requests=%d\n' "$LAB_URL" "$LAB_PROBE_COUNT"
