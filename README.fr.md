# Lab AWS RDS, Python et Application Load Balancer

**Français** | [English](README.md)

Déployer une application Flask sur deux instances EC2 privées, stocker ses données dans une base Amazon RDS MySQL privée et distribuer les requêtes avec un Application Load Balancer public dans **us-east-2 (Ohio)**.

Ce projet utilise CloudFormation pour créer le réseau. Les groupes de sécurité, EC2, RDS, l'application, l'ALB et les tests de panne seront réalisés étape par étape.

## Périmètre actuel

**L'étape 01 est préparée : le socle réseau. Le déploiement AWS et les étapes applicatives ne sont pas encore vérifiés.**

| Étape | Résultat | État |
|---|---|---|
| 01 | VPC, cinq sous-réseaux, routage et NAT Gateway optionnel | Template et instructions préparés |
| 02 | Quatre groupes de sécurité et flux restreints | Prévu |
| 03 | Clé SSH, bastion et deux serveurs web privés | Prévu |
| 04 | RDS MySQL privé et compte applicatif aux droits limités | Prévu |
| 05 | Application Python et connexion TLS à la base | Prévu |
| 06 | ALB, groupe cible et contrôles de santé | Prévu |
| 07 | Tests de panne, preuves et nettoyage complet | Prévu |

## Branches et documentation

- [main](https://github.com/rachadk1/aws-rds-python-alb-lab/tree/main) : accueil du portfolio.
- [develop](https://github.com/rachadk1/aws-rds-python-alb-lab/tree/develop) : travail intégré du lab.
- `infra/01-network` : première branche de réalisation ; une branche et une pull request vers `develop` pour chaque étape suivante.
- [Workflow Git et GitHub](docs/git-workflow.md).
- [Étape 01 : déployer et comprendre le réseau](docs/01-network.md).
- [Template CloudFormation](cloudformation/01-network.yaml).

Les liens deviennent accessibles après la création du dépôt et la publication des branches correspondantes. Les fichiers des étapes suivantes seront ajoutés au fur et à mesure du travail réalisé.

## Objectifs et limites

Pratiquer les réseaux AWS, les bases gérées, les références entre groupes de sécurité, SSH ProxyJump, les droits SQL, TLS, la répartition de charge, le dépannage et les pull requests Git.

Les deux serveurs web seront répartis sur deux zones de disponibilité. La base prévue est **Single-AZ** et le réseau utilise **un seul NAT Gateway zonal** : cette architecture temporaire d'apprentissage n'offre pas une haute disponibilité complète pour la production. Le trafic NAT entre zones peut ajouter des frais de transfert.

Le NAT Gateway, les adresses IPv4 publiques et, plus tard, EC2, RDS et l'ALB peuvent générer des frais. Le NAT est désactivé par défaut dans le template. Active-le au moment d'installer les serveurs privés et supprime les ressources après le lab. Ne publie jamais d'identifiants, de mots de passe SQL ni de clés SSH privées.

## Référence et attribution

Adaptation pédagogique du [lab RDS Python ALB d'inspiredevgen](https://github.com/inspiredevgen/devops-worksphops/blob/main/2-Cloud-Infrastructure/LABS/RDS/aws-lab-rds-python-alb/RDS-Python-ALB-Lab.en.md). Ce dépôt contient un nouveau template réseau et ses explications ; les scripts applicatifs d'origine ne sont pas copiés à l'étape 01. Avant leur utilisation, vérifier leur version et corriger les chemins de téléchargement pour inclure `2-Cloud-Infrastructure/LABS/RDS/aws-lab-rds-python-alb/`.
