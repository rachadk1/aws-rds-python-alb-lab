# Étape 02 — Groupes de sécurité avec CloudFormation

[English](en/02-security-groups.md) | [Accueil](../README.fr.md)

## Objectif

Créer les quatre groupes et les six règles entrantes avec une stack **`lab6-security`**, depuis Git Bash dans **us-east-2**. Toutes les ressources du lab seront gérées par CloudFormation au fil des étapes ; aucune création manuelle dans la console AWS n'est nécessaire.

La stack réseau existe déjà. Cette étape ajoute une stack séparée, sans redéployer le réseau. Le VPC est transmis comme paramètre depuis les sorties de la stack réseau. Ce passage par paramètre ne crée pas de dépendance automatique entre les stacks : respecter l'ordre de suppression expliqué plus bas.

## Branche et fichiers

Conserver la branche d'étape 02 déjà créée, par exemple `infra/02-security-groups`. Vérifier :

```bash
git branch --show-current
git status
```

Extraire le correctif à la racine du dépôt en conservant les chemins et en remplaçant les anciens guides de cette étape. Il contient le template `cloudformation/02-security-groups.yaml`, le script `scripts/deploy-security-groups.sh` et la documentation FR/EN. Relire les éventuels ajouts personnels avant de remplacer les README.

## Ce que CloudFormation crée

| Groupe destinataire | TCP | Source | Usage |
|---|---|---|---|
| `lab6-alb-sg` | 80 | `0.0.0.0/0` | HTTP public |
| `lab6-bastion-sg` | 22 | IPv4 publique de l'administrateur `/32` | SSH |
| `lab6-web-sg` | 8080 | Groupe ALB | Application et contrôles de santé |
| `lab6-web-sg` | 22 | Groupe bastion | SSH vers les serveurs privés |
| `lab6-rds-sg` | 3306 | Groupe web | Requêtes MySQL de l'application |
| `lab6-rds-sg` | 3306 | Groupe bastion | Initialisation de la base |

`/32` autorise une seule IPv4. Une référence à un groupe autorise ses interfaces réseau sur le port indiqué, sans copier ses règles. Les ressources recevront ces groupes dans les prochaines étapes.

Les quatre règles de sortie autorisent explicitement tout le trafic IPv4, conformément au lab d'origine. Le contrôle des sorties reste donc large. Les règles entrantes sont des ressources CloudFormation séparées : leurs références permettent à CloudFormation de gérer l'ordre de création et de suppression.

## Déploiement depuis Git Bash

Prérequis : AWS CLI connecté, Git Bash et `curl` (fourni habituellement avec Git Bash). Le script utilise le profil AWS actif et la région Ohio.

Depuis la racine du dépôt :

```bash
bash scripts/deploy-security-groups.sh lab6-network
```

Le premier argument doit être le **nom exact de la stack réseau existante**. Si elle s'appelle `lab6network`, utiliser :

```bash
bash scripts/deploy-security-groups.sh lab6network
```

Pour retrouver ce nom sans console AWS :

```bash
aws cloudformation describe-stacks \
  --query 'Stacks[].[StackName,StackStatus]' \
  --output table --region us-east-2 --no-cli-pager
```

Le script :
1. vérifie que la stack réseau est stable et récupère sa sortie `VpcId` ;
2. détecte l'IPv4 publique actuelle via `https://checkip.amazonaws.com`, puis ajoute `/32` ;
3. valide le template et déploie `lab6-security` ;
4. affiche le statut et les quatre IDs, puis conserve les règles réelles dans `local/security-group-rules.json`, ignoré par Git.

Le template n'embarque aucune IP personnelle. Si nécessaire, fournir explicitement la source SSH de confiance à la place de la détection automatique, par exemple lorsqu'un navigateur/proxy et SSH empruntent des sorties différentes :

```bash
LAB_ADMIN_CIDR=203.0.113.10/32 bash scripts/deploy-security-groups.sh lab6-network
```

Cette adresse est un exemple de documentation : la remplacer par la véritable IPv4 publique de sortie SSH. Si l'IP change, relancer le script avec la bonne source ; CloudFormation mettra à jour la règle. La règle et le paramètre restent visibles dans le compte AWS, même si les valeurs ne sont pas enregistrées dans Git.

Les groupes ne doivent pas déjà exister sous les mêmes noms dans le VPC. Si un déploiement échoue, le script s'arrête : examiner les événements ci-dessous avant de relancer.

## Vérifier le résultat

Résultat attendu au premier déploiement : **`CREATE_COMPLETE`**. Une mise à jour réussie retourne **`UPDATE_COMPLETE`**. Les sorties contiennent `VpcId`, `AlbSecurityGroupId`, `BastionSecurityGroupId`, `WebSecurityGroupId` et `RdsSecurityGroupId`.

```bash
aws cloudformation list-stack-resources \
  --stack-name lab6-security \
  --query 'StackResourceSummaries[].[LogicalResourceId,ResourceType,ResourceStatus]' \
  --output table --region us-east-2 --no-cli-pager

cat local/security-group-rules.json
```

Vérifier dix ressources CloudFormation : quatre groupes et six règles entrantes ; chaque groupe a aussi sa règle de sortie intégrée. Dans le JSON, vérifier le même VPC, les six règles du tableau, les sources SG pour web/RDS et SSH limité au `/32` sur le bastion. Ces vérifications portent sur la configuration ; aucun test applicatif n'est encore effectué.

En cas d'échec :

```bash
aws cloudformation describe-stack-events \
  --stack-name lab6-security \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED` || ResourceStatus==`UPDATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
  --output table --region us-east-2 --no-cli-pager
```

Si la stack est en `ROLLBACK_COMPLETE`, corriger la cause, supprimer uniquement la stack échouée, attendre sa suppression puis relancer. Si elle a déjà été utilisée par des ressources ultérieures, ne pas la supprimer avant d'avoir traité ces dépendances.

## Commit et PR après validation AWS

Mettre les deux README à jour une fois le déploiement réellement réussi. Ils sont fournis avec l'étape 02 encore « à déployer » pour éviter d'annoncer un résultat non obtenu.

```bash
git add README.md README.fr.md cloudformation/02-security-groups.yaml scripts/deploy-security-groups.sh docs/
git diff --cached --check
git diff --cached --stat
git commit -m "infra: manage RDS lab security groups with CloudFormation"
git push -u origin HEAD
```

Créer une PR avec **base `develop`** et la branche actuelle comme comparaison. Titre : `Infra: manage ALB, bastion, web and RDS security groups with CloudFormation`. Noter les validations réellement obtenues ; conserver les IP et détails du compte hors des preuves publiées.

## Nettoyage et prochaines étapes

EC2, RDS et ALB seront ajoutés par les prochains templates, puis le déploiement applicatif sera automatisé. Pour nettoyer le lab : supprimer d'abord leurs stacks, puis celle de sécurité et enfin celle du réseau.

```bash
aws cloudformation delete-stack --stack-name lab6-security --region us-east-2
aws cloudformation wait stack-delete-complete --stack-name lab6-security --region us-east-2
```

Ne pas exécuter le nettoyage pendant la réalisation du lab. Supprimer la stack de sécurité ne supprime pas le NAT du réseau. Aucune commande de création/suppression manuelle de groupe n'est requise.

## Sources

- [CloudFormation — SecurityGroup](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-ec2-securitygroup.html)
- [CloudFormation — SecurityGroupIngress](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-ec2-securitygroupingress.html)
- [AWS — règles des groupes de sécurité](https://docs.aws.amazon.com/vpc/latest/userguide/security-group-rules.html)
- [Lab d'origine](https://github.com/inspiredevgen/devops-worksphops/blob/main/2-Cloud-Infrastructure/LABS/RDS/aws-lab-rds-python-alb/RDS-Python-ALB-Lab.en.md)
