#!/usr/bin/env bash
set -euo pipefail
umask 077
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

LAB_ROOT=/opt/lab6-app
LAB_UNIT=/etc/systemd/system/labapp.service
LAB_RELEASE=
LAB_PREVIOUS=
LAB_SWITCHED=false
LAB_READY=false
LAB_STEP=dependencies

cleanup() {
  local status=$?
  if [[ "$LAB_READY" != true ]]; then
    printf 'APP_DEPLOY_FAILED step=%s / Echec du deploiement\n' "$LAB_STEP" >&2
    if [[ "$LAB_SWITCHED" == true ]]; then
      if [[ -n "$LAB_PREVIOUS" ]]; then
        ln -sfnT "$LAB_PREVIOUS" "$LAB_ROOT/current"
        install -m 0644 "$LAB_PREVIOUS/labapp.service" "$LAB_UNIT"
        systemctl daemon-reload
        systemctl restart labapp.service || true
      else
        systemctl disable --now labapp.service 2>/dev/null || true
        rm -f "$LAB_ROOT/current" "$LAB_UNIT"
        systemctl daemon-reload
      fi
    fi
    if [[ -n "$LAB_RELEASE" ]]; then rm -rf -- "$LAB_RELEASE"; fi
  fi
  exit "$status"
}
trap cleanup EXIT

dnf -y install python3.11 python3.11-pip > /var/log/lab6-app-packages.log 2>&1
getent group labapp >/dev/null || groupadd --system labapp
id labapp >/dev/null 2>&1 || useradd --system --gid labapp --no-create-home --shell /sbin/nologin labapp
install -d -m 0755 "$LAB_ROOT"
exec 9>"$LAB_ROOT/install.lock"
flock -w 60 9
LAB_PREVIOUS="$(readlink "$LAB_ROOT/current" || true)"
LAB_RELEASE="$(mktemp -d "$LAB_ROOT/release.XXXXXXXX")"
chmod 0755 "$LAB_RELEASE"
install -d -m 0755 "$LAB_RELEASE/templates"
install -m 0644 labapp.py requirements.txt labapp.service "$LAB_RELEASE/"
install -m 0644 templates/index.html "$LAB_RELEASE/templates/"
(
  # These files contain only executable code and package data.
  # Ces fichiers contiennent uniquement du code et ses dépendances.
  umask 022
  python3.11 -m venv "$LAB_RELEASE/venv"
  "$LAB_RELEASE/venv/bin/python" -m pip install --no-input --disable-pip-version-check -r requirements.txt \
    >> /var/log/lab6-app-packages.log 2>&1
)

LAB_STEP=tls_certificate
curl --fail --silent --show-error --retry 3 --connect-timeout 10 --max-time 60   https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o "$LAB_RELEASE/rds-ca.pem"
chmod 0644 "$LAB_RELEASE/rds-ca.pem"

LAB_STEP=application_secret
LAB_SECRET_READY=false
for ((attempt=1; attempt<=6; attempt++)); do
  if aws secretsmanager get-secret-value --secret-id "$LAB_SECRET_ARN" --region "$LAB_REGION"     --query SecretString --output text --no-cli-pager --cli-connect-timeout 5 --cli-read-timeout 10     > "$LAB_RELEASE/db.json" 2>/dev/null &&
    python3.11 -c 'import json, sys
with open(sys.argv[1], encoding="utf-8") as secret:
    data = json.load(secret)
sys.exit(0 if data.get("username") == "appuser" and data.get("dbname") == "labapp"
         and isinstance(data.get("password"), str) and data["password"] else 1)' "$LAB_RELEASE/db.json" 2>/dev/null; then
    LAB_SECRET_READY=true
    break
  fi
  sleep 5
done
[[ "$LAB_SECRET_READY" == true ]]
chmod 0600 "$LAB_RELEASE/db.json"

LAB_STEP=instance_metadata
LAB_METADATA=http://169.254.169.254/latest
LAB_TOKEN="$(curl --fail --silent --show-error --max-time 5 --noproxy '*' -X PUT \
  -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' "$LAB_METADATA/api/token")"
LAB_INSTANCE_ID="$(curl --fail --silent --show-error --max-time 5 --noproxy '*' \
  -H "X-aws-ec2-metadata-token: $LAB_TOKEN" "$LAB_METADATA/meta-data/instance-id")"
LAB_AZ="$(curl --fail --silent --show-error --max-time 5 --noproxy '*' \
  -H "X-aws-ec2-metadata-token: $LAB_TOKEN" "$LAB_METADATA/meta-data/placement/availability-zone")"
[[ "$LAB_INSTANCE_ID" =~ ^i-[0-9a-f]+$ && "$LAB_AZ" =~ ^us-east-2[a-z]$ ]]
printf 'LAB_DB_HOST=%s\nLAB_INSTANCE_ID=%s\nLAB_AZ=%s\nLAB_CA_FILE=%s/rds-ca.pem\n' \
  "$LAB_DB_HOST" "$LAB_INSTANCE_ID" "$LAB_AZ" "$LAB_RELEASE" > "$LAB_RELEASE/labapp.env"

LAB_STEP=service_start
ln -sfnT "$LAB_RELEASE" "$LAB_ROOT/current"
LAB_SWITCHED=true
install -m 0644 "$LAB_RELEASE/labapp.service" "$LAB_UNIT"
systemctl daemon-reload
systemctl restart labapp.service

LAB_STEP=local_health
for ((attempt=1; attempt<=12; attempt++)); do
  if curl --fail --silent --max-time 2 http://127.0.0.1:8080/health >/dev/null; then
    break
  fi
  sleep 2
done
curl --fail --silent --show-error --max-time 5 http://127.0.0.1:8080/health >/dev/null

LAB_STEP=mysql_readiness
curl --fail --silent --show-error --max-time 15 'http://127.0.0.1:8080/health?strict=1' > "$LAB_RELEASE/readiness.json"
python3.11 - "$LAB_RELEASE/readiness.json" "$LAB_INSTANCE_ID" "$LAB_AZ" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if (
    report.get("db") != "reachable"
    or not report.get("db_tls")
    or report.get("served_by") != sys.argv[2]
    or report.get("az") != sys.argv[3]
    or not isinstance(report.get("students"), int)
    or report["students"] < 12
):
    raise SystemExit("Invalid readiness response / Réponse readiness invalide")
print(f"APP_READY instance={report['served_by']} az={report['az']} db_tls={report['db_tls']} students={report['students']}")
PY
curl --fail --silent --show-error --max-time 15 http://127.0.0.1:8080/ >/dev/null
systemctl enable labapp.service
LAB_READY=true
if [[ "$LAB_PREVIOUS" == "$LAB_ROOT"/release.* && "$LAB_PREVIOUS" != "$LAB_RELEASE" ]]; then
  rm -rf -- "$LAB_PREVIOUS"
fi
