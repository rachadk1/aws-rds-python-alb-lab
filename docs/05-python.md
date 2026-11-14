# Étape 05 — Application Python et TLS vers RDS

**Français** | [English](en/05-python.md)

Flask traite les requêtes HTTP. Gunicorn écoute sur le port 8080 sur chacune des deux EC2 privées. Le service `labapp` tourne avec un compte Linux dédié. Les deux copies utilisent la même base MySQL pour lire les cours et enregistrer les inscriptions.

Le script rend localement le template en y intégrant l'archive du dossier [app](../app). CloudFormation déploie le document Systems Manager (SSM) et une association par EC2 web. Chaque agent SSM installe l'application et teste le service sur sa propre instance. Le NAT déjà déployé permet le téléchargement des paquets et du certificat RDS. Les ressources SSM sont gérées par la stack `lab6-python`.

Le profil IAM créé à l'étape 04B autorise la lecture du secret `appuser` dans Secrets Manager. L'installation récupère ce secret et systemd le fournit au service sous forme de fichier. MySQL valide les droits SQL d'`appuser` tandis que le client Python vérifie le certificat et le nom DNS de RDS. Le mot de passe n'est saisi dans aucune commande.

## Déployer depuis Git Bash

Depuis la racine du dépôt sur `app/05-python`, avec les stacks 01 à 04B actives dans `us-east-2` :

```bash
git status --short --branch
aws sts get-caller-identity --region us-east-2 --query Arn --output text
bash scripts/deploy-python.sh
```

Si la session AWS a expiré, exécute `aws login --region us-east-2`, puis relance le script. Celui-ci requiert les deux agents SSM `Online`, la base `available` et le NAT activé.

## Lire et comprendre les résultats

```bash
bash scripts/show-python-results.sh
```

| Test local à chaque EC2 | Résultat attendu | Ce qu'il vérifie |
|---|---|---|
| `GET /health` | HTTP 200 | Gunicorn et Flask traitent la requête sans interroger RDS. |
| `GET /health?strict=1` | HTTP 200, chiffrement TLS et au moins 12 étudiants | Flask ouvre une session MySQL chiffrée vers RDS avec le compte applicatif et peut lire la table. |
| `GET /` | HTTP 200 | Flask rend la page avec les cours et les dernières inscriptions. |

Attends deux résultats `Status: Success` et deux lignes `APP_READY` avec des identifiants et zones distincts. Les résultats de la requête stricte montrent les champs `db_tls` et `students`. Les deux EC2 interrogent les mêmes données. L'étape 06 ajoutera l'accès par ALB et permettra d'essayer l'inscription dans le navigateur avec des données fictives.

En cas d'échec, relève la valeur `step=` dans `APP_DEPLOY_FAILED` si le résultat de l'association est disponible. `dependencies` pointe vers `/var/log/lab6-app-packages.log` sur l'instance. `application_secret` indique un problème de récupération du secret ou du profil IAM. `mysql_readiness` pointe vers le flux EC2 → RDS, le certificat ou les droits MySQL. `bash scripts/deploy-python.sh --retry` force une nouvelle exécution des associations pour une stack déjà déployée. Pour un premier déploiement en `ROLLBACK_COMPLETE`, supprime uniquement la stack `lab6-python` et attends sa suppression avant de relancer le déploiement.

## Workflow GitHub

Quand les deux instances ont réussi, publie ta branche et ouvre la PR avec **base `develop`**, **compare `app/05-python`**. Ajoute au résumé les deux AZ, le nombre d'étudiants et le résultat TLS. `main` sert de page d'accueil du portfolio.

Pour le nettoyage complet du lab, retire `lab6-python` avant les stacks dont elle lit les sorties. La suppression des associations SSM ne désinstalle pas les fichiers déjà copiés sur les EC2. La suppression de la stack EC2 supprime ces fichiers avec les volumes racine du lab.
