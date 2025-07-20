const mic = require('mic');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

class VAD {
    constructor() {
        this.isRecording = false;
        this.micInstance = null;
        this.micInputStream = null;
        this.currentAudioFile = null;
        this.silenceTimeout = null;
        this.audioCounter = 0;
        this.tempDir = path.join(__dirname, '../data/temp');
        
        // Configurações VAD
        this.silenceThreshold = 1000; // ms de silêncio para parar
        this.minRecordingTime = 500; // ms mínimo de gravação
        this.recordingStartTime = null;
        
        this.ensureTempDir();
    }

    ensureTempDir() {
        if (!fs.existsSync(this.tempDir)) {
            fs.mkdirSync(this.tempDir, { recursive: true });
        }
    }

    startListening() {
        console.log('Iniciando escuta por voz...');
        
        // Configuração do microfone
        this.micInstance = mic({
            rate: '16000',
            channels: '1',
            debug: false,
            exitOnSilence: 0
        });

        this.micInputStream = this.micInstance.getAudioStream();
        
        // Detectar início de fala
        this.micInputStream.on('data', (data) => {
            this.handleAudioData(data);
        });

        this.micInputStream.on('error', (err) => {
            console.error('Erro no microfone:', err);
        });

        this.micInstance.start();
        console.log('Microfone ativo. Aguardando voz...');
    }

    handleAudioData(data) {
        const audioLevel = this.calculateAudioLevel(data);
        
        // Detectar início de fala (threshold simples)
        if (audioLevel > 5000 && !this.isRecording) {
            this.startRecording();
        }
        
        // Durante a gravação, resetar timeout de silêncio
        if (this.isRecording) {
            if (audioLevel > 3000) {
                this.resetSilenceTimeout();
            }
            this.writeAudioData(data);
        }
    }

    calculateAudioLevel(buffer) {
        let sum = 0;
        for (let i = 0; i < buffer.length; i += 2) {
            const sample = buffer.readInt16LE(i);
            sum += Math.abs(sample);
        }
        return sum / (buffer.length / 2);
    }

    startRecording() {
        if (this.isRecording) return;
        
        this.isRecording = true;
        this.recordingStartTime = Date.now();
        this.audioCounter++;
        
        const filename = `audio_${String(this.audioCounter).padStart(4, '0')}.wav`;
        this.currentAudioFile = path.join(this.tempDir, filename);
        
        console.log(`Iniciando gravação: ${filename}`);
        
        // Criar arquivo WAV com cabeçalho
        this.createWavFile(this.currentAudioFile);
        
        this.resetSilenceTimeout();
    }

    writeAudioData(data) {
        if (!this.isRecording || !this.currentAudioFile) return;
        
        fs.appendFileSync(this.currentAudioFile, data);
    }

    resetSilenceTimeout() {
        if (this.silenceTimeout) {
            clearTimeout(this.silenceTimeout);
        }
        
        this.silenceTimeout = setTimeout(() => {
            this.stopRecording();
        }, this.silenceThreshold);
    }

    stopRecording() {
        if (!this.isRecording) return;
        
        const recordingDuration = Date.now() - this.recordingStartTime;
        
        // Verificar duração mínima
        if (recordingDuration < this.minRecordingTime) {
            console.log('Gravação muito curta, descartando...');
            this.discardCurrentRecording();
            return;
        }
        
        this.isRecording = false;
        console.log(`Parando gravação: ${path.basename(this.currentAudioFile)}`);
        
        // Finalizar arquivo WAV
        this.finalizeWavFile(this.currentAudioFile);
        
        // Notificar que há um arquivo pronto para transcrição
        if (this.onAudioReady) {
            this.onAudioReady(this.currentAudioFile);
        }
        
        this.currentAudioFile = null;
        
        if (this.silenceTimeout) {
            clearTimeout(this.silenceTimeout);
            this.silenceTimeout = null;
        }
    }

    discardCurrentRecording() {
        if (this.currentAudioFile && fs.existsSync(this.currentAudioFile)) {
            fs.unlinkSync(this.currentAudioFile);
        }
        this.isRecording = false;
        this.currentAudioFile = null;
    }

    createWavFile(filename) {
        const sampleRate = 16000;
        const channels = 1;
        const bitsPerSample = 16;
        
        const header = Buffer.alloc(44);
        
        // RIFF header
        header.write('RIFF', 0);
        header.writeUInt32LE(36, 4); // File size - 8 (will be updated later)
        header.write('WAVE', 8);
        
        // fmt chunk
        header.write('fmt ', 12);
        header.writeUInt32LE(16, 16); // Subchunk1Size
        header.writeUInt16LE(1, 20); // AudioFormat (PCM)
        header.writeUInt16LE(channels, 22);
        header.writeUInt32LE(sampleRate, 24);
        header.writeUInt32LE(sampleRate * channels * bitsPerSample / 8, 28); // ByteRate
        header.writeUInt16LE(channels * bitsPerSample / 8, 32); // BlockAlign
        header.writeUInt16LE(bitsPerSample, 34);
        
        // data chunk
        header.write('data', 36);
        header.writeUInt32LE(0, 40); // Subchunk2Size (will be updated later)
        
        fs.writeFileSync(filename, header);
    }

    finalizeWavFile(filename) {
        const stats = fs.statSync(filename);
        const fileSize = stats.size;
        const dataSize = fileSize - 44;
        
        const fd = fs.openSync(filename, 'r+');
        
        // Update file size
        const fileSizeBuffer = Buffer.alloc(4);
        fileSizeBuffer.writeUInt32LE(fileSize - 8, 0);
        fs.writeSync(fd, fileSizeBuffer, 0, 4, 4);
        
        // Update data size
        const dataSizeBuffer = Buffer.alloc(4);
        dataSizeBuffer.writeUInt32LE(dataSize, 0);
        fs.writeSync(fd, dataSizeBuffer, 0, 4, 40);
        
        fs.closeSync(fd);
    }

    stop() {
        if (this.micInstance) {
            this.micInstance.stop();
        }
        if (this.silenceTimeout) {
            clearTimeout(this.silenceTimeout);
        }
        console.log('VAD parado.');
    }
}

module.exports = VAD;