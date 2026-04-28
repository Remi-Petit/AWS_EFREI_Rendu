# Scripts d'administration — Environnement de test

## Prérequis

- AWS CLI configuré avec les droits `ecs:UpdateService`, `rds:StartDBInstance`, `rds:StopDBInstance`
- Variable `AWS_PROFILE` optionnelle pour sélectionner un profil AWS spécifique

## Variables d'environnement

| Variable | Défaut | Description |
|---|---|---|
| `AWS_REGION` | `eu-west-3` | Région AWS |
| `PROJECT` | `myapp` | Nom du projet (doit correspondre à la variable Terraform) |
| `ECS_DESIRED_COUNT` | `1` | Nombre de tâches ECS à lancer au démarrage |
| `AWS_PROFILE` | *(profil par défaut)* | Profil AWS CLI à utiliser |

## Exécution manuelle

```bash
# Arrêter l'environnement de test (ECS + RDS)
bash /home/aws/scripts/stop_test_env.sh

# Démarrer l'environnement de test (ECS + RDS)
# Note : attend la disponibilité RDS (~2-3 min) avant de relancer ECS
bash /home/aws/scripts/start_test_env.sh

# Avec surcharge de variables
AWS_REGION=eu-west-1 PROJECT=myapp ECS_DESIRED_COUNT=2 bash /home/aws/scripts/start_test_env.sh
```

## Planification automatique via cron

```bash
# Ouvrir l'éditeur cron
crontab -e
```

Ajouter les lignes suivantes pour arrêter à 19h et démarrer à 8h (jours ouvrés) :

```
0 19 * * 1-5 /home/aws/scripts/stop_test_env.sh  >> /var/log/aws_scheduler.log 2>&1
0 8  * * 1-5 /home/aws/scripts/start_test_env.sh >> /var/log/aws_scheduler.log 2>&1
```

## Vérification

```bash
# Voir les crons actifs
crontab -l

# Consulter les logs d'exécution
cat /var/log/aws_scheduler.log
```