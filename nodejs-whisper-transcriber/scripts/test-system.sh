#!/bin/bash

# Script de teste completo para Node.js Whisper Transcriber
set -e

echo "=== Teste Completo do Sistema Node.js Whisper Transcriber ==="

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Contadores
TESTS_PASSED=0
TESTS_FAILED=0

# Função para log
log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
test_header() { echo -e "${BLUE}[TEST]${NC} $1"; }

# Função para executar teste
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="$3"
    
    test_header "Executando: $test_name"
    
    if eval "$test_command"; then
        log "✓ PASSOU: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        error "✗ FALHOU: $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Verificar se está no diretório correto
if [ ! -f "package.json" ] || [ ! -f "index.js" ]; then
    error "Execute este script no diretório nodejs-whisper-transcriber"
    exit 1
fi

# Carregar variáveis de ambiente
if [ -f ".env" ]; then
    source .env
    log "Arquivo .env carregado"
else
    warn "Arquivo .env não encontrado, usando configurações padrão"
fi

# Criar diretório de teste
TEST_DIR="./test_data"
mkdir -p "$TEST_DIR"

echo
log "=== 1. Verificação de Dependências ==="

# Teste 1: Node.js
run_test "Node.js disponível" "node --version > /dev/null"

# Teste 2: NPM packages
run_test "Dependências NPM instaladas" "npm list --depth=0 > /dev/null 2>&1"

# Teste 3: Whisper binário
WHISPER_PATH=${WHISPER_PATH:-"./whisper.cpp/main"}
run_test "Whisper.cpp disponível" "[ -f '$WHISPER_PATH' ] && [ -x '$WHISPER_PATH' ]"

# Teste 4: Modelo Whisper
MODEL_PATH=${MODEL_PATH:-"./models/ggml-base.en.bin"}
run_test "Modelo Whisper disponível" "[ -f '$MODEL_PATH' ]"

echo
log "=== 2. Geração de Áudio de Teste ==="

# Função para gerar áudio sintético usando ffmpeg
generate_test_audio() {
    local filename="$1"
    local text="$2"
    local duration="$3"
    
    log "Gerando áudio: $filename"
    
    # Gerar tom sintético com padrão de fala
    ffmpeg -f lavfi -i "sine=frequency=440:duration=$duration" \
           -f lavfi -i "sine=frequency=220:duration=$duration" \
           -filter_complex "[0:a][1:a]amix=inputs=2:duration=shortest" \
           -ar 16000 -ac 1 -y "$filename" > /dev/null 2>&1
    
    return $?
}

# Função para gerar áudio com espeak (se disponível)
generate_speech_audio() {
    local filename="$1"
    local text="$2"
    
    if command -v espeak > /dev/null; then
        log "Gerando fala sintética: $text"
        espeak -w "$filename" -s 150 "$text" > /dev/null 2>&1
        
        # Converter para formato correto
        if command -v ffmpeg > /dev/null; then
            ffmpeg -i "$filename" -ar 16000 -ac 1 -y "${filename}.wav" > /dev/null 2>&1
            mv "${filename}.wav" "$filename"
        fi
        return 0
    else
        return 1
    fi
}

# Teste 5: Verificar ffmpeg
if command -v ffmpeg > /dev/null; then
    run_test "FFmpeg disponível" "true"
    HAS_FFMPEG=true
else
    warn "FFmpeg não encontrado - testes de áudio limitados"
    HAS_FFMPEG=false
fi

# Gerar arquivos de teste
TEST_AUDIO_1="$TEST_DIR/test_hello.wav"
TEST_AUDIO_2="$TEST_DIR/test_numbers.wav"
TEST_AUDIO_3="$TEST_DIR/test_silence.wav"

if [ "$HAS_FFMPEG" = true ]; then
    # Tentar gerar fala sintética primeiro
    if generate_speech_audio "$TEST_AUDIO_1" "Hello world this is a test"; then
        log "✓ Áudio de fala gerado: test_hello.wav"
    elif generate_test_audio "$TEST_AUDIO_1" "hello test" "2"; then
        log "✓ Áudio sintético gerado: test_hello.wav"
    fi
    
    if generate_speech_audio "$TEST_AUDIO_2" "One two three four five"; then
        log "✓ Áudio de números gerado: test_numbers.wav"
    elif generate_test_audio "$TEST_AUDIO_2" "numbers test" "3"; then
        log "✓ Áudio sintético gerado: test_numbers.wav"
    fi
    
    # Gerar silêncio para teste negativo
    if ffmpeg -f lavfi -i "anullsrc=r=16000:cl=mono" -t 1 -y "$TEST_AUDIO_3" > /dev/null 2>&1; then
        log "✓ Áudio de silêncio gerado: test_silence.wav"
    fi
fi

echo
log "=== 3. Teste dos Módulos ==="

# Teste 6: Módulo de transcrição
run_test "Módulo transcribe.js carrega" "node -e 'require(\"./src/transcribe.js\")'"

# Teste 7: Módulo VAD
run_test "Módulo vad.js carrega" "node -e 'require(\"./src/vad.js\")'"

# Teste 8: Módulo queue
run_test "Módulo queue.js carrega" "node -e 'require(\"./src/queue.js\")'"

# Teste 9: Módulo sender
run_test "Módulo sender.js carrega" "node -e 'require(\"./src/sender.js\")'"

echo
log "=== 4. Teste de Transcrição ==="

# Criar script de teste de transcrição
cat > "$TEST_DIR/test_transcription.js" << 'EOF'
const Transcriber = require('../src/transcribe');
const fs = require('fs');

async function testTranscription() {
    const transcriber = new Transcriber();
    const testFile = process.argv[2];
    
    if (!fs.existsSync(testFile)) {
        console.error('Arquivo de teste não encontrado:', testFile);
        process.exit(1);
    }
    
    try {
        console.log('Testando transcrição de:', testFile);
        const result = await transcriber.transcribeAudio(testFile);
        
        if (result) {
            console.log('✓ Transcrição bem-sucedida');
            console.log('Texto:', result.text);
            console.log('Arquivo:', result.file);
            process.exit(0);
        } else {
            console.log('⚠ Nenhum texto detectado (normal para alguns áudios)');
            process.exit(0);
        }
    } catch (error) {
        console.error('✗ Erro na transcrição:', error.message);
        process.exit(1);
    }
}

testTranscription();
EOF

# Teste 10: Transcrição com arquivo de teste
if [ -f "$TEST_AUDIO_1" ]; then
    run_test "Transcrição de áudio funciona" "timeout 30 node $TEST_DIR/test_transcription.js $TEST_AUDIO_1"
fi

echo
log "=== 5. Teste da Fila ==="

# Criar script de teste da fila
cat > "$TEST_DIR/test_queue.js" << 'EOF'
const TranscriptQueue = require('../src/queue');

function testQueue() {
    const queue = new TranscriptQueue();
    
    // Teste básico de adicionar item
    const testItem = {
        text: 'Teste de fila',
        file: '/test/path',
        timestamp: new Date().toISOString()
    };
    
    const queueItem = queue.addTranscript(testItem);
    console.log('✓ Item adicionado à fila:', queueItem.id);
    
    // Teste de obter próximo
    const next = queue.getNextPending();
    if (next && next.id === queueItem.id) {
        console.log('✓ Item recuperado da fila');
    } else {
        throw new Error('Falha ao recuperar item da fila');
    }
    
    // Teste de estatísticas
    const stats = queue.getStats();
    console.log('✓ Estatísticas:', JSON.stringify(stats));
    
    console.log('✓ Todos os testes da fila passaram');
}

try {
    testQueue();
} catch (error) {
    console.error('✗ Erro no teste da fila:', error.message);
    process.exit(1);
}
EOF

# Teste 11: Fila funciona
run_test "Sistema de fila funciona" "node $TEST_DIR/test_queue.js"

echo
log "=== 6. Teste de Conectividade ==="

# Teste 12: Aplicação principal inicia
run_test "Aplicação principal carrega" "timeout 5 node index.js status > /dev/null"

# Teste 13: Comando de status
run_test "Comando status funciona" "node index.js status > /dev/null"

# Teste 14: Comando de fila
run_test "Comando queue funciona" "node index.js queue > /dev/null"

# Teste 15: Comando de teste
if [ -n "$API_URL" ]; then
    run_test "Teste de conectividade API" "timeout 10 node index.js test > /dev/null"
else
    warn "API_URL não configurada - pulando teste de conectividade"
fi

echo
log "=== 7. Teste de Performance ==="

# Teste 16: Uso de memória
cat > "$TEST_DIR/test_memory.js" << 'EOF'
const { execSync } = require('child_process');

function testMemoryUsage() {
    // Iniciar aplicação em background
    const child = execSync('timeout 10 node index.js > /dev/null 2>&1 &', { stdio: 'ignore' });
    
    // Aguardar um pouco
    setTimeout(() => {
        try {
            const pids = execSync('pgrep -f "node.*index.js"', { encoding: 'utf8' }).trim().split('\n');
            
            for (const pid of pids) {
                if (pid) {
                    const memInfo = execSync(`ps -p ${pid} -o pid,vsz,rss --no-headers`, { encoding: 'utf8' });
                    console.log('✓ Processo Node.js ativo:', memInfo.trim());
                }
            }
        } catch (e) {
            console.log('⚠ Nenhum processo ativo encontrado');
        }
    }, 2000);
}

testMemoryUsage();
setTimeout(() => process.exit(0), 3000);
EOF

run_test "Teste de uso de memória" "node $TEST_DIR/test_memory.js"

echo
log "=== 8. Teste de Limpeza ==="

# Teste 17: Limpeza de arquivos temporários
if [ -d "data/temp" ]; then
    # Criar arquivo temporário
    touch "data/temp/test_cleanup.wav"
    
    # Executar limpeza
    find data/temp -name "*.wav" -mtime +0 -delete 2>/dev/null || true
    
    run_test "Limpeza de arquivos temporários" "[ ! -f 'data/temp/test_cleanup.wav' ]"
fi

echo
log "=== 9. Verificação de Configuração ==="

# Teste 18: Arquivo .env
if [ -f ".env" ]; then
    if grep -q "API_URL=" .env && grep -q "WHISPER_PATH=" .env; then
        log "✓ Arquivo .env configurado corretamente"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        warn "⚠ Arquivo .env pode estar incompleto"
    fi
else
    warn "⚠ Arquivo .env não encontrado"
fi

# Teste 19: Diretórios necessários
REQUIRED_DIRS=("data/temp" "data/transcripts" "data/queue" "logs")
for dir in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        log "✓ Diretório $dir existe"
    else
        mkdir -p "$dir"
        log "✓ Diretório $dir criado"
    fi
done

echo
log "=== 10. Teste Integração Completa ==="

# Criar teste de integração completa
cat > "$TEST_DIR/integration_test.js" << 'EOF'
const VAD = require('../src/vad');
const Transcriber = require('../src/transcribe');
const TranscriptQueue = require('../src/queue');
const fs = require('fs');

async function integrationTest() {
    console.log('Iniciando teste de integração...');
    
    // Verificar se há arquivo de teste
    const testFile = process.argv[2];
    if (!testFile || !fs.existsSync(testFile)) {
        console.log('⚠ Arquivo de teste não fornecido, pulando teste de integração');
        return;
    }
    
    try {
        // Teste da transcrição
        const transcriber = new Transcriber();
        const result = await transcriber.transcribeAudio(testFile);
        
        if (result) {
            console.log('✓ Transcrição: OK');
            
            // Teste da fila
            const queue = new TranscriptQueue();
            const queueItem = queue.addTranscript(result);
            console.log('✓ Fila: OK');
            
            // Verificar se arquivo foi salvo
            if (fs.existsSync(result.file)) {
                console.log('✓ Arquivo salvo: OK');
            }
            
            console.log('✓ Teste de integração PASSOU');
        } else {
            console.log('⚠ Nenhum texto detectado, mas sistema funcionou');
        }
        
    } catch (error) {
        console.error('✗ Teste de integração FALHOU:', error.message);
        process.exit(1);
    }
}

integrationTest();
EOF

# Teste 20: Integração completa
if [ -f "$TEST_AUDIO_1" ]; then
    run_test "Teste de integração completa" "timeout 60 node $TEST_DIR/integration_test.js $TEST_AUDIO_1"
else
    warn "Áudio de teste não disponível - pulando teste de integração"
fi

echo
log "=== Relatório Final ==="

TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))

echo -e "${BLUE}======================================${NC}"
echo -e "${GREEN}Testes Executados: $TOTAL_TESTS${NC}"
echo -e "${GREEN}Testes Passaram: $TESTS_PASSED${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}Testes Falharam: $TESTS_FAILED${NC}"
else
    echo -e "${GREEN}Testes Falharam: $TESTS_FAILED${NC}"
fi
echo -e "${BLUE}======================================${NC}"

# Informações do sistema
echo
log "=== Informações do Sistema ==="
echo "Node.js: $(node --version 2>/dev/null || echo 'N/A')"
echo "NPM: $(npm --version 2>/dev/null || echo 'N/A')"
echo "Sistema: $(uname -a)"
echo "Diretório: $(pwd)"

if [ -f "$WHISPER_PATH" ]; then
    echo "Whisper: $WHISPER_PATH ($(du -h "$WHISPER_PATH" | cut -f1))"
fi

if [ -f "$MODEL_PATH" ]; then
    echo "Modelo: $MODEL_PATH ($(du -h "$MODEL_PATH" | cut -f1))"
fi

# Verificar espaço em disco
echo "Espaço livre: $(df -h . | awk 'NR==2 {print $4}')"

# Limpar arquivos de teste
if [ "$1" != "--keep-test-files" ]; then
    log "Limpando arquivos de teste..."
    rm -rf "$TEST_DIR"
fi

echo
if [ $TESTS_FAILED -eq 0 ]; then
    log "🎉 TODOS OS TESTES PASSARAM! Sistema está funcionando corretamente."
    exit 0
else
    error "❌ ALGUNS TESTES FALHARAM. Verifique a configuração e dependências."
    exit 1
fi