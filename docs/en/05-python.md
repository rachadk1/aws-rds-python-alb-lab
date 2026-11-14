# Stage 05 — Python application and TLS to RDS

[Français](../05-python.md) | **English**

Flask handles HTTP requests. Gunicorn listens on port 8080 on each private EC2 instance. The `labapp` service runs under a dedicated Linux account. Both copies use the same MySQL database to read courses and save registrations.

The script renders the template locally by embedding an archive of the [app](../../app) directory. CloudFormation deploys a Systems Manager (SSM) document and one association per web instance. Each SSM agent installs and tests the service on its own instance. The existing NAT lets the instances download packages and the RDS certificate bundle. The `lab6-python` stack manages these SSM resources.

The stage 04B IAM profile grants access to the `appuser` secret in Secrets Manager. The installer retrieves the secret and systemd supplies it to the service as a file. MySQL enforces `appuser` privileges, and the Python client verifies both the RDS certificate and DNS name. No command asks you to type the password.

## Deploy from Git Bash

From the repository root on `app/05-python`, with stacks 01 through 04B active in `us-east-2`:

```bash
git status --short --branch
aws sts get-caller-identity --region us-east-2 --query Arn --output text
bash scripts/deploy-python.sh
```

If the AWS session has expired, run `aws login --region us-east-2` and retry. The script requires both SSM agents to be `Online`, the database to be `available`, and NAT to be enabled.

## Read the results

```bash
bash scripts/show-python-results.sh
```

| Test on each EC2 instance | Expected result | What it verifies |
|---|---|---|
| `GET /health` | HTTP 200 | Gunicorn and Flask handle the request without querying RDS. |
| `GET /health?strict=1` | HTTP 200, a TLS cipher and at least 12 students | Flask opens an encrypted MySQL session to RDS as the application account and can read the table. |
| `GET /` | HTTP 200 | Flask renders the page with courses and recent registrations. |

Expect two `Status: Success` results and two `APP_READY` lines with different instance IDs and Availability Zones. The strict check reports `db_tls` and `students`. Both EC2 instances query the same data. Stage 06 adds the ALB so you can try the browser registration form with fictional data.

If the deployment fails, look for `step=` in `APP_DEPLOY_FAILED` if the association output is available. `dependencies` points to `/var/log/lab6-app-packages.log` on the instance. `application_secret` points to secret retrieval or the IAM profile. `mysql_readiness` points to the EC2-to-RDS path, certificate, or MySQL privileges. `bash scripts/deploy-python.sh --retry` requests another association run for an already deployed stack. If an initial deployment reaches `ROLLBACK_COMPLETE`, delete only `lab6-python` and wait for deletion before deploying again.

## GitHub workflow

Once both instances pass, push your branch and open the PR with **base `develop`** and **compare `app/05-python`**. Include both AZs, the student count and the TLS result in the summary. The `main` branch serves as the portfolio landing page.

For full lab cleanup, remove `lab6-python` before the stacks it reads outputs from. Deleting SSM associations leaves already installed files on the instances. Deleting the EC2 stack deletes those files with the lab root volumes.
