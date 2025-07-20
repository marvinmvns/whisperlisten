#!/bin/bash

# Script específico para configuração inicial do Raspberry Pi
set -e

echo "=== Configuração do Raspberry Pi para Whisper Transcriber ==="

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Verificar se está no Raspberry Pi
if ! grep -q "Raspberry Pi" /proc/cpuinfo; then
    error "Este script deve ser executado em um Raspberry Pi"
fi

# Detectar modelo do Pi
PI_MODEL=$(cat /proc/cpuinfo | grep "Raspberry Pi" | head -1 | cut -d':' -f2 | xargs)
log "Detectado: $PI_MODEL"

# Verificar memória
TOTAL_RAM=$(free -m | awk 'NR==2{printf "%.0f", $2}')
log "RAM total: ${TOTAL_RAM}MB"

# Configurações recomendadas baseadas no modelo
case "$PI_MODEL" in
    *"Pi 5"*)
        log "Configurando para Raspberry Pi 5..."
        RECOMMENDED_THREADS=4
        RECOMMENDED_MODEL="base.en"
        SWAP_SIZE=1024
        ;;
    *"Pi 4"*)
        log "Configurando para Raspberry Pi 4..."
        RECOMMENDED_THREADS=2
        if [ "$TOTAL_RAM" -gt 4000 ]; then
            RECOMMENDED_MODEL="base.en"
            SWAP_SIZE=1024
        else
            RECOMMENDED_MODEL="tiny.en"
            SWAP_SIZE=2048
        fi
        ;;
    *)
        warn "Modelo de Pi não reconhecido, usando configurações conservadoras..."
        RECOMMENDED_THREADS=1
        RECOMMENDED_MODEL="tiny.en"
        SWAP_SIZE=2048
        ;;
esac

log "Configurações recomendadas:"
log "  - Threads: $RECOMMENDED_THREADS"
log "  - Modelo: $RECOMMENDED_MODEL"
log "  - Swap: ${SWAP_SIZE}MB"

# Atualizar sistema
log "Atualizando sistema..."
sudo apt-get update
sudo apt-get upgrade -y

# Configurar swap se necessário
CURRENT_SWAP=$(free -m | awk 'NR==3{printf "%.0f", $2}')
if [ "$CURRENT_SWAP" -lt "$SWAP_SIZE" ]; then
    log "Configurando swap para ${SWAP_SIZE}MB..."
    
    # Parar swap atual
    sudo dphys-swapfile swapoff || true
    
    # Configurar novo tamanho
    sudo sed -i "s/CONF_SWAPSIZE=.*/CONF_SWAPSIZE=$SWAP_SIZE/" /etc/dphys-swapfile
    
    # Recriar e ativar
    sudo dphys-swapfile setup
    sudo dphys-swapfile swapon
    
    log "✓ Swap configurado para ${SWAP_SIZE}MB"
else
    log "Swap já configurado adequadamente (${CURRENT_SWAP}MB)"
fi

# Configurar GPU memory split (liberar RAM para CPU)
log "Configurando divisão de memória GPU/CPU..."
if ! grep -q "gpu_mem=" /boot/config.txt; then
    echo "gpu_mem=16" | sudo tee -a /boot/config.txt
    log "✓ GPU memory definida para 16MB"
else
    log "GPU memory já configurada"
fi

# Habilitar áudio I2C e SPI se necessário
log "Verificando interfaces..."
sudo raspi-config nonint do_i2c 0
sudo raspi-config nonint do_spi 0
log "✓ I2C e SPI habilitados"

# Configurar áudio
log "Configurando sistema de áudio..."

# Verificar se há conflito com PulseAudio
if systemctl is-active --quiet pulseaudio; then
    warn "PulseAudio ativo - pode causar conflitos"
    read -p "Desativar PulseAudio? (recomendado) (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo systemctl disable pulseaudio
        sudo systemctl stop pulseaudio
        log "✓ PulseAudio desativado"
    fi
fi

# Configurar ALSA
if [ ! -f ~/.asoundrc ]; then
    log "Criando configuração ALSA..."
    cat > ~/.asoundrc << 'EOF'
pcm.!default {
    type asym
    playback.pcm "plughw:0,0"
    capture.pcm "plughw:1,0"
}

ctl.!default {
    type hw
    card 0
}
EOF
    log "✓ ALSA configurado"
fi

# Testar dispositivos de áudio
log "Testando dispositivos de áudio..."
arecord -l | head -10

# Configurar grupos de usuário
log "Configurando permissões de usuário..."
sudo usermod -a -G audio,dialout,i2c,spi $USER
log "✓ Usuário adicionado aos grupos necessários"

# Configurar CPU governor para performance
log "Configurando CPU governor..."
echo 'GOVERNOR="ondemand"' | sudo tee /etc/default/cpufrequtils
sudo systemctl enable cpufrequtils || true
log "✓ CPU governor configurado"

# Configurar limites de sistema
log "Configurando limites de sistema..."
cat | sudo tee -a /etc/security/limits.conf << 'EOF'
# Limites para whisper transcriber
* soft nofile 65536
* hard nofile 65536
* soft nproc 32768
* hard nproc 32768
EOF

# Configurar sysctl
cat | sudo tee /etc/sysctl.d/99-whisper.conf << 'EOF'
# Otimizações para whisper transcriber
vm.swappiness=10
vm.dirty_ratio=15
vm.dirty_background_ratio=5
net.core.rmem_max=16777216
net.core.wmem_max=16777216
EOF

log "✓ Limites de sistema configurados"

# Configurar watchdog para estabilidade
if [ -f /dev/watchdog ]; then
    log "Configurando watchdog..."
    echo 'watchdog-device = /dev/watchdog' | sudo tee -a /etc/watchdog.conf
    echo 'max-load-1 = 24' | sudo tee -a /etc/watchdog.conf
    sudo systemctl enable watchdog
    log "✓ Watchdog configurado"
fi

# Criar script de monitoramento
log "Criando script de monitoramento..."
cat > monitor_pi.sh << 'EOF'
#!/bin/bash
# Script de monitoramento do Raspberry Pi

echo "=== Status do Sistema ==="
echo "Temperatura CPU: $(vcgencmd measure_temp)"
echo "Frequência CPU: $(vcgencmd measure_clock arm)"
echo "Voltagem: $(vcgencmd measure_volts)"
echo "Throttling: $(vcgencmd get_throttled)"
echo

echo "=== Uso de Recursos ==="
free -h
echo
df -h /
echo

echo "=== Processos Top ==="
ps aux --sort=-%cpu | head -10
echo

if [ -f venv/bin/python ]; then
    echo "=== Status Whisper Transcriber ==="
    source venv/bin/activate
    python main.py status 2>/dev/null || echo "Whisper Transcriber não está rodando"
fi
EOF

chmod +x monitor_pi.sh
log "✓ Script de monitoramento criado: ./monitor_pi.sh"

# Configurar log rotation
log "Configurando rotação de logs..."
sudo tee /etc/logrotate.d/whisper-transcriber << 'EOF'
/home/*/whisper-transcriber*/logs/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 pi audio
    postrotate
        systemctl reload whisper-transcriber-py 2>/dev/null || true
    endscript
}
EOF

log "✓ Rotação de logs configurada"

# Configurar backup automático (opcional)
create_backup_script() {
    log "Criando script de backup..."
    
    cat > backup_config.sh << 'EOF'
#!/bin/bash
# Backup das configurações e dados importantes

BACKUP_DIR="/home/pi/backups/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

# Backup configurações
cp .env "$BACKUP_DIR/" 2>/dev/null || true
cp -r data/transcripts "$BACKUP_DIR/" 2>/dev/null || true
tar -czf "$BACKUP_DIR/queue.tar.gz" data/queue/ 2>/dev/null || true

# Manter apenas últimos 7 dias
find /home/pi/backups/ -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true

echo "Backup salvo em: $BACKUP_DIR"
EOF

    chmod +x backup_config.sh
    
    # Adicionar ao crontab
    (crontab -l 2>/dev/null; echo "0 2 * * * $(pwd)/backup_config.sh") | crontab -
    
    log "✓ Backup automático configurado (diário às 2h)"
}

read -p "Configurar backup automático? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    create_backup_script
fi

# Criar arquivo de configuração otimizada
log "Criando arquivo de configuração otimizada..."
cat > pi_optimized.env << EOF
# Configuração otimizada para $PI_MODEL
# RAM: ${TOTAL_RAM}MB

# Threading otimizado
N_THREADS=$RECOMMENDED_THREADS

# Modelo recomendado
WHISPER_BACKEND=pywhispercpp
MODEL_PATH=./models/ggml-${RECOMMENDED_MODEL}-q5_0.bin

# VAD otimizado para Pi
VAD_AGGRESSIVENESS=2
SILENCE_DURATION_MS=800
MIN_RECORDING_DURATION_MS=300

# Conectividade conservadora
CONNECTIVITY_CHECK_INTERVAL=10
SEND_CHECK_INTERVAL=3
REQUEST_TIMEOUT=15
MAX_RETRIES=3

# Otimizações de performance
SAMPLE_RATE=16000
CHUNK_DURATION_MS=30
EOF

log "✓ Configuração otimizada criada: pi_optimized.env"

# Teste final do sistema
log "Executando teste final do sistema..."

echo "=== Informações do Sistema ==="
echo "Modelo: $PI_MODEL"
echo "RAM: ${TOTAL_RAM}MB"
echo "Swap: $(free -m | awk 'NR==3{printf "%.0f", $2}')MB"
echo "Temperatura: $(vcgencmd measure_temp 2>/dev/null || echo 'N/A')"
echo "Throttling: $(vcgencmd get_throttled 2>/dev/null || echo 'N/A')"
echo

# Verificar se precisa reiniciar
REBOOT_REQUIRED=false

if [ -f /var/run/reboot-required ]; then
    REBOOT_REQUIRED=true
fi

# Verificar se swap foi alterado
NEW_SWAP=$(free -m | awk 'NR==3{printf "%.0f", $2}')
if [ "$NEW_SWAP" != "$CURRENT_SWAP" ]; then
    REBOOT_REQUIRED=true
fi

echo
log "=== Configuração do Raspberry Pi Concluída ==="
echo
echo -e "${GREEN}Otimizações aplicadas:${NC}"
echo "✓ Swap configurado para ${SWAP_SIZE}MB"
echo "✓ GPU memory otimizada"
echo "✓ Áudio configurado"
echo "✓ Usuário adicionado aos grupos necessários"
echo "✓ CPU governor configurado"
echo "✓ Limites de sistema ajustados"
echo "✓ Rotação de logs configurada"
echo "✓ Script de monitoramento criado"
echo
echo -e "${GREEN}Próximos passos:${NC}"
echo "1. Use a configuração: cp pi_optimized.env .env"
echo "2. Execute: bash scripts/install.sh"
echo "3. Teste: ./monitor_pi.sh"

if [ "$REBOOT_REQUIRED" = true ]; then
    echo
    warn "REINICIALIZAÇÃO NECESSÁRIA para aplicar todas as configurações"
    read -p "Reiniciar agora? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Reiniciando sistema..."
        sudo reboot
    else
        warn "Lembre-se de reiniciar antes de usar o sistema!"
    fi
fi

log "Configuração concluída com sucesso!"