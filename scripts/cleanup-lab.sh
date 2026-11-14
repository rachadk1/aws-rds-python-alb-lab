#!/usr/bin/env bash
# Delete the lab stacks from CloudFormation / Supprimer les stacks du lab depuis CloudFormation.
set -euo pipefail
export AWS_CLI_OUTPUT_ENCODING=UTF-8
export MSYS2_ARG_CONV_EXCL="arn:aws:cloudformation:${MSYS2_ARG_CONV_EXCL:+;$MSYS2_ARG_CONV_EXCL}"

fail() { printf 'ERROR / ERREUR: %s\n' "$1" >&2; exit 1; }
[[ $# -eq 0 || ( $# -eq 1 && "$1" == --delete ) ]] || fail 'Usage: bash scripts/cleanup-lab.sh [--delete]'
aws_lab() { aws "$@" --region us-east-2 --no-cli-pager; }
LAB_STACKS=(lab6-alb lab6-python lab6-ec2 lab6-sql-bootstrap lab6-rds lab6-security lab6-network)
LAB_STACK_IDS=()
LAB_ACCOUNT="$(aws_lab sts get-caller-identity --query Account --output text)"
[[ "$LAB_ACCOUNT" =~ ^[0-9]{12}$ ]] || fail 'Unable to verify the AWS account / compte AWS non vérifié.'
printf 'AWS account / Compte AWS: %s | us-east-2\n' "$LAB_ACCOUNT"

for LAB_STACK in "${LAB_STACKS[@]}"; do
  LAB_ID="$(aws_lab cloudformation list-stacks \
    --query "StackSummaries[?StackName=='$LAB_STACK' && StackStatus!='DELETE_COMPLETE'].StackId | [0]" \
    --output json)"
  if [[ "$LAB_ID" == null ]]; then
    LAB_STACK_IDS+=('')
    printf 'Absent / Absente: %s\n' "$LAB_STACK"
    continue
  fi
  LAB_ID="${LAB_ID%\"}"
  LAB_ID="${LAB_ID#\"}"
  [[ "$LAB_ID" == "arn:aws:cloudformation:us-east-2:$LAB_ACCOUNT:stack/$LAB_STACK/"* ]] || \
    fail "Unexpected stack ID / identifiant de stack inattendu: $LAB_STACK"
  LAB_STACK_IDS+=("$LAB_ID")
  printf 'Planned deletion / Suppression prévue: %s\n' "$LAB_STACK"
done

if [[ $# -eq 0 ]]; then
  printf '\nPreview only / Aperçu. To delete / Pour supprimer: bash scripts/cleanup-lab.sh --delete\n'
  exit 0
fi

printf '\nDeleting stacks and lab database / Suppression des stacks et de la base du lab.\n'
for index in "${!LAB_STACKS[@]}"; do
  LAB_STACK="${LAB_STACKS[$index]}"
  LAB_ID="${LAB_STACK_IDS[$index]}"
  [[ -n "$LAB_ID" ]] || continue
  printf '\nDeleting / Suppression: %s\n' "$LAB_STACK"
  aws_lab cloudformation delete-stack --stack-name "$LAB_ID"
  if ! aws_lab cloudformation wait stack-delete-complete --stack-name "$LAB_ID"; then
    aws_lab cloudformation describe-stack-events --stack-name "$LAB_ID" \
      --query 'StackEvents[?ResourceStatus==`DELETE_FAILED`].[LogicalResourceId,ResourceStatusReason] | [:8]' --output table
    fail "Deletion incomplete / suppression incomplète: $LAB_STACK"
  fi
  printf 'DELETE_COMPLETE: %s\n' "$LAB_STACK"
done

LAB_DB="$(aws_lab rds describe-db-instances \
  --query "DBInstances[?DBInstanceIdentifier=='lab6-mysql'].DBInstanceIdentifier" --output json)"
LAB_BACKUPS="$(aws_lab rds describe-db-instance-automated-backups \
  --query "DBInstanceAutomatedBackups[?DBInstanceIdentifier=='lab6-mysql'].DBInstanceAutomatedBackupsArn" --output json)"
LAB_SNAPSHOTS="$(aws_lab rds describe-db-snapshots --snapshot-type manual \
  --query "DBSnapshots[?DBInstanceIdentifier=='lab6-mysql'].DBSnapshotIdentifier" --output json)"
printf '\nRDS instances / Instances RDS: %s\nAutomated backups / Sauvegardes automatiques: %s\nManual snapshots / Snapshots manuels: %s\n' \
  "$LAB_DB" "$LAB_BACKUPS" "$LAB_SNAPSHOTS"
[[ "$LAB_DB" == '[]' && "$LAB_BACKUPS" == '[]' && "$LAB_SNAPSHOTS" == '[]' ]] || \
  fail 'Review remaining RDS resources / examiner les ressources RDS restantes.'
printf 'CLEANUP_OK region=us-east-2\n'
