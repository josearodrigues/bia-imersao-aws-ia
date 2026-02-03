#!/bin/bash

# Deploy com versionamento - Projeto BIA
# Uso: ./deploy-versioned.sh [commit-hash]

set -e

# Configurações
CLUSTER_NAME="cluster-bia"
SERVICE_NAME="service-bia"
TASK_FAMILY="task-def-bia"
ECR_REPO="381491977261.dkr.ecr.us-east-1.amazonaws.com/bia"
REGION="us-east-1"

# Obter commit hash
if [ -n "$1" ]; then
    COMMIT_HASH="$1"
else
    COMMIT_HASH=$(git rev-parse --short HEAD)
fi

echo "🚀 Iniciando deploy com versão: $COMMIT_HASH"

# 1. Build e push da imagem
echo "📦 Fazendo build da imagem..."
docker build -t bia:$COMMIT_HASH .

echo "🏷️  Taggeando imagem para ECR..."
docker tag bia:$COMMIT_HASH $ECR_REPO:$COMMIT_HASH

echo "🔐 Fazendo login no ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REPO

echo "⬆️  Fazendo push da imagem..."
docker push $ECR_REPO:$COMMIT_HASH

# 2. Obter task definition atual
echo "📋 Obtendo task definition atual..."
TASK_DEF=$(aws ecs describe-task-definition --task-definition $TASK_FAMILY --region $REGION)

# 3. Criar nova task definition com nova imagem
echo "🔄 Criando nova task definition..."
NEW_TASK_DEF=$(echo $TASK_DEF | jq --arg IMAGE "$ECR_REPO:$COMMIT_HASH" '
  .taskDefinition |
  .containerDefinitions[0].image = $IMAGE |
  del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy)
')

# 4. Registrar nova task definition
echo "📝 Registrando nova task definition..."
echo $NEW_TASK_DEF > /tmp/task-def.json
NEW_TASK_ARN=$(aws ecs register-task-definition --region $REGION --cli-input-json file:///tmp/task-def.json --query 'taskDefinition.taskDefinitionArn' --output text)

echo "✅ Nova task definition criada: $NEW_TASK_ARN"

# 5. Atualizar service
echo "🔄 Atualizando service ECS..."
aws ecs update-service \
  --cluster $CLUSTER_NAME \
  --service $SERVICE_NAME \
  --task-definition $NEW_TASK_ARN \
  --region $REGION \
  --query 'service.serviceName' \
  --output text

echo "⏳ Aguardando deploy estabilizar..."
aws ecs wait services-stable \
  --cluster $CLUSTER_NAME \
  --services $SERVICE_NAME \
  --region $REGION

echo "🎉 Deploy concluído com sucesso!"
echo "📊 Versão deployada: $COMMIT_HASH"
echo "🔗 Task Definition: $NEW_TASK_ARN"
