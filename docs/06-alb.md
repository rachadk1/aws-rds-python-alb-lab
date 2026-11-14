# Étape 06 — Application Load Balancer

**Français** | [English](en/06-alb.md)

Le navigateur envoie une requête HTTP au nom DNS de l’ALB sur le port 80. Le listener la transmet à un groupe cible qui contient WebA et WebB sur le port 8080. L’ALB occupe les deux sous-réseaux publics des zones `us-east-2a` et `us-east-2b`. Ses connexions vers les EC2 passent par leurs adresses privées. Le groupe de sécurité Web accepte le port 8080 depuis le groupe de sécurité de l’ALB. Chaque application continue d’interroger la même base MySQL privée sur le port 3306.

## Déployer et vérifier

Depuis la racine du dépôt sur `infra/06-alb`, avec les stacks des étapes 01 à 05 actives :

```bash
bash scripts/deploy-alb.sh
bash scripts/check-alb.sh
```

Si la session AWS a expiré, exécute `aws login --region us-east-2` et reprends à la commande qui a échoué. Le déploiement crée la stack `lab6-alb`, qui contient l’ALB, le listener et le groupe cible. CloudFormation produit l’URL publique. Le script de vérification attend deux cibles `healthy`, teste la page d’accueil, puis envoie 20 requêtes. `ALB_OK` signifie que l’accueil a rendu HTTP 200 et que les deux EC2 ont répondu avec leur zone et une connexion RDS TLS via l’ALB.

| Test | Ce qu’il vérifie |
|---|---|
| Contrôle ALB `/health` sur chaque cible | Gunicorn et Flask répondent. La route ne consulte pas MySQL. |
| Accueil public `/` | Le navigateur peut atteindre l’ALB et Flask rend la page des cours. |
| `/health?strict=1` via l’ALB | Flask atteint RDS, négocie TLS et peut compter les étudiants. `served_by` et `az` identifient le serveur. |

Si une cible est `unhealthy`, lis la colonne `Reason`, puis vérifie le service Flask et le flux ALB → EC2 sur 8080. Si la route stricte rend HTTP 503, vérifie la connexion EC2 → RDS à l’aide des tests de [l’étape 05](05-python.md).

## Essayer le formulaire

1. Ouvre l’URL `http://` affichée par le script. Vérifie la présence des cours et du champ **Serveur**.
2. Inscris un étudiant fictif avec une adresse unique se terminant par `@example.com`. Note l’instance affichée dans le message de confirmation.
3. Recharge la page jusqu’à voir l’autre instance dans le champ **Serveur**. Le même étudiant doit apparaître, car les deux serveurs lisent la même base.
4. Soumets de nouveau le même courriel. Le formulaire doit signaler le doublon. Le contrôle strict doit maintenant indiquer 13 étudiants si la base n’avait que les 12 étudiants initiaux.

Le listener est en HTTP pour cet exercice public. Utilise seulement des données fictives. AWS peut facturer l’ALB, son utilisation et ses adresses IPv4 publiques. Pour arrêter ces frais après l’exercice, supprime la stack `lab6-alb` et attends la fin de sa suppression. Les autres stacks du lab peuvent continuer à générer leurs propres frais.

```bash
aws cloudformation delete-stack --stack-name lab6-alb --region us-east-2
aws cloudformation wait stack-delete-complete --stack-name lab6-alb --region us-east-2
```

## GitHub

Quand les tests ont réussi, publie `infra/06-alb` et ouvre une PR avec **base `develop`** et **compare `infra/06-alb`**. Note les deux AZ et le nombre de réponses par serveur dans la PR.
