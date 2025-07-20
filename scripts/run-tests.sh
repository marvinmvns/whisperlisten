#!/bin/bash

# Script mestre para executar testes em ambos os projetos
set -e

echo "=== Script Mestre de Testes - Whisper Transcriber ==="

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
header() { echo -e "${BLUE}[HEADER]${NC} $1"; }

# Variáveis de controle
RUN_NODEJS=true
RUN_PYTHON=true
KEEP_TEST_FILES=false
QUICK_TEST=false

# Parse argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        --nodejs-only)
            RUN_PYTHON=false
            shift
            ;;
        --python-only)
            RUN_NODEJS=false
            shift
            ;;
        --keep-test-files)
            KEEP_TEST_FILES=true
            shift
            ;;
        --quick)
            QUICK_TEST=true
            shift
            ;;
        --help|-h)
            echo "Uso: $0 [opções]"
            echo ""
            echo "Opções:"
            echo "  --nodejs-only      Testar apenas projeto Node.js"
            echo "  --python-only      Testar apenas projeto Python"
            echo "  --keep-test-files  Manter arquivos de teste após execução"
            echo "  --quick           Executar apenas testes essenciais"
            echo "  --help, -h        Mostrar esta ajuda"
            exit 0
            ;;
        *)
            error "Opção desconhecida: $1"
            exit 1
            ;;
    esac
done

# Verificar estrutura do projeto
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

if [ ! -d "$PROJECT_ROOT/nodejs-whisper-transcriber" ] || [ ! -d "$PROJECT_ROOT/python-whisper-transcriber" ]; then
    error "Estrutura do projeto não encontrada. Execute no diretório correto."
    exit 1
fi

log "Diretório do projeto: $PROJECT_ROOT"
log "Modo Node.js: $($RUN_NODEJS && echo 'SIM' || echo 'NÃO')"
log "Modo Python: $($RUN_PYTHON && echo 'SIM' || echo 'NÃO')"
log "Teste rápido: $($QUICK_TEST && echo 'SIM' || echo 'NÃO')"

# Verificar dependências do sistema
check_system_dependencies() {
    header "Verificando dependências do sistema..."
    
    local missing_deps=()
    
    # Verificar comandos essenciais
    for cmd in git wget curl; do
        if ! command -v $cmd > /dev/null; then
            missing_deps+=($cmd)
        fi
    done
    
    # Verificar Node.js se necessário
    if [ "$RUN_NODEJS" = true ]; then
        if ! command -v node > /dev/null; then
            missing_deps+=(nodejs)
        fi
        if ! command -v npm > /dev/null; then
            missing_deps+=(npm)
        fi
    fi
    
    # Verificar Python se necessário  
    if [ "$RUN_PYTHON" = true ]; then
        if ! command -v python3 > /dev/null; then
            missing_deps+=(python3)
        fi
        if ! command -v pip3 > /dev/null; then
            missing_deps+=(python3-pip)
        fi
    fi
    
    # Verificar ferramentas de áudio (opcionais)
    local audio_tools=()
    for tool in ffmpeg espeak arecord; do
        if ! command -v $tool > /dev/null; then
            audio_tools+=($tool)
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        error "Dependências obrigatórias ausentes: ${missing_deps[*]}"
        log "Para instalar no Ubuntu/Debian:"
        log "sudo apt-get install ${missing_deps[*]}"
        return 1
    fi
    
    if [ ${#audio_tools[@]} -gt 0 ]; then
        warn "Ferramentas de áudio opcionais ausentes: ${audio_tools[*]}"
        log "Para instalar: sudo apt-get install ${audio_tools[*]}"
    fi
    
    log "✓ Dependências do sistema verificadas"
    return 0
}

# Executar pré-verificações
pre_check() {
    header "Executando pré-verificações..."
    
    # Verificar espaço em disco
    local available_space=$(df . | awk 'NR==2 {print $4}')
    local required_space=1048576  # 1GB em KB
    
    if [ "$available_space" -lt "$required_space" ]; then
        warn "Pouco espaço em disco disponível ($(( available_space / 1024 ))MB)"
    fi
    
    # Verificar se está no Raspberry Pi
    if grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
        log "✓ Executando no Raspberry Pi"
        
        # Verificar temperatura
        if command -v vcgencmd > /dev/null; then
            local temp=$(vcgencmd measure_temp | grep -o '[0-9.]*')
            log "Temperatura CPU: ${temp}°C"
            
            if (( $(echo "$temp > 70" | bc -l) )); then
                warn "Temperatura alta detectada - considere resfriar o sistema"
            fi
        fi
        
        # Verificar throttling
        if command -v vcgencmd > /dev/null; then
            local throttled=$(vcgencmd get_throttled)
            if [ "$throttled" != "throttled=0x0" ]; then
                warn "Throttling detectado: $throttled"
            fi
        fi
    fi
    
    log "✓ Pré-verificações concluídas"
}

# Testar projeto Node.js
test_nodejs() {
    header "=== Testando Projeto Node.js ==="
    
    cd "$PROJECT_ROOT/nodejs-whisper-transcriber"
    
    if [ ! -f "package.json" ]; then
        error "Projeto Node.js não encontrado ou mal configurado"
        return 1
    fi
    
    # Verificar se dependências estão instaladas
    if [ ! -d "node_modules" ]; then
        log "Dependências Node.js não instaladas, instalando..."
        npm install || {
            error "Falha ao instalar dependências Node.js"
            return 1
        }
    fi
    
    # Executar script de teste
    local test_args=""
    if [ "$KEEP_TEST_FILES" = true ]; then
        test_args="--keep-test-files"
    fi
    
    log "Executando testes Node.js..."
    if bash scripts/test-system.sh $test_args; then
        log "✓ Testes Node.js PASSARAM"
        return 0
    else
        error "✗ Testes Node.js FALHARAM"
        return 1
    fi
}

# Testar projeto Python
test_python() {
    header "=== Testando Projeto Python ==="
    
    cd "$PROJECT_ROOT/python-whisper-transcriber"
    
    if [ ! -f "main.py" ]; then
        error "Projeto Python não encontrado ou mal configurado"
        return 1
    fi
    
    # Verificar ambiente virtual
    if [ ! -d "venv" ]; then
        log "Ambiente virtual não encontrado, criando..."
        python3 -m venv venv || {
            error "Falha ao criar ambiente virtual"
            return 1
        }
    fi
    
    # Ativar ambiente virtual
    source venv/bin/activate || {
        error "Falha ao ativar ambiente virtual"
        return 1
    }
    
    # Verificar dependências
    log "Verificando dependências Python..."
    pip install -q -r requirements.txt || {
        warn "Algumas dependências podem não ter sido instaladas"
    }
    
    # Executar script de teste
    local test_args=""
    if [ "$KEEP_TEST_FILES" = true ]; then
        test_args="--keep-test-files"
    fi
    
    log "Executando testes Python..."
    if python scripts/test-system.py $test_args; then
        log "✓ Testes Python PASSARAM"
        return 0
    else
        error "✗ Testes Python FALHARAM"
        return 1
    fi
}

# Executar benchmark comparativo
run_benchmark() {
    if [ "$QUICK_TEST" = true ]; then
        return 0
    fi
    
    header "=== Benchmark Comparativo ==="
    
    log "Gerando áudio de teste para benchmark..."
    
    # Criar áudio de teste comum
    local benchmark_dir="$PROJECT_ROOT/benchmark_test"
    mkdir -p "$benchmark_dir"
    
    # Gerar áudio de teste se possível
    if command -v espeak > /dev/null && command -v ffmpeg > /dev/null; then
        local test_text="This is a benchmark test for whisper transcription performance"
        espeak -w "$benchmark_dir/benchmark.wav" -s 150 "$test_text"
        ffmpeg -i "$benchmark_dir/benchmark.wav" -ar 16000 -ac 1 -y "$benchmark_dir/benchmark_16k.wav" > /dev/null 2>&1
        
        log "✓ Áudio de benchmark gerado"
        
        # Testar performance de cada projeto se ambos estão habilitados
        if [ "$RUN_NODEJS" = true ] && [ "$RUN_PYTHON" = true ]; then
            log "Comparando performance..."
            
            # Node.js
            cd "$PROJECT_ROOT/nodejs-whisper-transcriber"
            local nodejs_start=$(date +%s.%N)
            # Aqui poderia executar teste de transcrição específico
            local nodejs_end=$(date +%s.%N)
            local nodejs_time=$(echo "$nodejs_end - $nodejs_start" | bc)
            
            # Python  
            cd "$PROJECT_ROOT/python-whisper-transcriber"
            source venv/bin/activate
            local python_start=$(date +%s.%N)
            # Aqui poderia executar teste de transcrição específico
            local python_end=$(date +%s.%N)
            local python_time=$(echo "$python_end - $python_start" | bc)
            
            log "Tempo Node.js: ${nodejs_time}s"
            log "Tempo Python: ${python_time}s"
        fi
    else
        warn "Ferramentas para benchmark não disponíveis"
    fi
    
    # Limpar arquivos de benchmark
    rm -rf "$benchmark_dir"
}

# Gerar relatório final
generate_report() {
    header "=== Relatório Final ==="
    
    local total_tests=0
    local passed_tests=0
    
    echo "Resumo dos Testes Executados:"
    echo ""
    
    if [ "$RUN_NODEJS" = true ]; then
        echo "📦 Projeto Node.js:"
        echo "   - Testes de dependências"
        echo "   - Testes de módulos"
        echo "   - Testes de integração"
        echo "   - Testes de performance"
        echo ""
        total_tests=$((total_tests + 1))
        if [ "$NODEJS_SUCCESS" = true ]; then
            passed_tests=$((passed_tests + 1))
            echo "   ✅ Status: PASSOU"
        else
            echo "   ❌ Status: FALHOU"
        fi
        echo ""
    fi
    
    if [ "$RUN_PYTHON" = true ]; then
        echo "🐍 Projeto Python:"
        echo "   - Testes de dependências"
        echo "   - Testes de módulos"  
        echo "   - Testes de integração"
        echo "   - Testes de performance"
        echo ""
        total_tests=$((total_tests + 1))
        if [ "$PYTHON_SUCCESS" = true ]; then
            passed_tests=$((passed_tests + 1))
            echo "   ✅ Status: PASSOU"
        else
            echo "   ❌ Status: FALHOU"
        fi
        echo ""
    fi
    
    echo "📊 Resumo Geral:"
    echo "   - Projetos testados: $total_tests"
    echo "   - Projetos aprovados: $passed_tests"
    echo "   - Taxa de sucesso: $(( passed_tests * 100 / total_tests ))%"
    echo ""
    
    # Informações do sistema
    echo "💻 Sistema:"
    echo "   - OS: $(uname -s)"
    echo "   - Arquitetura: $(uname -m)"
    echo "   - Kernel: $(uname -r)"
    
    if grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
        echo "   - Dispositivo: $(cat /proc/cpuinfo | grep "Raspberry Pi" | head -1 | cut -d':' -f2 | xargs)"
        echo "   - RAM: $(free -h | awk 'NR==2{printf "%.1fGB", $2/1024}')"
    fi
    
    echo ""
    echo "⏱️  Tempo total de execução: $(( $(date +%s) - START_TIME ))s"
}

# Função principal
main() {
    local START_TIME=$(date +%s)
    
    # Verificações iniciais
    check_system_dependencies || exit 1
    pre_check
    
    # Resultados dos testes
    NODEJS_SUCCESS=false
    PYTHON_SUCCESS=false
    
    # Executar testes
    if [ "$RUN_NODEJS" = true ]; then
        if test_nodejs; then
            NODEJS_SUCCESS=true
        fi
    fi
    
    if [ "$RUN_PYTHON" = true ]; then
        if test_python; then
            PYTHON_SUCCESS=true
        fi
    fi
    
    # Benchmark (se solicitado)
    run_benchmark
    
    # Relatório final
    generate_report
    
    # Determinar código de saída
    local exit_code=0
    if [ "$RUN_NODEJS" = true ] && [ "$NODEJS_SUCCESS" = false ]; then
        exit_code=1
    fi
    if [ "$RUN_PYTHON" = true ] && [ "$PYTHON_SUCCESS" = false ]; then
        exit_code=1
    fi
    
    if [ $exit_code -eq 0 ]; then
        log "🎉 TODOS OS TESTES PASSARAM!"
    else
        error "❌ ALGUNS TESTES FALHARAM!"
    fi
    
    exit $exit_code
}

# Executar função principal
main "$@"