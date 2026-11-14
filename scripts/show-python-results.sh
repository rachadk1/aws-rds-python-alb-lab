#!/usr/bin/env bash
# Show the last deployment output for both instances / afficher le résultat sur les deux instances.
set -euo pipefail
export AWS_CLI_OUTPUT_ENCODING=UTF-8
LAB_REGION=us-east-2
aws_lab() { aws "$@" --region "$LAB_REGION" --no-cli-pager; }
stack_output() {
  aws_lab cloudformation describe-stacks --stack-name "$1" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue | [0]" --output text
}
LAB_SUCCESS=true
for LAB_WEB in WebA WebB; do
  LAB_INSTANCE="$(stack_output lab6-ec2 "${LAB_WEB}InstanceId")"
  LAB_ASSOCIATION="$(stack_output lab6-python "${LAB_WEB}AssociationId")"
  printf '\n%s (%s)\n' "$LAB_WEB" "$LAB_INSTANCE"
  LAB_EXECUTION="$(aws_lab ssm describe-association-executions --association-id "$LAB_ASSOCIATION" \
    --query 'AssociationExecutions[0].ExecutionId' --output text)"
  if [[ "$LAB_EXECUTION" == None || -z "$LAB_EXECUTION" ]]; then
    printf 'No SSM execution yet / aucune exécution SSM pour le moment.\n' >&2
    LAB_SUCCESS=false
    continue
  fi
  LAB_COMMAND="$(aws_lab ssm describe-association-execution-targets --association-id "$LAB_ASSOCIATION" \
    --execution-id "$LAB_EXECUTION" --query 'AssociationExecutionTargets[0].OutputSource.OutputSourceId' --output text)"
  if [[ "$LAB_COMMAND" == None || -z "$LAB_COMMAND" ]]; then
    printf 'SSM command output is pending / sortie de la commande SSM en attente.\n' >&2
    LAB_SUCCESS=false
    continue
  fi
  LAB_REPORT="$(aws_lab ssm get-command-invocation --command-id "$LAB_COMMAND" --instance-id "$LAB_INSTANCE" \
    --query '{Status:Status,Output:StandardOutputContent,Errors:StandardErrorContent}' --output yaml)"
  printf '%s\n' "$LAB_REPORT"
  if [[ "$LAB_REPORT" != *'Status: Success'* || "$LAB_REPORT" != *'APP_READY instance='* ]]; then
    LAB_SUCCESS=false
  fi
done
[[ "$LAB_SUCCESS" == true ]]
