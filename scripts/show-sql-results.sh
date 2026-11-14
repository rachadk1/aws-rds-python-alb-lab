#!/usr/bin/env bash
# Read CloudFormation-managed SSM execution logs / lire les journaux d'execution SSM.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
LAB_REGION=us-east-2
stack_output() {
  aws cloudformation describe-stacks --stack-name "$1" --region "$LAB_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue | [0]" --output text --no-cli-pager
}
for LAB_PAIR in InitializeAssociationId:BastionInstanceId WebAAssociationId:WebAInstanceId WebBAssociationId:WebBInstanceId; do
  LAB_ASSOCIATION="$(stack_output lab6-sql-bootstrap "${LAB_PAIR%%:*}")"
  LAB_INSTANCE="$(stack_output lab6-ec2 "${LAB_PAIR#*:}")"
  [[ "$LAB_ASSOCIATION" != None && -n "$LAB_ASSOCIATION" ]] || { printf 'Association missing / association absente: %s\n' "$LAB_PAIR" >&2; exit 1; }
  LAB_EXECUTION="$(aws ssm describe-association-executions --association-id "$LAB_ASSOCIATION" \
    --query 'AssociationExecutions[0].ExecutionId' --output text --region "$LAB_REGION" --no-cli-pager)"
  [[ "$LAB_EXECUTION" != None && -n "$LAB_EXECUTION" ]] || { printf 'Execution not yet available / execution pas encore disponible.\n' >&2; exit 1; }
  LAB_COMMAND="$(aws ssm describe-association-execution-targets --association-id "$LAB_ASSOCIATION" --execution-id "$LAB_EXECUTION" \
    --query 'AssociationExecutionTargets[0].OutputSource.OutputSourceId' --output text --region "$LAB_REGION" --no-cli-pager)"
  [[ "$LAB_COMMAND" != None && -n "$LAB_COMMAND" ]] || { printf 'Command output not yet available / sortie de commande pas encore disponible.\n' >&2; exit 1; }
  printf '\n%s\n' "$LAB_PAIR"
  aws ssm get-command-invocation --command-id "$LAB_COMMAND" --instance-id "$LAB_INSTANCE" \
    --query '{Status:Status,Output:StandardOutputContent,Errors:StandardErrorContent}' \
    --output yaml --region "$LAB_REGION" --no-cli-pager
  LAB_STATUS="$(aws ssm get-command-invocation --command-id "$LAB_COMMAND" --instance-id "$LAB_INSTANCE" \
    --query Status --output text --region "$LAB_REGION" --no-cli-pager)"
  [[ "$LAB_STATUS" == Success ]] || { printf 'SQL execution not successful / execution SQL non reussie: %s\n' "$LAB_STATUS" >&2; exit 1; }
done
