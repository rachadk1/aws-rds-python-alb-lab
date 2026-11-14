# Lab AWS avec Flask, RDS privé et Application Load Balancer

**Français** | [English](README.md)

Lab terminé dans **us-east-2 (Ohio)** avec CloudFormation et Git Bash. Les serveurs Flask sont répartis sur deux zones et accèdent à la même base Single-AZ via TLS.

Navigateur → ALB public sur le port 80 → deux EC2 privées sur le port 8080 → MySQL RDS privé sur le port 3306.

## Résultats vérifiés

WebB a servi les 10 requêtes mesurées en HTTP 200 après la perte de WebA. Les deux cibles sont redevenues saines sur le port 8080. Le script de nettoyage a confirmé la suppression des sept stacks et l’absence de la base du lab, de sauvegardes automatiques et de snapshots manuels.

## Guides et captures

[develop](https://github.com/rachadk1/aws-rds-python-alb-lab/tree/develop) · [Branches de réalisation](https://github.com/rachadk1/aws-rds-python-alb-lab/branches)

- [VPC et routage](https://github.com/rachadk1/aws-rds-python-alb-lab/blob/develop/docs/01-network.md)
- [Groupes de sécurité](https://github.com/rachadk1/aws-rds-python-alb-lab/blob/develop/docs/02-security-groups.md)
- [Bastion et EC2 privées](https://github.com/rachadk1/aws-rds-python-alb-lab/blob/develop/docs/03-ec2.md)
- [MySQL RDS privé](https://github.com/rachadk1/aws-rds-python-alb-lab/blob/develop/docs/04-rds.md)
- [Initialisation SQL et droits](https://github.com/rachadk1/aws-rds-python-alb-lab/blob/develop/docs/04b-sql-bootstrap.md)
- [Déploiement de Flask et TLS](https://github.com/rachadk1/aws-rds-python-alb-lab/blob/develop/docs/05-python.md)
- [ALB et validation dans le navigateur](https://github.com/rachadk1/aws-rds-python-alb-lab/blob/develop/docs/06-alb.md)
- [Basculement et nettoyage AWS](https://github.com/rachadk1/aws-rds-python-alb-lab/blob/develop/docs/07-failover-cleanup.md)
- [Workflow Git](https://github.com/rachadk1/aws-rds-python-alb-lab/blob/develop/docs/git-workflow.md)

## Reference

[inspiredevgen’s RDS Python ALB lab](https://github.com/inspiredevgen/devops-worksphops/blob/main/2-Cloud-Infrastructure/LABS/RDS/aws-lab-rds-python-alb/RDS-Python-ALB-Lab.en.md)
