# AWS RDS, Python and Application Load Balancer Lab

[Français](README.fr.md) | **English**

Build a Flask application on two private EC2 instances, store its data in private Amazon RDS for MySQL, and serve traffic through an internet-facing Application Load Balancer in **us-east-2 (Ohio)**.

This learning project manages infrastructure through staged CloudFormation templates deployed from Git Bash. Security groups, EC2, RDS, ALB and application bootstrap will be automated as the stages progress. AWS console provisioning is not required.

## Current scope

**Stages 01–03 are deployed and SSH is verified. Stage 04A RDS is available with private access and encrypted storage. Stage 04B initialized the database and validated TLS and the application account permissions from both web servers. Stage 05 deployed Flask and verified the shared RDS connection over TLS from both private web servers. Stage 06 adds the public ALB.**

| Stage | Deliverable | State |
|---|---|---|
| 01 | VPC, five subnets, routing and optional NAT Gateway | Deployed: CREATE_COMPLETE |
| 02 | Four security groups and restricted traffic paths | Deployed: CREATE_COMPLETE |
| 03 | Existing SSH key, bastion and two private web servers | Deployed; EC2 checks and three SSH tests passed |
| 04 | Private RDS MySQL and least-privilege application account | RDS available and SQL tests passed on both web instances |
| 05 | Python application and TLS database connection | Deployed; Flask and RDS TLS verified on both EC2 instances |
| 06 | ALB, target group and health checks | Template and verification script ready; AWS validation pending |
| 07 | Failure tests, evidence and complete cleanup | Planned |

## Branches and documentation

- [main](https://github.com/rachadk1/aws-rds-python-alb-lab/tree/main): portfolio overview.
- [develop](https://github.com/rachadk1/aws-rds-python-alb-lab/tree/develop): integrated lab work.
- `infra/01-network`: first implementation branch; subsequent stages use separate branches and pull requests to `develop`.
- [Git and GitHub workflow](docs/en/git-workflow.md).
- [Stage 01: deploy and understand the network](docs/en/01-network.md).
- [Stage 02: configure security groups](docs/en/02-security-groups.md).
- [Stage 03: reuse the SSH key and deploy EC2](docs/en/03-ec2.md).
- [Stage 04: understand and deploy RDS](docs/en/04-rds.md).
- [Stage 04B: automate SQL initialization and tests](docs/en/04b-sql-bootstrap.md).
- [Stage 05: deploy Flask and verify TLS](docs/en/05-python.md).
- [Stage 06: deploy the ALB and verify both targets](docs/en/06-alb.md).
- [SQL bootstrap CloudFormation template](cloudformation/04b-sql-bootstrap.yaml).
- [RDS CloudFormation template](cloudformation/04-rds.yaml).
- [RDS deployment script](scripts/deploy-rds.sh).
- [EC2 CloudFormation template](cloudformation/03-ec2.yaml).
- [EC2 deployment script](scripts/deploy-ec2.sh).
- [Network CloudFormation template](cloudformation/01-network.yaml).
- [Security CloudFormation template](cloudformation/02-security-groups.yaml).
- [Security deployment script](scripts/deploy-security-groups.sh).

These links become available as the repository and corresponding branches are pushed. Files for later stages are added only when that work is completed.

## Learning goals and limits

Practice AWS networking, managed databases, security-group references, SSH ProxyJump, SQL permissions, TLS, load balancing, troubleshooting and Git pull requests.

Two web servers span two Availability Zones. The planned database is **Single-AZ**, and the network uses **one zonal NAT Gateway**: this is a temporary learning design, not an end-to-end highly available production deployment. Cross-AZ NAT traffic can add data-transfer charges.

The NAT Gateway, public IPv4 addresses and later compute, RDS and ALB resources can incur charges. NAT is disabled by default in the template. Enable it when ready to install the private web servers, and delete the resources after the lab. Never commit credentials, database passwords or private SSH keys.

## Reference and attribution

Learning adaptation of [inspiredevgen's RDS Python ALB lab](https://github.com/inspiredevgen/devops-worksphops/blob/main/2-Cloud-Infrastructure/LABS/RDS/aws-lab-rds-python-alb/RDS-Python-ALB-Lab.en.md). This repository contains a new network template and accompanying notes; upstream application scripts are not copied in stage 01. Before using them, verify their current version and correct download paths to include `2-Cloud-Infrastructure/LABS/RDS/aws-lab-rds-python-alb/`.
