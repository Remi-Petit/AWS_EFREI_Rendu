# Infrastructure Complète - AWS ECS Fargate

## Architecture

```
Internet
    │
   WAF (AWS WAF v2)
    │
   ALB (multi-AZ)
    │
  ┌─┴─────────────┐
  │  Subnets       │
  │  Privés ECS    │ ← Fargate Tasks (auto scaling CPU + mémoire)
  └────────────────┘
  
  Subnets Admin (isolés, accès VPN uniquement)
```

## Fichiers

| Fichier | Rôle |
|---|---|
| `provider.tf` | Configuration AWS provider |
| `variables.tf` | Variables globales |
| `locals.tf` | Config prod/test (CIDR, CPU, mémoire, scaling) |
| `vpc.tf` | VPC, subnets (public/privé/admin), IGW, NAT, routes |
| `nacl.tf` | Network ACLs (couche réseau) |
| `security_groups.tf` | Security Groups (ALB, ECS, RDS, Admin) |
| `iam.tf` | Rôles ECS, groupes IAM (admin/dev/readonly), password policy |
| `secrets.tf` | AWS Secrets Manager |
| `ecr.tf` | Dépôts ECR (scan on push, lifecycle 10 images) |
| `ecs.tf` | Clusters, task definitions, services |
| `alb.tf` | Application Load Balancer, target groups, listeners |
| `autoscaling.tf` | Auto scaling CPU (cible 60 %) + mémoire (cible 70 %) |
| `aurora.tf` | Base de données PostgreSQL (RDS) |
| `directus.tf` | Service Directus CMS (module ECS) |
| `pgadmin.tf` | Interface pgAdmin (module ECS) |
| `s3.tf` | Buckets S3 assets (versioning prod, lecture publique) |
| `dns.tf` | Zone Route 53 + certificat ACM wildcard |
| `waf.tf` | WAF (common rules, bot control, rate limiting) |
| `vpn.tf` | AWS Client VPN (accès admin nomade) |
| `cloudtrail.tf` | Audit de toutes les actions AWS |
| `monitoring.tf` | Alarmes CloudWatch + SNS + Dashboard |
| `scheduler.tf` | Arrêt/démarrage automatique env test via Lambda + EventBridge |
| `budget.tf` | Budget mensuel AWS avec alerte email |
| `outputs.tf` | URLs et informations utiles |
| `modules/` | Modules réutilisables (directus, pgadmin, …) |
| `lambda/` | Sources Python des Lambdas du scheduler |

## Déploiement

```bash
# 1. Initialiser
terraform init

# 2. Vérifier
terraform plan

# 3. Déployer
terraform apply

terraform destroy
```

## VPN (étape manuelle requise)

Voir les commentaires dans `vpn.tf` pour générer les certificats.
Une fois les ARNs obtenus, les ajouter dans `terraform.tfvars` :

```hcl
vpn_server_cert_arn = "arn:aws:acm:eu-west-3:XXXX:certificate/..."
vpn_client_cert_arn = "arn:aws:acm:eu-west-3:XXXX:certificate/..."
```

## Environnements

| Paramètre | Prod | Test |
|---|---|---|
| VPC CIDR | 10.0.0.0/16 | 10.1.0.0/16 |
| Tasks souhaitées | 3 | 1 |
| CPU | 512 | 256 |
| Mémoire | 1024 MB | 512 MB |
| Min tasks | 3 | 1 |
| Max tasks | 10 | 3 |

## IAM - Groupes utilisateurs

| Groupe | Accès |
|---|---|
| `myapp-admins` | AdministratorAccess |
| `myapp-developers` | ECS deploy + CloudWatch read |
| `myapp-readonly` | ReadOnlyAccess |

## Sécurité réseau

- **WAF** : règles communes AWS + bot control + rate limiting (2 000 req/5 min par IP)
- **NACLs** : filtre réseau avant les security groups
- **Security Groups** : ECS accepte uniquement le trafic depuis l'ALB
- **Subnets admin** : réseau isolé, accès VPN uniquement
- **CloudTrail** : audit de toutes les actions multi-région

## Monitoring

- Alarme CPU > 80%
- Alarme erreurs 5xx > 10
- Alarme latence > 1s
- Notifications par email via SNS
- Dashboard CloudWatch (CPU, mémoire, requêtes, erreurs, latence)

## Voir le mot de passe pour pgAdmin
terraform output aurora_endpoints 2>/dev/null || terraform output -json aurora_endpoints 2>/dev/null

aws secretsmanager get-secret-value --secret-id "myapp/test/pgadmin" --region eu-west-3 --query SecretString --output text 2>/dev/null

## Voir le mot de passe PostgreSQL
python3 -c "
import json
with open('terraform.tfstate') as f:
    s = json.load(f)
for r in s['resources']:
    if r['type'] == 'random_password' and r['name'] == 'aurora':
        for i in r['instances']:
            print(i.get('index_key'), ':', i['attributes']['result'])
" 2>&1