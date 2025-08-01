# 🎙️ Real-Time Audio Transcription System

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Node.js](https://img.shields.io/badge/Node.js-16+-green.svg)](https://nodejs.org/)
[![Python](https://img.shields.io/badge/Python-3.8+-blue.svg)](https://python.org/)
[![Raspberry Pi](https://img.shields.io/badge/Raspberry%20Pi-4%2F5-red.svg)](https://www.raspberrypi.org/)

Sistema completo de transcrição de áudio em tempo real usando Whisper local com VAD (Voice Activity Detection), otimizado para execução em Raspberry Pi e outras plataformas Linux.

## 🌟 Características Principais

- **🎯 Detecção Inteligente de Voz**: VAD automático para iniciar transcrição apenas quando há fala
- **🔒 Processamento Local**: Whisper.cpp executado offline, sem dependência de internet
- **📦 Fila Persistente**: Sistema robusto de filas com retry automático e recuperação de falhas
- **🌐 Conectividade Adaptável**: Monitora conexão e envia dados quando online
- **🔄 Duas Implementações**: Versões completas em Node.js e Python com APIs equivalentes
- **🐳 Containerização**: Suporte Docker com docker-compose
- **⚙️ Execução como Serviço**: Configuração systemd e PM2 para execução contínua
- **📊 Monitoramento**: Logs detalhados e comandos de status em tempo real

## 🏗️ Arquitetura do Sistema

```mermaid
graph TD
    A[Microfone] --> B[VAD - Voice Activity Detection]
    B --> C[Whisper.cpp - Transcrição Local]
    C --> D[Fila Persistente]
    D --> E[Monitor de Conectividade]
    E --> F[API Externa]
    
    G[Logs & Monitoramento] --> H[Status Dashboard]
    D --> G
    E --> G
```

## 📁 Estrutura do Projeto

```
newproject/
├── 📄 README.md                    # Este arquivo
├── 📄 CLAUDE.md                    # Documentação técnica completa
├── 📂 nodejs-whisper-transcriber/  # Implementação Node.js
│   ├── 🎯 index.js                 # Aplicação principal
│   ├── 📦 package.json             # Dependências e scripts
│   ├── 🐳 Dockerfile               # Container Node.js
│   ├── 🐳 docker-compose.yml       # Orquestração Docker
│   ├── ⚙️ ecosystem.config.js      # Configuração PM2
│   ├── 🔧 whisper-transcriber.service # Serviço systemd
│   ├── 📂 src/                     # Código fonte
│   │   ├── vad.js                  # Detecção de voz
│   │   ├── transcribe.js           # Interface Whisper
│   │   ├── queue.js                # Gerenciamento de fila
│   │   └── sender.js               # Cliente HTTP
│   └── 📂 scripts/                 # Scripts de instalação
│       ├── install-whisper.sh      # Setup automático Whisper
│       └── test-system.sh          # Testes do sistema
│
├── 📂 python-whisper-transcriber/  # Implementação Python
│   ├── 🎯 main.py                  # Aplicação principal
│   ├── 📦 requirements.txt         # Dependências Python
│   ├── 📂 src/                     # Código fonte
│   │   ├── vad.py                  # VAD com webrtcvad
│   │   ├── transcribe.py           # Múltiplos backends Whisper
│   │   ├── queue.py                # Fila SQLite
│   │   └── sender.py               # Cliente HTTP async
│   └── 📂 scripts/                 # Scripts de setup
│       ├── install.sh              # Instalação geral
│       ├── setup-pi.sh             # Configuração Raspberry Pi
│       └── test-system.py          # Suite de testes
│
├── 📂 examples/                    # Exemplos e mocks
│   ├── mock-api-server.js          # Servidor de teste Node.js
│   ├── mock-api-server.py          # Servidor de teste Python
│   └── api-examples.sh             # Exemplos de uso da API
│
└── 📂 scripts/                     # Scripts gerais
    └── run-tests.sh                # Testes integrados
```

## 🚀 Quick Start

### 📱 Hardware Setup - ReSpeaker 2-Mic Pi HAT (Recomendado)

Para usar com ReSpeaker 2-Mic Pi HAT V1.0, execute primeiro o script de instalação:

```bash
# Instalação automática completa do ReSpeaker + Sistema
bash scripts/install-respeaker.sh

# Ou siga os passos manuais na seção Hardware Setup abaixo
```

### Node.js (Recomendado para iniciantes)

```bash
# 1. Clone e configure
git clone <repository-url>
cd newproject/nodejs-whisper-transcriber

# 2. Instalação automática (instala Whisper.cpp + dependências)
npm run setup

# 3. Configure variáveis de ambiente
cp .env.example .env
nano .env  # Edite API_URL e API_TOKEN

# 4. Teste a instalação
npm run test

# 5. Execute
npm start
```

### Python (Para usuários avançados)

```bash
# 1. Configurar ambiente virtual
cd python-whisper-transcriber
python -m venv venv
source venv/bin/activate  # Linux/Mac

# 2. Instalar dependências
pip install -r requirements.txt

# 3. Configurar
cp .env.example .env
nano .env

# 4. Testar sistema
python main.py test

# 5. Executar
python main.py start
```

## ⚙️ Configuração

### Variáveis de Ambiente (.env)

```bash
# API de destino (obrigatório)
API_URL=https://sua-api.com/transcripts
API_TOKEN=seu_token_secreto_aqui

# Configurações do Whisper
MODEL_PATH=./models/ggml-base.en.bin
WHISPER_PATH=./whisper.cpp/main  # Node.js apenas
LANG=en
N_THREADS=2  # Ajuste conforme CPU

# Configurações de VAD
SILENCE_THRESHOLD=1000
MIN_RECORDING_TIME=500
VAD_AGGRESSIVENESS=2  # 0-3, maior = mais sensível

# Rede e conectividade
CONNECTIVITY_CHECK_INTERVAL=5000
MAX_RETRIES=5
RETRY_BACKOFF_MS=1000

# Logs (opcional)
LOG_LEVEL=info
LOG_FILE=./logs/transcriber.log
```

### Modelos Recomendados por Hardware

| Hardware | RAM | Modelo Recomendado | Tamanho | Velocidade |
|----------|-----|-------------------|---------|------------|
| Pi Zero/1GB | 1GB | `ggml-tiny.en-q8_0.bin` | ~40MB | Rápido |
| Pi 4/2GB | 2GB | `ggml-base.en-q5_0.bin` | ~60MB | Médio |
| Pi 4/4GB+ | 4GB+ | `ggml-small.en-q5_0.bin` | ~180MB | Lento |
| Desktop | 8GB+ | `ggml-medium.en-q5_0.bin` | ~800MB | Muito lento |

## 🔧 Comandos CLI

### Node.js

```bash
# Status e monitoramento
npm run status           # Status detalhado do sistema
npm run test             # Testar conectividade e componentes
node index.js queue      # Informações da fila

# Operações da fila
node index.js retry <id> # Reenviar item específico
node index.js cleanup    # Limpar itens antigos

# Execução como daemon
npm run daemon           # Iniciar com PM2
npm run daemon-logs      # Ver logs em tempo real
npm run daemon-restart   # Reiniciar serviço
npm run daemon-stop      # Parar serviço
```

### Python

```bash
# Status e testes
python main.py status              # Status do sistema
python main.py test                # Suite de testes completa
python main.py queue               # Estado da fila

# Operações avançadas
python main.py retry --item-id X   # Reenviar item
python main.py cleanup --days 30   # Limpar antigos
python main.py --log-level DEBUG start  # Debug mode
```

## 🐳 Docker

### Node.js com Docker Compose

```bash
cd nodejs-whisper-transcriber

# Primeira execução
docker-compose up --build

# Execução normal
docker-compose up -d

# Logs
docker-compose logs -f

# Parar
docker-compose down
```

### Python Docker (Manual)

```bash
cd python-whisper-transcriber

# Build
docker build -t whisper-transcriber-py .

# Run
docker run -d \
  --name whisper-transcriber \
  --device /dev/snd:/dev/snd \
  -v $(pwd)/data:/app/data \
  -v $(pwd)/.env:/app/.env:ro \
  whisper-transcriber-py
```

## ⚡ Execução como Serviço do Sistema

### Systemd (Linux)

```bash
# Node.js
sudo cp nodejs-whisper-transcriber/whisper-transcriber.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable whisper-transcriber
sudo systemctl start whisper-transcriber

# Verificar status
sudo systemctl status whisper-transcriber
journalctl -u whisper-transcriber -f
```

### PM2 (Node.js apenas)

```bash
# Instalar PM2 globalmente
npm install -g pm2

# Gerenciar serviço
npm run daemon          # Iniciar
pm2 list               # Listar processos
pm2 monit              # Monitor visual
pm2 startup            # Auto-iniciar no boot
```

## 🧪 Testes e Diagnósticos

### Teste de Microfone

```bash
# Verificar dispositivos de áudio
arecord -l
lsusb | grep -i audio

# Teste básico de gravação (3 segundos)
arecord -f cd -t raw -d 3 /dev/null

# Aplicação (Python possui teste integrado)
python main.py test
```

### Teste de Conectividade

```bash
# Manual com curl
curl -X POST $API_URL \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"test": true, "timestamp": "'$(date -Iseconds)'"}'

# Via aplicação
node index.js test      # Node.js
python main.py test     # Python
```

### Simulação de Falha de Rede

```bash
# Desconectar WiFi temporariamente para testar fila
sudo ifconfig wlan0 down
sleep 30
sudo ifconfig wlan0 up

# Verificar se fila mantém dados
node index.js queue
```

## 📊 Monitoramento e Logs

### Logs em Tempo Real

```bash
# Node.js
tail -f logs/combined.log
npm run daemon-logs    # Se usando PM2

# Python
tail -f logs/transcriber.log

# Systemd
journalctl -u whisper-transcriber -f
```

### Métricas de Performance

```bash
# Status atualizado a cada 5 segundos
watch -n 5 "node index.js status"     # Node.js
watch -n 5 "python main.py status"    # Python

# CPU e memória
htop
```

## 🐛 Troubleshooting

### Problemas Comuns e Soluções

#### 1. **Erro de Microfone**
```bash
# Verificar permissões
sudo usermod -a -G audio $USER
# Reiniciar sessão após este comando

# Testar microfone
arecord -f cd -t raw -d 3 /dev/null
```

#### 2. **Whisper.cpp não compila**
```bash
# Para Raspberry Pi, instalar OpenBLAS
sudo apt update && sudo apt install libopenblas-dev

# Recompilar com otimizações
cd whisper.cpp
make clean
make GGML_OPENBLAS=1
```

#### 3. **Modelo não encontrado**
```bash
# Download manual de modelo
cd models
wget https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
```

#### 4. **Erro de memória insuficiente**
```bash
# Usar modelo menor no .env
MODEL_PATH=./models/ggml-tiny.en-q8_0.bin

# Aumentar swap (Raspberry Pi)
sudo dphys-swapfile swapoff
sudo nano /etc/dphys-swapfile  # CONF_SWAPSIZE=1024
sudo dphys-swapfile setup && sudo dphys-swapfile swapon
```

#### 5. **Fila não processa**
```bash
# Verificar conectividade
node index.js status
python main.py status

# Forçar reenvio de item específico
node index.js retry <item-id>
python main.py retry --item-id <id>
```

#### 6. **API retorna erro 401/403**
```bash
# Verificar token no .env
echo $API_TOKEN

# Testar autenticação manualmente
curl -H "Authorization: Bearer $API_TOKEN" $API_URL
```

## 🔒 Segurança

### Boas Práticas Implementadas

- ✅ **Não execução como root**: Sempre execute como usuário normal
- ✅ **Tokens em variáveis de ambiente**: Nunca hardcode credenciais
- ✅ **HTTPS obrigatório**: Conexões sempre criptografadas
- ✅ **Logs sanitizados**: Tokens não são logados
- ✅ **Validação de entrada**: Inputs são validados antes do processamento

### Configurações de Segurança

```bash
# Firewall básico (UFW)
sudo ufw enable
sudo ufw allow ssh
sudo ufw allow out 443  # HTTPS apenas

# Limitar recursos no systemd
echo "MemoryLimit=512M" >> whisper-transcriber.service
echo "CPUQuota=50%" >> whisper-transcriber.service
```

## 🎛️ Hardware Setup - ReSpeaker 2-Mic Pi HAT V1.0

### Visão Geral do Hardware

O **keyestudio ReSpeaker 2-Mic Pi HAT V1.0** é uma placa de áudio de baixo consumo projetada para aplicações de IA e voz. Baseada no codec estéreo WM8960, oferece:

- ✅ **Dois microfones** (Mic L e Mic R) para captura de áudio estéreo
- ✅ **3 LEDs RGB APA102** para feedback visual  
- ✅ **Botão programável** conectado ao GPIO17
- ✅ **Saída de áudio dupla**: jack 3.5mm e conector XH2.54-2P
- ✅ **Conectores Grove**: I2C e GPIO digital
- ✅ **Compatibilidade**: Raspberry Pi 3B, 4B, 5

![ReSpeaker 2-Mic Pi HAT](https://wiki.keyestudio.com/images/2/2e/KS0314.png)

### Pinout e Interfaces

| Interface | Conexão | Descrição |
|-----------|---------|-----------|
| **Button** | GPIO17 | Botão programável padrão |
| **Mic L/R** | WM8960 | Microfones esquerdo e direito |
| **RGB LED** | SPI | 3x APA102 RGB LEDs |
| **I2C Grove** | I2C-1 | Porta Grove para sensores I2C |
| **GPIO Grove** | GPIO12/13 | Porta Grove digital |
| **Audio Out** | 3.5mm + XH2.54 | Saída para fones/speakers |
| **Power** | Micro USB | Alimentação externa (opcional) |

### Instalação Automática

```bash
# Download e execução do script de instalação completo
curl -fsSL https://raw.githubusercontent.com/seu-usuario/newproject/main/scripts/install-respeaker.sh | bash

# Ou clone o repositório primeiro
git clone <repository-url>
cd newproject
bash scripts/install-respeaker.sh
```

### Instalação Manual

#### 1. Preparar Sistema Base

```bash
# Atualizar sistema
sudo apt-get update && sudo apt-get upgrade -y

# Instalar dependências base
sudo apt-get install -y git wget unzip build-essential cmake
sudo apt-get install -y portaudio19-dev libatlas-base-dev
```

#### 2. Instalar Driver ReSpeaker

```bash
# Download do driver
wget -O seeed-voicecard-6.1.zip "https://www.dropbox.com/scl/fo/4x60kwe9gpr3no0h6s2xl/AP9QcnN3ApKXkGh9CJPLDzU?rlkey=1sjn1xxr114zviozu0pguwpnd&e=1&dl=1"

# Descompactar e instalar
unzip seeed-voicecard-6.1.zip
cd seeed-voicecard-6.1
sudo ./install.sh

# Reiniciar sistema
sudo reboot
```

#### 3. Verificar Instalação

```bash
# Verificar se a placa foi detectada
aplay -l
arecord -l

# Saída esperada: "seeed-2mic-voicecard" na lista

# Testar microfone (grave 5 segundos e reproduza)
arecord -D "plughw:3,0" -f S16_LE -r 16000 -d 5 -t wav test.wav
aplay -D "plughw:3,0" test.wav
```

#### 4. Instalar Dependências Python para LEDs/Botão

```bash
# Para controle dos LEDs e botão
sudo apt-get install -y python3-pip python3-dev
pip3 install RPi.GPIO spidev

# Download dos scripts de exemplo
wget -O mic_hat-master.zip "https://github.com/respeaker/mic_hat/archive/master.zip"
unzip mic_hat-master.zip
cd mic_hat-master
```

#### 5. Testar Componentes

```bash
# Testar LEDs RGB (devem piscar em cores diferentes)
python3 interfaces/pixels.py

# Testar botão (deve exibir "on" quando pressionado)
python3 interfaces/button.py
```

### Configuração Avançada

#### Sistema Operacional Recomendado

Para compatibilidade máxima com o ReSpeaker 2-Mic Pi HAT, recomendamos:

```bash
# Raspberry Pi OS (32-bit ou 64-bit)
# Download direto:
wget https://downloads.raspberrypi.com/raspios_lite_armhf/images/raspios_lite_armhf-2022-09-07/2022-09-06-raspios-bullseye-armhf-lite.img.xz

# Ou use o Raspberry Pi Imager (recomendado)
# https://www.raspberrypi.org/software/
```

#### Habilitação de Interfaces no Raspberry Pi

```bash
# Após instalação do OS, habilitar interfaces necessárias
sudo raspi-config

# Navegue para:
# 3 Interface Options -> I1 SSH (Enable)
# 3 Interface Options -> I4 SPI (Enable) 
# 3 Interface Options -> I5 I2C (Enable)
# 5 Advanced Options -> A1 Expand Filesystem

# Reiniciar após mudanças
sudo reboot
```

#### Ajustar Qualidade de Áudio

```bash
# Para melhor qualidade (mais CPU):
# No .env do projeto:
AUDIO_SAMPLE_RATE=44100
AUDIO_CHANNELS=2

# Para economia de recursos (Raspberry Pi Zero):
AUDIO_SAMPLE_RATE=16000
AUDIO_CHANNELS=1
```

#### Configurar Auto-Detecção de Dispositivo

```bash
# Adicionar ao .env para auto-detecção:
AUDIO_DEVICE_AUTO=true
AUDIO_DEVICE_NAME="seeed-2mic-voicecard"

# Ou definir manualmente:
AUDIO_DEVICE="plughw:3,0"  # Ajuste conforme aplay -l
```

#### Otimizações de Performance

```bash
# Aumentar buffer de áudio para evitar dropouts
echo "AUDIO_BUFFER_SIZE=2048" >> .env

# Configurar prioridade de processo
echo "PROCESS_PRIORITY=high" >> .env
```

### Troubleshooting Específico do ReSpeaker

#### Problema: Placa não detectada

```bash
# Verificar conexão física
dmesg | grep -i audio
dmesg | grep -i wm8960

# Reinstalar driver
cd seeed-voicecard-6.1
sudo ./uninstall.sh
sudo ./install.sh
sudo reboot
```

#### Problema: LEDs não funcionam

```bash
# Verificar SPI habilitado
sudo raspi-config  # Interface Options -> SPI -> Enable

# Testar permissões
sudo usermod -a -G spi,gpio $USER
# Reiniciar sessão após este comando
```

#### Problema: Audio com ruído

```bash
# Verificar alimentação
# Use fonte externa via micro USB se necessário

# Ajustar ganho do microfone
amixer -c 3 set 'Left PGA Mixer Mic' 50%
amixer -c 3 set 'Right PGA Mixer Mic' 50%
```

#### Problema: Botão não responde

```bash
# Verificar GPIO
gpio readall | grep 17

# Testar manualmente
echo 17 > /sys/class/gpio/export
echo in > /sys/class/gpio/gpio17/direction
cat /sys/class/gpio/gpio17/value  # Deve mudar ao pressionar
```

### Integração com o Sistema de Transcrição

Após instalar o ReSpeaker, configure o projeto:

```bash
# No arquivo .env:
AUDIO_DEVICE="plughw:3,0"
AUDIO_SAMPLE_RATE=16000
AUDIO_CHANNELS=1
USE_RGB_FEEDBACK=true
USE_BUTTON_CONTROL=true

# Para feedback visual:
LED_STATUS_RECORDING=red
LED_STATUS_PROCESSING=blue  
LED_STATUS_READY=green
```

## 🚀 Otimizações para Raspberry Pi

### Performance

```bash
# CPU governor para balancear performance/energia
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Para economia de energia
echo powersave | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

### Configurações de Rede

```bash
# Reduzir frequência de verificação para economizar energia
CONNECTIVITY_CHECK_INTERVAL=10000
SEND_CHECK_INTERVAL=5000
```

## 🤝 Contribuição

### Ambiente de Desenvolvimento

```bash
# Node.js com hot reload
npm run dev

# Python com debug
python main.py --log-level DEBUG start
```

### Executar Testes

```bash
# Testes integrados
bash scripts/run-tests.sh

# Testes específicos
node scripts/test-system.sh      # Node.js
python scripts/test-system.py    # Python
```

## 📚 Recursos Adicionais

- 📖 **[Documentação Técnica Completa](./CLAUDE.md)** - Guia detalhado de instalação e configuração
- 🔗 **[Exemplos de API](./examples/)** - Servidores mock e exemplos de integração
- 🎯 **[Whisper.cpp](https://github.com/ggerganov/whisper.cpp)** - Engine de transcrição usado
- 📊 **[Modelos Whisper](https://huggingface.co/ggerganov/whisper.cpp)** - Download de modelos otimizados

## 📄 Licença

MIT License - veja [LICENSE](LICENSE) para detalhes.

## 🆘 Suporte

Para problemas ou dúvidas:

1. 📚 Consulte a [documentação técnica](./CLAUDE.md)
2. 🔍 Verifique as [issues conhecidas](#troubleshooting)
3. 📊 Execute `npm run status` ou `python main.py status` para diagnósticos
4. 📝 Verifique os logs em `./logs/`

---

**Desenvolvido para Raspberry Pi** 🥧 | **Funciona em qualquer Linux** 🐧 | **Totalmente offline** 🔒