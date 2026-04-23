"""
stop_test_env.py
Objectif   : Arrêter tous les services ECS et l'instance RDS de l'environnement
             de test. Déclenché par EventBridge Scheduler à 19h (lun-ven).
Prérequis  : Variables d'environnement ECS_CLUSTER, RDS_IDENTIFIER, AWS_REGION_NAME.
"""
import boto3
import os


def handler(event, context):
    region     = os.environ["AWS_REGION_NAME"]
    cluster    = os.environ["ECS_CLUSTER"]
    rds_id     = os.environ["RDS_IDENTIFIER"]

    ecs = boto3.client("ecs", region_name=region)
    rds = boto3.client("rds", region_name=region)

    # ── Arrêt de tous les services ECS (desired_count → 0) ───────────────────
    paginator = ecs.get_paginator("list_services")
    for page in paginator.paginate(cluster=cluster):
        for arn in page["serviceArns"]:
            name = arn.split("/")[-1]
            ecs.update_service(cluster=cluster, service=name, desiredCount=0)
            print(f"ECS stoppé : {name} → desiredCount=0")

    # ── Arrêt RDS ─────────────────────────────────────────────────────────────
    try:
        status = rds.describe_db_instances(DBInstanceIdentifier=rds_id)[
            "DBInstances"
        ][0]["DBInstanceStatus"]
        if status == "available":
            rds.stop_db_instance(DBInstanceIdentifier=rds_id)
            print(f"RDS arrêt demandé : {rds_id}")
        else:
            print(f"RDS déjà dans l'état '{status}', ignoré.")
    except rds.exceptions.DBInstanceNotFoundFault:
        print(f"RDS '{rds_id}' introuvable, ignoré.")

    return {"status": "success"}
