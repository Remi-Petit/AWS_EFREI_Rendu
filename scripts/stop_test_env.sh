#!/bin/bash
# =============================================================================
# stop_test_env.sh
# Objectif   : Arrêter l'environnement de test (ECS + RDS) pour réduire les
#              coûts en dehors des heures ouvrées (ex. 19h → 8h).
# Prérequis  : aws CLI configuré avec les droits ecs:UpdateService et
#              rds:StopDBInstance, variable AWS_PROFILE optionnelle.
# Paramètres : Aucun (valeurs codées ci-dessous, modifiables via variables
#              d'environnement).
# Usage      : ./stop_test_env.sh
#              ou via cron : 0 19 * * 1-5 /chemin/stop_test_env.sh >> /var/log/aws_scheduler.log 2>&1
# =============================================================================

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
AWS_REGION="${AWS_REGION:-eu-west-3}"
PROJECT="${PROJECT:-myapp}"
ENV="test"

ECS_CLUSTER="${PROJECT}-${ENV}-cluster"
RDS_IDENTIFIER="${PROJECT}-${ENV}-postgres"

# ── Fonctions utilitaires ─────────────────────────────────────────────────────
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

stop_ecs_service() {
  local service=$1
  log "Arrêt du service ECS : ${service}"
  DESIRED=$(aws ecs update-service \
    --region "${AWS_REGION}" \
    --cluster "${ECS_CLUSTER}" \
    --service "${service}" \
    --desired-count 0 \
    --output text \
    --query "service.desiredCount" 2>/dev/null || echo "not-found")
  if [[ "${DESIRED}" == "not-found" ]]; then
    log "  ⚠ Service '${service}' introuvable, ignoré."
  else
    log "  → desiredCount = ${DESIRED}"
  fi
}

# ── Arrêt de tous les services ECS du cluster test ────────────────────────────
SERVICES=$(aws ecs list-services \
  --cluster "${ECS_CLUSTER}" \
  --region "${AWS_REGION}" \
  --query "serviceArns[*]" \
  --output text)

for SERVICE_ARN in $SERVICES; do
  SERVICE_NAME=$(basename "${SERVICE_ARN}")
  stop_ecs_service "${SERVICE_NAME}"
done

# ── Arrêt de l'instance RDS ───────────────────────────────────────────────────
# Vérification du statut avant tentative d'arrêt (évite une erreur si déjà arrêtée)
RDS_STATUS=$(aws rds describe-db-instances \
  --region "${AWS_REGION}" \
  --db-instance-identifier "${RDS_IDENTIFIER}" \
  --query "DBInstances[0].DBInstanceStatus" \
  --output text 2>/dev/null || echo "not-found")

if [[ "${RDS_STATUS}" == "available" ]]; then
  log "Arrêt de l'instance RDS : ${RDS_IDENTIFIER} (statut actuel : ${RDS_STATUS})"
  NEW_STATUS=$(aws rds stop-db-instance \
    --region "${AWS_REGION}" \
    --db-instance-identifier "${RDS_IDENTIFIER}" \
    --output text \
    --query "DBInstance.DBInstanceStatus")
  log "  → nouveau statut = ${NEW_STATUS}"
elif [[ "${RDS_STATUS}" == "not-found" ]]; then
  log "  ⚠ Instance RDS '${RDS_IDENTIFIER}' introuvable, ignorée."
else
  log "  → RDS déjà dans l'état '${RDS_STATUS}', aucune action nécessaire."
fi

log "Environnement '${ENV}' arrêté avec succès."
