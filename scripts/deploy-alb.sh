#!/usr/bin/env bash
# Deploy the load balancer through CloudFormation / Déployer l'ALB avec CloudFormation.
set -euo pipefail
export AWS_CLI_OUTPUT_ENCODING=UTF-8
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

LAB_REGION=us-east-2
LAB_STACK=lab6-alb
LAB_TEMPLATE=cloudformation/06-alb.yaml
fail() { printf 'ERROR / ERREUR: %s\n' "$1" >&2; exit 1; }
command -v aws >/dev/null || fail 'AWS CLI is required / AWS CLI est requis.'

aws_lab() { aws "$@" --region "$LAB_REGION" --no-cli-pager; }
stack_output() {
  local value
  value="$(aws_lab cloudformation describe-stacks --stack-name "$1" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue | [0]" --output text)"
  [[ -n "$value" && "$value" != None ]] || fail "Missing output / sortie absente: $1.$2"
  printf '%s\n' "$value"
}

LAB_VPC="$(stack_output lab6-network VpcId)"
LAB_SUBNET_A="$(stack_output lab6-network PublicSubnetAId)"
LAB_SUBNET_B="$(stack_output lab6-network PublicSubnetBId)"
LAB_ALB_SG="$(stack_output lab6-security AlbSecurityGroupId)"
LAB_WEB_A="$(stack_output lab6-ec2 WebAInstanceId)"
LAB_WEB_B="$(stack_output lab6-ec2 WebBInstanceId)"
LAB_PORT="$(stack_output lab6-python ApplicationPort)"
[[ "$LAB_VPC" == "$(stack_output lab6-security VpcId)" &&
   "$LAB_VPC" == "$(stack_output lab6-ec2 VpcId)" ]] || fail 'Expected one lab VPC / VPC commun requis.'

aws_lab cloudformation validate-template --template-body "file://$LAB_TEMPLATE" \
  --query Description --output text
aws_lab cloudformation deploy --template-file "$LAB_TEMPLATE" --stack-name "$LAB_STACK" \
  --parameter-overrides VpcId="$LAB_VPC" PublicSubnetAId="$LAB_SUBNET_A" PublicSubnetBId="$LAB_SUBNET_B" \
    AlbSecurityGroupId="$LAB_ALB_SG" WebAInstanceId="$LAB_WEB_A" WebBInstanceId="$LAB_WEB_B" ApplicationPort="$LAB_PORT" \
  --tags Project=lab6 Purpose=Learning --no-fail-on-empty-changeset

printf '\nApplication URL / URL de l’application: %s\n' "$(stack_output "$LAB_STACK" ApplicationUrl)"
printf 'Verify both targets / Vérifier les deux cibles: bash scripts/check-alb.sh\n'
