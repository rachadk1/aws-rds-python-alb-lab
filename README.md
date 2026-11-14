# AWS lab with Flask, private RDS and an Application Load Balancer

[Français](README.fr.md) | **English**

Completed in **us-east-2 (Ohio)** with CloudFormation and Git Bash. The two Flask servers span two Availability Zones and use TLS to connect to the same Single-AZ database.

Browser → public ALB on port 80 → two private EC2 servers on port 8080 → private MySQL RDS on port 3306.

## Verified results

WebB served all 10 measured requests with HTTP 200 after WebA became unhealthy. Both targets recovered on port 8080. The cleanup script confirmed the deletion of seven CloudFormation stacks and the absence of the lab database, automated backups and manual snapshots.

## Guides and screenshots

[develop](https://github.com/rachadk1/aws-rds-python-alb-lab/tree/develop) · [Implementation branches](https://github.com/rachadk1/aws-rds-python-alb-lab/branches)

- [VPC and routing](https://github.com/rachadk1/aws-rds-python-alb-lab/blob/develop/docs/en/01-network.md)
- [Security groups](https://github.com/rachadk1/aws-rds-python-alb-lab/blob/develop/docs/en/02-security-groups.md)
- [Bastion and private EC2](https://github.com/rachadk1/aws-rds-python-alb-lab/blob/develop/docs/en/03-ec2.md)
- [Private MySQL RDS](https://github.com/rachadk1/aws-rds-python-alb-lab/blob/develop/docs/en/04-rds.md)
- [SQL initialization and permissions](https://github.com/rachadk1/aws-rds-python-alb-lab/blob/develop/docs/en/04b-sql-bootstrap.md)
- [Flask deployment and TLS](https://github.com/rachadk1/aws-rds-python-alb-lab/blob/develop/docs/en/05-python.md)
- [ALB and browser validation](https://github.com/rachadk1/aws-rds-python-alb-lab/blob/develop/docs/en/06-alb.md)
- [Failover and AWS cleanup](https://github.com/rachadk1/aws-rds-python-alb-lab/blob/develop/docs/en/07-failover-cleanup.md)
- [Git workflow](https://github.com/rachadk1/aws-rds-python-alb-lab/blob/develop/docs/en/git-workflow.md)

## Reference

[inspiredevgen’s RDS Python ALB lab](https://github.com/inspiredevgen/devops-worksphops/blob/main/2-Cloud-Infrastructure/LABS/RDS/aws-lab-rds-python-alb/RDS-Python-ALB-Lab.en.md)
