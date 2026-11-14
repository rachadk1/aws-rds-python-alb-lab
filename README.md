# AWS RDS, Python and Application Load Balancer Lab

[Français](README.fr.md) | **English**

Build a Flask application on two private EC2 instances, store its data in private Amazon RDS for MySQL, and serve traffic through an internet-facing Application Load Balancer in **us-east-2 (Ohio)**.

This learning project uses CloudFormation for the network foundation. Security groups, EC2, RDS, application deployment, ALB configuration and failure experiments will be completed step by step.

## Current scope

**Stage 01 is prepared: network foundation. AWS deployment and application stages are not yet verified.**

| Stage | Deliverable | State |
|---|---|---|
| 01 | VPC, five subnets, routing and optional NAT Gateway | Template and instructions prepared |
| 02 | Four security groups and restricted traffic paths | Planned |
| 03 | SSH key, bastion and two private web servers | Planned |
| 04 | Private RDS MySQL and least-privilege application account | Planned |
| 05 | Python application and TLS database connection | Planned |
| 06 | ALB, target group and health checks | Planned |
| 07 | Failure tests, evidence and complete cleanup | Planned |

## Branches and documentation

- [main](https://github.com/rachadk1/aws-rds-python-alb-lab/tree/main): portfolio overview.
- [develop](https://github.com/rachadk1/aws-rds-python-alb-lab/tree/develop): integrated lab work.
- `infra/01-network`: first implementation branch; subsequent stages use separate branches and pull requests to `develop`.
- [Git and GitHub workflow](docs/en/git-workflow.md).
- [Stage 01: deploy and understand the network](docs/en/01-network.md).
- [CloudFormation template](cloudformation/01-network.yaml).

These links become available as the repository and corresponding branches are pushed. Files for later stages are added only when that work is completed.

## Learning goals and limits

Practice AWS networking, managed databases, security-group references, SSH ProxyJump, SQL permissions, TLS, load balancing, troubleshooting and Git pull requests.

Two web servers span two Availability Zones. The planned database is **Single-AZ**, and the network uses **one zonal NAT Gateway**: this is a temporary learning design, not an end-to-end highly available production deployment. Cross-AZ NAT traffic can add data-transfer charges.

The NAT Gateway, public IPv4 addresses and later compute, RDS and ALB resources can incur charges. NAT is disabled by default in the template. Enable it when ready to install the private web servers, and delete the resources after the lab. Never commit credentials, database passwords or private SSH keys.

## Reference and attribution

Learning adaptation of [inspiredevgen's RDS Python ALB lab](https://github.com/inspiredevgen/devops-worksphops/blob/main/2-Cloud-Infrastructure/LABS/RDS/aws-lab-rds-python-alb/RDS-Python-ALB-Lab.en.md). This repository contains a new network template and accompanying notes; upstream application scripts are not copied in stage 01. Before using them, verify their current version and correct download paths to include `2-Cloud-Infrastructure/LABS/RDS/aws-lab-rds-python-alb/`.
