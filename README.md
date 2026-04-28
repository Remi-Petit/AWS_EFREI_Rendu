# Architecture AWS — myapp (aws.remipetit.fr)

> Région : **eu-west-3 (Paris)** · Deux environnements : **prod** et **test**  
> Infrastructure as Code : **Terraform** · Déploiements : **Ansible**

---

## Vue d'ensemble

```mermaid
flowchart TD
    Internet((Internet))

    subgraph DNS_TLS["DNS & TLS"]
        R53[Route 53\naws.remipetit.fr]
        ACM[ACM Wildcard\n*.aws.remipetit.fr]
    end

    subgraph WAF["Sécurité périmétrique"]
        WAFV2[WAF v2\nCommonRuleSet · BotControl\nRate Limit 2000 req/IP]
    end

    subgraph PROD_VPC["VPC prod — 10.0.0.0/16"]
        direction TB

        subgraph PUB_P["Subnets publics (AZ a/b/c)"]
            ALB_P[ALB prod\nHTTP→HTTPS redirect\nHTTPS :443 · TLS 1.3]
        end

        subgraph PRIV_P["Subnets privés (AZ a/b/c)"]
            ECS_P[ECS Fargate — Cluster prod\nApp  ·  Directus  ·  pgAdmin\nAuto-scaling CPU 60% / Mem 70%\nmin 3 · max 10 tasks]
            RDS_P[RDS PostgreSQL 18\nMulti-AZ · db.t3.micro\nchiffrement activé\nsnapshot final]
            S3_P[S3 Assets prod\nVersioning activé\nLecture publique + CORS]
        end

        subgraph ADMIN_P["Subnets admin (AZ a/b/c)"]
            VPN_P[Client VPN prod\n10.200.0.0/22\nSplit-tunnel · cert mTLS]
        end
    end

    subgraph TEST_VPC["VPC test — 10.1.0.0/16"]
        direction TB

        subgraph PUB_T["Subnets publics (AZ a/b/c)"]
            ALB_T[ALB test\nHTTP→HTTPS redirect\nHTTPS :443]
        end

        subgraph PRIV_T["Subnets privés (AZ a/b/c)"]
            ECS_T[ECS Fargate — Cluster test\nApp  ·  Directus  ·  pgAdmin\nAuto-scaling CPU 60% / Mem 70%\nmin 1 · max 3 tasks]
            RDS_T[RDS PostgreSQL 18\nSingle-AZ · db.t3.micro\nSSL désactivé]
            S3_T[S3 Assets test\nVersioning suspendu\nLecture publique + CORS]
        end

        subgraph ADMIN_T["Subnets admin (AZ a/b/c)"]
            VPN_T[Client VPN test\n10.200.4.0/22]
        end
    end

    subgraph SHARED["Services partagés AWS"]
        ECR[ECR\nmyapp/prod · myapp/test\nScan on push · 10 images max]
        CW[CloudWatch Logs\n/ecs/ · /vpn/\nRétention 30j]
        SNS[SNS\nAlertes email admin]
        CT[CloudTrail\nMulti-région · S3 dédié]
        SCHED[EventBridge Scheduler\n+ Lambda\nStop test 19h · Start 8h L-V]
        SM[Secrets Manager\nMots de passe DB]
        BUDGET[AWS Budgets\nAlertes coût]
    end

    subgraph CICD["CI/CD — Ansible"]
        ANS[Ansible\nbuild Docker\npush ECR\ndeploy ECS]
    end

    %% Flux principal
    Internet --> R53
    R53 --> WAFV2
    WAFV2 --> ALB_P
    WAFV2 --> ALB_T

    %% PROD
    ALB_P --> ECS_P
    ECS_P --> RDS_P
    ECS_P --> S3_P
    VPN_P -.->|accès admin| ECS_P
    VPN_P -.->|accès admin| RDS_P

    %% TEST
    ALB_T --> ECS_T
    ECS_T --> RDS_T
    ECS_T --> S3_T
    VPN_T -.->|accès admin| ECS_T
    VPN_T -.->|accès admin| RDS_T

    %% Shared
    ECR --> ECS_P
    ECR --> ECS_T
    ECS_P --> CW
    ECS_T --> CW
    CW --> SNS
    ANS --> ECR
    SCHED -.->|stop/start| ECS_T
    SCHED -.->|stop/start| RDS_T
    SM --> ECS_P
    SM --> ECS_T

    %% DNS/TLS
    ACM --> ALB_P
    ACM --> ALB_T
```

# AWS
https://us-east-1.console.aws.amazon.com/console/home?region=us-east-1

# Test
https://directus-test.aws.remipetit.fr
https://test.aws.remipetit.fr/pgadmin
https://directus-test.aws.remipetit.fr/items/products
https://directus-test.aws.remipetit.fr/server/health

# Prod
https://directus-app.aws.remipetit.fr
https://app.aws.remipetit.fr/pgadmin
https://directus-app.aws.remipetit.fr/items/products
https://directus-app.aws.remipetit.fr/server/health

aws secretsmanager get-secret-value --secret-id myapp/test/directus --region eu-west-3 --query "SecretString" --output text 2>&1 | python3 -m json.tool