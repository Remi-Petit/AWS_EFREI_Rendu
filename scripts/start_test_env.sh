#!/bin/bash
# =============================================================================
# start_test_env.sh
# Objectif   : Redémarrer l'environnement de test (ECS + RDS) en début de
#              journée (ex. 8h) après l'arrêt nocturne.
# Prérequis  : aws CLI configuré avec les droits ecs:UpdateService et
#              rds:StartDBInstance, variable AWS_PROFILE optionnelle.
# Paramètres : Aucun (valeurs codées ci-dessous, modifiables via variables
#              d'environnement).
# Usage      : ./start_test_env.sh
#              ou via cron : 0 8 * * 1-5 /chemin/start_test_env.sh >> /var/log/aws_scheduler.log 2>&1
# =============================================================================

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
AWS_REGION="${AWS_REGION:-eu-west-3}"
PROJECT="${PROJECT:-myapp}"
ENV="test"

ECS_CLUSTER="${PROJECT}-${ENV}-cluster"
RDS_IDENTIFIER="${PROJECT}-${ENV}-postgres"
ECS_DESIRED_COUNT="${ECS_DESIRED_COUNT:-1}"   # desired_count de l'env test dans locals.tf

# ── Fonctions utilitaires ─────────────────────────────────────────────────────
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

start_ecs_service() {
  local service=$1
  log "Démarrage du service ECS : ${service} (desired=${ECS_DESIRED_COUNT})"
  DESIRED=$(aws ecs update-service \
    --region "${AWS_REGION}" \
    --cluster "${ECS_CLUSTER}" \
    --service "${service}" \
    --desired-count "${ECS_DESIRED_COUNT}" \
    --output text \
    --query "service.desiredCount" 2>/dev/null || echo "not-found")
  if [[ "${DESIRED}" == "not-found" ]]; then
    log "  ⚠ Service '${service}' introuvable, ignoré."
  else
    log "  → desiredCount = ${DESIRED}"
  fi
}

# ── Démarrage de l'instance RDS ───────────────────────────────────────────────
RDS_STATUS=$(aws rds describe-db-instances \
  --region "${AWS_REGION}" \
  --db-instance-identifier "${RDS_IDENTIFIER}" \
  --query "DBInstances[0].DBInstanceStatus" \
  --output text 2>/dev/null || echo "not-found")

if [[ "${RDS_STATUS}" == "stopped" ]]; then
  log "Démarrage de l'instance RDS : ${RDS_IDENTIFIER}"
  NEW_STATUS=$(aws rds start-db-instance \
    --region "${AWS_REGION}" \
    --db-instance-identifier "${RDS_IDENTIFIER}" \
    --output text \
    --query "DBInstance.DBInstanceStatus")
  log "  → nouveau statut = ${NEW_STATUS}"

  # Attendre que RDS soit disponible avant de relancer ECS
  log "Attente disponibilité RDS (peut prendre ~2-3 minutes)..."
  aws rds wait db-instance-available \
    --region "${AWS_REGION}" \
    --db-instance-identifier "${RDS_IDENTIFIER}"
  log "  → RDS disponible."

elif [[ "${RDS_STATUS}" == "not-found" ]]; then
  log "  ⚠ Instance RDS '${RDS_IDENTIFIER}' introuvable, ignorée."
else
  log "  → RDS déjà dans l'état '${RDS_STATUS}', aucune action nécessaire."
fi

# ── Démarrage de tous les services ECS du cluster test ────────────────────────
SERVICES=$(aws ecs list-services \
  --cluster "${ECS_CLUSTER}" \
  --region "${AWS_REGION}" \
  --query "serviceArns[*]" \
  --output text)

for SERVICE_ARN in $SERVICES; do
  SERVICE_NAME=$(basename "${SERVICE_ARN}")
  start_ecs_service "${SERVICE_NAME}"
done

log "Environnement '${ENV}' démarré avec succès."
