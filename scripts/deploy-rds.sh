#!/usr/bin/env bash
# Usage: bash scripts/deploy-rds.sh [NETWORK_STACK] [SECURITY_STACK]
# Optional explicit changes / changements explicites: LAB_DB_CLASS, LAB_MYSQL_VERSION.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
LAB_REGION=us-east-2
LAB_RDS_STACK=lab6-rds
LAB_NETWORK_STACK="${1:-lab6-network}"
LAB_SECURITY_STACK="${2:-lab6-security}"
fail() { printf 'ERROR / ERREUR: %s\n' "$1" >&2; exit 1; }
[[ $# -le 2 ]] || fail 'Use at most network and security stack names / indiquer au plus les noms des deux stacks requises.'
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
LAB_VPC_ID="$(stack_output "$LAB_NETWORK_STACK" VpcId)"
LAB_SECURITY_VPC="$(stack_output "$LAB_SECURITY_STACK" VpcId)"
[[ "$LAB_VPC_ID" =~ ^vpc-([0-9a-f]{8}|[0-9a-f]{17})$ && "$LAB_VPC_ID" == "$LAB_SECURITY_VPC" ]] || \
  fail 'Network and security must share the same VPC / reseau et securite doivent partager le meme VPC.'
LAB_PRIVATE_A="$(stack_output "$LAB_NETWORK_STACK" PrivateSubnetAId)"
LAB_PRIVATE_B="$(stack_output "$LAB_NETWORK_STACK" PrivateSubnetBId)"
LAB_AZ_A="$(stack_output "$LAB_NETWORK_STACK" AvailabilityZoneA)"
LAB_AZ_B="$(stack_output "$LAB_NETWORK_STACK" AvailabilityZoneB)"
LAB_RDS_SG="$(stack_output "$LAB_SECURITY_STACK" RdsSecurityGroupId)"
for LAB_SUBNET in "$LAB_PRIVATE_A" "$LAB_PRIVATE_B"; do
  [[ "$LAB_SUBNET" =~ ^subnet-([0-9a-f]{8}|[0-9a-f]{17})$ ]] || fail 'Missing private subnet output / sortie sous-reseau prive absente.'
done
[[ "$LAB_PRIVATE_A" != "$LAB_PRIVATE_B" ]] || fail 'Two distinct subnets required / deux sous-reseaux distincts requis.'
[[ "$LAB_AZ_A" =~ ^us-east-2[a-z]$ && "$LAB_AZ_B" =~ ^us-east-2[a-z]$ && "$LAB_AZ_A" != "$LAB_AZ_B" ]] || \
  fail 'Two distinct Ohio AZs required / deux AZ distinctes dans Ohio requises.'
[[ "$LAB_RDS_SG" =~ ^sg-([0-9a-f]{8}|[0-9a-f]{17})$ ]] || fail 'Invalid RDS group output / sortie groupe RDS invalide.'

# Keep existing version/class on repeat deployments / conserver version et classe lors des relances.
LAB_MATCH="$(aws cloudformation describe-stacks --region "$LAB_REGION" \
  --query "Stacks[?StackName=='$LAB_RDS_STACK'].StackName" --output json --no-cli-pager)"
if [[ "$LAB_MATCH" != '[]' ]]; then
  LAB_RDS_STATUS="$(aws cloudformation describe-stacks --stack-name "$LAB_RDS_STACK" \
    --query 'Stacks[0].StackStatus' --output text --region "$LAB_REGION" --no-cli-pager)"
  case "$LAB_RDS_STATUS" in
    CREATE_COMPLETE|UPDATE_COMPLETE|UPDATE_ROLLBACK_COMPLETE) ;;
    *) fail "Existing RDS stack requires investigation / stack RDS existante a examiner: $LAB_RDS_STATUS" ;;
  esac
  if [[ -z "${LAB_DB_CLASS:-}" ]]; then
    LAB_DB_CLASS="$(aws cloudformation describe-stacks --stack-name "$LAB_RDS_STACK" --region "$LAB_REGION" \
      --query 'Stacks[0].Parameters[?ParameterKey==`DbInstanceClass`].ParameterValue | [0]' --output text --no-cli-pager)"
  fi
  if [[ -z "${LAB_MYSQL_VERSION:-}" ]]; then
    LAB_MYSQL_VERSION="$(aws cloudformation describe-stacks --stack-name "$LAB_RDS_STACK" --region "$LAB_REGION" \
      --query 'Stacks[0].Parameters[?ParameterKey==`EngineVersion`].ParameterValue | [0]' --output text --no-cli-pager)"
  fi
fi
LAB_DB_CLASS="${LAB_DB_CLASS:-db.t4g.micro}"
[[ "$LAB_DB_CLASS" == db.t4g.micro || "$LAB_DB_CLASS" == db.t3.micro ]] || fail 'Only micro lab classes allowed / seules les classes micro du lab sont autorisees.'

# Ask AWS what is orderable now; do not guess a current patch / verifier les versions disponibles dans AWS.
LAB_QUERY="OrderableDBInstanceOptions[?starts_with(EngineVersion, '8.4.') && StorageType=='gp3' && SupportsStorageEncryption && MinStorageSize<=\`20\` && MaxStorageSize>=\`20\` && contains(AvailabilityZones[].Name, '$LAB_AZ_A')].EngineVersion"
LAB_OPTIONS="$(aws rds describe-orderable-db-instance-options --engine mysql --db-instance-class "$LAB_DB_CLASS" \
  --vpc --query "$LAB_QUERY" --output text --region "$LAB_REGION" --no-cli-pager)"
LAB_VERSIONS="$(printf '%s\n' "$LAB_OPTIONS" | tr '\t' '\n' | sort -Vu)"
if [[ -z "${LAB_MYSQL_VERSION:-}" ]]; then
  LAB_MYSQL_VERSION="$(printf '%s\n' "$LAB_VERSIONS" | tail -n 1)"
fi
[[ "$LAB_MYSQL_VERSION" =~ ^8\.4\.[0-9]+$ ]] || fail 'No compatible MySQL 8.4 patch found / aucune version MySQL 8.4 compatible trouvee.'
LAB_FOUND=false
while IFS= read -r LAB_VERSION; do
  if [[ "$LAB_VERSION" == "$LAB_MYSQL_VERSION" ]]; then LAB_FOUND=true; fi
done <<< "$LAB_VERSIONS"
[[ "$LAB_FOUND" == true ]] || fail 'Selected version/class/storage/AZ combination unavailable / combinaison version-classe-stockage-AZ indisponible.'

printf 'Region: %s\nVPC: %s\nMySQL: %s\nClass / classe: %s\nSingle-AZ: %s\n' \
  "$LAB_REGION" "$LAB_VPC_ID" "$LAB_MYSQL_VERSION" "$LAB_DB_CLASS" "$LAB_AZ_A"
printf 'Billable RDS, storage and managed secret / RDS, stockage et secret gere facturables.\n'
printf 'Lab cleanup policy: DELETE without final snapshot / nettoyage du lab: SUPPRESSION sans snapshot final.\n'
aws cloudformation validate-template --template-body file://cloudformation/04-rds.yaml \
  --query Description --output text --region "$LAB_REGION" --no-cli-pager
aws cloudformation deploy --template-file cloudformation/04-rds.yaml --stack-name "$LAB_RDS_STACK" \
  --parameter-overrides ProjectName=lab6 VpcId="$LAB_VPC_ID" PrivateSubnetAId="$LAB_PRIVATE_A" \
    PrivateSubnetBId="$LAB_PRIVATE_B" AvailabilityZoneA="$LAB_AZ_A" RdsSecurityGroupId="$LAB_RDS_SG" \
    EngineVersion="$LAB_MYSQL_VERSION" DbInstanceClass="$LAB_DB_CLASS" \
  --tags Project=lab6 Purpose=Learning --region "$LAB_REGION" --no-fail-on-empty-changeset

aws cloudformation describe-stacks --stack-name "$LAB_RDS_STACK" --region "$LAB_REGION" \
  --query 'Stacks[0].{Status:StackStatus,Outputs:Outputs}' --output table --no-cli-pager
aws rds describe-db-instances --db-instance-identifier lab6-mysql --region "$LAB_REGION" \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Engine:Engine,Version:EngineVersion,Class:DBInstanceClass,AZ:AvailabilityZone,MultiAZ:MultiAZ,Public:PubliclyAccessible,Encrypted:StorageEncrypted,StorageGiB:AllocatedStorage,StorageType:StorageType,BackupDays:BackupRetentionPeriod,Database:DBName,Vpc:DBSubnetGroup.VpcId,Endpoint:Endpoint.Address,Port:Endpoint.Port,SecretStatus:MasterUserSecret.SecretStatus}' \
  --output table --no-cli-pager
LAB_PARAMETER_GROUP="$(stack_output "$LAB_RDS_STACK" DbParameterGroupName)"
LAB_TLS="$(aws rds describe-db-parameters --db-parameter-group-name "$LAB_PARAMETER_GROUP" --region "$LAB_REGION" \
  --query 'Parameters[?ParameterName==`require_secure_transport`].ParameterValue | [0]' --output text --no-cli-pager)"
case "$LAB_TLS" in 1|ON|on) ;; *) fail "TLS requirement not confirmed / exigence TLS non confirmee: $LAB_TLS" ;; esac
printf 'require_secure_transport=%s\nSQL account and login tests remain / compte applicatif et tests SQL restent a realiser.\n' "$LAB_TLS"
mkdir -p local
aws cloudformation describe-stacks --stack-name "$LAB_RDS_STACK" --region "$LAB_REGION" \
  --query 'Stacks[0].Outputs' --output json --no-cli-pager > local/rds-outputs.json
