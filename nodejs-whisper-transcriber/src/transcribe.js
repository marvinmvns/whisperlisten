const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

class Transcriber {
    constructor() {
        this.whisperPath = process.env.WHISPER_PATH || './whisper.cpp/main';
        this.modelPath = process.env.MODEL_PATH || './models/ggml-base.en.bin';
        this.language = process.env.LANG || 'en';
        this.outputDir = path.join(__dirname, '../data/transcripts');
        this.transcriptCounter = 0;
        
        this.ensureOutputDir();
        this.loadLastCounter();
    }

    ensureOutputDir() {
        if (!fs.existsSync(this.outputDir)) {
            fs.mkdirSync(this.outputDir, { recursive: true });
        }
    }

    loadLastCounter() {
        const counterFile = path.join(this.outputDir, '.counter');
        if (fs.existsSync(counterFile)) {
            const content = fs.readFileSync(counterFile, 'utf8');
            this.transcriptCounter = parseInt(content) || 0;
        }
    }

    saveCounter() {
        const counterFile = path.join(this.outputDir, '.counter');
        fs.writeFileSync(counterFile, this.transcriptCounter.toString());
    }

    async transcribeAudio(audioFilePath) {
        return new Promise((resolve, reject) => {
            console.log(`Transcrevendo: ${path.basename(audioFilePath)}`);
            
            const args = [
                '-m', this.modelPath,
                '-f', audioFilePath,
                '-l', this.language,
                '--output-txt',
                '--no-timestamps'
            ];

            const whisperProcess = spawn(this.whisperPath, args, {
                stdio: ['pipe', 'pipe', 'pipe']
            });

            let outputText = '';
            let errorText = '';

            whisperProcess.stdout.on('data', (data) => {
                outputText += data.toString();
            });

            whisperProcess.stderr.on('data', (data) => {
                errorText += data.toString();
            });

            whisperProcess.on('close', (code) => {
                if (code === 0) {
                    // Extrair texto da saída do whisper
                    const text = this.extractTextFromOutput(outputText);
                    
                    if (text && text.trim().length > 0) {
                        const transcriptFile = this.saveTranscript(text.trim());
                        console.log(`Transcrição salva: ${path.basename(transcriptFile)}`);
                        
                        // Limpar arquivo de áudio temporário
                        this.cleanupAudioFile(audioFilePath);
                        
                        resolve({
                            text: text.trim(),
                            file: transcriptFile,
                            timestamp: new Date().toISOString()
                        });
                    } else {
                        console.log('Nenhum texto detectado na transcrição');
                        this.cleanupAudioFile(audioFilePath);
                        resolve(null);
                    }
                } else {
                    console.error('Erro na transcrição:', errorText);
                    reject(new Error(`Whisper falhou com código ${code}: ${errorText}`));
                }
            });

            whisperProcess.on('error', (err) => {
                console.error('Erro ao executar whisper:', err);
                reject(err);
            });
        });
    }

    extractTextFromOutput(output) {
        // Whisper pode incluir informações de debug, extrair apenas o texto
        const lines = output.split('\n');
        let text = '';
        
        for (const line of lines) {
            // Pular linhas de debug/info
            if (line.includes('[BLANK_AUDIO]') || 
                line.includes('whisper_') || 
                line.includes('load_') ||
                line.startsWith('[')) {
                continue;
            }
            
            const cleanLine = line.trim();
            if (cleanLine.length > 0) {
                text += cleanLine + ' ';
            }
        }
        
        return text.trim();
    }

    saveTranscript(text) {
        this.transcriptCounter++;
        const filename = `${String(this.transcriptCounter).padStart(4, '0')}.txt`;
        const filepath = path.join(this.outputDir, filename);
        
        const content = `${new Date().toISOString()}\n${text}\n`;
        fs.writeFileSync(filepath, content, 'utf8');
        
        this.saveCounter();
        return filepath;
    }

    cleanupAudioFile(audioFilePath) {
        try {
            if (fs.existsSync(audioFilePath)) {
                fs.unlinkSync(audioFilePath);
                console.log(`Arquivo de áudio removido: ${path.basename(audioFilePath)}`);
            }
        } catch (err) {
            console.error('Erro ao remover arquivo de áudio:', err);
        }
    }

    // Alternativa usando node-whisper se disponível
    async transcribeWithNodeWhisper(audioFilePath) {
        try {
            const whisper = require('node-whisper');
            
            const result = await whisper(audioFilePath, {
                modelName: this.modelPath,
                language: this.language,
                removeWavFileAfterTranscription: false // Controlamos isso manualmente
            });
            
            if (result && result.transcription) {
                const transcriptFile = this.saveTranscript(result.transcription);
                this.cleanupAudioFile(audioFilePath);
                
                return {
                    text: result.transcription,
                    file: transcriptFile,
                    timestamp: new Date().toISOString()
                };
            }
            
            this.cleanupAudioFile(audioFilePath);
            return null;
            
        } catch (err) {
            console.error('Erro com node-whisper, usando whisper.cpp:', err);
            return this.transcribeAudio(audioFilePath);
        }
    }

    getTranscriptFiles() {
        if (!fs.existsSync(this.outputDir)) return [];
        
        return fs.readdirSync(this.outputDir)
            .filter(file => file.endsWith('.txt') && !file.startsWith('.'))
            .sort();
    }

    readTranscript(filename) {
        const filepath = path.join(this.outputDir, filename);
        if (fs.existsSync(filepath)) {
            return fs.readFileSync(filepath, 'utf8');
        }
        return null;
    }
}

module.exports = Transcriber;