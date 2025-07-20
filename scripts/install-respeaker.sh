#!/bin/bash

# 🎙️ ReSpeaker 2-Mic Pi HAT V1.0 - Universal Installation Script
# Instala e configura automaticamente o ReSpeaker 2-Mic Pi HAT no Raspberry Pi
# Compatível com Raspberry Pi 3B, 4B, 5 e Raspberry Pi OS (32/64-bit)

set -e  # Parar em caso de erro

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Símbolos
SUCCESS="✅"
WARNING="⚠️"
ERROR="❌"
INFO="ℹ️"
ROCKET="🚀"
GEAR="⚙️"
MIC="🎙️"

# Variáveis globais
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/tmp/respeaker-install.log"
BACKUP_DIR="/tmp/respeaker-backup-$(date +%Y%m%d-%H%M%S)"

# URLs dos recursos
SEEED_DRIVER_URL="https://www.dropbox.com/scl/fo/4x60kwe9gpr3no0h6s2xl/AP9QcnN3ApKXkGh9CJPLDzU?rlkey=1sjn1xxr114zviozu0pguwpnd&e=1&dl=1"
MIC_HAT_URL="https://github.com/respeaker/mic_hat/archive/master.zip"

# Função para logging
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Função para output colorido
print_status() {
    local type="$1"
    local message="$2"
    
    case $type in
        "success") echo -e "${GREEN}${SUCCESS} ${message}${NC}" ;;
        "warning") echo -e "${YELLOW}${WARNING} ${message}${NC}" ;;
        "error") echo -e "${RED}${ERROR} ${message}${NC}" ;;
        "info") echo -e "${BLUE}${INFO} ${message}${NC}" ;;
        "gear") echo -e "${CYAN}${GEAR} ${message}${NC}" ;;
        "mic") echo -e "${PURPLE}${MIC} ${message}${NC}" ;;
        "rocket") echo -e "${GREEN}${ROCKET} ${message}${NC}" ;;
    esac
    log "$type: $message"
}

# Função para verificar se está executando no Raspberry Pi
check_raspberry_pi() {
    print_status "info" "Verificando se está executando em Raspberry Pi..."
    
    if [[ ! -f /proc/device-tree/model ]]; then
        print_status "error" "Arquivo /proc/device-tree/model não encontrado"
        return 1
    fi
    
    local model=$(cat /proc/device-tree/model 2>/dev/null)
    if [[ "$model" =~ "Raspberry Pi" ]]; then
        print_status "success" "Detectado: $model"
        return 0
    else
        print_status "warning" "Este script foi otimizado para Raspberry Pi, mas tentará continuar"
        print_status "info" "Sistema detectado: $model"
        return 0
    fi
}

# Função para verificar permissões
check_permissions() {
    print_status "info" "Verificando permissões do usuário..."
    
    if [[ $EUID -eq 0 ]]; then
        print_status "error" "Não execute este script como root (sudo)"
        print_status "info" "Execute como usuário normal: bash $0"
        exit 1
    fi
    
    # Verificar se pode usar sudo
    if ! sudo -n true 2>/dev/null; then
        print_status "warning" "Você precisará inserir a senha do sudo durante a instalação"
    fi
    
    print_status "success" "Permissões verificadas"
}

# Função para criar backup
create_backup() {
    print_status "info" "Criando backup de configurações importantes..."
    
    mkdir -p "$BACKUP_DIR"
    
    # Backup de arquivos importantes
    [[ -f /boot/config.txt ]] && sudo cp /boot/config.txt "$BACKUP_DIR/"
    [[ -f /etc/asound.conf ]] && sudo cp /etc/asound.conf "$BACKUP_DIR/"
    [[ -d /etc/pulse ]] && sudo cp -r /etc/pulse "$BACKUP_DIR/"
    
    print_status "success" "Backup criado em: $BACKUP_DIR"
}

# Função para atualizar sistema
update_system() {
    print_status "gear" "Atualizando sistema base..."
    
    sudo apt-get update -y
    print_status "info" "Instalando dependências essenciais..."
    
    sudo apt-get install -y \
        git \
        wget \
        curl \
        unzip \
        build-essential \
        cmake \
        libasound2-dev \
        portaudio19-dev \
        libatlas-base-dev \
        python3-pip \
        python3-dev \
        python3-setuptools \
        alsa-utils \
        pulseaudio \
        pulseaudio-utils
    
    print_status "success" "Sistema atualizado e dependências instaladas"
}

# Função para habilitar interfaces do Raspberry Pi
enable_interfaces() {
    print_status "gear" "Habilitando interfaces necessárias (SPI, I2C)..."
    
    # Habilitar SPI
    if ! grep -q "dtparam=spi=on" /boot/config.txt; then
        echo "dtparam=spi=on" | sudo tee -a /boot/config.txt
        print_status "info" "SPI habilitado"
    else
        print_status "info" "SPI já estava habilitado"
    fi
    
    # Habilitar I2C
    if ! grep -q "dtparam=i2c_arm=on" /boot/config.txt; then
        echo "dtparam=i2c_arm=on" | sudo tee -a /boot/config.txt
        print_status "info" "I2C habilitado"
    else
        print_status "info" "I2C já estava habilitado"
    fi
    
    # Adicionar usuário aos grupos necessários
    sudo usermod -a -G spi,i2c,audio,gpio "$USER"
    
    print_status "success" "Interfaces habilitadas"
}

# Função para baixar e instalar o driver ReSpeaker
install_respeaker_driver() {
    print_status "mic" "Baixando e instalando driver ReSpeaker..."
    
    local temp_dir="/tmp/respeaker-install"
    mkdir -p "$temp_dir"
    cd "$temp_dir"
    
    # Download do driver
    print_status "info" "Baixando seeed-voicecard-6.1.zip..."
    wget -O seeed-voicecard-6.1.zip "$SEEED_DRIVER_URL" || {
        print_status "error" "Falha ao baixar driver ReSpeaker"
        exit 1
    }
    
    # Descompactar
    print_status "info" "Descompactando driver..."
    unzip -q seeed-voicecard-6.1.zip
    cd seeed-voicecard-6.1
    
    # Verificar se o script existe
    if [[ ! -f "install.sh" ]]; then
        print_status "error" "Script de instalação não encontrado no driver"
        exit 1
    fi
    
    # Instalar driver
    print_status "info" "Executando instalação do driver (pode levar alguns minutos)..."
    sudo ./install.sh || {
        print_status "error" "Falha na instalação do driver ReSpeaker"
        exit 1
    }
    
    print_status "success" "Driver ReSpeaker instalado com sucesso"
}

# Função para instalar bibliotecas Python para LEDs e botão
install_python_libs() {
    print_status "gear" "Instalando bibliotecas Python para controle de LEDs e botão..."
    
    # Instalar dependências Python
    pip3 install --user RPi.GPIO spidev || {
        print_status "warning" "Falha ao instalar algumas bibliotecas Python, tentando com sudo..."
        sudo pip3 install RPi.GPIO spidev
    }
    
    print_status "success" "Bibliotecas Python instaladas"
}

# Função para baixar scripts de exemplo do mic_hat
download_mic_hat_examples() {
    print_status "info" "Baixando scripts de exemplo para LEDs e botão..."
    
    local examples_dir="$PROJECT_ROOT/respeaker-examples"
    mkdir -p "$examples_dir"
    
    local temp_dir="/tmp/mic-hat-download"
    mkdir -p "$temp_dir"
    cd "$temp_dir"
    
    # Download dos exemplos
    wget -O mic_hat-master.zip "$MIC_HAT_URL" || {
        print_status "warning" "Falha ao baixar exemplos, mas continuando..."
        return 0
    }
    
    unzip -q mic_hat-master.zip
    
    # Copiar exemplos importantes
    if [[ -d "mic_hat-master/interfaces" ]]; then
        cp -r mic_hat-master/interfaces "$examples_dir/"
        print_status "success" "Exemplos copiados para: $examples_dir"
    fi
}

# Função para verificar instalação
verify_installation() {
    print_status "info" "Verificando instalação..."
    
    # Verificar se a placa de som foi detectada
    local audio_devices=$(aplay -l 2>/dev/null | grep -i "seeed\|voicecard" || true)
    if [[ -n "$audio_devices" ]]; then
        print_status "success" "Placa de áudio ReSpeaker detectada:"
        echo "$audio_devices" | while read line; do
            print_status "info" "  $line"
        done
    else
        print_status "warning" "Placa de áudio ReSpeaker não detectada ainda"
        print_status "info" "Isso é normal - será detectada após reinicialização"
    fi
    
    # Verificar interfaces
    if [[ -e /dev/spidev0.0 ]]; then
        print_status "success" "SPI disponível"
    else
        print_status "warning" "SPI não disponível (será ativado após reboot)"
    fi
    
    if [[ -e /dev/i2c-1 ]]; then
        print_status "success" "I2C disponível"
    else
        print_status "warning" "I2C não disponível (será ativado após reboot)"
    fi
}

# Função para criar arquivo de configuração do projeto
create_project_config() {
    print_status "gear" "Criando configuração do projeto..."
    
    local config_file="$PROJECT_ROOT/.env.respeaker"
    
    cat > "$config_file" << 'EOF'
# Configurações específicas do ReSpeaker 2-Mic Pi HAT V1.0
# Adicione estas linhas ao seu arquivo .env principal

# === ÁUDIO ===
AUDIO_DEVICE_AUTO=true
AUDIO_DEVICE_NAME="seeed-2mic-voicecard"
AUDIO_DEVICE="plughw:seeed2micvoicec,0"
AUDIO_SAMPLE_RATE=16000
AUDIO_CHANNELS=1
AUDIO_BUFFER_SIZE=2048

# === FEEDBACK VISUAL (LEDs RGB) ===
USE_RGB_FEEDBACK=true
LED_STATUS_READY=green
LED_STATUS_RECORDING=red
LED_STATUS_PROCESSING=blue
LED_STATUS_ERROR=yellow

# === CONTROLE POR BOTÃO ===
USE_BUTTON_CONTROL=true
BUTTON_GPIO=17
BUTTON_DEBOUNCE_MS=50

# === OTIMIZAÇÕES RASPBERRY PI ===
PROCESS_PRIORITY=high
VAD_AGGRESSIVENESS=2
MIN_RECORDING_TIME=1000
SILENCE_THRESHOLD=800

# === REDE (Otimizado para Pi) ===
CONNECTIVITY_CHECK_INTERVAL=10000
SEND_CHECK_INTERVAL=5000
MAX_RETRIES=3
RETRY_BACKOFF_MS=2000
EOF
    
    print_status "success" "Configuração criada: $config_file"
    print_status "info" "Copie essas configurações para seu arquivo .env principal"
}

# Função para teste rápido
quick_test() {
    print_status "info" "Executando teste rápido (não será executado por estar pendente de reboot)..."
    
    # Este teste só funcionará após o reboot, então apenas preparamos o script
    local test_script="$PROJECT_ROOT/scripts/test-respeaker.sh"
    
    cat > "$test_script" << 'EOF'
#!/bin/bash
# Script de teste pós-instalação do ReSpeaker

echo "🎙️ Testando ReSpeaker 2-Mic Pi HAT V1.0..."

echo "📋 Dispositivos de áudio disponíveis:"
aplay -l

echo ""
echo "🎧 Dispositivos de gravação disponíveis:"
arecord -l

echo ""
echo "🔊 Testando microfone (grave 3 segundos)..."
if arecord -D "plughw:seeed2micvoicec,0" -f S16_LE -r 16000 -d 3 -t wav /tmp/test-respeaker.wav 2>/dev/null; then
    echo "✅ Gravação concluída"
    echo "🔊 Reproduzindo gravação..."
    aplay -D "plughw:seeed2micvoicec,0" /tmp/test-respeaker.wav 2>/dev/null
    echo "✅ Teste de áudio concluído"
    rm -f /tmp/test-respeaker.wav
else
    echo "❌ Falha no teste de áudio"
fi

echo ""
echo "💡 Testando LEDs (se os exemplos estiverem disponíveis)..."
if [[ -f "$HOME/respeaker-examples/interfaces/pixels.py" ]]; then
    timeout 5 python3 "$HOME/respeaker-examples/interfaces/pixels.py" 2>/dev/null || echo "LEDs testados"
else
    echo "⚠️ Exemplos de LED não encontrados"
fi

echo ""
echo "🔘 Testando botão (pressione o botão por 3 segundos)..."
if [[ -f "$HOME/respeaker-examples/interfaces/button.py" ]]; then
    timeout 5 python3 "$HOME/respeaker-examples/interfaces/button.py" 2>/dev/null || echo "Teste de botão finalizado"
else
    echo "⚠️ Exemplos de botão não encontrados"
fi

echo ""
echo "🎙️ Teste do ReSpeaker concluído!"
echo "Execute este script novamente após o reboot: bash $0"
EOF
    
    chmod +x "$test_script"
    print_status "success" "Script de teste criado: $test_script"
}

# Função para mostrar próximos passos
show_next_steps() {
    print_status "rocket" "Instalação concluída com sucesso!"
    
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                           🎙️ PRÓXIMOS PASSOS                                 ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║                                                                              ║${NC}"
    echo -e "${CYAN}║  1. 🔄 REBOOT OBRIGATÓRIO:                                                   ║${NC}"
    echo -e "${CYAN}║     sudo reboot                                                              ║${NC}"
    echo -e "${CYAN}║                                                                              ║${NC}"
    echo -e "${CYAN}║  2. 🧪 Após o reboot, teste a instalação:                                   ║${NC}"
    echo -e "${CYAN}║     bash $PROJECT_ROOT/scripts/test-respeaker.sh                         ║${NC}"
    echo -e "${CYAN}║                                                                              ║${NC}"
    echo -e "${CYAN}║  3. ⚙️ Configure seu projeto:                                               ║${NC}"
    echo -e "${CYAN}║     cp $PROJECT_ROOT/.env.respeaker $PROJECT_ROOT/.env                    ║${NC}"
    echo -e "${CYAN}║     # Edite o arquivo .env com suas configurações                          ║${NC}"
    echo -e "${CYAN}║                                                                              ║${NC}"
    echo -e "${CYAN}║  4. 🚀 Execute seu sistema de transcrição:                                  ║${NC}"
    echo -e "${CYAN}║     cd $PROJECT_ROOT/nodejs-whisper-transcriber && npm start               ║${NC}"
    echo -e "${CYAN}║     # OU                                                                     ║${NC}"
    echo -e "${CYAN}║     cd $PROJECT_ROOT/python-whisper-transcriber && python main.py start    ║${NC}"
    echo -e "${CYAN}║                                                                              ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    print_status "info" "📋 Log completo da instalação: $LOG_FILE"
    print_status "info" "💾 Backup das configurações: $BACKUP_DIR"
    print_status "warning" "🔄 REBOOT NECESSÁRIO para ativar o driver do ReSpeaker"
}

# Função para limpeza em caso de erro
cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        print_status "error" "Instalação falhou com código: $exit_code"
        print_status "info" "Log de erros disponível em: $LOG_FILE"
        print_status "info" "Backup das configurações em: $BACKUP_DIR"
    fi
}

# Função de ajuda
show_help() {
    echo -e "${BLUE}🎙️ ReSpeaker 2-Mic Pi HAT V1.0 - Script de Instalação Universal${NC}"
    echo ""
    echo "USO:"
    echo "  bash $0 [opções]"
    echo ""
    echo "OPÇÕES:"
    echo "  -h, --help          Mostra esta ajuda"
    echo "  -q, --quiet         Modo silencioso (apenas erros)"
    echo "  -v, --verbose       Modo verboso (debug)"
    echo "  --skip-update       Pula atualização do sistema"
    echo "  --skip-backup       Pula criação de backup"
    echo "  --force             Força instalação mesmo em sistemas não-Pi"
    echo ""
    echo "EXEMPLOS:"
    echo "  bash $0                    # Instalação padrão"
    echo "  bash $0 --skip-update      # Pula atualização do sistema"
    echo "  bash $0 --verbose          # Instalação com debug"
    echo ""
    echo "APÓS A INSTALAÇÃO:"
    echo "  1. sudo reboot"
    echo "  2. bash scripts/test-respeaker.sh"
    echo "  3. Configure seu projeto com as variáveis do .env.respeaker"
    echo ""
}

# Processamento de argumentos
SKIP_UPDATE=false
SKIP_BACKUP=false
VERBOSE=false
QUIET=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --skip-update)
            SKIP_UPDATE=true
            shift
            ;;
        --skip-backup)
            SKIP_BACKUP=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            print_status "error" "Opção desconhecida: $1"
            show_help
            exit 1
            ;;
    esac
done

# Configurar logging baseado nas opções
if [[ "$QUIET" == "true" ]]; then
    exec 1>/dev/null
elif [[ "$VERBOSE" == "true" ]]; then
    set -x
fi

# Função principal
main() {
    # Configurar tratamento de erros
    trap cleanup_on_error EXIT
    
    # Cabeçalho
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                 🎙️ ReSpeaker 2-Mic Pi HAT V1.0 Installer                    ║"
    echo "║                      Universal Installation Script                           ║"
    echo "║                                                                              ║"
    echo "║           Instala automaticamente o driver e dependências                   ║"
    echo "║              Compatível com Raspberry Pi 3B/4B/5                           ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    
    # Iniciar log
    log "=== Iniciando instalação ReSpeaker 2-Mic Pi HAT V1.0 ==="
    log "Usuário: $USER"
    log "Sistema: $(uname -a)"
    log "Argumentos: $*"
    
    # Verificações iniciais
    check_permissions
    
    if [[ "$FORCE" != "true" ]]; then
        check_raspberry_pi
    fi
    
    # Backup
    if [[ "$SKIP_BACKUP" != "true" ]]; then
        create_backup
    fi
    
    # Instalação
    if [[ "$SKIP_UPDATE" != "true" ]]; then
        update_system
    fi
    
    enable_interfaces
    install_respeaker_driver
    install_python_libs
    download_mic_hat_examples
    verify_installation
    create_project_config
    quick_test
    
    # Finalização
    show_next_steps
    
    # Remover tratamento de erro (sucesso)
    trap - EXIT
    
    log "=== Instalação concluída com sucesso ==="
}

# Executar função principal
main "$@"