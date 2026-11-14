# Stage 04B — Automated SQL initialization with CloudFormation and SSM

[Français](../04b-sql-bootstrap.md) | [RDS 04A](04-rds.md) | [Home](../../README.md)

## What we add

RDS is available. This stage creates tables and the application account, then tests access **from the actual private servers**. All added AWS resources, execution documents and associations are managed by CloudFormation.

The local script orchestrates deployments from Git Bash. SQL runs on EC2 through Systems Manager, without typing passwords or copying an SSH key.

## 1. Three different controls

| Control | Question | Configuration |
|---|---|---|
| Security group | Can this machine reach RDS on TCP 3306? | Web and bastion groups allowed |
| IAM | Can this EC2 instance read this AWS secret? | Bastion: admin and app secrets; web: app secret only |
| MySQL | Can this account perform this SQL operation? | `appuser`: SELECT, INSERT, UPDATE, DELETE on `labapp.*` |

**The IAM role and MySQL account are different identities.** The role retrieves a password from AWS; that password then authenticates the SQL account to MySQL.

The role's trust policy lets EC2 assume it. Its permissions policy specifies readable secrets. An **instance profile** associates the role with EC2. No persistent IAM access key is created.

## 2. New stack resources

`cloudformation/04b-sql-bootstrap.yaml` creates **`lab6-sql-bootstrap`**:

- an application secret: username `appuser`, generated 32-character password;
- a role and profile for the bastion, then a role and profile for web servers;
- an SSM document containing Python client installation and the SQL program;
- three SSM associations enabled only once profiles and agents are ready.

An **SSM association** connects an execution document to a target instance. `WaitForSuccessTimeoutSeconds` makes CloudFormation wait for its result. Both web tests depend on successful bastion initialization.

SSM Agent is present in the Amazon Linux 2023 AMI used here. It contacts AWS services outbound; no new inbound SSM port is added. Private EC2 instances use NAT for SSM, Secrets Manager and downloads. SQL access to RDS remains private through VPC local routes.

## 3. Why the EC2 template also changes

All three EC2 instances receive a profile through a `lab6-ec2` update. The AMI parameter becomes a pinned ID: the script reuses **the already-deployed AMI**, preventing an unintended refresh of the latest public image during this update.

The first lab key name is kept with `UsePreviousValue`. The script inspects a change set and **refuses any announced EC2 replacement, including conditional replacement**. Existing stack values retain security groups, subnets, disks and SSH settings. IAM profiles attach in place.

The updated `deploy-ec2.sh` also preserves AMI and profiles on future reruns. On first creation it still resolves Amazon Linux 2023 through the AWS public parameter.

## 4. What SQL does on the bastion

Open `SqlDocument → Content → mainSteps` in template 04B. The embedded Python program:

1. retrieves secrets into memory using the bastion IAM role;
2. opens TLS to the RDS DNS name with certificate and hostname verification;
3. creates `courses`, `students`, `enrollments` and the `v_course_stats` view;
4. loads fictional demonstration data: 8 courses and 12 learners;
5. creates the two MySQL `appuser@host` identities matching web networks;
6. grants only four required privileges and checks accounts;
7. confirms that `appuser` cannot log in from the bastion.

The schema matches fields needed by the reference lab application. Sample data is fictional and specific to this adaptation. `CREATE TABLE IF NOT EXISTS` and `INSERT IGNORE` make reruns compatible with existing tables and data. Tables are not dropped to reload sample data.

MySQL hosts are:

- `10.10.11.0/255.255.255.0`;
- `10.10.12.0/255.255.255.0`.

These are the two private web networks in network/netmask notation. MySQL identities include **username and host**: the same `appuser` name can therefore have two entries with identical privileges and one shared secret. The bastion is in `10.10.0.0/28`, outside those networks.

Accounts have `REQUIRE SSL`. Stage 04A already requires TLS at the server; the client also verifies server identity. Passwords are not printed, supplied as command-line arguments or written into repository files.

## 5. What both web servers verify

The same SSM document runs separately on web A and web B in test mode:

- application secret retrieval allowed;
- administrator secret retrieval denied by IAM;
- MySQL connection using `appuser`, TLS and server verification;
- effective account identification through `CURRENT_USER()`;
- select, insert, update and delete of a probe row;
- final `ROLLBACK` so that row is not retained;
- MySQL denial of reads from system table `mysql.user`.

`AUTO_INCREMENT` counters can advance after a rollback: gaps in IDs do not imply lost data. Each probe row uses a unique fictional address.

## 6. Run from your current branch

Stay on **`infra/04-rds`**. Extract the patch at the repository root, preserving paths; review personal edits before replacing README files.

```bash
git branch --show-current
git status
bash scripts/deploy-sql-bootstrap.sh
```

The script:

1. checks prerequisite stacks, RDS availability, enabled NAT, running EC2 instances and consistent AMI;
2. deploys SQL with `RunSqlBootstrap=false`: secret, roles, profiles and document, without SQL execution;
3. attaches profiles through a checked EC2 change set, keeping the AMI and SSH key;
4. waits for all three SSM agents to be `Online`;
5. updates SQL with `RunSqlBootstrap=true`;
6. displays all three results.

`CAPABILITY_IAM` explicitly acknowledges that the stack creates IAM roles. The account running CloudFormation needs permissions for these operations and for passing roles to EC2.

A rerun disables and recreates associations to execute the current document; it keeps the existing application secret. Installation uses PyMySQL 1.2.3 in a virtual environment on each instance.

Role propagation and SSM registration can take several minutes. Agents are waited for at most ten minutes per instance. The new application secret adds Secrets Manager charges; the three EC2 instances, RDS and NAT remain deployed.

## 7. Read success evidence

Final deployment should end with `UPDATE_COMPLETE` on `lab6-sql-bootstrap`. Each SSM invocation must show **`Status: Success`**.

| Result | Meaning |
|---|---|
| `SQL_INIT_OK` | Administrator initialization succeeded with TLS |
| `app_login_from_bastion=denied` | Application account is restricted to web networks |
| Two `SQL_APP_OK` results | Application access validated from each private EC2 |
| `SELECT_INSERT_UPDATE_DELETE=ok` | All four operations actually worked |
| `admin_table=denied` | MySQL administration tables remain forbidden |
| `master_secret=denied` | Web role cannot retrieve the administrator secret |
| `tls=...` | TLS was negotiated with client-side server verification |

Read results without rerunning initialization:

```bash
bash scripts/show-sql-results.sh
```

Package logs remain on instances at `/var/log/lab6-sql-packages.log`. SQL errors expose a stage and numeric code rather than raw server messages that could contain sensitive information.

On stack failure:

```bash
aws cloudformation describe-stack-events \
  --stack-name lab6-sql-bootstrap \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED` || ResourceStatus==`UPDATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
  --output table --region us-east-2 --no-cli-pager
```

If an agent remains offline, check its profile, agent and egress before retrying. On execution failure, read its SSM result. If command output is not available immediately after deployment, wait a few seconds and rerun only the results reader.

**CloudFormation orchestrates commands but does not track each table or row as a separate resource.** Stack rollback does not undo SQL already executed. Initialization is designed for reruns after correction; schema and account changes do not form one globally reversible transaction.

## 8. Commit and PR after real validation

```bash
git add README.md README.fr.md cloudformation/03-ec2.yaml cloudformation/04-rds.yaml cloudformation/04b-sql-bootstrap.yaml scripts/deploy-ec2.sh scripts/deploy-rds.sh scripts/deploy-sql-bootstrap.sh scripts/show-sql-results.sh docs/
git diff --cached --check
git diff --cached --stat
git commit -m "infra: provision private RDS and bootstrap restricted SQL accounts"
git push -u origin infra/04-rds
```

Before the final commit, record actual results in both README files and guides. The PR into `develop` covers 04A and 04B, including EC2 profile changes. Stage 05 then installs Flask and Gunicorn on web servers using only the application secret.

## 9. Cleanup at the end

The SQL stack manages an application secret and profiles used by EC2. For full cleanup: first remove future dependent ALB/application resources, then EC2, SQL bootstrap, RDS, security and network stacks.

Do not delete SQL bootstrap alone while instances use its profiles and secret. To recover from deployment issues, correct and rerun scripts rather than deleting credentials.

Removing SSM associations does not remove MySQL tables or accounts. Full deletion occurs when RDS is deleted. The existing SSH key pair stays outside these stacks.

## Sources

- [CloudFormation — SSM associations](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-ssm-association.html)
- [AWS — SSM Agent](https://docs.aws.amazon.com/systems-manager/latest/userguide/ssm-agent.html)
- [CloudFormation — EC2 IAM profile](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-ec2-instance.html)
- [CloudFormation — application secret](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-secretsmanager-secret.html)
- [MySQL — username and network host](https://dev.mysql.com/doc/refman/8.4/en/account-names.html)
- [PyMySQL 1.2.3](https://pypi.org/project/PyMySQL/1.2.3/)
- [Reference lab schema](https://github.com/inspiredevgen/devops-worksphops/blob/main/2-Cloud-Infrastructure/LABS/RDS/aws-lab-rds-python-alb/scripts/db/seed.sql)
