#!/usr/bin/env node

require('dotenv').config();
const VAD = require('./src/vad');
const Transcriber = require('./src/transcribe');
const TranscriptQueue = require('./src/queue');
const TranscriptSender = require('./src/sender');
const fs = require('fs');
const path = require('path');

class WhisperTranscriber {
    constructor() {
        this.vad = new VAD();
        this.transcriber = new Transcriber();
        this.queue = new TranscriptQueue();
        this.sender = new TranscriptSender(this.queue);
        
        this.setupEventHandlers();
        this.setupSignalHandlers();
        
        console.log('Whisper Transcriber iniciado');
        this.logStatus();
    }

    setupEventHandlers() {
        // Quando VAD detecta áudio pronto
        this.vad.onAudioReady = async (audioFile) => {
            try {
                const result = await this.transcriber.transcribeAudio(audioFile);
                if (result) {
                    this.queue.addTranscript(result);
                    console.log(`Transcrição: "${result.text}"`);
                }
            } catch (err) {
                console.error('Erro na transcrição:', err);
            }
        };
    }

    setupSignalHandlers() {
        // Graceful shutdown
        process.on('SIGINT', () => {
            console.log('\nParando Whisper Transcriber...');
            this.stop();
            process.exit(0);
        });

        process.on('SIGTERM', () => {
            console.log('Recebido SIGTERM, parando...');
            this.stop();
            process.exit(0);
        });

        // Log de status a cada 30 segundos
        this.statusInterval = setInterval(() => {
            this.logStatus();
        }, 30000);
    }

    logStatus() {
        const status = this.sender.getStatus();
        const stats = status.queue;
        
        console.log(`Status: ${status.online ? 'ONLINE' : 'OFFLINE'} | ` +
                   `Fila: ${stats.pending} pendentes, ${stats.sent} enviados, ${stats.failed} falharam`);
    }

    start() {
        console.log('Iniciando captura de áudio...');
        this.vad.startListening();
    }

    stop() {
        console.log('Parando serviços...');
        
        if (this.vad) {
            this.vad.stop();
        }
        
        if (this.sender) {
            this.sender.stop();
        }
        
        if (this.statusInterval) {
            clearInterval(this.statusInterval);
        }
        
        console.log('Todos os serviços parados');
    }

    // CLI commands
    async handleCommand(command, args = []) {
        switch (command) {
            case 'status':
                return this.getDetailedStatus();
                
            case 'queue':
                return this.getQueueInfo();
                
            case 'test':
                return await this.testConnection();
                
            case 'retry':
                const itemId = args[0];
                if (itemId) {
                    this.sender.retryItem(itemId);
                    return `Tentando reenviar: ${itemId}`;
                }
                return 'Uso: retry <item-id>';
                
            case 'cleanup':
                const days = parseInt(args[0]) || 30;
                const removed = this.queue.cleanup(days);
                return `Removidos ${removed} itens antigos (>${days} dias)`;
                
            case 'transcripts':
                return this.listTranscripts();
                
            default:
                return this.getHelp();
        }
    }

    getDetailedStatus() {
        const status = this.sender.getStatus();
        const memUsage = process.memoryUsage();
        
        return {
            system: {
                online: status.online,
                sending: status.sending,
                uptime: process.uptime(),
                memory: {
                    rss: Math.round(memUsage.rss / 1024 / 1024) + 'MB',
                    heapUsed: Math.round(memUsage.heapUsed / 1024 / 1024) + 'MB'
                }
            },
            queue: status.queue,
            config: {
                apiUrl: status.apiUrl,
                hasToken: status.hasToken,
                whisperPath: process.env.WHISPER_PATH,
                modelPath: process.env.MODEL_PATH,
                language: process.env.LANG
            }
        };
    }

    getQueueInfo() {
        return this.queue.listAll();
    }

    async testConnection() {
        return await this.sender.testConnection();
    }

    listTranscripts() {
        const files = this.transcriber.getTranscriptFiles();
        return files.map(file => {
            const content = this.transcriber.readTranscript(file);
            const lines = content.split('\n');
            return {
                file,
                timestamp: lines[0],
                text: lines.slice(1).join('\n').trim()
            };
        });
    }

    getHelp() {
        return `
Whisper Transcriber - Comandos disponíveis:

  status      - Status detalhado do sistema
  queue       - Informações da fila de envio
  test        - Testar conexão com API
  retry <id>  - Tentar reenviar item específico
  cleanup     - Limpar itens antigos (padrão: 30 dias)
  transcripts - Listar todas as transcrições
  help        - Esta ajuda

Variáveis de ambiente:
  API_URL     - URL da API para envio
  API_TOKEN   - Token de autenticação
  WHISPER_PATH - Caminho para whisper.cpp
  MODEL_PATH  - Caminho para modelo whisper
  LANG        - Idioma (padrão: en)
        `;
    }
}

// Executar se chamado diretamente
if (require.main === module) {
    const command = process.argv[2];
    const args = process.argv.slice(3);
    
    if (command && command !== 'start') {
        // Modo comando único
        const app = new WhisperTranscriber();
        app.handleCommand(command, args).then(result => {
            if (typeof result === 'object') {
                console.log(JSON.stringify(result, null, 2));
            } else {
                console.log(result);
            }
            app.stop();
            process.exit(0);
        }).catch(err => {
            console.error('Erro:', err);
            app.stop();
            process.exit(1);
        });
    } else {
        // Modo daemon
        const app = new WhisperTranscriber();
        app.start();
    }
}

module.exports = WhisperTranscriber;