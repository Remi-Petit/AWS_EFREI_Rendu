# Ansible — Déploiement applicatif sur ECS

Ce dossier gère la partie **logicielle** de l'infrastructure, en complément de Terraform qui gère la partie réseau et infrastructure.

## Principe de séparation des responsabilités

```
Terraform  →  Infrastructure (VPC, ALB, ECS cluster, IAM, ECR, ...)
Ansible    →  Logiciel       (build image, push ECR, déploiement ECS)
```

Terraform est configuré avec `lifecycle { ignore_changes }` sur les task definitions et les services ECS : il ne réécrasera jamais ce qu'Ansible déploie.

---

## Prérequis

### Outils locaux
- Python ≥ 3.10
- Ansible ≥ 2.15
- AWS CLI v2 configuré (`aws configure`)
- Docker (daemon en cours d'exécution)

### Permissions AWS requises
Le profil AWS utilisé doit avoir accès à :
- `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:PutImage`, ...
- `ecs:RegisterTaskDefinition`, `ecs:UpdateService`, `ecs:DescribeServices`
- `sts:GetCallerIdentity`

### Infrastructure Terraform déployée
Les ressources suivantes doivent exister avant d'utiliser ces playbooks :
- Dépôts ECR (`terraform output ecr_repository_urls`)
- Clusters ECS (`terraform output ecs_cluster_names`)
- Services ECS (`terraform output ecs_service_names`)

---

## Installation

```bash
# Créer et activer le virtualenv Python attendu par ansible.cfg
python3 -m venv ~/.venv/ansible
source ~/.venv/ansible/bin/activate
pip install boto3 botocore

# Installer les collections Ansible AWS
ansible-galaxy collection install -r requirements.yml

# AWS CLI v2 (hors virtualenv)
sudo apt install awscli   # ou utiliser le binaire officiel AWS
```

---

## Structure

```
ansible/
├── ansible.cfg               # Configuration Ansible (roles path, stdout_callback, venv Python)
├── requirements.yml          # Collections : amazon.aws, community.aws (>=7.0.0)
├── deploy.yml                # Playbook principal
├── collections/              # Collections installées localement (ansible-galaxy)
├── group_vars/
│   └── all.yml               # Variables globales (aws_region, project)
└── roles/
    ├── ecr_push/             # Build Docker + push vers ECR
    │   ├── defaults/main.yml
    │   └── tasks/main.yml
    └── ecs_deploy/           # Mise à jour task definition + déploiement ECS
        ├── defaults/main.yml
        └── tasks/main.yml
```

---

## Variables

| Variable | Défaut | Description |
|---|---|---|
| `env` | `test` | Environnement cible (`prod` ou `test`) |
| `image_tag` | `latest` | Tag de l'image Docker à déployer |
| `dockerfile_path` | `.` | Chemin vers le dossier contenant le Dockerfile |
| `aws_region` | `eu-west-3` | Région AWS (défini dans `group_vars/all.yml`) |
| `project` | `myapp` | Nom du projet (doit correspondre à la variable Terraform) |

---

## Utilisation

### Déploiement complet (build → push → déploiement)

```bash
# Environnement de test, tag latest
ansible-playbook deploy.yml \
  -e env=test \
  -e dockerfile_path=../app

# Environnement de production, tag versionné
ansible-playbook deploy.yml \
  -e env=prod \
  -e image_tag=1.2.3 \
  -e dockerfile_path=../app
```

### Déploiement uniquement (image déjà dans ECR)

```bash
ansible-playbook deploy.yml \
  -e env=prod \
  -e image_tag=1.2.3 \
  --tags ecs_deploy
```

---

## Flux d'exécution

```
deploy.yml
│
├── [role: ecr_push]
│   ├── 1. Récupère l'ID du compte AWS (sts:GetCallerIdentity)
│   ├── 2. Calcule l'URI ECR  →  <account>.dkr.ecr.<region>.amazonaws.com/<project>/<env>:<tag>
│   ├── 3. Authentification Docker auprès d'ECR
│   ├── 4. docker build -t <uri> <dockerfile_path>
│   └── 5. docker push <uri>
│
└── [role: ecs_deploy]
    ├── 1. Récupère la task definition courante (pour réutiliser CPU/mémoire/logs)
    ├── 2. Enregistre une nouvelle révision avec la nouvelle image
    ├── 3. Met à jour le service ECS (force_new_deployment: true)
    └── 4. Attend la stabilisation (running == desired, retries: 30 × 20s)
```

---

## Exemples de sortie

```
TASK [ecs_deploy : Afficher l'état final du service] ***
ok: [localhost] => {
    "msg": "Service myapp-prod-service stable : 3/3 tâches actives — image : 123456789.dkr.ecr.eu-west-3.amazonaws.com/myapp/prod:1.2.3"
}
```

---

## Rollback

Pour revenir à une version précédente, rejouer le playbook avec le tag de l'image souhaitée :

```bash
ansible-playbook deploy.yml \
  -e env=prod \
  -e image_tag=1.1.0 \
  -e dockerfile_path=../app
```

Chaque `image_tag` correspond à une image disponible dans le dépôt ECR. Les 10 dernières images sont conservées (lifecycle policy ECR).
