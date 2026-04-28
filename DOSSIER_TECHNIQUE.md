# Dossier Technique — Déploiement et sécurisation d'une application web sur AWS
**Projet : WebMarket+** | Module : Panorama du Cloud et Déploiement AWS | EFREI Paris  
Région AWS : **eu-west-3 (Paris)** | Domaine : **aws.remipetit.fr**

---

## Table des matières

1. [Partie 1 — Conception de l'architecture cloud](#partie-1)
2. [Partie 2 — Infrastructure as Code et automatisation](#partie-2)
3. [Partie 3 — Monitoring et analyse performance / coûts](#partie-3)
4. [Partie 4 — Sécurisation de l'architecture](#partie-4)
5. [Partie 5 — Synthèse et recommandations à la DSI](#partie-5)

---

<a name="partie-1"></a>
## Partie 1 — Conception de l'architecture cloud (C21, C24, C26)

### 1.1 Architecture cible sur AWS

L'architecture déployée s'articule autour de **deux environnements isolés** (prod et test), chacun dans son propre VPC, couvrant les quatre piliers demandés.

#### Schéma d'architecture

```
                          ┌─────────────────────────────────────────┐
                          │           Internet / Utilisateurs         │
                          └────────────────────┬────────────────────┘
                                               │ HTTPS
                          ┌────────────────────▼────────────────────┐
                          │     Route 53 — aws.remipetit.fr          │
                          │   ACM Wildcard *.aws.remipetit.fr (TLS)  │
                          └────────────────────┬────────────────────┘
                                               │
                          ┌────────────────────▼────────────────────┐
                          │         WAF v2 (REGIONAL)                │
                          │  • AWS Managed Rules (CommonRuleSet)     │
                          │  • Bot Control                           │
                          │  • Rate Limit 2 000 req/IP               │
                          └──────────┬─────────────────┬────────────┘
                                     │                 │
               ┌─────────────────────▼───┐   ┌────────▼────────────────┐
               │   VPC PROD 10.0.0.0/16  │   │  VPC TEST 10.1.0.0/16  │
               │                         │   │                          │
               │ ┌─ Subnets publics ────┐ │   │ ┌─ Subnets publics ───┐ │
               │ │ ALB (3 AZ)           │ │   │ │ ALB (3 AZ)          │ │
               │ │ HTTP→HTTPS, TLS 1.3  │ │   │ │ HTTP→HTTPS          │ │
               │ └──────────┬───────────┘ │   │ └─────────┬───────────┘ │
               │            │             │   │           │             │
               │ ┌─ Subnets privés ─────┐ │   │ ┌─Subnets privés ────┐ │
               │ │ ECS Fargate (3→10)   │ │   │ │ ECS Fargate (1→3)  │ │
               │ │  • App principale    │ │   │ │  • App principale  │ │
               │ │  • Directus CMS      │ │   │ │  • Directus CMS    │ │
               │ │  • pgAdmin           │ │   │ │  • pgAdmin         │ │
               │ │          │           │ │   │ │         │          │ │
               │ │ RDS PostgreSQL 18    │ │   │ │ RDS PostgreSQL 18  │ │
               │ │  Multi-AZ, chiffré   │ │   │ │  Single-AZ         │ │
               │ │ S3 Assets (public)   │ │   │ │ S3 Assets          │ │
               │ └──────────────────────┘ │   │ └────────────────────┘ │
               │                         │   │                          │
               │ ┌─ Subnets admin ──────┐ │   │ ┌─ Subnets admin ────┐ │
               │ │ Client VPN (mTLS)    │ │   │ │ Client VPN (mTLS)  │ │
               │ └──────────────────────┘ │   │ └────────────────────┘ │
               └─────────────────────────┘   └──────────────────────────┘

               ┌────────────────────────────────────────────────────────┐
               │                  Services partagés                     │
               │  ECR · CloudWatch · SNS · CloudTrail · Secrets Manager │
               │  EventBridge Scheduler · Lambda · AWS Budgets · IAM    │
               └────────────────────────────────────────────────────────┘

               ┌────────────────────────────────────────────────────────┐
               │              CI/CD — Ansible (local)                   │
               │  docker build → ECR push → ECS force-new-deployment    │
               └────────────────────────────────────────────────────────┘
```

#### Services de calcul

| Service | Rôle | Justification |
|---------|------|---------------|
| **ECS Fargate** | Hébergement des containers (App, Directus, pgAdmin) | Serverless : pas de gestion de serveurs, facturation à la tâche, scaling natif |
| **ECR** | Registry Docker privée | Intégration native ECS, scan de vulnérabilités à chaque push |
| **EventBridge + Lambda** | Planification arrêt/démarrage env test | Automatisation sans serveur, coût quasi nul |

Dimensionnement prod : **512 vCPU / 1 024 MB** par task, 3 à 10 tâches.  
Dimensionnement test : **256 vCPU / 512 MB** par task, 1 à 3 tâches.

#### Gestion des données

| Service | Rôle |
|---------|------|
| **RDS PostgreSQL 18** | Base de données applicative — Multi-AZ en prod, Single-AZ en test |
| **S3** | Stockage des fichiers uploadés via Directus (assets, images produits) |
| **Secrets Manager** | Stockage sécurisé des mots de passe DB et clés API |
| **S3 (CloudTrail)** | Archivage des logs d'audit AWS |

#### Réseau (VPC)

Chaque environnement dispose d'un VPC dédié avec **3 niveaux de subnets** répartis sur 3 zones de disponibilité :

| Tier | CIDR prod | CIDR test | Contenu |
|------|-----------|-----------|---------|
| Public | `10.0.0.x/20` | `10.1.0.x/20` | Application Load Balancer |
| Privé | `10.0.3.x/20` | `10.1.3.x/20` | ECS Fargate, RDS PostgreSQL |
| Admin | `10.0.6.x/20` | `10.1.6.x/20` | Client VPN (accès opérateur) |

Chaque VPC dispose d'une **Internet Gateway** pour le tier public et d'une **NAT Gateway** (ou VPC Endpoint) pour les sorties des tiers privés.

#### IAM — Gestion des identités et des accès

| Entité IAM | Permissions | Principe |
|------------|-------------|---------|
| `ecs-execution-role` | `AmazonECSTaskExecutionRolePolicy` + lecture Secrets Manager | Permet à ECS de démarrer les containers et lire les secrets |
| `ecs-task-role` | S3 `Get/Put/Delete/List` sur les buckets assets | Permissions minimales pour l'application |
| `lambda-scheduler-role` | ECS `ListServices/UpdateService`, RDS `Stop/Start/Describe` | Dédié aux Lambdas de planification |
| Groupe `admins` | `AdministratorAccess` | Équipe infrastructure uniquement |
| Groupe `developers` | ECS read/deploy, CloudWatch read, ECR pull | Moindre privilège — pas d'accès prod DB |
| Groupe `readonly` | `ReadOnlyAccess` | Observabilité sans modification |

---

### 1.2 Justification des choix

#### Réponse aux besoins métiers et contraintes de performance

**Pics de charge (soldes, fêtes)** : L'auto-scaling ECS Fargate ajuste automatiquement le nombre de tâches selon le CPU (seuil 60 %) et la mémoire (seuil 70 %). En prod, le cluster peut passer de 3 à 10 tâches en moins de 60 secondes (`scale_out_cooldown = 60`). L'ALB distribue le trafic sur plusieurs tâches et plusieurs AZ.

**Disponibilité et résilience** : La prod s'étend sur 3 zones de disponibilité (AZ a, b, c en eu-west-3). L'ALB est multi-AZ. RDS est en mode Multi-AZ (failover automatique en cas de panne AZ). Le `desired_count = 3` garantit qu'une panne d'AZ n'interrompt pas le service.

**Sécurité et traçabilité** : WAF v2 filtre les attaques communes (OWASP Top 10, bots, rate limiting). CloudTrail enregistre toutes les actions API AWS. CloudWatch Logs centralise les logs applicatifs avec une rétention de 30 jours.

#### Influence des choix sur les coûts (FinOps)

| Levier | Impact coût |
|--------|------------|
| ECS Fargate vs EC2 | Pas d'instances sous-utilisées — facturation à la seconde de task active |
| Env test arrêté 15h/jour (19h-8h) et week-ends | Économie ~60 % sur le coût test |
| RDS test Single-AZ | Coût divisé par ~2 vs Multi-AZ |
| S3 pour les assets | Coût négligeable vs EFS ou EBS |
| AWS Budgets | Alerte email à 80 % du budget mensuel (50 USD par défaut) puis à 100 % |
| ECR lifecycle policy | Conservation de 10 images max — évite l'accumulation de storage ECR |

#### Architecture comme levier d'optimisation du SI

- **Évolutivité** : Ajout d'un nouvel environnement (staging, QA) = ajouter une entrée dans `local.env_config`. Tout le reste se déploie automatiquement.
- **Industrialisation** : Terraform gère l'infrastructure de façon reproductible et versionnable. Ansible automatise les déploiements sans intervention manuelle.
- **Résilience** : Multi-AZ sur l'ensemble des composants critiques en prod. Snapshots RDS automatiques. S3 avec versioning activé.
- **Séparation prod/test** : VPCs isolés — une erreur en test n'impacte jamais la prod.

---

<a name="partie-2"></a>
## Partie 2 — Infrastructure as Code et automatisation (C22, C23)

### 2.1 Infrastructure as Code avec Terraform

L'ensemble de l'infrastructure est décrit sous forme de code Terraform organisé en fichiers thématiques.

#### Structure des fichiers IaC

```
terraform/
├── provider.tf          # Provider AWS, région eu-west-3
├── variables.tf         # Variables (région, projet, environnements, domaine)
├── locals.tf            # Configurations par env (CIDR, CPU, mémoire, scaling)
├── vpc.tf               # VPC, subnets public/privé/admin, IGW, routes
├── nacl.tf              # Network ACLs (filtrage L3)
├── security_groups.tf   # Security Groups ALB, ECS, RDS, Admin
├── alb.tf               # Application Load Balancer, listeners HTTP/HTTPS
├── dns.tf               # Route 53, ACM wildcard, validation DNS
├── ecr.tf               # ECR repositories, lifecycle policies
├── ecs.tf               # Clusters, task definitions, services ECS Fargate
├── aurora.tf            # RDS PostgreSQL 18, subnet groups, parameter groups
├── s3.tf                # Buckets assets + CloudTrail, versioning, CORS, policies
├── iam.tf               # Rôles et groupes IAM
├── secrets.tf           # Secrets Manager (mots de passe DB, clés API)
├── waf.tf               # WAF v2, règles managées, rate limiting
├── vpn.tf               # Client VPN endpoint, associations subnets
├── autoscaling.tf       # Application Auto Scaling (CPU + mémoire)
├── monitoring.tf        # CloudWatch alarms, SNS topics
├── cloudtrail.tf        # CloudTrail multi-région
├── scheduler.tf         # EventBridge Scheduler + Lambda stop/start
├── budget.tf            # AWS Budgets avec alertes
├── directus.tf          # Module Directus CMS (ECS service dédié)
├── pgadmin.tf           # Module pgAdmin (ECS service dédié)
└── modules/
    ├── directus/        # Module réutilisable : task def, service, target group
    └── pgadmin/         # Module réutilisable : task def, service, target group
```

#### Points clés de l'IaC

**Réseau (vpc.tf)** : Chaque VPC est créé via `for_each = local.env_config`. Les subnets sont calculés dynamiquement avec `cidrsubnet()` et répartis sur 3 AZ. Les CIDR publics, privés et admin sont décalés par index (`idx`, `idx+3`, `idx+6`) pour éviter les chevauchements.

**Calcul (ecs.tf)** : Les task definitions référencent les images ECR via leur URL dynamique. La clause `lifecycle { ignore_changes = [container_definitions] }` empêche Terraform d'écraser les déploiements gérés par Ansible.

**Base de données (aurora.tf)** : En prod, `multi_az = true` et `deletion_protection = true`. En test, `multi_az = false` et un parameter group désactivant SSL est appliqué pour simplifier les connexions locales.

**Modularisation** : Les services Directus et pgAdmin sont implémentés comme des modules Terraform réutilisables, acceptant les paramètres de VPC, cluster ECS et listener ALB en entrée.

---

### 2.2 Automatisation des tâches d'administration

#### a) Pipeline de déploiement CI/CD — Ansible

```yaml
# ansible/deploy.yml
- name: Build et push de l'image Docker vers ECR
  hosts: localhost
  roles: [ecr_push]

- name: Déploiement de la nouvelle image sur ECS
  hosts: localhost
  roles: [ecs_deploy]
```

**Usage** :
```bash
ansible-playbook deploy.yml -e env=prod -e image_tag=1.2.3 -e dockerfile_path=../app
ansible-playbook deploy.yml -e env=test   # image_tag=latest par défaut
```

Le rôle `ecr_push` exécute `docker build` et `docker push` vers ECR.  
Le rôle `ecs_deploy` force un nouveau déploiement ECS (`update-service --force-new-deployment`).

#### b) Arrêt / démarrage planifié de l'environnement test — Lambda + EventBridge

**Objectif** : Réduire les coûts en arrêtant l'env test en dehors des heures de bureau.

```
EventBridge Scheduler
  ├─ Lundi–Vendredi 19h00 UTC → Lambda stop_test_env
  │     ├─ ECS : desired_count = 0 sur tous les services du cluster test
  │     └─ RDS : StopDBInstance (myapp-test-postgres)
  │
  └─ Lundi–Vendredi 08h00 UTC → Lambda start_test_env
        ├─ ECS : desired_count = 1 sur tous les services
        └─ RDS : StartDBInstance
```

Les Lambdas listent dynamiquement tous les services ECS du cluster test : aucune modification du code n'est nécessaire lors de l'ajout d'un nouveau service.

**Prérequis** : `terraform/lambda/stop_test_env.py` et `start_test_env.py` packagés en ZIP et déployés automatiquement par Terraform.

#### c) Scripts manuels complémentaires (scripts/)

| Script | Objectif |
|--------|---------|
| `start_test_env.sh` | Démarrage manuel de l'env test (CLI AWS) |
| `stop_test_env.sh` | Arrêt manuel de l'env test (CLI AWS) |

---

<a name="partie-3"></a>
## Partie 3 — Monitoring et analyse de la performance / des coûts (C21, C24, C26)

### 3.1 Indicateurs de pilotage retenus

| # | Indicateur | Type | Source | Seuil d'alerte |
|---|-----------|------|--------|----------------|
| 1 | **CPU ECS** (`ECSServiceAverageCPUUtilization`) | Technique | CloudWatch / ECS | > 80 % pendant 2 min |
| 2 | **Taux d'erreurs 5xx ALB** (`HTTPCode_Target_5XX_Count`) | Technique | CloudWatch / ALB | > 10 erreurs / min × 2 |
| 3 | **Latence ALB** (`TargetResponseTime`) | Technique | CloudWatch / ALB | > seuil × 3 périodes |
| 4 | **Coût mensuel** (AWS Budgets) | Coût | AWS Budgets | Prévision > 80 % du budget ($50) |
| 5 | **Utilisation mémoire ECS** (`ECSServiceAverageMemoryUtilization`) | Technique | CloudWatch / ECS | Déclenche l'auto-scaling à 70 % |

### 3.2 Dispositif de monitoring

#### Dashboard CloudWatch

Un dashboard CloudWatch est créé automatiquement par Terraform pour chaque environnement (`myapp-prod`, `myapp-test`). URL d'accès générée en output :

```
https://console.aws.amazon.com/cloudwatch/home?region=eu-west-3#dashboards:name=myapp-prod
```

**Widgets recommandés à configurer** :
- Graphe CPU ECS (moyenne par service, fenêtre 1h)
- Graphe mémoire ECS
- Compteur erreurs 5xx ALB (SUM, 5 min)
- Latence ALB (P95, 5 min)
- Coût journalier (AWS Cost Explorer widget)

#### Alertes configurées

```hcl
# monitoring.tf — Alarme CPU ECS > 80%
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "myapp-prod-cpu-high"
  threshold           = 80
  evaluation_periods  = 2
  alarm_actions       = [aws_sns_topic.alerts["prod"].arn]
}

# Alarme erreurs 5xx ALB > 10
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "myapp-prod-alb-5xx"
  threshold           = 10
  evaluation_periods  = 2
  alarm_actions       = [aws_sns_topic.alerts["prod"].arn]
}
```

Toutes les alarmes envoient une notification email via **SNS** à `remi.petit@efrei.net`.  
Une alerte **AWS Budgets** est configurée à 80 % de la prévision mensuelle ($40 sur $50) et à 100 % des coûts réels.

### 3.3 Analyse et pistes d'optimisation

#### Scénario de charge simulé

En période nominale (charge moyenne) :
- CPU ECS prod : ~35 % → 3 tâches actives suffisent
- Latence ALB : < 200 ms
- Erreurs 5xx : 0

En pic de charge (×5 requêtes) :
- CPU monte à ~65 % → auto-scaling déclenche l'ajout de tâches (cooldown 60 s)
- La montée en charge est absorbée sous 2 minutes

#### Piste d'optimisation 1 — Rightsizing des task ECS

**Constat** : La configuration prod actuelle (512 vCPU / 1 024 MB) est généreuse. En charge nominale, la mémoire est utilisée à ~40 %.  
**Action** : Passer à 256 vCPU / 512 MB en phase initiale, surveiller 2 semaines, puis ajuster.  
**Impact SI** : Réduction du coût Fargate de ~40 %. Aucun risque si l'auto-scaling est actif.

#### Piste d'optimisation 2 — Extension des plages d'arrêt test

**Constat** : L'env test est actuellement arrêté de 19h à 8h en semaine (13h/jour) et actif le week-end.  
**Action** : Étendre l'arrêt au week-end complet (vendredi 19h → lundi 8h) via un ajustement du scheduler EventBridge.  
**Impact SI** : L'env test passerait de ~120h actives/semaine à ~45h, soit une économie supplémentaire de ~62 % sur le coût test.

---

<a name="partie-4"></a>
## Partie 4 — Sécurisation de l'architecture cloud (C25, C26)

### 4.1 Stratégie IAM — Moindre privilège

#### Groupes d'utilisateurs

| Groupe | Membres | Permissions |
|--------|---------|-------------|
| `myapp-admins` | Équipe infrastructure | `AdministratorAccess` — accès complet |
| `myapp-developers` | Développeurs | ECS describe/list/update, ECR pull, CloudWatch read, logs read |
| `myapp-readonly` | Métier / monitoring | `ReadOnlyAccess` — lecture seule sur tous les services |

#### Rôles de service

| Rôle | Attaché à | Permissions accordées |
|------|-----------|----------------------|
| `myapp-ecs-execution-role` | ECS (démarrage tasks) | `AmazonECSTaskExecutionRolePolicy` + `secretsmanager:GetSecretValue` sur `myapp/*` uniquement |
| `myapp-ecs-task-role` | Containers applicatifs | S3 `Get/Put/Delete/List` sur les buckets assets — rien d'autre |
| `myapp-lambda-scheduler-role` | Lambdas stop/start | ECS `ListServices/UpdateService`, RDS `Stop/Start/Describe` — périmètre minimal |

**Application du moindre privilège** :
- Le rôle task ne peut pas lire les secrets (séparation du rôle execution et task)
- Le rôle execution ne peut lire que les secrets avec le préfixe `myapp/`
- Les développeurs ne peuvent pas modifier la configuration d'infrastructure (pas de `terraform apply`)

---

### 4.2 Politique de sécurité réseau

#### Segmentation

```
Internet
  └─▶ ALB (subnets publics) ─ SG-ALB : in 80/443 from 0.0.0.0/0
        └─▶ ECS Fargate (subnets privés) ─ SG-ECS : in 80/8055 from SG-ALB only
              └─▶ RDS PostgreSQL (subnets privés) ─ SG-RDS : in 5432 from SG-ECS only

Administrateur
  └─▶ VPN Client (subnets admin) ─ SG-Admin : in 22/443 from VPN CIDR 10.200.0.0/16
        └─▶ RDS, ECS (port 5432, debug)
```

#### Security Groups

| SG | Inbound autorisé | Outbound |
|----|-----------------|---------|
| `sg-alb` | 80/443 depuis `0.0.0.0/0` | Tout |
| `sg-ecs` | 80 et 8055 depuis `sg-alb` uniquement | Tout |
| `sg-rds` | 5432 depuis `sg-ecs` uniquement | Tout |
| `sg-admin` | 22 et 443 depuis `10.200.0.0/16` (VPN) uniquement | Tout |

#### Network ACLs (double couche de filtrage)

- **NACL publique** : autorise TCP 80/443 et les ports éphémères (1024-65535) en entrée
- **NACL admin** : autorise uniquement le CIDR VPN (`10.200.0.0/16`) sur les ports 22 et 443
- Les subnets privés n'ont pas de route vers l'Internet Gateway (isolation réseau totale)

---

### 4.3 Protection des données

#### Chiffrement

| Donnée | Mécanisme | Détail |
|--------|-----------|--------|
| RDS au repos | `storage_encrypted = true` | Chiffrement AES-256 via AWS KMS |
| Secrets Manager | Chiffrement natif AWS | Mots de passe DB et clés API chiffrés au repos |
| Transit HTTPS | TLS 1.3 | `ELBSecurityPolicy-TLS13-1-2-2021-06` sur l'ALB |
| Transit DB | SSL activé en prod | Parameter group `default.postgres18` force SSL en prod |
| S3 | Chiffrement serveur (SSE-S3) | Activé par défaut sur tous les buckets |

#### Journalisation et audit

| Service | Logs | Rétention |
|---------|------|-----------|
| CloudTrail | Toutes les actions API AWS (multi-région) | Illimitée (S3) |
| CloudWatch Logs `/ecs/myapp/*` | Logs applicatifs containers | 30 jours |
| CloudWatch Logs `/vpn/myapp/*` | Connexions VPN (qui, quand, depuis où) | 90 jours |
| ALB Access Logs | Requêtes HTTP/HTTPS (IP, URL, code retour) | À activer sur S3 |

---

### 4.4 Mini-revue d'audit

#### Tableau Risque → Impact → Mesure

| # | Risque identifié | Probabilité | Impact | Mesure / Action corrective | Priorité |
|---|-----------------|------------|--------|---------------------------|---------|
| 1 | **Bucket S3 assets public en lecture** — des fichiers sensibles pourraient être exposés par erreur si uploadés dans Directus sans contrôle | Moyenne | Élevé | Mettre en place une politique de nommage des fichiers privés + activer S3 Object Lock pour les données sensibles. Envisager CloudFront avec signed URLs pour ne plus exposer S3 directement. | **Haute** |
| 2 | **Credentials ECR/AWS sur la machine Ansible** — si le poste du développeur est compromis, les secrets AWS peuvent être volés | Moyenne | Élevé | Utiliser des rôles IAM assumables via AWS STS (`sts:AssumeRole`) plutôt que des access keys statiques. Activer MFA sur tous les comptes IAM du groupe admins. | **Haute** |
| 3 | **Pas de WAF sur les endpoints internes** (pgAdmin, Directus) — ils sont accessibles depuis Internet via l'ALB avec seulement la priorité de règle comme protection | Faible | Moyen | Restreindre les Target Groups de pgAdmin et Directus admin à une IP fixe ou au CIDR VPN via une règle de condition ALB (`aws:SourceIp`). Ou placer pgAdmin derrière le VPN uniquement. | **Moyenne** |

---

<a name="partie-5"></a>
## Partie 5 — Synthèse et recommandations à la DSI (C21 à C26)

### 5.1 Synthèse du dossier technique

#### Contexte et besoins de WebMarket+

WebMarket+ gère un catalogue produit et des stocks pour des commerçants. L'hébergement on-premise posait quatre problèmes : incapacité à gérer les pics de charge, manque de visibilité sur les coûts, risques de sécurité, et dépendance à une petite équipe. La migration AWS répond à chacun de ces points.

#### Architecture cloud déployée

L'architecture s'appuie sur **ECS Fargate** pour le calcul (pas de gestion de serveurs), **RDS PostgreSQL** pour les données (multi-AZ en prod), **S3** pour les fichiers statiques, et **ALB + WAF + Route 53 + ACM** pour l'exposition sécurisée. Deux environnements (prod, test) sont isolés dans des VPCs distincts.

#### Infrastructure as Code

100 % de l'infrastructure est codifiée en **Terraform**, découpée en 20+ fichiers thématiques. Les déploiements applicatifs sont gérés par **Ansible** (build Docker → push ECR → update ECS). Cette séparation claire permet à l'équipe infrastructure (Terraform) et aux développeurs (Ansible) de travailler indépendamment.

#### Monitoring

4 alarmes CloudWatch actives (CPU, mémoire, 5xx, latence) déclenchent des alertes email via SNS. AWS Budgets surveille les coûts avec alerte à 80 % de prévision. CloudTrail assure l'audit complet de toutes les actions AWS.

#### Sécurité

Architecture en défense en profondeur : WAF → ALB → Security Groups → NACL → RDS isolé. IAM avec moindre privilège. Chiffrement au repos (RDS, S3, Secrets Manager) et en transit (TLS 1.3). VPN mTLS pour l'accès admin.

---

### 5.2 Recommandations à la DSI (C26)

#### Actions prioritaires

| Priorité | Action | Horizon | Intérêt SI | Impact coût | Risques |
|----------|--------|---------|-----------|------------|---------|
| 🔴 **1** | Activer MFA obligatoire sur tous les comptes IAM admins + remplacer les access keys statiques Ansible par des rôles IAM assumables via STS | Court terme (< 1 mois) | Sécurité critique — protection contre le vol de credentials | Nul | Légère friction pour les développeurs lors du setup initial |
| 🔴 **2** | Restreindre pgAdmin et l'interface admin Directus au VPN uniquement (condition `aws:SourceIp` sur les listener rules ALB) | Court terme (< 1 mois) | Réduction drastique de la surface d'attaque | Nul | Oblige les admins à se connecter via VPN |
| 🟡 **3** | Activer CloudFront devant S3 (signed URLs) pour ne plus exposer les buckets publiquement | Moyen terme (1-3 mois) | Sécurité des assets + performance CDN (edge caching) | Léger surcoût CloudFront (~$0.01/GB), compensé par la réduction des requêtes S3 directes | Nécessite des modifications dans Directus pour la génération des URLs |
| 🟡 **4** | Étendre l'arrêt de l'env test au week-end entier via EventBridge Scheduler | Court terme (< 2 semaines) | Optimisation FinOps — économie ~62 % sur le coût test | **−$10 à −15/mois** estimés | Aucun — l'env test doit rester non utilisé le week-end |
| 🟢 **5** | Rightsizing ECS prod (256 vCPU / 512 MB) après 2 semaines de métriques | Moyen terme (1-2 mois) | Réduction des coûts Fargate sans impact performance | **−30 à −40 %** sur le coût Fargate | À surveiller avec les alarmes CPU existantes — rollback facile |
| 🟢 **6** | Activer AWS Compute Optimizer pour les recommandations automatiques de sizing | Moyen terme | Pilotage continu du rightsizing sans effort manuel | Gratuit | Aucun |

#### Projection de scalabilité

**Doublement de la charge** : L'auto-scaling ECS absorbe le doublement en ajoutant des tâches (de 3 à 6 en prod). L'ALB est dimensionné pour supporter ce volume. Le seul point de vigilance est la connexion RDS (`max_connections` de PostgreSQL dépend de la RAM de l'instance) — envisager **RDS Proxy** pour le pooling de connexions si le nombre de tâches ECS dépasse 8-10.

#### Vision à moyen terme (6-12 mois)

1. **Mettre en place un pipeline CI/CD complet** (GitHub Actions ou CodePipeline) pour remplacer l'exécution manuelle d'Ansible — meilleure traçabilité, déploiements automatiques sur merge.
2. **Évaluer Aurora Serverless v2** à la place de RDS PostgreSQL — facturation à la capacité consommée, idéal pour les charges variables comme WebMarket+.
3. **Activer AWS Cost Anomaly Detection** — détection automatique des pics de dépenses inattendus par apprentissage automatique.
4. **Documenter un PRA (Plan de Reprise d'Activité)** — tester le failover Multi-AZ RDS et la reconstruction de l'infrastructure depuis zéro via Terraform.
