# Git and GitHub workflow

[Français](../git-workflow.md) | [Home](../../README.md)

## 1. Create an empty repository

On GitHub, create **`aws-rds-python-alb-lab`** under `rachadk1`. Select Public for the portfolio, without generating a README, license or `.gitignore`. The supplied folder already contains the starter files. If the repository already exists, do not overwrite it: clone and inspect its contents before applying these instructions.

Extract the archive, open Git Bash in `aws-rds-python-alb-lab`, then run:

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

If Git requires an identity, use your name and verified GitHub email or the private GitHub email listed in Settings → Emails. If pushing requires authentication, use the browser sign-in offered by Git Credential Manager; an ordinary GitHub account password does not work for Git over HTTPS.

The `cloudformation/` and `docs/` files are still untracked: this is expected. They belong on the stage 01 branch.

## 2. Validate and publish the network stage

Follow [stage 01](01-network.md), verify the AWS stack, then run:

```bash
git status
git diff --check
git add cloudformation/01-network.yaml docs/
git diff --cached --check
git diff --cached --stat
git commit -m "infra: add two-AZ network foundation for RDS lab"
git push -u origin infra/01-network
```

Open a GitHub PR with **base `develop`** and **compare `infra/01-network`**.

Title: `Infra: add two-AZ network foundation for RDS lab`

Update this description with the results actually obtained:

```text
EN: Add a VPC, five subnets across two AZs, public/private routing and
an optional zonal NAT Gateway for the RDS/Python/ALB lab in us-east-2.
FR : Ajouter le VPC, cinq sous-reseaux sur deux AZ, le routage et
un NAT Gateway zonal optionnel pour le lab RDS/Python/ALB en us-east-2.

Validation: [record the actual commands and results / noter les resultats reels]
AWS stack: [CREATE_COMPLETE or explain failure / expliquer tout echec]
NAT: [enabled or disabled / active ou desactive]
```

After review and merge on GitHub:

```bash
git switch develop
git pull --ff-only origin develop
```

Create the next branch from `develop` only when that stage starts, for example `infra/02-security-groups`. Do not delete the local work branch before merging.

## 3. Build portfolio evidence

For each stage: explain the technical choice, validate it, record actual results in both languages, and open a PR into `develop`. Keep evidence free of secrets. After the complete lab and cleanup are verified, open a `develop` to `main` PR to publish the final version.
