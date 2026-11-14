#!/usr/bin/env bash
# Usage: bash scripts/configure-ssh.sh /path/to/existing-private-key.pem
# Configuration stays in ignored local/; the key is never copied / la cle n'est jamais copiee.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
fail() { printf 'ERROR / ERREUR: %s\n' "$1" >&2; exit 1; }
[[ $# -eq 1 && -f "$1" ]] || fail 'Provide the existing private key file / indiquer le fichier de cle privee existant.'
command -v aws >/dev/null 2>&1 || fail 'AWS CLI is required / AWS CLI est requis.'
LAB_KEY_PATH="$(cd -- "$(dirname -- "$1")" && pwd -P)/$(basename -- "$1")"
if command -v cygpath >/dev/null 2>&1; then LAB_KEY_PATH="$(cygpath -m -- "$LAB_KEY_PATH")"; fi
[[ "$LAB_KEY_PATH" != *$'\n'* && "$LAB_KEY_PATH" != *$'\r'* && "$LAB_KEY_PATH" != *'"'* && "$LAB_KEY_PATH" != *'%'* ]] || \
  fail 'Unsupported characters in key path / caracteres non pris en charge dans le chemin de cle.'
LAB_REGION=us-east-2
instance_id() {
  aws cloudformation describe-stacks --stack-name lab6-ec2 --region "$LAB_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue | [0]" --output text --no-cli-pager
}
LAB_BASTION_ID="$(instance_id BastionInstanceId)"
LAB_WEB_A_ID="$(instance_id WebAInstanceId)"
LAB_WEB_B_ID="$(instance_id WebBInstanceId)"
for LAB_INSTANCE in "$LAB_BASTION_ID" "$LAB_WEB_A_ID" "$LAB_WEB_B_ID"; do
  [[ "$LAB_INSTANCE" =~ ^i-([0-9a-f]{8}|[0-9a-f]{17})$ ]] || fail 'Invalid instance output / sortie instance invalide.'
done
LAB_BASTION_IP="$(aws ec2 describe-instances --instance-ids "$LAB_BASTION_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text --region "$LAB_REGION" --no-cli-pager)"
LAB_WEB_A_IP="$(aws ec2 describe-instances --instance-ids "$LAB_WEB_A_ID" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text --region "$LAB_REGION" --no-cli-pager)"
LAB_WEB_B_IP="$(aws ec2 describe-instances --instance-ids "$LAB_WEB_B_ID" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text --region "$LAB_REGION" --no-cli-pager)"
LAB_OCTET='(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])'
for LAB_IP in "$LAB_BASTION_IP" "$LAB_WEB_A_IP" "$LAB_WEB_B_IP"; do
  [[ "$LAB_IP" =~ ^${LAB_OCTET}\.${LAB_OCTET}\.${LAB_OCTET}\.${LAB_OCTET}$ ]] || fail 'Missing or invalid instance IP / IP instance absente ou invalide.'
done
mkdir -p local
umask 077
cat > local/ssh_config <<EOF
# Generated locally / genere localement
Host lab6-bastion lab6-web-a lab6-web-b
    User ec2-user
    IdentityFile "$LAB_KEY_PATH"
    IdentitiesOnly yes
    ForwardAgent no
    StrictHostKeyChecking ask

Host lab6-bastion
    HostName $LAB_BASTION_IP

Host lab6-web-a
    HostName $LAB_WEB_A_IP
    ProxyJump lab6-bastion

Host lab6-web-b
    HostName $LAB_WEB_B_IP
    ProxyJump lab6-bastion
EOF
printf 'Ready / pret: ssh -F local/ssh_config lab6-bastion\n'
printf 'Private hosts / hotes prives: lab6-web-a, lab6-web-b\n'
