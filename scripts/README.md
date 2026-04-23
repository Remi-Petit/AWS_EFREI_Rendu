# Scripts d'administration — Environnement de test

## Exécution manuelle

```bash
# Arrêter l'environnement de test (ECS + RDS)
bash /home/admin/Cloud_Efrei_AWS/AWS_Cloud/scripts/stop_test_env.sh

# Démarrer l'environnement de test (ECS + RDS)
bash /home/admin/Cloud_Efrei_AWS/AWS_Cloud/scripts/start_test_env.sh
```

## Planification automatique via cron

```bash
# Ouvrir l'éditeur cron
crontab -e
```

Ajouter les lignes suivantes pour arrêter à 19h et démarrer à 8h (jours ouvrés) :

```
0 19 * * 1-5 /home/admin/Cloud_Efrei_AWS/AWS_Cloud/scripts/stop_test_env.sh  >> /var/log/aws_scheduler.log 2>&1
0 8  * * 1-5 /home/admin/Cloud_Efrei_AWS/AWS_Cloud/scripts/start_test_env.sh >> /var/log/aws_scheduler.log 2>&1
```

## Vérification

```bash
# Voir les crons actifs
crontab -l

# Consulter les logs d'exécution
cat /var/log/aws_scheduler.log
```
r.log 2>&1