# Workflow Git et GitHub

[English](en/git-workflow.md) | [Accueil](../README.fr.md)

## 1. Créer le dépôt vide

Sur GitHub, créer **`aws-rds-python-alb-lab`** dans le compte `rachadk1`. Choisir Public pour le portfolio, sans ajouter de README, de licence ni de `.gitignore` lors de la création. Le dossier fourni contient déjà les fichiers de départ. Si ce dépôt existe déjà, ne pas l'écraser : le cloner et vérifier son contenu avant d'appliquer ces instructions.

Extraire l'archive, ouvrir Git Bash dans le dossier `aws-rds-python-alb-lab`, puis :

```bash
git init -b main
git add README.md README.fr.md .gitignore .gitattributes
git commit -m "docs: initialize bilingual RDS lab overview"
git remote add origin https://github.com/rachadk1/aws-rds-python-alb-lab.git
git push -u origin main
git switch -c develop
git push -u origin develop
git switch -c infra/01-network
```

Si Git demande une identité, utiliser ton nom et ton adresse GitHub vérifiée ou l'adresse privée GitHub fournie dans Settings → Emails. Si `git push` demande une connexion, utiliser l'authentification GitHub du navigateur proposée par Git Credential Manager ; un mot de passe GitHub classique ne fonctionne pas pour Git HTTPS.

Les fichiers `cloudformation/` et `docs/` sont encore non suivis : c'est attendu. Ils appartiennent à la branche de l'étape 01.

## 2. Valider et publier l'étape réseau

Suivre [l'étape 01](01-network.md), vérifier la stack dans AWS, puis :

```bash
git status
git diff --check
git add cloudformation/01-network.yaml docs/
git diff --cached --check
git diff --cached --stat
git commit -m "infra: add two-AZ network foundation for RDS lab"
git push -u origin infra/01-network
```

Créer une PR sur GitHub avec **base `develop`** et **compare `infra/01-network`**.

Titre : `Infra: add two-AZ network foundation for RDS lab`

Description à adapter avec les résultats réellement obtenus :

```text
EN: Add a VPC, five subnets across two AZs, public/private routing and
an optional zonal NAT Gateway for the RDS/Python/ALB lab in us-east-2.
FR : Ajouter le VPC, cinq sous-reseaux sur deux AZ, le routage et
un NAT Gateway zonal optionnel pour le lab RDS/Python/ALB en us-east-2.

Validation: [record the actual commands and results / noter les resultats reels]
AWS stack: [CREATE_COMPLETE or explain failure / expliquer tout echec]
NAT: [enabled or disabled / active ou desactive]
```

Après revue et fusion sur GitHub :

```bash
git switch develop
git pull --ff-only origin develop
```

Créer la prochaine branche depuis `develop` seulement quand l'étape suivante commence, par exemple `infra/02-security-groups`. Ne pas supprimer la branche locale de travail avant la fusion.

## 3. Constituer le portfolio

Pour chaque étape : expliquer le choix technique, valider, noter les résultats dans les deux langues, puis ouvrir une PR vers `develop`. Conserver les preuves expurgées des secrets. Après validation du lab complet et du nettoyage, ouvrir une PR `develop` vers `main` pour publier la version finale.
