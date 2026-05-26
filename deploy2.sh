#!/bin/bash
# Uso:
#   Deploy:   ./deploy.sh [sem-alb|com-alb] deploy [commit-hash]
#   Rollback: ./deploy.sh [sem-alb|com-alb] rollback [image-tag]

set -e

ECR_REPO="381491977261.dkr.ecr.us-east-1.amazonaws.com/bia"
REGION="us-east-1"

# ── Ambiente ──────────────────────────────────────────────────────────────────
AMBIENTE="${1:-sem-alb}"
case "$AMBIENTE" in
  sem-alb)
    CLUSTER="cluster-bia"
    SERVICE="service-bia"
    TASK_FAMILY="task-def-bia"
    ;;
  com-alb)
    CLUSTER="cluster-bia-alb"
    SERVICE="service-bia-alb"
    TASK_FAMILY="task-def-bia-alb"
    ;;
  *)
    echo "❌ Ambiente inválido. Use: sem-alb | com-alb"
    exit 1
    ;;
esac

MODO="${2:-deploy}"

# ── Função: encontra task definition pela image tag ───────────────────────────
find_task_def_by_tag() {
  local TAG="$1"
  aws ecs list-task-definitions \
    --family-prefix "$TASK_FAMILY" \
    --sort DESC \
    --region "$REGION" \
    --query 'taskDefinitionArns[]' \
    --output text | tr '\t' '\n' | while read -r ARN; do
      IMAGE=$(aws ecs describe-task-definition --task-definition "$ARN" --region "$REGION" \
        --query 'taskDefinition.containerDefinitions[0].image' --output text)
      if [[ "$IMAGE" == *":$TAG" ]]; then
        echo "$ARN"
        return
      fi
    done
}

# ── Função: atualiza service e aguarda ────────────────────────────────────────
update_service() {
  local TASK_ARN="$1"
  echo "🔄 Atualizando service $SERVICE..."
  aws ecs update-service \
    --cluster "$CLUSTER" \
    --service "$SERVICE" \
    --task-definition "$TASK_ARN" \
    --region "$REGION" \
    --query 'service.taskDefinition' \
    --output text

  echo "⏳ Aguardando estabilização..."
  aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE" --region "$REGION"
}

# ── Rollback ──────────────────────────────────────────────────────────────────
if [ "$MODO" = "rollback" ]; then
  if [ -n "$3" ]; then
    IMAGE_TAG="$3"
  else
    echo ""
    echo "📋 Imagens disponíveis no ECR (últimas 10):"
    aws ecr describe-images \
      --repository-name bia \
      --region "$REGION" \
      --query 'sort_by(imageDetails, &imagePushedAt) | reverse(@) | [:10].[imageTags[0], imagePushedAt]' \
      --output table
    echo ""
    read -rp "Digite a image tag para rollback: " IMAGE_TAG
  fi

  echo "🔍 Buscando task definition para tag: $IMAGE_TAG"
  TASK_ARN=$(find_task_def_by_tag "$IMAGE_TAG")

  if [ -z "$TASK_ARN" ]; then
    echo "❌ Nenhuma task definition encontrada para a tag '$IMAGE_TAG'"
    exit 1
  fi

  echo "⏪ Rollback para: $TASK_ARN"
  update_service "$TASK_ARN"
  echo "✅ Rollback concluído! Tag: $IMAGE_TAG | Task: $TASK_ARN"
  exit 0
fi

# ── Deploy ────────────────────────────────────────────────────────────────────
COMMIT_HASH="${3:-$(git rev-parse --short HEAD)}"
IMAGE_URI="$ECR_REPO:$COMMIT_HASH"

echo "🚀 Deploy | Ambiente: $AMBIENTE | Versão: $COMMIT_HASH"

# Build
echo "📦 Build da imagem..."
docker build -t "bia:$COMMIT_HASH" .

# Push para ECR
echo "🔐 Login no ECR..."
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECR_REPO"

echo "⬆️  Push da imagem..."
docker tag "bia:$COMMIT_HASH" "$IMAGE_URI"
docker push "$IMAGE_URI"

# Registra nova task definition com a imagem do commit
echo "📋 Registrando nova task definition..."
TASK_DEF=$(aws ecs describe-task-definition --task-definition "$TASK_FAMILY" --region "$REGION")

NEW_TASK_DEF=$(echo "$TASK_DEF" | jq --arg IMAGE "$IMAGE_URI" '
  .taskDefinition |
  .containerDefinitions[0].image = $IMAGE |
  del(.taskDefinitionArn, .revision, .status, .requiresAttributes,
      .placementConstraints, .compatibilities, .registeredAt, .registeredBy)
')

echo "$NEW_TASK_DEF" > /tmp/task-def-bia.json
NEW_TASK_ARN=$(aws ecs register-task-definition \
  --region "$REGION" \
  --cli-input-json file:///tmp/task-def-bia.json \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)

echo "✅ Task definition: $NEW_TASK_ARN"
update_service "$NEW_TASK_ARN"

echo ""
echo "🎉 Deploy concluído!"
echo "   Versão : $COMMIT_HASH"
echo "   Imagem : $IMAGE_URI"
echo "   Task   : $NEW_TASK_ARN"
