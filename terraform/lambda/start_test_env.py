"""
start_test_env.py
Objectif   : Démarrer l'instance RDS puis tous les services ECS de l'environnement
             de test. Déclenché par EventBridge Scheduler à 8h (lun-ven).
             RDS est démarré en premier ; la Lambda attend qu'il soit disponible
             avant de relancer ECS (timeout Lambda : 10 min).
Prérequis  : Variables d'environnement ECS_CLUSTER, RDS_IDENTIFIER,
             AWS_REGION_NAME, DESIRED_COUNT (optionnel, défaut=1).
"""
import boto3
import os


def handler(event, context):
    region        = os.environ["AWS_REGION_NAME"]
    cluster       = os.environ["ECS_CLUSTER"]
    rds_id        = os.environ["RDS_IDENTIFIER"]
    desired_count = int(os.environ.get("DESIRED_COUNT", "1"))

    ecs = boto3.client("ecs", region_name=region)
    rds = boto3.client("rds", region_name=region)

    # ── Démarrage RDS ─────────────────────────────────────────────────────────
    try:
        status = rds.describe_db_instances(DBInstanceIdentifier=rds_id)[
            "DBInstances"
        ][0]["DBInstanceStatus"]

        if status == "stopped":
            rds.start_db_instance(DBInstanceIdentifier=rds_id)
            print(f"RDS démarrage demandé : {rds_id}")
            # Attente disponibilité (max 20 × 30s = 10 min)
            waiter = rds.get_waiter("db_instance_available")
            waiter.wait(
                DBInstanceIdentifier=rds_id,
                WaiterConfig={"Delay": 30, "MaxAttempts": 20},
            )
            print(f"RDS disponible : {rds_id}")
        else:
            print(f"RDS déjà dans l'état '{status}', aucune action.")
    except rds.exceptions.DBInstanceNotFoundFault:
        print(f"RDS '{rds_id}' introuvable, ignoré.")

    # ── Démarrage de tous les services ECS ────────────────────────────────────
    paginator = ecs.get_paginator("list_services")
    for page in paginator.paginate(cluster=cluster):
        for arn in page["serviceArns"]:
            name = arn.split("/")[-1]
            ecs.update_service(
                cluster=cluster, service=name, desiredCount=desired_count
            )
            print(f"ECS démarré : {name} → desiredCount={desired_count}")

    return {"status": "success"}
