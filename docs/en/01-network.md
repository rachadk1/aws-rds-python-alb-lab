# Stage 01 — CloudFormation network in us-east-2

[Français](../01-network.md) | [Git workflow](git-workflow.md) | [Home](../../README.md)

## What the template creates

| Resource | Address / placement | Purpose |
|---|---|---|
| VPC `lab6-vpc` | `10.10.0.0/16` | Isolated lab network with DNS resolution enabled |
| `lab6-bastion-subnet` | `10.10.0.0/28`, AZ A | SSH access through a future public bastion |
| `lab6-public-a` | `10.10.1.0/24`, AZ A | Public ALB and NAT Gateway |
| `lab6-public-b` | `10.10.2.0/24`, AZ B | Second ALB zone |
| `lab6-private-a` | `10.10.11.0/24`, AZ A | Web server A and RDS subnet group member |
| `lab6-private-b` | `10.10.12.0/24`, AZ B | Web server B and RDS subnet group member |
| Internet Gateway + public route table | Route `0.0.0.0/0 → IGW` | Internet routing for the three public subnets |
| Private route table + optional NAT | Route `0.0.0.0/0 → NAT` when enabled | Outbound Internet access for private servers |

A public subnet is defined by its route to the IGW. Automatic public IPv4 assignment stays disabled on the two ALB subnets; the ALB service will manage its own addresses. It is enabled only on the bastion subnet.

The five CIDRs are fixed to match the upstream SQL host grants. Names use `lab6-` to identify this lab; select our IDs on screens where the upstream guide uses `lab-vpc` or `lab-public-a`.

This template creates only the network. Security groups, EC2, RDS and ALB will be added through the next CloudFormation templates, deployed from Git Bash. The RDS subnet group will use both private subnets; that alone does not turn the planned Single-AZ database into Multi-AZ.

## 1. Sign in and select the region

In Git Bash, interrupt any old waiting `aws login` command with **Ctrl+C**, then run:

```bash
aws configure set region us-east-2
aws login --region us-east-2
aws sts get-caller-identity --query Arn --output text --region us-east-2
aws ec2 describe-availability-zones \
  --region us-east-2 \
  --query 'AvailabilityZones[?State==`available`].ZoneName' \
  --output table
```

Complete browser authentication before continuing. These commands assume the `default` profile. Check that `us-east-2a` and `us-east-2b` are available; otherwise replace the two AZ values below with two distinct available zones. If a command returns `AccessDenied`, stop and address the exact message.

## 2. Validate the template

From the repository root, on `infra/01-network`:

```bash
aws cloudformation validate-template \
  --template-body file://cloudformation/01-network.yaml \
  --region us-east-2
```

This validates the template structure. It does not guarantee creation permissions, quotas or deployment success.

## 3. Deploy the network

NAT is disabled by default. To create the full network needed for private installations, this command enables it **with a billable public IPv4 address**. NAT is charged while provisioned, even without traffic; data processing and some transfers add charges. Do not infer free usage from the account type.

```bash
aws cloudformation deploy \
  --template-file cloudformation/01-network.yaml \
  --stack-name lab6-network \
  --parameter-overrides \
    ProjectName=lab6 \
    AvailabilityZoneA=us-east-2a \
    AvailabilityZoneB=us-east-2b \
    EnableNatGateway=true \
  --tags Project=lab6 Purpose=Learning \
  --region us-east-2 \
  --no-fail-on-empty-changeset
```

To prepare the network without NAT or EIP, replace `EnableNatGateway=true` with `EnableNatGateway=false`. Rerun this same command with `true` before installing dependencies on the private EC2 instances. A single zonal NAT serves both AZs to reduce the number of NAT gateways; this does not provide Internet egress resilient to an AZ failure.

## 4. Verify and keep IDs locally

```bash
aws cloudformation describe-stacks \
  --stack-name lab6-network \
  --query 'Stacks[0].StackStatus' \
  --output text \
  --region us-east-2

aws cloudformation describe-stacks \
  --stack-name lab6-network \
  --query 'Stacks[0].Outputs' \
  --output table \
  --region us-east-2
```

Expected result: **`CREATE_COMPLETE`** on the first deployment, then **`UPDATE_COMPLETE`** after an update. The CLI output above provides IDs for the VPC, five subnets and NAT when enabled. To inspect managed resources without the AWS console, run:

```bash
aws cloudformation list-stack-resources \
  --stack-name lab6-network \
  --query 'StackResourceSummaries[].[LogicalResourceId,ResourceType,ResourceStatus]' \
  --output table --region us-east-2 --no-cli-pager
```

To keep outputs without publishing them:

```bash
mkdir -p local
aws cloudformation describe-stacks \
  --stack-name lab6-network \
  --query 'Stacks[0].Outputs' \
  --output json \
  --region us-east-2 > local/network-outputs.json
```

If deployment fails, inspect events rather than retrying blindly:

```bash
aws cloudformation describe-stack-events \
  --stack-name lab6-network \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
  --output table \
  --region us-east-2
```

After `ROLLBACK_COMPLETE`, fix the cause, then delete the failed stack before recreating it. Do not manually modify resources managed by this stack. Return to the [Git workflow](git-workflow.md) for the commit and PR.

## 5. End the session and clean up

To disable NAT while keeping the network, rerun the deployment command with the **same AZs**, but `EnableNatGateway=false`. CloudFormation removes the private default route, NAT and EIP. Private EC2 instances then lose Internet egress through this NAT. This does not delete or stop separately created EC2, RDS or ALB resources.

To delete the network, **first delete the CloudFormation stacks whose resources use this VPC**, including the future ALB, EC2 and RDS stacks, then `lab6-security`. Check any retained backups or snapshots. Use AWS CLI for deletion and respect dependency order. Then:

```bash
aws cloudformation delete-stack --stack-name lab6-network --region us-east-2
aws cloudformation wait stack-delete-complete --stack-name lab6-network --region us-east-2
```

Deleting the network alone is not complete lab cleanup. An in-use network interface can block VPC deletion; inspect deletion events and remove the owning resource.

## Sources

- [Upstream lab](https://github.com/inspiredevgen/devops-worksphops/blob/main/2-Cloud-Infrastructure/LABS/RDS/aws-lab-rds-python-alb/RDS-Python-ALB-Lab.en.md)
- [AWS CLI console-credential sign-in](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html)
- [CloudFormation NAT Gateway](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-ec2-natgateway.html)
- [RDS in a VPC and two-AZ subnet groups](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_VPC.WorkingWithRDSInstanceinaVPC.html)
- [NAT and IPv4 pricing](https://aws.amazon.com/vpc/pricing/)
