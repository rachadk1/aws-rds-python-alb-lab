#!/usr/bin/env bash
# Stage 04B: all AWS provisioning and SQL execution is CloudFormation-managed.
# Etape 04B : provisionnement AWS et execution SQL pilotes par CloudFormation.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
LAB_REGION=us-east-2
LAB_SQL_STACK=lab6-sql-bootstrap
fail() { printf 'ERROR / ERREUR: %s\n' "$1" >&2; exit 1; }
[[ $# -eq 0 ]] || fail 'Usage: bash scripts/deploy-sql-bootstrap.sh'
command -v aws >/dev/null 2>&1 || fail 'AWS CLI is required / AWS CLI est requis.'
stack_output() {
  aws cloudformation describe-stacks --stack-name "$1" --region "$LAB_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue | [0]" --output text --no-cli-pager
}
stack_parameter() {
  aws cloudformation describe-stacks --stack-name lab6-ec2 --region "$LAB_REGION" \
    --query "Stacks[0].Parameters[?ParameterKey=='$1'].ParameterValue | [0]" --output text --no-cli-pager
}
for LAB_STACK in lab6-network lab6-security lab6-ec2 lab6-rds; do
  LAB_STATUS="$(aws cloudformation describe-stacks --stack-name "$LAB_STACK" --region "$LAB_REGION" \
    --query 'Stacks[0].StackStatus' --output text --no-cli-pager)"
  case "$LAB_STATUS" in
    CREATE_COMPLETE|UPDATE_COMPLETE|UPDATE_ROLLBACK_COMPLETE) ;;
    *) fail "Prerequisite stack not ready / stack requise non prete: $LAB_STACK ($LAB_STATUS)" ;;
  esac
done
[[ "$(stack_output lab6-network NatGatewayEnabled)" == true ]] || \
  fail 'Private servers need NAT for SSM and package installation / NAT requis pour SSM et les paquets prives.'
LAB_DB_STATUS="$(aws rds describe-db-instances --db-instance-identifier lab6-mysql --region "$LAB_REGION" \
  --query 'DBInstances[0].DBInstanceStatus' --output text --no-cli-pager)"
[[ "$LAB_DB_STATUS" == available ]] || fail 'RDS must be available / RDS doit etre disponible.'
LAB_MASTER_ARN="$(stack_output lab6-rds MasterSecretArn)"
LAB_ENDPOINT="$(stack_output lab6-rds DbEndpoint)"
LAB_BASTION_ID="$(stack_output lab6-ec2 BastionInstanceId)"
LAB_WEB_A_ID="$(stack_output lab6-ec2 WebAInstanceId)"
LAB_WEB_B_ID="$(stack_output lab6-ec2 WebBInstanceId)"
LAB_AMI_ID="$(stack_output lab6-ec2 AmiId)"
[[ "$LAB_MASTER_ARN" =~ ^arn:aws:secretsmanager:us-east-2:[0-9]{12}:secret:.+$ ]] || fail 'Invalid master secret identifier / identifiant du secret admin invalide.'
[[ "$LAB_ENDPOINT" =~ ^[a-zA-Z0-9.-]+\.us-east-2\.rds\.amazonaws\.com$ ]] || fail 'Invalid RDS endpoint / endpoint RDS invalide.'
[[ "$LAB_AMI_ID" =~ ^ami-([0-9a-f]{8}|[0-9a-f]{17})$ ]] || fail 'Invalid pinned AMI / AMI conservee invalide.'
for LAB_ID in "$LAB_BASTION_ID" "$LAB_WEB_A_ID" "$LAB_WEB_B_ID"; do
  [[ "$LAB_ID" =~ ^i-([0-9a-f]{8}|[0-9a-f]{17})$ ]] || fail 'Invalid instance output / sortie instance invalide.'
  LAB_STATE="$(aws ec2 describe-instances --instance-ids "$LAB_ID" --region "$LAB_REGION" \
    --query 'Reservations[0].Instances[0].State.Name' --output text --no-cli-pager)"
  LAB_IMAGE="$(aws ec2 describe-instances --instance-ids "$LAB_ID" --region "$LAB_REGION" \
    --query 'Reservations[0].Instances[0].ImageId' --output text --no-cli-pager)"
  [[ "$LAB_STATE" == running && "$LAB_IMAGE" == "$LAB_AMI_ID" ]] || \
    fail 'Instances must run the original AMI / instances requises en execution avec AMI originale.'
done
deploy_sql_stack() {
  aws cloudformation deploy --template-file cloudformation/04b-sql-bootstrap.yaml \
    --stack-name "$LAB_SQL_STACK" --capabilities CAPABILITY_IAM \
    --parameter-overrides MasterSecretArn="$LAB_MASTER_ARN" RdsEndpoint="$LAB_ENDPOINT" \
      BastionInstanceId="$LAB_BASTION_ID" WebAInstanceId="$LAB_WEB_A_ID" WebBInstanceId="$LAB_WEB_B_ID" RunSqlBootstrap="$1" \
    --tags Project=lab6 Purpose=Learning --region "$LAB_REGION" --no-fail-on-empty-changeset
}
aws cloudformation validate-template --template-body file://cloudformation/04b-sql-bootstrap.yaml \
  --query Description --output text --region "$LAB_REGION" --no-cli-pager
printf '1/4 Prepare IAM, SSM document and app secret / preparer IAM, document SSM et secret applicatif.\n'
deploy_sql_stack false
LAB_BASTION_PROFILE="$(stack_output "$LAB_SQL_STACK" BastionProfileName)"
LAB_WEB_PROFILE="$(stack_output "$LAB_SQL_STACK" WebProfileName)"
for LAB_PROFILE in "$LAB_BASTION_PROFILE" "$LAB_WEB_PROFILE"; do
  [[ "$LAB_PROFILE" =~ ^[a-zA-Z0-9+=,.@_-]{1,128}$ ]] || fail 'Invalid instance profile / profil instance invalide.'
done

printf '2/4 Attach profiles through EC2 CloudFormation stack / associer les profils via la stack EC2.\n'
if [[ "$(stack_parameter BastionInstanceProfileName)" != "$LAB_BASTION_PROFILE" || "$(stack_parameter WebInstanceProfileName)" != "$LAB_WEB_PROFILE" ]]; then
  LAB_CHANGESET="sql-profiles-$(date +%Y%m%d%H%M%S)"
  aws cloudformation create-change-set --stack-name lab6-ec2 --change-set-name "$LAB_CHANGESET" --change-set-type UPDATE \
    --template-body file://cloudformation/03-ec2.yaml \
    --parameters ParameterKey=ProjectName,UsePreviousValue=true ParameterKey=KeyName,UsePreviousValue=true \
      ParameterKey=VpcId,UsePreviousValue=true ParameterKey=BastionSubnetId,UsePreviousValue=true \
      ParameterKey=PrivateSubnetAId,UsePreviousValue=true ParameterKey=PrivateSubnetBId,UsePreviousValue=true \
      ParameterKey=BastionSecurityGroupId,UsePreviousValue=true ParameterKey=WebSecurityGroupId,UsePreviousValue=true \
      "ParameterKey=LatestAl2023Ami,ParameterValue=$LAB_AMI_ID" \
      "ParameterKey=BastionInstanceProfileName,ParameterValue=$LAB_BASTION_PROFILE" \
      "ParameterKey=WebInstanceProfileName,ParameterValue=$LAB_WEB_PROFILE" \
    --region "$LAB_REGION" --no-cli-pager
  aws cloudformation wait change-set-create-complete --stack-name lab6-ec2 --change-set-name "$LAB_CHANGESET" --region "$LAB_REGION"
  LAB_REPLACEMENTS="$(aws cloudformation describe-change-set --stack-name lab6-ec2 --change-set-name "$LAB_CHANGESET" \
    --query "Changes[?ResourceChange.ResourceType=='AWS::EC2::Instance' && ResourceChange.Replacement!='False']" \
    --output json --region "$LAB_REGION" --no-cli-pager)"
  [[ "$LAB_REPLACEMENTS" == '[]' ]] || fail "EC2 replacement blocked; inspect change set / remplacement EC2 bloque, examiner: $LAB_CHANGESET"
  aws cloudformation describe-change-set --stack-name lab6-ec2 --change-set-name "$LAB_CHANGESET" \
    --query 'Changes[].ResourceChange.{Resource:LogicalResourceId,Action:Action,Replacement:Replacement}' \
    --output table --region "$LAB_REGION" --no-cli-pager
  aws cloudformation execute-change-set --stack-name lab6-ec2 --change-set-name "$LAB_CHANGESET" --region "$LAB_REGION"
  aws cloudformation wait stack-update-complete --stack-name lab6-ec2 --region "$LAB_REGION"
fi

printf '3/4 Wait for three SSM agents / attendre les trois agents SSM (up to 10 min / jusqu a 10 min par instance).\n'
for LAB_ID in "$LAB_BASTION_ID" "$LAB_WEB_A_ID" "$LAB_WEB_B_ID"; do
  LAB_ONLINE=false
  for ((LAB_ATTEMPT=1; LAB_ATTEMPT<=60; LAB_ATTEMPT++)); do
    LAB_PING="$(aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$LAB_ID" \
      --query 'InstanceInformationList[0].PingStatus' --output text --region "$LAB_REGION" --no-cli-pager)"
    if [[ "$LAB_PING" == Online ]]; then LAB_ONLINE=true; break; fi
    if ((LAB_ATTEMPT % 6 == 0)); then printf 'Waiting / attente: %s (%s)\n' "$LAB_ID" "$LAB_PING"; fi
    sleep 10
  done
  [[ "$LAB_ONLINE" == true ]] || fail "SSM is not online; check role, agent and egress / verifier role, agent et sortie reseau: $LAB_ID"
  printf 'SSM Online: %s\n' "$LAB_ID"
done
printf '4/4 Initialize from bastion, then test from both web servers / initialiser puis tester depuis les deux serveurs web.\n'
deploy_sql_stack true
aws cloudformation describe-stacks --stack-name "$LAB_SQL_STACK" \
  --query 'Stacks[0].{Status:StackStatus,Outputs:Outputs}' --output table --region "$LAB_REGION" --no-cli-pager
bash scripts/show-sql-results.sh
