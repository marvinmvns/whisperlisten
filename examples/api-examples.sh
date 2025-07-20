#!/bin/bash

# Exemplos de API - Curl para testar endpoints de recebimento de transcrições
# Execute estes comandos para testar se sua API está funcionando corretamente

echo "=== Exemplos de API Curl para Whisper Transcriber ==="

# Cores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
header() { echo -e "${BLUE}[HEADER]${NC} $1"; }

# Configurações padrão (edite conforme necessário)
API_URL="${API_URL:-https://sua-api.com/transcripts}"
API_TOKEN="${API_TOKEN:-seu_token_aqui}"

header "1. Exemplo Básico - Envio de Transcrição"

cat << 'EOF'
# Envio básico de uma transcrição
curl -X POST $API_URL \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_TOKEN" \
  -d '{
    "id": "trans_001",
    "timestamp": "2025-01-20T10:30:00.000Z",
    "text": "Hello world this is a test transcription",
    "queued_at": "2025-01-20T10:30:05.000Z",
    "attempt": 1
  }'
EOF

echo
header "2. Exemplo com Metadata Estendida"

cat << 'EOF'
# Envio com metadata adicional
curl -X POST $API_URL \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_TOKEN" \
  -d '{
    "id": "trans_002",
    "timestamp": "2025-01-20T10:31:00.000Z",
    "text": "Good morning team this is our daily standup",
    "queued_at": "2025-01-20T10:31:03.000Z",
    "attempt": 1,
    "metadata": {
      "duration": 2.5,
      "confidence": 0.89,
      "language": "en",
      "device_id": "raspberry_pi_001",
      "whisper_model": "base.en",
      "audio_quality": "good"
    }
  }'
EOF

echo
header "3. Exemplo de Teste de Conectividade"

cat << 'EOF'
# Teste básico de conectividade (health check)
curl -X GET $API_URL/health \
  -H "Authorization: Bearer $API_TOKEN" \
  -w "\nStatus: %{http_code}\nTempo: %{time_total}s\n"

# Ou se não houver endpoint de health
curl -X POST $API_URL \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_TOKEN" \
  -d '{"test": true}' \
  -w "\nStatus: %{http_code}\nTempo: %{time_total}s\n"
EOF

echo
header "4. Exemplo de Retry (Reenvio)"

cat << 'EOF'
# Simulando reenvio após falha
curl -X POST $API_URL \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_TOKEN" \
  -d '{
    "id": "trans_003",
    "timestamp": "2025-01-20T10:32:00.000Z",
    "text": "This is a retry attempt for a failed transcription",
    "queued_at": "2025-01-20T10:32:05.000Z",
    "attempt": 3,
    "previous_errors": [
      {
        "attempt": 1,
        "error": "Connection timeout",
        "timestamp": "2025-01-20T10:32:07.000Z"
      },
      {
        "attempt": 2,
        "error": "Server unavailable",
        "timestamp": "2025-01-20T10:32:15.000Z"
      }
    ]
  }'
EOF

echo
header "5. Exemplo de Batch (Múltiplas Transcrições)"

cat << 'EOF'
# Envio de múltiplas transcrições em lote
curl -X POST $API_URL/batch \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_TOKEN" \
  -d '{
    "transcriptions": [
      {
        "id": "trans_004",
        "timestamp": "2025-01-20T10:33:00.000Z",
        "text": "First transcription in batch",
        "queued_at": "2025-01-20T10:33:05.000Z",
        "attempt": 1
      },
      {
        "id": "trans_005", 
        "timestamp": "2025-01-20T10:33:30.000Z",
        "text": "Second transcription in batch",
        "queued_at": "2025-01-20T10:33:35.000Z",
        "attempt": 1
      }
    ]
  }'
EOF

echo
header "6. Exemplo com Autenticação por API Key"

cat << 'EOF'
# Se usar API Key no header ao invés de Bearer token
curl -X POST $API_URL \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_TOKEN" \
  -d '{
    "id": "trans_006",
    "timestamp": "2025-01-20T10:34:00.000Z", 
    "text": "Using API key authentication",
    "queued_at": "2025-01-20T10:34:02.000Z",
    "attempt": 1
  }'
EOF

echo
header "7. Exemplo com Query Parameters"

cat << 'EOF'
# Enviando dados via query parameters (método alternativo)
curl -X POST "$API_URL?id=trans_007&timestamp=2025-01-20T10:35:00.000Z" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_TOKEN" \
  -d '{
    "text": "Transcription sent with query parameters",
    "queued_at": "2025-01-20T10:35:03.000Z",
    "attempt": 1
  }'
EOF

echo
header "8. Exemplo de Debug/Verbose"

cat << 'EOF'
# Comando com debug completo para troubleshooting
curl -X POST $API_URL \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_TOKEN" \
  -d '{
    "id": "trans_008",
    "timestamp": "2025-01-20T10:36:00.000Z",
    "text": "Debug transcription for troubleshooting",
    "queued_at": "2025-01-20T10:36:01.000Z",
    "attempt": 1
  }' \
  -v \
  -w "\n\nDetalhes da Resposta:\nStatus: %{http_code}\nTempo Total: %{time_total}s\nTempo DNS: %{time_namelookup}s\nTempo Conexão: %{time_connect}s\nTamanho Download: %{size_download} bytes\n"
EOF

echo
header "9. Exemplo de Webhook (Callback)"

cat << 'EOF'
# Se sua API suportar webhooks para confirmação de recebimento
curl -X POST $API_URL \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_TOKEN" \
  -d '{
    "id": "trans_009",
    "timestamp": "2025-01-20T10:37:00.000Z",
    "text": "Transcription with webhook callback",
    "queued_at": "2025-01-20T10:37:02.000Z",
    "attempt": 1,
    "webhook_url": "https://meu-callback.com/webhook",
    "webhook_secret": "meu_webhook_secret"
  }'
EOF

echo
header "10. Script de Teste Automatizado"

cat << 'EOF'
#!/bin/bash
# Script para testar API automaticamente

API_URL="https://sua-api.com/transcripts"
API_TOKEN="seu_token_aqui"

# Função para testar envio
test_api() {
    local test_id="test_$(date +%s)"
    local response=$(curl -s -w "%{http_code}" -X POST $API_URL \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $API_TOKEN" \
        -d "{
            \"id\": \"$test_id\",
            \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)\",
            \"text\": \"Automated test transcription\",
            \"queued_at\": \"$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)\",
            \"attempt\": 1
        }")
    
    local body="${response%???}"
    local status="${response: -3}"
    
    if [[ "$status" =~ ^2[0-9][0-9]$ ]]; then
        echo "✅ Teste $test_id: SUCCESS (Status: $status)"
        echo "   Resposta: $body"
    else
        echo "❌ Teste $test_id: FAILED (Status: $status)"
        echo "   Resposta: $body"
    fi
}

# Executar múltiplos testes
for i in {1..5}; do
    test_api
    sleep 1
done
EOF

echo
header "11. Exemplo de Dados Reais (Simulados)"

cat << 'EOF'
# Simulando diferentes tipos de transcrições reais

# Comando de sistema
curl -X POST $API_URL \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_TOKEN" \
  -d '{
    "id": "cmd_001",
    "timestamp": "2025-01-20T10:38:00.000Z",
    "text": "sudo systemctl restart nginx",
    "queued_at": "2025-01-20T10:38:01.000Z",
    "attempt": 1,
    "category": "command"
  }'

# Nota pessoal
curl -X POST $API_URL \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_TOKEN" \
  -d '{
    "id": "note_001", 
    "timestamp": "2025-01-20T10:39:00.000Z",
    "text": "Remember to buy milk and eggs from the grocery store",
    "queued_at": "2025-01-20T10:39:02.000Z",
    "attempt": 1,
    "category": "note"
  }'

# Reunião
curl -X POST $API_URL \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_TOKEN" \
  -d '{
    "id": "meeting_001",
    "timestamp": "2025-01-20T10:40:00.000Z", 
    "text": "The quarterly sales figures show a twenty percent increase compared to last quarter",
    "queued_at": "2025-01-20T10:40:03.000Z",
    "attempt": 1,
    "category": "meeting",
    "participants": ["john", "mary", "robert"]
  }'
EOF

echo
header "12. Exemplo de Tratamento de Erros"

cat << 'EOF'
# Teste com dados inválidos para verificar tratamento de erro
curl -X POST $API_URL \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_TOKEN" \
  -d '{
    "invalid_field": "test",
    "missing_required_fields": true
  }' \
  -w "\nStatus: %{http_code}\n"

# Teste com token inválido
curl -X POST $API_URL \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer INVALID_TOKEN" \
  -d '{
    "id": "test_invalid_auth",
    "timestamp": "2025-01-20T10:41:00.000Z",
    "text": "Test with invalid token",
    "queued_at": "2025-01-20T10:41:01.000Z",
    "attempt": 1
  }' \
  -w "\nStatus: %{http_code}\n"
EOF

echo
echo "===================="
log "Para usar estes exemplos:"
echo "1. Substitua \$API_URL pela URL real da sua API"
echo "2. Substitua \$API_TOKEN pelo seu token real"
echo "3. Ajuste os campos conforme sua API específica"
echo "4. Teste primeiro com curl -v para debug"
echo ""
warn "IMPORTANTE: Nunca exponha tokens reais em logs ou código público!"
echo ""
log "Exemplo de uso rápido:"
echo "export API_URL='https://minha-api.com/transcripts'"
echo "export API_TOKEN='meu_token_secreto'"
echo "bash api-examples.sh"