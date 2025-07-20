const fs = require('fs');
const path = require('path');

class TranscriptQueue {
    constructor() {
        this.queueDir = path.join(__dirname, '../data/queue');
        this.queueFile = path.join(this.queueDir, 'pending.json');
        this.sentFile = path.join(this.queueDir, 'sent.json');
        this.queue = [];
        this.sentItems = [];
        
        this.ensureQueueDir();
        this.loadQueue();
    }

    ensureQueueDir() {
        if (!fs.existsSync(this.queueDir)) {
            fs.mkdirSync(this.queueDir, { recursive: true });
        }
    }

    loadQueue() {
        try {
            if (fs.existsSync(this.queueFile)) {
                const data = fs.readFileSync(this.queueFile, 'utf8');
                this.queue = JSON.parse(data) || [];
            }
            
            if (fs.existsSync(this.sentFile)) {
                const data = fs.readFileSync(this.sentFile, 'utf8');
                this.sentItems = JSON.parse(data) || [];
            }
        } catch (err) {
            console.error('Erro ao carregar fila:', err);
            this.queue = [];
            this.sentItems = [];
        }
    }

    saveQueue() {
        try {
            fs.writeFileSync(this.queueFile, JSON.stringify(this.queue, null, 2));
            fs.writeFileSync(this.sentFile, JSON.stringify(this.sentItems, null, 2));
        } catch (err) {
            console.error('Erro ao salvar fila:', err);
        }
    }

    addTranscript(transcriptData) {
        const queueItem = {
            id: this.generateId(),
            timestamp: new Date().toISOString(),
            text: transcriptData.text,
            file: transcriptData.file,
            transcriptTimestamp: transcriptData.timestamp,
            attempts: 0,
            lastAttempt: null,
            status: 'pending'
        };
        
        this.queue.push(queueItem);
        this.saveQueue();
        
        console.log(`Adicionado à fila: ${queueItem.id}`);
        return queueItem;
    }

    generateId() {
        return Date.now().toString(36) + Math.random().toString(36).substr(2);
    }

    getNextPending() {
        // Retornar em ordem (FIFO)
        return this.queue.find(item => item.status === 'pending');
    }

    getAllPending() {
        return this.queue.filter(item => item.status === 'pending');
    }

    markAsSending(itemId) {
        const item = this.queue.find(q => q.id === itemId);
        if (item) {
            item.status = 'sending';
            item.attempts++;
            item.lastAttempt = new Date().toISOString();
            this.saveQueue();
        }
    }

    markAsSent(itemId, response = null) {
        const itemIndex = this.queue.findIndex(q => q.id === itemId);
        if (itemIndex !== -1) {
            const item = this.queue[itemIndex];
            item.status = 'sent';
            item.sentAt = new Date().toISOString();
            item.response = response;
            
            // Mover para lista de enviados
            this.sentItems.push(item);
            this.queue.splice(itemIndex, 1);
            
            this.saveQueue();
            console.log(`Item enviado com sucesso: ${itemId}`);
        }
    }

    markAsFailed(itemId, error = null) {
        const item = this.queue.find(q => q.id === itemId);
        if (item) {
            item.status = 'pending'; // Voltar para pending para retry
            item.lastError = error;
            item.lastErrorTime = new Date().toISOString();
            
            // Implementar backoff exponencial
            const delay = Math.min(1000 * Math.pow(2, item.attempts - 1), 60000); // Max 1 minuto
            item.nextRetry = new Date(Date.now() + delay).toISOString();
            
            this.saveQueue();
            console.log(`Falha no envio: ${itemId}, tentativa ${item.attempts}, próximo retry em ${delay}ms`);
        }
    }

    getRetryableItems() {
        const now = new Date().toISOString();
        return this.queue.filter(item => 
            item.status === 'pending' && 
            item.attempts > 0 && 
            (!item.nextRetry || item.nextRetry <= now)
        );
    }

    getStats() {
        const pending = this.queue.filter(q => q.status === 'pending').length;
        const sending = this.queue.filter(q => q.status === 'sending').length;
        const sent = this.sentItems.length;
        const failed = this.queue.filter(q => q.attempts > 0 && q.status === 'pending').length;
        
        return {
            pending,
            sending,
            sent,
            failed,
            total: pending + sending + sent
        };
    }

    // Limpar itens antigos (opcional)
    cleanup(daysOld = 30) {
        const cutoff = new Date();
        cutoff.setDate(cutoff.getDate() - daysOld);
        const cutoffISO = cutoff.toISOString();
        
        // Limpar itens enviados antigos
        const originalSentCount = this.sentItems.length;
        this.sentItems = this.sentItems.filter(item => item.sentAt > cutoffISO);
        
        const removed = originalSentCount - this.sentItems.length;
        if (removed > 0) {
            console.log(`Limpeza: removidos ${removed} itens enviados antigos`);
            this.saveQueue();
        }
        
        return removed;
    }

    // Resetar tentativas de um item específico
    resetAttempts(itemId) {
        const item = this.queue.find(q => q.id === itemId);
        if (item) {
            item.attempts = 0;
            item.status = 'pending';
            item.lastError = null;
            item.nextRetry = null;
            this.saveQueue();
            console.log(`Tentativas resetadas para: ${itemId}`);
        }
    }

    // Listar todos os itens (para debug)
    listAll() {
        return {
            queue: this.queue,
            sent: this.sentItems
        };
    }
}

module.exports = TranscriptQueue;