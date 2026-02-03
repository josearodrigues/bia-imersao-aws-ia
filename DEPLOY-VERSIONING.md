# Deploy com Versionamento - Projeto BIA

## Visão Geral
Sistema de deploy que usa commit hash como versionamento, criando task definitions específicas para cada versão sem sobrepor a rotina existente.

## Arquivos Criados
- `deploy-versioned.sh` - Script principal de deploy
- `version-utils.sh` - Utilitários para listagem e rollback
- `DEPLOY-VERSIONING.md` - Esta documentação

## Como Usar

### 1. Deploy com Versão Automática
```bash
./deploy-versioned.sh
```
Usa o commit hash atual do Git como tag da imagem.

### 2. Deploy com Versão Específica
```bash
./deploy-versioned.sh abc1234
```
Usa `abc1234` como tag da imagem.

### 3. Listar Versões Disponíveis
```bash
./version-utils.sh list
```
Mostra imagens no ECR e task definitions recentes.

### 4. Rollback para Versão Anterior
```bash
./version-utils.sh rollback abc1234
```
Faz rollback para a versão `abc1234`.

## Fluxo do Deploy

1. **Build da Imagem**: Cria imagem Docker com tag do commit
2. **Push para ECR**: Envia imagem taggeada para o repositório
3. **Nova Task Definition**: Cria task definition com nova imagem
4. **Update Service**: Atualiza service ECS com nova task definition
5. **Aguarda Estabilização**: Espera deploy completar

## Vantagens

- ✅ **Versionamento Claro**: Cada commit vira uma versão rastreável
- ✅ **Rollback Rápido**: Volta para qualquer versão anterior
- ✅ **Não Invasivo**: Não altera sua rotina atual de deploy
- ✅ **Histórico Completo**: Mantém todas as task definitions
- ✅ **Automático**: Usa commit hash do Git automaticamente

## Estrutura de Versionamento

```
ECR Repository: 381491977261.dkr.ecr.us-east-1.amazonaws.com/bia
├── bia:abc1234  (commit hash)
├── bia:def5678  (commit hash)
├── bia:latest   (sua versão atual)
└── ...

Task Definitions:
├── task-def-bia:7   (atual)
├── task-def-bia:8   (nova versão)
├── task-def-bia:9   (próxima versão)
└── ...
```

## Pré-requisitos

- Docker instalado e rodando
- AWS CLI configurado
- Git repository inicializado
- Permissões ECR e ECS configuradas

## Troubleshooting

### Erro de Login ECR
```bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 381491977261.dkr.ecr.us-east-1.amazonaws.com
```

### Verificar Status do Service
```bash
aws ecs describe-services --cluster cluster-bia --services service-bia --region us-east-1
```

### Ver Logs do Deploy
```bash
aws logs tail /ecs/task-def-bia --follow --region us-east-1
```
