# Étape 01 — Réseau CloudFormation dans us-east-2

[English](en/01-network.md) | [Workflow Git](git-workflow.md) | [Accueil](../README.fr.md)

## Ce que crée le template

| Ressource | Adresse / placement | Utilité |
|---|---|---|
| VPC `lab6-vpc` | `10.10.0.0/16` | Réseau isolé du lab, résolution DNS activée |
| `lab6-bastion-subnet` | `10.10.0.0/28`, AZ A | Accès SSH via un futur bastion public |
| `lab6-public-a` | `10.10.1.0/24`, AZ A | ALB public et NAT Gateway |
| `lab6-public-b` | `10.10.2.0/24`, AZ B | Deuxième zone de l'ALB |
| `lab6-private-a` | `10.10.11.0/24`, AZ A | Serveur web A et sous-réseau du groupe RDS |
| `lab6-private-b` | `10.10.12.0/24`, AZ B | Serveur web B et sous-réseau du groupe RDS |
| Internet Gateway + table publique | Route `0.0.0.0/0 → IGW` | Routage Internet des trois sous-réseaux publics |
| Table privée + NAT optionnel | Route `0.0.0.0/0 → NAT` si activé | Sortie Internet des serveurs privés |

Un sous-réseau public est défini par sa route vers l'IGW. L'attribution automatique d'IPv4 publiques reste désactivée sur les deux sous-réseaux de l'ALB ; le service ALB gérera ses propres adresses. Elle est activée uniquement sur le sous-réseau du bastion.

Les cinq CIDR sont fixes pour rester compatibles avec les droits SQL du guide d'origine. Les noms utilisent `lab6-` pour distinguer ce lab ; sélectionner nos IDs dans les écrans où le guide emploie `lab-vpc` ou `lab-public-a`.

Ce template crée le réseau uniquement. Les groupes de sécurité, EC2, RDS et l'ALB seront ajoutés par les templates CloudFormation suivants, déployés depuis Git Bash. Le groupe de sous-réseaux RDS utilisera les deux sous-réseaux privés ; cela ne transforme pas la future base Single-AZ en base Multi-AZ.

## 1. Connexion et région

Dans Git Bash, si une ancienne commande `aws login` attend encore, l'interrompre avec **Ctrl+C**. Puis :

```bash
aws configure set region us-east-2
aws login --region us-east-2
aws sts get-caller-identity --query Arn --output text --region us-east-2
aws ec2 describe-availability-zones \
  --region us-east-2 \
  --query 'AvailabilityZones[?State==`available`].ZoneName' \
  --output table
```

Terminer la connexion dans le navigateur avant les commandes suivantes. Ces commandes supposent le profil `default`. Vérifier que `us-east-2a` et `us-east-2b` sont disponibles ; sinon remplacer les deux valeurs AZ plus bas par deux zones distinctes réellement disponibles. Si une commande échoue avec `AccessDenied`, s'arrêter et traiter le message exact.

## 2. Valider le template

Depuis la racine du dépôt, sur `infra/01-network` :

```bash
aws cloudformation validate-template \
  --template-body file://cloudformation/01-network.yaml \
  --region us-east-2
```

Cette validation vérifie la structure du template. Elle ne garantit ni les permissions de création, ni les quotas, ni le déploiement.

## 3. Déployer le réseau

Le NAT est désactivé par défaut. Pour créer directement le réseau complet requis par les installations privées, la commande suivante l'active **avec une IPv4 publique facturable**. Il sera facturé tant qu'il reste provisionné, même sans trafic ; le traitement de données et certains transferts s'ajoutent. Ne pas supposer la gratuité à partir du type de compte.

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

Pour préparer le réseau sans NAT ni EIP, remplacer `EnableNatGateway=true` par `EnableNatGateway=false`. Réexécuter ensuite cette même commande avec `true` avant d'installer les dépendances sur les EC2 privées. Un seul NAT zonal dessert les deux AZ pour limiter le nombre de NAT ; cela ne fournit pas une sortie Internet tolérante à la panne d'une AZ.

## 4. Vérifier et garder les IDs localement

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

Résultat attendu : **`CREATE_COMPLETE`** au premier déploiement, puis **`UPDATE_COMPLETE`** après une mise à jour. La sortie CLI ci-dessus fournit les IDs du VPC, des cinq sous-réseaux et du NAT si activé. Pour inspecter les ressources gérées sans console AWS, utiliser :

```bash
aws cloudformation list-stack-resources \
  --stack-name lab6-network \
  --query 'StackResourceSummaries[].[LogicalResourceId,ResourceType,ResourceStatus]' \
  --output table --region us-east-2 --no-cli-pager
```

Pour conserver les sorties sans les publier :

```bash
mkdir -p local
aws cloudformation describe-stacks \
  --stack-name lab6-network \
  --query 'Stacks[0].Outputs' \
  --output json \
  --region us-east-2 > local/network-outputs.json
```

En cas d'échec, lire les événements, sans relancer la création à l'aveugle :

```bash
aws cloudformation describe-stack-events \
  --stack-name lab6-network \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
  --output table \
  --region us-east-2
```

Après `ROLLBACK_COMPLETE`, corriger la cause puis supprimer la stack échouée avant de recréer. Ne pas modifier manuellement les ressources gérées par cette stack. Revenir au [workflow Git](git-workflow.md) pour le commit et la PR.

## 5. Fin de session et nettoyage

Pour désactiver le NAT tout en gardant le réseau, réexécuter la commande de déploiement avec les **mêmes AZ**, mais `EnableNatGateway=false`. CloudFormation supprime la route privée, le NAT et son EIP. Les EC2 privées perdent alors leur sortie Internet via ce NAT. Cela ne supprime et n'arrête pas EC2, RDS ou l'ALB créés séparément.

Pour supprimer le réseau, **supprimer d'abord les stacks CloudFormation des ressources qui utilisent ce VPC**, notamment les futures stacks ALB, EC2 et RDS, puis `lab6-security`. Vérifier les éventuelles sauvegardes ou snapshots conservés. La suppression s'effectue depuis AWS CLI ; respecter l'ordre des dépendances. Puis :

```bash
aws cloudformation delete-stack --stack-name lab6-network --region us-east-2
aws cloudformation wait stack-delete-complete --stack-name lab6-network --region us-east-2
```

La suppression du réseau seule ne constitue pas le nettoyage complet du lab. Une interface réseau encore utilisée peut bloquer la suppression du VPC ; lire alors les événements de suppression et retirer sa ressource propriétaire.

## Sources

- [Lab d'origine](https://github.com/inspiredevgen/devops-worksphops/blob/main/2-Cloud-Infrastructure/LABS/RDS/aws-lab-rds-python-alb/RDS-Python-ALB-Lab.en.md)
- [AWS CLI : connexion avec les identifiants de console](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html)
- [CloudFormation : NAT Gateway](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-ec2-natgateway.html)
- [RDS dans un VPC et sous-réseaux sur deux AZ](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_VPC.WorkingWithRDSInstanceinaVPC.html)
- [Tarification NAT et IPv4](https://aws.amazon.com/vpc/pricing/)
