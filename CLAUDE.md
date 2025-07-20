# Projetos de Transcrição de Áudio em Tempo Real - Whisper Local

Este repositório contém duas implementações completas de um sistema de transcrição de áudio em tempo real usando Whisper local com VAD (Voice Activity Detection), otimizadas para Raspberry Pi.

## 📁 Estrutura do Projeto

```
newproject/
├── nodejs-whisper-transcriber/     # Implementação Node.js
│   ├── src/
│   │   ├── vad.js                  # Detecção de atividade de voz
│   │   ├── transcribe.js           # Transcrição com Whisper
│   │   ├── queue.js                # Gerenciamento de fila
│   │   └── sender.js               # Envio para API
│   ├── index.js                    # Aplicação principal
│   ├── package.json
│   ├── .env.example
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── whisper-transcriber.service # Serviço systemd
│   └── scripts/
│       └── install-whisper.sh      # Script de instalação
│
├── python-whisper-transcriber/     # Implementação Python
│   ├── src/
│   │   ├── vad.py                  # VAD com webrtcvad
│   │   ├── transcribe.py           # Múltiplos backends Whisper
│   │   ├── queue.py                # Fila SQLite
│   │   └── sender.py               # Cliente HTTP com retry
│   ├── main.py                     # Aplicação principal
│   ├── requirements.txt
│   └── .env.example
│
└── CLAUDE.md                       # Esta documentação
```

## 🚀 Características Principais

### Funcionalidades Comuns
- **VAD (Voice Activity Detection)**: Detecta automaticamente quando há fala
- **Transcrição Local**: Usa Whisper.cpp sem dependência de internet
- **Fila Persistente**: Armazena transcrições para envio ordenado
- **Retry Automático**: Reenvio com backoff exponencial em caso de falha
- **Detecção de Internet**: Monitora conectividade e envia quando online
- **Limpeza Automática**: Remove arquivos temporários após processamento
- **Modo Daemon**: Execução como serviço do sistema

### Específico Node.js
- Interface simples com `mic` para captura de áudio
- Suporte a whisper.cpp binário e node-whisper
- Fila em JSON com backup em disco
- Sistema de logs integrado
- Suporte a PM2 para gerenciamento de processo

### Específico Python
- VAD avançado com `webrtcvad`
- Múltiplos backends: pywhispercpp, OpenAI Whisper, faster-whisper
- Fila SQLite com transações ACID
- Interface CLI robusta com comandos
- Suporte nativo a asyncio

## 📋 Requisitos

### Hardware Recomendado
- **Raspberry Pi 4** (4GB+ RAM) ou **Raspberry Pi 5**
- **Cartão SD**: Classe 10, 32GB+ 
- **Microfone USB** ou HAT de áudio
- **Conexão de rede** (WiFi/Ethernet)

### Software Base
- **Raspberry Pi OS** (64-bit recomendado)
- **Node.js 18+** (para versão Node.js)
- **Python 3.8+** (para versão Python)
- **Git**, **build-essential**, **cmake**

## 🛠️ Instalação

### Node.js

```bash
# 1. Clonar e configurar
cd nodejs-whisper-transcriber
cp .env.example .env

# 2. Executar instalação automática
npm run setup
# ou manualmente:
bash scripts/install-whisper.sh
npm install

# 3. Editar configurações
nano .env

# 4. Testar
npm run status
npm run test

# 5. Executar
npm start
```

### Python

```bash
# 1. Configurar ambiente
cd python-whisper-transcriber
python -m venv venv
source venv/bin/activate  # Linux/Mac
# venv\Scripts\activate    # Windows

# 2. Instalar dependências
pip install -r requirements.txt

# 3. Configurar
cp .env.example .env
nano .env

# 4. Testar
python main.py test

# 5. Executar
python main.py start
```

## ⚙️ Configuração

### Variáveis de Ambiente (.env)

```bash
# API de destino
API_URL=https://sua-api.com/transcripts
API_TOKEN=seu_token_aqui

# Configurações Whisper
WHISPER_PATH=./whisper.cpp/main        # Node.js
MODEL_PATH=./models/ggml-base.en.bin
LANG=en

# Modelos recomendados por RAM:
# 1-2GB: ggml-tiny.en-q8_0.bin
# 2-4GB: ggml-base.en-q5_0.bin  
# 4GB+:  ggml-small.en-q5_0.bin

# VAD (opcional)
SILENCE_THRESHOLD=1000
MIN_RECORDING_TIME=500
VAD_AGGRESSIVENESS=2

# Conectividade (opcional)
CONNECTIVITY_CHECK_INTERVAL=5000
MAX_RETRIES=5
```

## 🐳 Docker

### Node.js

```bash
# Build e execução
docker-compose up -d

# Logs
docker-compose logs -f

# Parar
docker-compose down
```

### Python

```bash
# Criar Dockerfile similar ao Node.js se necessário
# Ou usar diretamente com bind mounts:

docker run -d \
  --name whisper-transcriber \
  --device /dev/snd \
  -v $(pwd)/data:/app/data \
  -v $(pwd)/.env:/app/.env:ro \
  python:3.11-slim \
  bash -c "pip install -r requirements.txt && python main.py start"
```

## 🔧 Execução como Serviço

### Systemd (Linux)

```bash
# Node.js
sudo cp nodejs-whisper-transcriber/whisper-transcriber.service /etc/systemd/system/
sudo systemctl enable whisper-transcriber
sudo systemctl start whisper-transcriber
sudo systemctl status whisper-transcriber

# Python - criar arquivo similar
sudo nano /etc/systemd/system/whisper-transcriber-py.service
```

### PM2 (Node.js)

```bash
npm run daemon          # Iniciar
npm run daemon-logs     # Ver logs
npm run daemon-restart  # Reiniciar
npm run daemon-stop     # Parar
```

## 📊 Comandos CLI

### Node.js

```bash
node index.js status      # Status detalhado
node index.js queue       # Informações da fila
node index.js test        # Testar conexão
node index.js retry <id>  # Reenviar item
node index.js cleanup     # Limpar antigos
```

### Python

```bash
python main.py status             # Status do sistema
python main.py test               # Testar componentes
python main.py queue              # Ver fila
python main.py retry --item-id X  # Reenviar
python main.py cleanup --days 30 # Limpar
```

## 🔍 Monitoramento

### Logs

```bash
# Node.js
tail -f logs/combined.log
npm run daemon-logs

# Python  
tail -f logs/transcriber.log
```

### Métricas de Performance

```bash
# Status em tempo real
watch -n 5 "node index.js status"    # Node.js
watch -n 5 "python main.py status"   # Python
```

## 🧪 Testes

### Teste de Microfone

```bash
# Sistema
arecord -f cd -t raw -d 3 /dev/null

# Aplicação
python main.py test  # Python inclui teste de mic
```

### Teste de Conectividade

```bash
# Manual
curl -X POST $API_URL \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"test": true}'

# Aplicação
node index.js test     # Node.js
python main.py test    # Python
```

### Simulação de Falha de Rede

```bash
# Desconectar WiFi temporariamente
sudo ifconfig wlan0 down
sleep 30
sudo ifconfig wlan0 up

# Verificar se fila mantém ordem
node index.js queue
```

## 🚨 Troubleshooting

### Problemas Comuns

**1. Erro de Microfone**
```bash
# Verificar dispositivos
arecord -l
lsusb | grep -i audio

# Adicionar usuário ao grupo audio
sudo usermod -a -G audio $USER
```

**2. Whisper.cpp não compila**
```bash
# Dependências extras para Pi
sudo apt install libopenblas-dev
cd whisper.cpp && make clean && make GGML_OPENBLAS=1
```

**3. Modelo não encontrado**
```bash
# Download manual
cd models
wget https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
```

**4. Erro de memória**
```bash
# Usar modelo menor
# No .env: MODEL_PATH=./models/ggml-tiny.en-q8_0.bin

# Aumentar swap
sudo dphys-swapfile swapoff
sudo nano /etc/dphys-swapfile  # CONF_SWAPSIZE=1024
sudo dphys-swapfile setup
sudo dphys-swapfile swapon
```

**5. Fila não processa**
```bash
# Verificar status de rede
node index.js status
python main.py status

# Forçar reenvio
node index.js retry <item-id>
python main.py retry --item-id <id>
```

## 📈 Otimizações para Raspberry Pi

### Performance

1. **Usar modelos quantizados**:
   - `ggml-tiny.en-q8_0.bin` (mais rápido)
   - `ggml-base.en-q5_0.bin` (balanceado)

2. **Ajustar threads**:
   ```bash
   N_THREADS=2  # Para Pi 4
   N_THREADS=4  # Para Pi 5
   ```

3. **GPU (se disponível)**:
   ```bash
   # Para Pi 5 com GPU
   export GGML_OPENCL=1
   ```

### Economia de Energia

```bash
# Reduzir frequência de verificação
CONNECTIVITY_CHECK_INTERVAL=10000
SEND_CHECK_INTERVAL=5000

# CPU Governor
echo powersave | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

## 🔒 Segurança

### Configurações Recomendadas

1. **Não usar root**: Executar como usuário `pi`
2. **Firewall**: Bloquear portas desnecessárias
3. **Tokens**: Usar variáveis de ambiente, não hardcode
4. **HTTPS**: Sempre usar para API_URL
5. **Logs**: Não logar tokens ou dados sensíveis

### Exemplo de Hardening

```bash
# Limitar recursos no systemd
echo "MemoryLimit=512M" >> whisper-transcriber.service
echo "CPUQuota=50%" >> whisper-transcriber.service

# Sandbox no Docker
docker run --read-only --tmpfs /tmp --tmpfs /var/tmp ...
```

## 📚 Extensões Possíveis

### Funcionalidades Avançadas

1. **Interface Web**: Flask/Express para controle remoto
2. **Webhook**: Receber comandos via HTTP
3. **Multi-idioma**: Detecção automática de idioma
4. **Streaming**: WebSocket para transcrição em tempo real
5. **Backup**: Sincronização com S3/Google Drive

### Integrações

```bash
# Home Assistant
mqtt_publish "homeassistant/sensor/transcriber/state" "$(node index.js status)"

# Telegram Bot
curl -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
  -d "chat_id=$CHAT_ID&text=Transcrição: $TEXTO"
```

## 🤝 Contribuição

### Estrutura para Desenvolvimento

```bash
# Ambiente de desenvolvimento Node.js
npm run dev  # nodemon com hot reload

# Python com debug
python main.py --log-level DEBUG start
```

### Testes Automatizados

```bash
# Adicionar ao package.json
"test": "jest",
"test:integration": "jest --testPathPattern=integration"

# Python
pytest tests/
```

## 📄 Licença

MIT License - veja arquivos individuais dos projetos.

## 📞 Suporte

Para problemas específicos:
1. Verificar logs detalhados
2. Executar comandos de diagnóstico
3. Verificar compatibilidade de hardware
4. Consultar issues conhecidos no repositório

---

**Última atualização**: 2025-01-20
**Versão Node.js**: 1.0.0  
**Versão Python**: 1.0.0
**Compatibilidade**: Raspberry Pi 4/5, Linux x64/ARM64