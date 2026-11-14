# Stage 02 — Security groups with CloudFormation

[Français](../02-security-groups.md) | [Home](../../README.md)

## Goal

Create four security groups and six inbound rules in a **`lab6-security`** stack, from Git Bash in **us-east-2**. All lab resources will be managed by CloudFormation as the stages progress; no manual AWS console provisioning is needed.

The network stack already exists. This stage adds a separate stack without redeploying the network. Its VPC is passed as a parameter from the network stack outputs. Passing a parameter does not establish an automatic cross-stack dependency: follow the cleanup order below.

## Branch and files

Keep the stage 02 branch already created, for example `infra/02-security-groups`. Check:

```bash
git branch --show-current
git status
```

Extract the patch at the repository root, preserving paths and replacing the previous stage guides. It includes `cloudformation/02-security-groups.yaml`, `scripts/deploy-security-groups.sh` and bilingual documentation. Review personal additions before replacing README files.

## What CloudFormation creates

| Destination group | TCP | Source | Purpose |
|---|---|---|---|
| `lab6-alb-sg` | 80 | `0.0.0.0/0` | Public HTTP |
| `lab6-bastion-sg` | 22 | Administrator public IPv4 `/32` | SSH |
| `lab6-web-sg` | 8080 | ALB group | Application and health checks |
| `lab6-web-sg` | 22 | Bastion group | SSH to private servers |
| `lab6-rds-sg` | 3306 | Web group | Application MySQL queries |
| `lab6-rds-sg` | 3306 | Bastion group | Database initialization |

`/32` allows one IPv4 address. A group reference allows its network interfaces on the specified port without copying its rules. Resources will receive these groups in the next stages.

All four egress rules explicitly allow all IPv4 traffic, following the upstream learning lab. Egress therefore remains broad. Inbound rules are separate CloudFormation resources: their references let CloudFormation manage creation and deletion order.

## Deploy from Git Bash

Prerequisites: authenticated AWS CLI, Git Bash and `curl` (normally included with Git Bash). The script uses the active AWS profile and the Ohio region.

From the repository root:

```bash
bash scripts/deploy-security-groups.sh lab6-network
```

The first argument must be the **exact existing network stack name**. If it is named `lab6network`, use:

```bash
bash scripts/deploy-security-groups.sh lab6network
```

To find that name without the AWS console:

```bash
aws cloudformation describe-stacks \
  --query 'Stacks[].[StackName,StackStatus]' \
  --output table --region us-east-2 --no-cli-pager
```

The script:
1. checks that the network stack is stable and reads its `VpcId` output;
2. detects the current public IPv4 through `https://checkip.amazonaws.com` and appends `/32`;
3. validates the template and deploys `lab6-security`;
4. displays status and the four IDs, then saves actual rules in Git-ignored `local/security-group-rules.json`.

The template contains no personal IP address. If needed, explicitly supply the trusted SSH source instead of automatic detection, for example when the browser/proxy and SSH use different egress addresses:

```bash
LAB_ADMIN_CIDR=203.0.113.10/32 bash scripts/deploy-security-groups.sh lab6-network
```

This address is a documentation example: replace it with the actual public IPv4 used for SSH egress. If it changes, rerun the script with the correct source; CloudFormation will update the rule. The rule and parameter remain visible in the AWS account even though their values are not recorded in Git.

The groups must not already exist with the same names in the VPC. If deployment fails, the script stops: inspect the events below before retrying.

## Verify the result

Expected on first deployment: **`CREATE_COMPLETE`**. A successful update returns **`UPDATE_COMPLETE`**. Outputs contain `VpcId`, `AlbSecurityGroupId`, `BastionSecurityGroupId`, `WebSecurityGroupId` and `RdsSecurityGroupId`.

```bash
aws cloudformation list-stack-resources \
  --stack-name lab6-security \
  --query 'StackResourceSummaries[].[LogicalResourceId,ResourceType,ResourceStatus]' \
  --output table --region us-east-2 --no-cli-pager

cat local/security-group-rules.json
```

Check ten CloudFormation resources: four groups and six inbound rules; each group also has its embedded egress rule. In the JSON, check the same VPC, the six rules above, SG sources for web/RDS and bastion SSH restricted to the `/32`. These checks cover configuration; no application test has been performed yet.

On failure:

```bash
aws cloudformation describe-stack-events \
  --stack-name lab6-security \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED` || ResourceStatus==`UPDATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
  --output table --region us-east-2 --no-cli-pager
```

If the stack is in `ROLLBACK_COMPLETE`, fix the cause, delete only the failed stack, wait for deletion and rerun. If later resources already use the stack, resolve those dependencies before deleting it.

## Commit and PR after AWS validation

Update both README files once deployment actually succeeds. The supplied versions mark stage 02 as awaiting deployment to avoid claiming an unverified result.

```bash
git add README.md README.fr.md cloudformation/02-security-groups.yaml scripts/deploy-security-groups.sh docs/
git diff --cached --check
git diff --cached --stat
git commit -m "infra: manage RDS lab security groups with CloudFormation"
git push -u origin HEAD
```

Open a PR with **base `develop`** and the current branch as comparison. Title: `Infra: manage ALB, bastion, web and RDS security groups with CloudFormation`. Record actual validation results; keep IP addresses and account details out of published evidence.

## Cleanup and next stages

EC2, RDS and ALB will be added through the next templates, followed by automated application deployment. To clean up the lab, delete their stacks first, then security and finally the network.

```bash
aws cloudformation delete-stack --stack-name lab6-security --region us-east-2
aws cloudformation wait stack-delete-complete --stack-name lab6-security --region us-east-2
```

Do not run cleanup while building the lab. Deleting the security stack does not remove the network NAT. No manual security-group creation/deletion commands are required.

## Sources

- [CloudFormation — SecurityGroup](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-ec2-securitygroup.html)
- [CloudFormation — SecurityGroupIngress](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-ec2-securitygroupingress.html)
- [AWS — security group rules](https://docs.aws.amazon.com/vpc/latest/userguide/security-group-rules.html)
- [Upstream lab](https://github.com/inspiredevgen/devops-worksphops/blob/main/2-Cloud-Infrastructure/LABS/RDS/aws-lab-rds-python-alb/RDS-Python-ALB-Lab.en.md)
