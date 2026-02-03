#!/bin/bash

# Utilitários de versionamento - Projeto BIA
# Uso: ./version-utils.sh [list|rollback] [versao]

set -e

CLUSTER_NAME="cluster-bia"
SERVICE_NAME="service-bia"
TASK_FAMILY="task-def-bia"
ECR_REPO="381491977261.dkr.ecr.us-east-1.amazonaws.com/bia"
REGION="us-east-1"

case "$1" in
  "list")
    echo "📋 Listando versões disponíveis no ECR:"
    aws ecr describe-images \
      --repository-name bia \
      --region $REGION \
      --query 'sort_by(imageDetails,&imagePushedAt)[*].[imageTags[0],imagePushedAt]' \
      --output table
    
    echo ""
    echo "📋 Task Definitions do projeto:"
    aws ecs list-task-definitions \
      --family-prefix $TASK_FAMILY \
      --region $REGION \
      --query 'taskDefinitionArns[-5:]' \
      --output table
    ;;
    
  "rollback")
    if [ -z "$2" ]; then
      echo "❌ Erro: Especifique a versão para rollback"
      echo "Uso: ./version-utils.sh rollback <commit-hash>"
      exit 1
    fi
    
    VERSION="$2"
    IMAGE_URI="$ECR_REPO:$VERSION"
    
    echo "🔄 Fazendo rollback para versão: $VERSION"
    
    # Verificar se a imagem existe
    if ! aws ecr describe-images --repository-name bia --image-ids imageTag=$VERSION --region $REGION >/dev/null 2>&1; then
      echo "❌ Erro: Versão $VERSION não encontrada no ECR"
      exit 1
    fi
    
    # Obter task definition atual e criar nova com imagem antiga
    TASK_DEF=$(aws ecs describe-task-definition --task-definition $TASK_FAMILY --region $REGION)
    
    NEW_TASK_DEF=$(echo $TASK_DEF | jq --arg IMAGE "$IMAGE_URI" '
      .taskDefinition |
      .containerDefinitions[0].image = $IMAGE |
      del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy)
    ')
    
    echo $NEW_TASK_DEF > /tmp/task-def-rollback.json
    NEW_TASK_ARN=$(aws ecs register-task-definition --region $REGION --cli-input-json file:///tmp/task-def-rollback.json --query 'taskDefinition.taskDefinitionArn' --output text)
    
    aws ecs update-service \
      --cluster $CLUSTER_NAME \
      --service $SERVICE_NAME \
      --task-definition $NEW_TASK_ARN \
      --region $REGION >/dev/null
    
    echo "✅ Rollback iniciado para versão: $VERSION"
    echo "🔗 Task Definition: $NEW_TASK_ARN"
    ;;
    
  *)
    echo "Uso: $0 [list|rollback] [versao]"
    echo ""
    echo "Comandos:"
    echo "  list              - Lista versões disponíveis"
    echo "  rollback <hash>   - Faz rollback para versão específica"
    ;;
esac
