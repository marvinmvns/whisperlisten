const axios = require('axios');
const dns = require('dns');
const { promisify } = require('util');

class TranscriptSender {
    constructor(queue) {
        this.queue = queue;
        this.apiUrl = process.env.API_URL;
        this.apiToken = process.env.API_TOKEN;
        this.isOnline = false;
        this.sendingActive = false;
        this.checkInterval = null;
        this.sendInterval = null;
        
        // Configurações
        this.connectivityCheckInterval = 5000; // 5s
        this.sendCheckInterval = 2000; // 2s
        this.requestTimeout = 10000; // 10s
        this.maxRetries = 5;
        
        this.setupAxios();
        this.startConnectivityCheck();
    }

    setupAxios() {
        this.httpClient = axios.create({
            timeout: this.requestTimeout,
            headers: {
                'Content-Type': 'application/json',
                'User-Agent': 'Whisper-Transcriber/1.0',
                ...(this.apiToken && { 'Authorization': `Bearer ${this.apiToken}` })
            }
        });
    }

    async checkInternetConnectivity() {
        try {
            // Teste básico de DNS
            const lookup = promisify(dns.lookup);
            await lookup('google.com');
            
            // Teste HTTP se API_URL estiver configurada
            if (this.apiUrl) {
                const testUrl = new URL('/health', this.apiUrl).toString();
                await this.httpClient.get(testUrl, { timeout: 3000 });
            }
            
            return true;
        } catch (err) {
            return false;
        }
    }

    startConnectivityCheck() {
        this.checkInterval = setInterval(async () => {
            const wasOnline = this.isOnline;
            this.isOnline = await this.checkInternetConnectivity();
            
            if (this.isOnline !== wasOnline) {
                console.log(`Status de conectividade: ${this.isOnline ? 'ONLINE' : 'OFFLINE'}`);
                
                if (this.isOnline && !this.sendingActive) {
                    this.startSending();
                } else if (!this.isOnline) {
                    this.stopSending();
                }
            }
        }, this.connectivityCheckInterval);

        // Verificar imediatamente
        this.checkInternetConnectivity().then(online => {
            this.isOnline = online;
            console.log(`Status inicial: ${online ? 'ONLINE' : 'OFFLINE'}`);
            if (online) {
                this.startSending();
            }
        });
    }

    startSending() {
        if (this.sendingActive || !this.isOnline) return;
        
        this.sendingActive = true;
        console.log('Iniciando envio de transcrições...');
        
        this.sendInterval = setInterval(() => {
            this.processPendingItems();
        }, this.sendCheckInterval);

        // Processar imediatamente
        this.processPendingItems();
    }

    stopSending() {
        if (!this.sendingActive) return;
        
        this.sendingActive = false;
        if (this.sendInterval) {
            clearInterval(this.sendInterval);
            this.sendInterval = null;
        }
        console.log('Parou o envio de transcrições (offline)');
    }

    async processPendingItems() {
        if (!this.isOnline || !this.sendingActive) return;
        
        // Processar itens pendentes em ordem
        const nextItem = this.queue.getNextPending();
        if (nextItem) {
            await this.sendTranscript(nextItem);
        }
        
        // Processar itens que falharam e estão prontos para retry
        const retryItems = this.queue.getRetryableItems();
        for (const item of retryItems.slice(0, 3)) { // Max 3 retries simultâneos
            await this.sendTranscript(item);
        }
    }

    async sendTranscript(item) {
        if (!this.apiUrl) {
            console.error('API_URL não configurada');
            return;
        }

        try {
            console.log(`Enviando transcrição: ${item.id}`);
            this.queue.markAsSending(item.id);
            
            const payload = {
                id: item.id,
                timestamp: item.transcriptTimestamp,
                text: item.text,
                queuedAt: item.timestamp,
                attempt: item.attempts
            };

            const response = await this.httpClient.post(this.apiUrl, payload);
            
            // Sucesso
            this.queue.markAsSent(item.id, {
                status: response.status,
                data: response.data
            });
            
            console.log(`✓ Enviado: ${item.id} (${response.status})`);
            
        } catch (err) {
            console.error(`✗ Falha no envio: ${item.id}`, err.message);
            
            // Verificar se é erro de conectividade
            if (err.code === 'ENOTFOUND' || err.code === 'ECONNREFUSED' || err.code === 'ETIMEDOUT') {
                this.isOnline = false;
                this.stopSending();
            }
            
            // Marcar como falha apenas se não excedeu máximo de tentativas
            if (item.attempts < this.maxRetries) {
                this.queue.markAsFailed(item.id, {
                    message: err.message,
                    code: err.code,
                    status: err.response?.status
                });
            } else {
                console.error(`Item ${item.id} excedeu máximo de tentativas (${this.maxRetries})`);
                // Opcionalmente mover para uma lista de "falhas permanentes"
            }
        }
    }

    // Forçar envio de um item específico
    async forceSend(itemId) {
        const item = this.queue.queue.find(q => q.id === itemId);
        if (item && this.isOnline) {
            await this.sendTranscript(item);
        } else {
            console.log(`Item ${itemId} não encontrado ou sistema offline`);
        }
    }

    // Resetar e tentar novamente um item
    retryItem(itemId) {
        this.queue.resetAttempts(itemId);
        if (this.isOnline) {
            setTimeout(() => this.processPendingItems(), 1000);
        }
    }

    getStatus() {
        const queueStats = this.queue.getStats();
        return {
            online: this.isOnline,
            sending: this.sendingActive,
            queue: queueStats,
            apiUrl: this.apiUrl,
            hasToken: !!this.apiToken
        };
    }

    // Teste de conectividade manual
    async testConnection() {
        if (!this.apiUrl) {
            return { success: false, error: 'API_URL não configurada' };
        }

        try {
            const response = await this.httpClient.get(this.apiUrl);
            return { 
                success: true, 
                status: response.status,
                data: response.data 
            };
        } catch (err) {
            return { 
                success: false, 
                error: err.message,
                status: err.response?.status 
            };
        }
    }

    stop() {
        if (this.checkInterval) {
            clearInterval(this.checkInterval);
        }
        if (this.sendInterval) {
            clearInterval(this.sendInterval);
        }
        this.sendingActive = false;
        console.log('TranscriptSender parado');
    }
}

module.exports = TranscriptSender;