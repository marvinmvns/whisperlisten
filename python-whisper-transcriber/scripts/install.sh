#!/bin/bash

# Script de instalação do Python Whisper Transcriber para Raspberry Pi
set -e

echo "=== Instalando Python Whisper Transcriber para Raspberry Pi ==="

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Função para log
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Verificar se está rodando no Raspberry Pi
if ! grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
    warn "Este script é otimizado para Raspberry Pi, mas tentará continuar..."
fi

# Verificar Python
log "Verificando Python..."
if ! command -v python3 > /dev/null; then
    error "Python 3 não encontrado. Instale com: sudo apt install python3 python3-pip"
fi

PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
log "Python version: $PYTHON_VERSION"

if [[ "$(echo $PYTHON_VERSION | cut -d. -f1)" -lt 3 ]] || [[ "$(echo $PYTHON_VERSION | cut -d. -f2)" -lt 8 ]]; then
    error "Python 3.8+ é necessário. Versão atual: $PYTHON_VERSION"
fi

# Atualizar sistema e instalar dependências
log "Instalando dependências do sistema..."
sudo apt-get update
sudo apt-get install -y \
    python3-pip \
    python3-venv \
    python3-dev \
    build-essential \
    cmake \
    git \
    wget \
    curl \
    pkg-config \
    portaudio19-dev \
    libffi-dev \
    libssl-dev \
    ffmpeg \
    sqlite3 \
    || error "Falha ao instalar dependências"

# Dependências específicas para compilação
sudo apt-get install -y \
    libasound2-dev \
    libportaudio2 \
    libportaudiocpp0 \
    || warn "Algumas dependências de áudio podem estar em falta"

# Criar diretórios
log "Criando diretórios..."
mkdir -p data/{temp,transcripts,queue} logs models

# Verificar se já existe venv
if [ ! -d "venv" ]; then
    log "Criando ambiente virtual Python..."
    python3 -m venv venv || error "Falha ao criar ambiente virtual"
fi

log "Ativando ambiente virtual..."
source venv/bin/activate || error "Falha ao ativar ambiente virtual"

# Atualizar pip
log "Atualizando pip..."
pip install --upgrade pip setuptools wheel || error "Falha ao atualizar pip"

# Instalar dependências Python baseadas na arquitetura
log "Detectando arquitetura..."
ARCH=$(uname -m)
log "Arquitetura: $ARCH"

# Pré-instalar numpy otimizado se possível
if [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "armv7l" ]]; then
    log "Instalando numpy otimizado para ARM..."
    pip install numpy==1.24.3 || warn "Falha ao instalar numpy otimizado"
fi

# Instalar PyAudio (pode ser problemático)
log "Instalando PyAudio..."
pip install pyaudio || {
    warn "Falha no pip install pyaudio, tentando compilar..."
    sudo apt-get install -y python3-pyaudio || error "Falha ao instalar PyAudio"
}

# Instalar webrtcvad
log "Instalando webrtcvad..."
pip install webrtcvad || error "Falha ao instalar webrtcvad"

# Instalar outras dependências base
log "Instalando dependências base..."
pip install \
    requests \
    python-dotenv \
    scipy \
    psutil \
    || error "Falha ao instalar dependências base"

# Escolher e instalar backend Whisper baseado na RAM
RAM_GB=$(free -m | awk 'NR==2{printf "%.1f", $2/1024}')
log "RAM detectada: ${RAM_GB}GB"

log "Instalando backend Whisper..."

# Instalar pywhispercpp (recomendado para Pi)
if pip install pywhispercpp; then
    log "✓ pywhispercpp instalado com sucesso"
    WHISPER_BACKEND="pywhispercpp"
else
    warn "Falha ao instalar pywhispercpp, tentando alternativas..."
    
    # Tentar faster-whisper
    if pip install faster-whisper; then
        log "✓ faster-whisper instalado"
        WHISPER_BACKEND="faster-whisper"
    else
        warn "Falha ao instalar faster-whisper, tentando openai-whisper..."
        
        # Última tentativa: openai-whisper
        if pip install openai-whisper; then
            log "✓ openai-whisper instalado"
            WHISPER_BACKEND="openai"
        else
            error "Falha ao instalar qualquer backend Whisper"
        fi
    fi
fi

# Download dos modelos se usando pywhispercpp
if [[ "$WHISPER_BACKEND" == "pywhispercpp" ]]; then
    log "Baixando modelos Whisper..."
    
    cd models
    
    # Função para download com retry
    download_model() {
        local model_name=$1
        local model_url=$2
        local max_attempts=3
        local attempt=1
        
        while [ $attempt -le $max_attempts ]; do
            log "Tentativa $attempt/$max_attempts: Baixando $model_name..."
            
            if wget -q --show-progress --timeout=60 "$model_url"; then
                log "✓ $model_name baixado com sucesso"
                return 0
            else
                warn "Falha na tentativa $attempt para $model_name"
                attempt=$((attempt + 1))
                sleep 5
            fi
        done
        
        warn "Falha ao baixar $model_name após $max_attempts tentativas"
        return 1
    }
    
    BASE_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
    
    # Escolher modelos baseado na RAM
    if (( $(echo "$RAM_GB < 2" | bc -l) )); then
        log "RAM baixa detectada - baixando modelo tiny"
        download_model "tiny.en" "$BASE_URL/ggml-tiny.en.bin"
        download_model "tiny.en quantizado" "$BASE_URL/ggml-tiny.en-q8_0.bin" || true
        DEFAULT_MODEL="./models/ggml-tiny.en.bin"
    elif (( $(echo "$RAM_GB < 4" | bc -l) )); then
        log "RAM média detectada - baixando modelo base"
        download_model "base.en" "$BASE_URL/ggml-base.en.bin"
        download_model "base.en quantizado" "$BASE_URL/ggml-base.en-q5_0.bin" || true
        DEFAULT_MODEL="./models/ggml-base.en-q5_0.bin"
    else
        log "RAM suficiente detectada - baixando modelos small e base"
        download_model "base.en" "$BASE_URL/ggml-base.en.bin"
        download_model "base.en quantizado" "$BASE_URL/ggml-base.en-q5_0.bin" || true
        download_model "small.en quantizado" "$BASE_URL/ggml-small.en-q5_0.bin" || true
        DEFAULT_MODEL="./models/ggml-base.en-q5_0.bin"
    fi
    
    cd ..
else
    log "Usando backend $WHISPER_BACKEND - modelos serão baixados automaticamente"
    DEFAULT_MODEL="base.en"
fi

# Configurar arquivo .env
if [ ! -f .env ]; then
    log "Criando arquivo .env..."
    cp .env.example .env
    
    # Ajustar configurações baseadas no sistema
    sed -i "s|WHISPER_BACKEND=.*|WHISPER_BACKEND=$WHISPER_BACKEND|" .env
    
    if [[ "$WHISPER_BACKEND" == "pywhispercpp" ]]; then
        sed -i "s|MODEL_PATH=.*|MODEL_PATH=$DEFAULT_MODEL|" .env
    else
        sed -i "s|MODEL_NAME=.*|MODEL_NAME=$DEFAULT_MODEL|" .env
    fi
    
    # Ajustar threads baseado no modelo de Pi
    if grep -q "Raspberry Pi 5" /proc/cpuinfo; then
        sed -i "s|N_THREADS=.*|N_THREADS=4|" .env
    else
        sed -i "s|N_THREADS=.*|N_THREADS=2|" .env
    fi
fi

# Configurar sistema de áudio
log "Configurando sistema de áudio..."

# Adicionar usuário ao grupo audio
sudo usermod -a -G audio $USER || warn "Falha ao adicionar usuário ao grupo audio"

# Testar captura de áudio
log "Testando captura de áudio..."
if command -v arecord > /dev/null; then
    if timeout 1s arecord -f cd -t raw /dev/null 2>/dev/null; then
        log "✓ Microfone funcionando"
    else
        warn "⚠ Problema com microfone - verifique conexões"
        warn "Dispositivos de áudio disponíveis:"
        arecord -l 2>/dev/null || true
    fi
fi

# Teste básico da aplicação
log "Testando aplicação..."
if python main.py test > /dev/null 2>&1; then
    log "✓ Aplicação funcionando"
else
    warn "⚠ Aplicação pode ter problemas - verifique logs"
fi

# Criar serviço systemd (opcional)
create_service() {
    local service_file="/etc/systemd/system/whisper-transcriber-py.service"
    local user=$(whoami)
    local working_dir=$(pwd)
    
    log "Criando serviço systemd..."
    
    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=Python Whisper Transcriber Service
Documentation=https://github.com/your-username/whisper-transcriber
After=network.target sound.target
Wants=network-online.target

[Service]
Type=simple
User=$user
Group=audio
WorkingDirectory=$working_dir
Environment=PATH=$working_dir/venv/bin
ExecStart=$working_dir/venv/bin/python main.py start
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=10
StartLimitInterval=60
StartLimitBurst=3
MemoryLimit=1G
StandardOutput=journal
StandardError=journal
SyslogIdentifier=whisper-transcriber-py
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$working_dir/data $working_dir/logs
SupplementaryGroups=audio
TimeoutStartSec=30
TimeoutStopSec=15

[Install]
WantedBy=multi-user.target
EOF

    log "Serviço criado em: $service_file"
    log "Para ativar:"
    log "  sudo systemctl enable whisper-transcriber-py"
    log "  sudo systemctl start whisper-transcriber-py"
}

# Perguntar se quer criar serviço
read -p "Criar serviço systemd? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    create_service
fi

echo
log "=== Instalação Concluída ==="
echo
echo -e "${GREEN}Próximos passos:${NC}"
echo "1. Ative o ambiente: source venv/bin/activate"
echo "2. Edite o arquivo .env com suas configurações"
echo "3. Teste: python main.py test"
echo "4. Execute: python main.py start"
echo
echo -e "${GREEN}Comandos úteis:${NC}"
echo "python main.py status    # Ver status"
echo "python main.py queue     # Ver fila"
echo "python main.py test      # Testar sistema"
echo
echo -e "${GREEN}Backend instalado:${NC} $WHISPER_BACKEND"
if [[ "$WHISPER_BACKEND" == "pywhispercpp" ]]; then
    echo -e "${GREEN}Modelo padrão:${NC} $DEFAULT_MODEL"
    echo -e "${YELLOW}Modelos baixados:${NC}"
    ls -lh models/*.bin 2>/dev/null || true
fi
echo
echo -e "${YELLOW}RAM disponível: ${RAM_GB}GB${NC}"
if (( $(echo "$RAM_GB < 2" | bc -l) )); then
    warn "RAM baixa - considere usar modelo tiny para melhor performance"
fi

log "Instalação concluída com sucesso!"