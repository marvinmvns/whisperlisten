# Exemplos e Testes de API

Esta pasta contém exemplos e ferramentas para testar os sistemas de transcrição Whisper.

## 📁 Arquivos Incluídos

### Scripts de Teste
- **`api-examples.sh`** - Exemplos de curl para testar APIs
- **`mock-api-server.js`** - Servidor mock Node.js para desenvolvimento
- **`mock-api-server.py`** - Servidor mock Python para desenvolvimento

## 🚀 Como Usar

### 1. Exemplos de API (curl)

```bash
# Tornar executável
chmod +x api-examples.sh

# Configurar variáveis
export API_URL="https://sua-api.com/transcripts"
export API_TOKEN="seu_token_aqui"

# Ver exemplos
./api-examples.sh
```

#### Exemplos Incluídos:

1. **Envio Básico** - Transcrição simples
2. **Metadata Estendida** - Com informações adicionais
3. **Teste de Conectividade** - Health check
4. **Retry/Reenvio** - Simulação de falha
5. **Batch/Lote** - Múltiplas transcrições
6. **Autenticação** - Diferentes métodos
7. **Query Parameters** - Método alternativo
8. **Debug/Verbose** - Troubleshooting
9. **Webhook** - Callback de confirmação
10. **Script Automatizado** - Teste contínuo
11. **Dados Reais** - Diferentes categorias
12. **Tratamento de Erros** - Cenários de falha

### 2. Servidor Mock para Desenvolvimento

#### Node.js

```bash
# Instalar dependências
npm install express cors

# Executar servidor
node mock-api-server.js

# Ou com porta customizada
PORT=4000 node mock-api-server.js
```

#### Python

```bash
# Instalar dependências
pip install flask flask-cors

# Executar servidor
python mock-api-server.py

# Ou com configurações customizadas
python mock-api-server.py --host 0.0.0.0 --port 4000 --debug
```

### 3. Endpoints Disponíveis

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| `GET` | `/health` | Health check (sem auth) |
| `GET` | `/status` | Status da API |
| `POST` | `/transcripts` | Receber transcrição |
| `POST` | `/transcripts/batch` | Receber lote |
| `GET` | `/analytics` | Estatísticas |
| `GET` | `/logs` | Ver logs |
| `DELETE` | `/logs` | Limpar logs |
| `POST` | `/webhook` | Simular webhook |

## 🔧 Configuração dos Projetos

### Para Node.js

```bash
cd ../nodejs-whisper-transcriber
cp .env.example .env

# Editar .env
API_URL=http://localhost:3001/transcripts
API_TOKEN=test-token
```

### Para Python

```bash
cd ../python-whisper-transcriber
cp .env.example .env

# Editar .env
API_URL=http://localhost:3001/transcripts
API_TOKEN=test-token
```

## 🧪 Testes Automatizados

### Executar Servidor Mock

```bash
# Terminal 1 - Iniciar servidor mock
node mock-api-server.js
# ou
python mock-api-server.py
```

### Testar Projetos

```bash
# Terminal 2 - Testar Node.js
cd ../nodejs-whisper-transcriber
npm run test

# Terminal 3 - Testar Python
cd ../python-whisper-transcriber
python scripts/test-system.py
```

## 📊 Funcionalidades do Mock Server

### Simulações Incluídas

1. **Respostas Realistas** - Delays e variação de tempo
2. **Diferentes Status Codes** - 200, 400, 401, 429, 500, 408
3. **Logging Completo** - Todas as requisições são logadas
4. **Autenticação Flexível** - Bearer token ou API key
5. **Cenários de Erro** - Baseado no conteúdo da transcrição
6. **Analytics Simuladas** - Dados estatísticos fake
7. **Rate Limiting** - Simulação de limite de taxa

### Cenários de Teste

**Trigger de Erros por Texto:**
- Contém "error" ou "fail" → 500 Internal Server Error
- Contém "timeout" ou "slow" → 408 Request Timeout  
- Contém "rate" ou "limit" → 429 Too Many Requests
- Outros → 201 Created (sucesso)

### Estrutura de Resposta

```json
{
  "success": true,
  "message": "Transcription received successfully",
  "data": {
    "id": "trans_001",
    "received_at": "2025-01-20T10:30:00.000Z",
    "processed": true,
    "status": "accepted",
    "length": 25,
    "word_count": 5,
    "processing_time_ms": 450
  },
  "metadata": {
    "attempt": 1,
    "queued_at": "2025-01-20T10:30:05.000Z",
    "server_id": "mock-server-001",
    "version": "1.0.0"
  }
}
```

## 🐛 Troubleshooting

### Problemas Comuns

**1. Servidor não inicia:**
```bash
# Verificar se porta está livre
netstat -an | grep 3001
# ou
lsof -i :3001

# Matar processo se necessário
kill $(lsof -t -i :3001)
```

**2. Erro de dependências:**
```bash
# Node.js
npm install express cors

# Python
pip install flask flask-cors
```

**3. Erro de permissão:**
```bash
chmod +x api-examples.sh
chmod +x mock-api-server.py
```

**4. CORS errors:**
- O servidor mock já inclui CORS habilitado
- Para APIs reais, configure CORS adequadamente

### Logs e Debug

**Ver logs do servidor mock:**
- Logs são exibidos no console
- Logs são salvos em `api_logs.json`
- Acesse via `GET /logs`

**Debug de requisições:**
```bash
# Usar curl com verbose
curl -v -X POST http://localhost:3001/transcripts \
  -H "Authorization: Bearer test" \
  -H "Content-Type: application/json" \
  -d '{"id":"test","timestamp":"2025-01-20T10:00:00Z","text":"debug test"}'
```

## 📈 Monitoramento

### Métricas Disponíveis

- Total de requisições processadas
- Tempo de uptime
- Logs de todas as requisições
- Estatísticas simuladas
- Status de saúde da API

### Health Check

```bash
# Verificar se API está online
curl http://localhost:3001/health

# Resposta esperada:
{
  "status": "healthy",
  "timestamp": "2025-01-20T10:00:00.000Z",
  "uptime": 3600,
  "version": "1.0.0",
  "service": "Mock Whisper API"
}
```

## 🔒 Autenticação

### Métodos Suportados

1. **Bearer Token:**
```bash
-H "Authorization: Bearer your-token-here"
```

2. **API Key:**
```bash
-H "X-API-Key: your-api-key-here"
```

### Tokens de Teste

Para desenvolvimento, qualquer token é aceito:
- `test-token`
- `dev-key-123`
- `any-string-works`

## 📚 Referências Úteis

### Códigos de Status HTTP

- `200` - OK (GET requests)
- `201` - Created (POST success)
- `400` - Bad Request (dados inválidos)
- `401` - Unauthorized (token ausente/inválido)
- `408` - Request Timeout (timeout simulado)
- `429` - Too Many Requests (rate limit)
- `500` - Internal Server Error (erro simulado)

### Headers Importantes

```bash
Content-Type: application/json
Authorization: Bearer <token>
X-API-Key: <key>
User-Agent: <identificação do cliente>
```

---

💡 **Dica:** Use estes exemplos como base para implementar sua própria API de produção!