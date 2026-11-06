#!/usr/bin/env bash
# Usage: bash scripts/deploy-ec2.sh KEY_NAME [NETWORK_STACK] [SECURITY_STACK]
# Reuse the first lab key / reutiliser la cle du premier lab.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
LAB_REGION=us-east-2
LAB_EC2_STACK=lab6-ec2
LAB_KEY_NAME="${1:-}"
LAB_NETWORK_STACK="${2:-lab6-network}"
LAB_SECURITY_STACK="${3:-lab6-security}"

fail() { printf 'ERROR / ERREUR: %s\n' "$1" >&2; exit 1; }
[[ $# -ge 1 && $# -le 3 && -n "$LAB_KEY_NAME" ]] || \
  fail 'Usage: bash scripts/deploy-ec2.sh KEY_NAME [NETWORK_STACK] [SECURITY_STACK]'
command -v aws >/dev/null 2>&1 || fail 'AWS CLI is required / AWS CLI est requis.'

stack_output() {
  aws cloudformation describe-stacks --stack-name "$1" --region "$LAB_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue | [0]" --output text --no-cli-pager
}
for LAB_STACK in "$LAB_NETWORK_STACK" "$LAB_SECURITY_STACK"; do
  LAB_STATUS="$(aws cloudformation describe-stacks --stack-name "$LAB_STACK" \
    --query 'Stacks[0].StackStatus' --output text --region "$LAB_REGION" --no-cli-pager)"
  case "$LAB_STATUS" in
    CREATE_COMPLETE|UPDATE_COMPLETE|UPDATE_ROLLBACK_COMPLETE) ;;
    *) fail "Prerequisite stack not ready / stack requise non prete: $LAB_STACK ($LAB_STATUS)" ;;
  esac
done

# Read-only check: never generate, replace or delete a key / verification sans modifier la cle.
if ! LAB_EXISTING_KEY="$(aws ec2 describe-key-pairs --key-names "$LAB_KEY_NAME" \
  --query 'KeyPairs[0].KeyName' --output text --region "$LAB_REGION" --no-cli-pager)"; then
  fail 'Existing key pair not found or inaccessible in Ohio / paire existante introuvable ou inaccessible dans Ohio.'
fi
[[ "$LAB_EXISTING_KEY" == "$LAB_KEY_NAME" ]] || fail 'Key name mismatch / nom de cle incoherent.'

LAB_VPC_ID="$(stack_output "$LAB_NETWORK_STACK" VpcId)"
LAB_SECURITY_VPC="$(stack_output "$LAB_SECURITY_STACK" VpcId)"
[[ "$LAB_VPC_ID" =~ ^vpc-([0-9a-f]{8}|[0-9a-f]{17})$ && "$LAB_VPC_ID" == "$LAB_SECURITY_VPC" ]] || \
  fail 'Network and security must use the same VPC / reseau et securite doivent utiliser le meme VPC.'
LAB_BASTION_SUBNET="$(stack_output "$LAB_NETWORK_STACK" BastionSubnetId)"
LAB_PRIVATE_A="$(stack_output "$LAB_NETWORK_STACK" PrivateSubnetAId)"
LAB_PRIVATE_B="$(stack_output "$LAB_NETWORK_STACK" PrivateSubnetBId)"
LAB_BASTION_SG="$(stack_output "$LAB_SECURITY_STACK" BastionSecurityGroupId)"
LAB_WEB_SG="$(stack_output "$LAB_SECURITY_STACK" WebSecurityGroupId)"
for LAB_SUBNET in "$LAB_BASTION_SUBNET" "$LAB_PRIVATE_A" "$LAB_PRIVATE_B"; do
  [[ "$LAB_SUBNET" =~ ^subnet-([0-9a-f]{8}|[0-9a-f]{17})$ ]] || fail 'Missing or invalid subnet output / sortie de sous-reseau absente ou invalide.'
done
[[ "$LAB_BASTION_SUBNET" != "$LAB_PRIVATE_A" && "$LAB_BASTION_SUBNET" != "$LAB_PRIVATE_B" && "$LAB_PRIVATE_A" != "$LAB_PRIVATE_B" ]] || \
  fail 'Three different subnets are required / trois sous-reseaux distincts sont requis.'
for LAB_SG in "$LAB_BASTION_SG" "$LAB_WEB_SG"; do
  [[ "$LAB_SG" =~ ^sg-([0-9a-f]{8}|[0-9a-f]{17})$ ]] || fail 'Missing or invalid security group output / sortie de groupe absente ou invalide.'
done

printf 'Region: %s\nVPC: %s\nExisting key / cle existante: %s\nStack: %s\n' \
  "$LAB_REGION" "$LAB_VPC_ID" "$LAB_KEY_NAME" "$LAB_EC2_STACK"
printf 'Creating 3 billable EC2 instances with EBS / creation de 3 EC2 avec disques EBS facturables.\n'
aws cloudformation validate-template --template-body file://cloudformation/03-ec2.yaml \
  --query Description --output text --region "$LAB_REGION" --no-cli-pager
aws cloudformation deploy --template-file cloudformation/03-ec2.yaml \
  --stack-name "$LAB_EC2_STACK" \
  --parameter-overrides ProjectName=lab6 KeyName="$LAB_KEY_NAME" VpcId="$LAB_VPC_ID" \
    BastionSubnetId="$LAB_BASTION_SUBNET" PrivateSubnetAId="$LAB_PRIVATE_A" PrivateSubnetBId="$LAB_PRIVATE_B" \
    BastionSecurityGroupId="$LAB_BASTION_SG" WebSecurityGroupId="$LAB_WEB_SG" \
  --tags Project=lab6 Purpose=Learning --region "$LAB_REGION" --no-fail-on-empty-changeset

LAB_BASTION_ID="$(stack_output "$LAB_EC2_STACK" BastionInstanceId)"
LAB_WEB_A_ID="$(stack_output "$LAB_EC2_STACK" WebAInstanceId)"
LAB_WEB_B_ID="$(stack_output "$LAB_EC2_STACK" WebBInstanceId)"
for LAB_INSTANCE in "$LAB_BASTION_ID" "$LAB_WEB_A_ID" "$LAB_WEB_B_ID"; do
  [[ "$LAB_INSTANCE" =~ ^i-([0-9a-f]{8}|[0-9a-f]{17})$ ]] || fail 'Invalid instance output / sortie instance invalide.'
done
printf 'Waiting for EC2 status checks / attente des controles EC2...\n'
aws ec2 wait instance-status-ok --instance-ids "$LAB_BASTION_ID" "$LAB_WEB_A_ID" "$LAB_WEB_B_ID" --region "$LAB_REGION"
aws cloudformation describe-stacks --stack-name "$LAB_EC2_STACK" \
  --query 'Stacks[0].{Status:StackStatus,Outputs:Outputs}' --output table --region "$LAB_REGION" --no-cli-pager
aws ec2 describe-instances --instance-ids "$LAB_BASTION_ID" "$LAB_WEB_A_ID" "$LAB_WEB_B_ID" \
  --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],Id:InstanceId,State:State.Name,AZ:Placement.AvailabilityZone,PrivateIP:PrivateIpAddress,PublicIP:PublicIpAddress,Key:KeyName}' \
  --output table --region "$LAB_REGION" --no-cli-pager
printf 'EC2 checks passed; SSH still to test / controles EC2 reussis ; SSH reste a tester.\n'
