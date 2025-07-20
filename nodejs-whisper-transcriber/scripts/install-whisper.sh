#!/bin/bash

# Script de instalação do Whisper.cpp para Raspberry Pi
set -e

echo "=== Instalando Whisper.cpp para Raspberry Pi ==="

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

# Verificar dependências do sistema
log "Verificando e instalando dependências..."

# Atualizar sistema
if command -v apt-get > /dev/null; then
    sudo apt-get update
    sudo apt-get install -y \
        build-essential \
        cmake \
        git \
        wget \
        curl \
        pkg-config \
        portaudio19-dev \
        libsdl2-dev \
        ffmpeg \
        || error "Falha ao instalar dependências"
else
    error "Sistema não suportado (apt-get não encontrado)"
fi

# Criar diretórios
log "Criando diretórios..."
mkdir -p models logs data/{temp,transcripts,queue}

# Clonar e compilar whisper.cpp
if [ ! -d "whisper.cpp" ]; then
    log "Clonando whisper.cpp..."
    git clone https://github.com/ggerganov/whisper.cpp.git || error "Falha ao clonar whisper.cpp"
fi

cd whisper.cpp

log "Compilando whisper.cpp..."

# Otimizações para Raspberry Pi
if grep -q "Raspberry Pi 4" /proc/cpuinfo; then
    log "Detectado Raspberry Pi 4 - usando otimizações ARM"
    make -j$(nproc) GGML_NO_ACCELERATE=1 GGML_OPENBLAS=1 || make -j$(nproc)
elif grep -q "Raspberry Pi 5" /proc/cpuinfo; then
    log "Detectado Raspberry Pi 5 - usando otimizações avançadas"
    make -j$(nproc) GGML_NO_ACCELERATE=1 || make -j$(nproc)
else
    log "Compilando para arquitetura genérica ARM"
    make -j2 || error "Falha na compilação"
fi

cd ..

# Verificar se a compilação foi bem-sucedida
if [ ! -f "whisper.cpp/main" ]; then
    error "Compilação falhou - binário não encontrado"
fi

log "Teste do binário..."
./whisper.cpp/main --help > /dev/null || error "Binário não funciona corretamente"

# Download dos modelos
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
    
    error "Falha ao baixar $model_name após $max_attempts tentativas"
}

# Modelos quantizados para melhor performance no Pi
BASE_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

# Tiny (mais rápido)
download_model "tiny.en" "$BASE_URL/ggml-tiny.en.bin"
download_model "tiny.en quantizado" "$BASE_URL/ggml-tiny.en-q8_0.bin"

# Base (recomendado)
download_model "base.en" "$BASE_URL/ggml-base.en.bin"
download_model "base.en quantizado" "$BASE_URL/ggml-base.en-q5_0.bin"

# Small (se tiver RAM suficiente)
if [ "$(free -m | awk 'NR==2{printf "%.1f", $2/1024}')" -gt "3.5" ]; then
    log "RAM suficiente detectada - baixando modelo small"
    download_model "small.en quantizado" "$BASE_URL/ggml-small.en-q5_0.bin"
fi

cd ..

# Verificar instalação do Node.js
log "Verificando Node.js..."
if ! command -v node > /dev/null; then
    log "Instalando Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install -y nodejs || error "Falha ao instalar Node.js"
fi

NODE_VERSION=$(node --version | cut -d'v' -f2)
log "Node.js version: $NODE_VERSION"

# Instalar PM2 globalmente (opcional)
if ! command -v pm2 > /dev/null; then
    log "Instalando PM2..."
    sudo npm install -g pm2 || warn "Falha ao instalar PM2 (opcional)"
fi

# Configurar áudio
log "Configurando sistema de áudio..."

# Adicionar usuário ao grupo audio
sudo usermod -a -G audio $USER || warn "Falha ao adicionar usuário ao grupo audio"

# Configurar ALSA (se necessário)
if [ ! -f ~/.asoundrc ]; then
    log "Criando configuração ALSA básica..."
    cat > ~/.asoundrc << EOF
pcm.!default {
    type pulse
}
ctl.!default {
    type pulse
}
EOF
fi

# Teste de microfone
log "Testando captura de áudio..."
if command -v arecord > /dev/null; then
    # Teste rápido de 1 segundo
    timeout 1s arecord -f cd -t raw /dev/null 2>/dev/null && \
        log "✓ Microfone funcionando" || \
        warn "⚠ Problema com microfone - verifique conexões"
fi

# Criar arquivo de configuração de exemplo
if [ ! -f .env ]; then
    log "Criando arquivo .env..."
    cp .env.example .env
    
    # Ajustar caminhos no .env
    sed -i "s|WHISPER_PATH=.*|WHISPER_PATH=$(pwd)/whisper.cpp/main|" .env
    
    # Escolher modelo baseado na RAM disponível
    RAM_GB=$(free -m | awk 'NR==2{printf "%.1f", $2/1024}')
    if (( $(echo "$RAM_GB > 3.5" | bc -l) )); then
        sed -i "s|MODEL_PATH=.*|MODEL_PATH=$(pwd)/models/ggml-base.en-q5_0.bin|" .env
    else
        sed -i "s|MODEL_PATH=.*|MODEL_PATH=$(pwd)/models/ggml-tiny.en-q8_0.bin|" .env
    fi
fi

# Instalar dependências Node.js
log "Instalando dependências Node.js..."
npm install || error "Falha ao instalar dependências Node.js"

# Teste final
log "Executando teste do sistema..."
if node index.js status > /dev/null 2>&1; then
    log "✓ Sistema funcional"
else
    warn "⚠ Sistema pode ter problemas - verifique logs"
fi

echo
log "=== Instalação Concluída ==="
echo
echo -e "${GREEN}Próximos passos:${NC}"
echo "1. Edite o arquivo .env com suas configurações"
echo "2. Teste: npm run status"
echo "3. Execute: npm start"
echo
echo -e "${GREEN}Para rodar como serviço:${NC}"
echo "sudo cp whisper-transcriber.service /etc/systemd/system/"
echo "sudo systemctl enable whisper-transcriber"
echo "sudo systemctl start whisper-transcriber"
echo
echo -e "${GREEN}Para usar Docker:${NC}"
echo "docker-compose up -d"
echo
echo -e "${YELLOW}Modelos instalados:${NC}"
ls -lh models/*.bin
echo
echo -e "${YELLOW}RAM disponível: ${RAM_GB}GB${NC}"

if (( $(echo "$RAM_GB < 2" | bc -l) )); then
    warn "RAM baixa detectada - use modelo tiny para melhor performance"
fi