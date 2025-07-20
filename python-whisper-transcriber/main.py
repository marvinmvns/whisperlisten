#!/usr/bin/env python3

import os
import sys
import asyncio
import signal
import logging
import argparse
import json
from pathlib import Path
from dotenv import load_dotenv

# Adicionar src ao path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from vad import VAD
from transcribe import Transcriber
from queue import TranscriptQueue
from sender import TranscriptSender

# Configurar logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler('./logs/transcriber.log', 'a')
    ]
)

logger = logging.getLogger(__name__)

class WhisperTranscriber:
    def __init__(self, config_file=None):
        # Carregar configurações
        load_dotenv()
        self.config = self._load_config(config_file)
        
        # Criar diretórios necessários
        self._ensure_directories()
        
        # Inicializar componentes
        self.vad = None
        self.transcriber = None
        self.queue = None
        self.sender = None
        
        self.is_running = False
        self.stats = {
            'start_time': None,
            'transcriptions': 0,
            'errors': 0
        }
        
        # Signal handlers
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)

    def _load_config(self, config_file):
        """Carregar configurações"""
        config = {}
        
        # Configurações padrão do ambiente
        config.update({
            # API
            'api_url': os.getenv('API_URL'),
            'api_token': os.getenv('API_TOKEN'),
            
            # Whisper
            'whisper_backend': os.getenv('WHISPER_BACKEND', 'pywhispercpp'),
            'model_path': os.getenv('MODEL_PATH', './models/ggml-base.en.bin'),
            'model_name': os.getenv('MODEL_NAME', 'base.en'),
            'language': os.getenv('LANG', 'en'),
            'n_threads': int(os.getenv('N_THREADS', '4')),
            
            # VAD
            'sample_rate': int(os.getenv('SAMPLE_RATE', '16000')),
            'vad_aggressiveness': int(os.getenv('VAD_AGGRESSIVENESS', '2')),
            'silence_duration_ms': int(os.getenv('SILENCE_DURATION_MS', '1000')),
            'min_recording_duration_ms': int(os.getenv('MIN_RECORDING_DURATION_MS', '500')),
            
            # Sender
            'connectivity_check_interval': int(os.getenv('CONNECTIVITY_CHECK_INTERVAL', '5')),
            'send_check_interval': int(os.getenv('SEND_CHECK_INTERVAL', '2')),
            'request_timeout': int(os.getenv('REQUEST_TIMEOUT', '10')),
            'max_retries': int(os.getenv('MAX_RETRIES', '5')),
            
            # Diretórios
            'temp_dir': os.getenv('TEMP_DIR', './data/temp'),
            'output_dir': os.getenv('OUTPUT_DIR', './data/transcripts'),
            'queue_dir': os.getenv('QUEUE_DIR', './data/queue'),
            'log_dir': os.getenv('LOG_DIR', './logs')
        })
        
        # Carregar arquivo de configuração se fornecido
        if config_file and os.path.exists(config_file):
            with open(config_file, 'r') as f:
                file_config = json.load(f)
                config.update(file_config)
        
        return config

    def _ensure_directories(self):
        """Criar diretórios necessários"""
        dirs = [
            self.config['temp_dir'],
            self.config['output_dir'],
            self.config['queue_dir'],
            self.config['log_dir']
        ]
        
        for dir_path in dirs:
            Path(dir_path).mkdir(parents=True, exist_ok=True)

    def _signal_handler(self, signum, frame):
        """Handler para sinais do sistema"""
        logger.info(f"Recebido sinal {signum}, parando...")
        self.stop()
        sys.exit(0)

    def initialize_components(self):
        """Inicializar todos os componentes"""
        try:
            # VAD
            vad_config = {
                'sample_rate': self.config['sample_rate'],
                'vad_aggressiveness': self.config['vad_aggressiveness'],
                'silence_duration_ms': self.config['silence_duration_ms'],
                'min_recording_duration_ms': self.config['min_recording_duration_ms'],
                'temp_dir': self.config['temp_dir']
            }
            self.vad = VAD(vad_config)
            
            # Transcriber
            transcriber_config = {
                'whisper_backend': self.config['whisper_backend'],
                'model_path': self.config['model_path'],
                'model_name': self.config['model_name'],
                'language': self.config['language'],
                'n_threads': self.config['n_threads'],
                'output_dir': self.config['output_dir']
            }
            self.transcriber = Transcriber(transcriber_config)
            
            # Queue
            queue_config = {
                'queue_dir': self.config['queue_dir'],
                'max_retries': self.config['max_retries']
            }
            self.queue = TranscriptQueue(queue_config)
            
            # Sender
            sender_config = {
                'api_url': self.config['api_url'],
                'api_token': self.config['api_token'],
                'connectivity_check_interval': self.config['connectivity_check_interval'],
                'send_check_interval': self.config['send_check_interval'],
                'request_timeout': self.config['request_timeout']
            }
            self.sender = TranscriptSender(self.queue, sender_config)
            
            # Configurar callback do VAD
            self.vad.on_audio_ready = self._on_audio_ready
            
            logger.info("Componentes inicializados com sucesso")
            return True
            
        except Exception as e:
            logger.error(f"Erro ao inicializar componentes: {e}")
            return False

    def _on_audio_ready(self, audio_file):
        """Callback quando áudio está pronto para transcrição"""
        try:
            # Usar asyncio para não bloquear o VAD
            asyncio.create_task(self._process_audio(audio_file))
        except Exception as e:
            logger.error(f"Erro no callback de áudio: {e}")

    async def _process_audio(self, audio_file):
        """Processar arquivo de áudio"""
        try:
            # Transcrever
            result = await self.transcriber.transcribe_audio(audio_file)
            
            if result:
                # Adicionar à fila
                self.queue.add_transcript(result)
                self.stats['transcriptions'] += 1
                
                logger.info(f"Transcrição: \"{result['text']}\"")
            
        except Exception as e:
            logger.error(f"Erro ao processar áudio: {e}")
            self.stats['errors'] += 1

    def start(self):
        """Iniciar transcritor"""
        if self.is_running:
            logger.warning("Transcriber já está rodando")
            return False
        
        if not self.initialize_components():
            logger.error("Falha na inicialização")
            return False
        
        # Testar microfone
        if not self.vad.test_microphone():
            logger.error("Falha no teste do microfone")
            return False
        
        # Iniciar VAD
        if not self.vad.start_listening():
            logger.error("Falha ao iniciar VAD")
            return False
        
        self.is_running = True
        self.stats['start_time'] = logger.info("Whisper Transcriber iniciado - aguardando voz...")
        
        # Loop principal
        try:
            asyncio.run(self._main_loop())
        except KeyboardInterrupt:
            logger.info("Interrompido pelo usuário")
        finally:
            self.stop()
        
        return True

    async def _main_loop(self):
        """Loop principal do programa"""
        try:
            while self.is_running:
                # Log de status a cada 30 segundos
                await asyncio.sleep(30)
                self._log_status()
                
        except Exception as e:
            logger.error(f"Erro no loop principal: {e}")

    def _log_status(self):
        """Log de status"""
        if self.sender:
            status = self.sender.get_status()
            queue_stats = status['queue']
            
            logger.info(
                f"Status: {'ONLINE' if status['online'] else 'OFFLINE'} | "
                f"Fila: {queue_stats['pending']} pendentes, "
                f"{queue_stats['sent']} enviados | "
                f"Transcrições: {self.stats['transcriptions']}, "
                f"Erros: {self.stats['errors']}"
            )

    def stop(self):
        """Parar transcriber"""
        if not self.is_running:
            return
        
        logger.info("Parando componentes...")
        self.is_running = False
        
        # Parar componentes na ordem correta
        if self.vad:
            self.vad.stop()
        
        if self.sender:
            self.sender.stop()
        
        logger.info("Whisper Transcriber parado")

    # Comandos CLI
    def cmd_status(self):
        """Comando: status detalhado"""
        if not self.initialize_components():
            return {"error": "Falha na inicialização"}
        
        import psutil
        process = psutil.Process()
        
        return {
            'system': {
                'running': self.is_running,
                'uptime': time.time() - self.stats['start_time'] if self.stats['start_time'] else 0,
                'memory_mb': process.memory_info().rss / 1024 / 1024,
                'cpu_percent': process.cpu_percent()
            },
            'stats': self.stats,
            'vad': self.vad.get_stats() if self.vad else {},
            'transcriber': self.transcriber.get_stats() if self.transcriber else {},
            'sender': self.sender.get_status() if self.sender else {},
            'queue': self.queue.get_stats() if self.queue else {}
        }

    def cmd_test(self):
        """Comando: testar conexão e componentes"""
        results = {}
        
        try:
            if not self.initialize_components():
                return {"error": "Falha na inicialização"}
            
            # Teste do microfone
            results['microphone'] = self.vad.test_microphone(2)
            
            # Teste da transcrição
            results['transcription'] = self.transcriber.test_transcription()
            
            # Teste da conexão
            results['connection'] = self.sender.test_connection()
            
            return results
            
        except Exception as e:
            return {"error": str(e)}

    def cmd_queue(self):
        """Comando: informações da fila"""
        if not self.queue:
            self.queue = TranscriptQueue({'queue_dir': self.config['queue_dir']})
        
        return {
            'stats': self.queue.get_stats(),
            'pending': self.queue.get_all_pending()[:10],  # Últimos 10
            'recent': self.queue.list_all(20)  # Últimos 20
        }

    def cmd_retry(self, item_id):
        """Comando: tentar reenviar item"""
        if not self.sender:
            if not self.initialize_components():
                return {"error": "Falha na inicialização"}
        
        success = self.sender.retry_item(item_id)
        return {"success": success, "message": f"Retry {'iniciado' if success else 'falhou'} para {item_id}"}

    def cmd_cleanup(self, days=30):
        """Comando: limpar itens antigos"""
        if not self.initialize_components():
            return {"error": "Falha na inicialização"}
        
        queue_removed = self.queue.cleanup_old_items(days)
        transcript_removed = self.transcriber.cleanup_old_transcripts(days)
        
        return {
            "queue_removed": queue_removed,
            "transcript_removed": transcript_removed,
            "total_removed": queue_removed + transcript_removed
        }

def main():
    parser = argparse.ArgumentParser(description='Whisper Transcriber em Python')
    parser.add_argument('command', nargs='?', default='start', 
                       choices=['start', 'status', 'test', 'queue', 'retry', 'cleanup'],
                       help='Comando a executar')
    parser.add_argument('--config', '-c', help='Arquivo de configuração JSON')
    parser.add_argument('--item-id', help='ID do item para retry')
    parser.add_argument('--days', type=int, default=30, help='Dias para cleanup')
    
    args = parser.parse_args()
    
    # Criar transcriber
    transcriber = WhisperTranscriber(args.config)
    
    # Executar comando
    if args.command == 'start':
        transcriber.start()
    elif args.command == 'status':
        result = transcriber.cmd_status()
        print(json.dumps(result, indent=2, default=str))
    elif args.command == 'test':
        result = transcriber.cmd_test()
        print(json.dumps(result, indent=2))
    elif args.command == 'queue':
        result = transcriber.cmd_queue()
        print(json.dumps(result, indent=2, default=str))
    elif args.command == 'retry':
        if not args.item_id:
            print("--item-id é obrigatório para retry")
            sys.exit(1)
        result = transcriber.cmd_retry(args.item_id)
        print(json.dumps(result, indent=2))
    elif args.command == 'cleanup':
        result = transcriber.cmd_cleanup(args.days)
        print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()