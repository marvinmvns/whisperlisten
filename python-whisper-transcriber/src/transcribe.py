import os
import logging
import time
from datetime import datetime
from pathlib import Path

logger = logging.getLogger(__name__)

class Transcriber:
    def __init__(self, config=None):
        self.config = config or {}
        
        # Configurações
        self.model_path = self.config.get('model_path', './models/ggml-base.en.bin')
        self.language = self.config.get('language', 'en')
        self.whisper_backend = self.config.get('whisper_backend', 'pywhispercpp')  # pywhispercpp, openai, faster-whisper
        
        # Diretórios
        self.output_dir = Path(self.config.get('output_dir', './data/transcripts'))
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
        # Contador de transcrições
        self.transcript_counter = 0
        self.counter_file = self.output_dir / '.counter'
        self._load_counter()
        
        # Inicializar backend
        self.whisper_model = None
        self._init_whisper()

    def _load_counter(self):
        """Carregar contador de transcrições"""
        try:
            if self.counter_file.exists():
                self.transcript_counter = int(self.counter_file.read_text().strip())
        except Exception as e:
            logger.warning(f"Erro ao carregar contador: {e}")
            self.transcript_counter = 0

    def _save_counter(self):
        """Salvar contador de transcrições"""
        try:
            self.counter_file.write_text(str(self.transcript_counter))
        except Exception as e:
            logger.error(f"Erro ao salvar contador: {e}")

    def _init_whisper(self):
        """Inicializar modelo Whisper"""
        try:
            if self.whisper_backend == 'pywhispercpp':
                self._init_pywhispercpp()
            elif self.whisper_backend == 'openai':
                self._init_openai_whisper()
            elif self.whisper_backend == 'faster-whisper':
                self._init_faster_whisper()
            else:
                raise ValueError(f"Backend não suportado: {self.whisper_backend}")
                
        except Exception as e:
            logger.error(f"Erro ao inicializar Whisper: {e}")
            # Fallback para pywhispercpp se possível
            if self.whisper_backend != 'pywhispercpp':
                logger.info("Tentando fallback para pywhispercpp...")
                self.whisper_backend = 'pywhispercpp'
                self._init_pywhispercpp()

    def _init_pywhispercpp(self):
        """Inicializar pywhispercpp"""
        try:
            from pywhispercpp.model import Model
            
            if not os.path.exists(self.model_path):
                raise FileNotFoundError(f"Modelo não encontrado: {self.model_path}")
                
            self.whisper_model = Model(
                model_path=self.model_path,
                n_threads=self.config.get('n_threads', 4),
                print_progress=False,
                print_realtime=False
            )
            
            logger.info(f"pywhispercpp inicializado com modelo: {self.model_path}")
            
        except ImportError:
            raise ImportError("pywhispercpp não está instalado. Execute: pip install pywhispercpp")

    def _init_openai_whisper(self):
        """Inicializar OpenAI Whisper"""
        try:
            import whisper
            
            # Extrair nome do modelo do caminho
            model_name = self.config.get('model_name', 'base.en')
            
            self.whisper_model = whisper.load_model(model_name)
            logger.info(f"OpenAI Whisper inicializado com modelo: {model_name}")
            
        except ImportError:
            raise ImportError("openai-whisper não está instalado. Execute: pip install openai-whisper")

    def _init_faster_whisper(self):
        """Inicializar Faster Whisper"""
        try:
            from faster_whisper import WhisperModel
            
            model_name = self.config.get('model_name', 'base.en')
            device = self.config.get('device', 'cpu')
            compute_type = self.config.get('compute_type', 'int8')
            
            self.whisper_model = WhisperModel(
                model_name, 
                device=device, 
                compute_type=compute_type
            )
            
            logger.info(f"Faster Whisper inicializado: {model_name} ({device}/{compute_type})")
            
        except ImportError:
            raise ImportError("faster-whisper não está instalado. Execute: pip install faster-whisper")

    async def transcribe_audio(self, audio_file_path):
        """Transcrever arquivo de áudio"""
        try:
            start_time = time.time()
            logger.info(f"Transcrevendo: {os.path.basename(audio_file_path)}")
            
            # Verificar se arquivo existe
            if not os.path.exists(audio_file_path):
                raise FileNotFoundError(f"Arquivo não encontrado: {audio_file_path}")
            
            # Transcrever baseado no backend
            if self.whisper_backend == 'pywhispercpp':
                text = self._transcribe_pywhispercpp(audio_file_path)
            elif self.whisper_backend == 'openai':
                text = self._transcribe_openai(audio_file_path)
            elif self.whisper_backend == 'faster-whisper':
                text = self._transcribe_faster_whisper(audio_file_path)
            else:
                raise ValueError(f"Backend desconhecido: {self.whisper_backend}")
            
            duration = time.time() - start_time
            
            # Verificar se há texto
            if not text or not text.strip():
                logger.info("Nenhum texto detectado")
                self._cleanup_audio_file(audio_file_path)
                return None
            
            # Salvar transcrição
            transcript_file = self._save_transcript(text.strip())
            
            # Limpar arquivo de áudio
            self._cleanup_audio_file(audio_file_path)
            
            logger.info(f"Transcrição salva: {transcript_file.name} ({duration:.2f}s)")
            
            return {
                'text': text.strip(),
                'file': str(transcript_file),
                'timestamp': datetime.now().isoformat(),
                'duration': duration,
                'backend': self.whisper_backend
            }
            
        except Exception as e:
            logger.error(f"Erro na transcrição: {e}")
            self._cleanup_audio_file(audio_file_path)
            raise

    def _transcribe_pywhispercpp(self, audio_file_path):
        """Transcrever usando pywhispercpp"""
        result = self.whisper_model.transcribe(audio_file_path)
        return result

    def _transcribe_openai(self, audio_file_path):
        """Transcrever usando OpenAI Whisper"""
        result = self.whisper_model.transcribe(
            audio_file_path,
            language=self.language if self.language != 'auto' else None,
            fp16=False  # Para compatibilidade com CPU
        )
        return result["text"]

    def _transcribe_faster_whisper(self, audio_file_path):
        """Transcrever usando Faster Whisper"""
        segments, info = self.whisper_model.transcribe(
            audio_file_path,
            language=self.language if self.language != 'auto' else None,
            beam_size=1,  # Mais rápido
            word_timestamps=False
        )
        
        # Juntar todos os segmentos
        text = ' '.join([segment.text for segment in segments])
        return text

    def _save_transcript(self, text):
        """Salvar transcrição em arquivo"""
        self.transcript_counter += 1
        filename = f"{self.transcript_counter:04d}.txt"
        filepath = self.output_dir / filename
        
        # Criar conteúdo com timestamp
        content = f"{datetime.now().isoformat()}\n{text}\n"
        
        filepath.write_text(content, encoding='utf-8')
        self._save_counter()
        
        return filepath

    def _cleanup_audio_file(self, audio_file_path):
        """Remover arquivo de áudio temporário"""
        try:
            if os.path.exists(audio_file_path):
                os.remove(audio_file_path)
                logger.debug(f"Arquivo removido: {os.path.basename(audio_file_path)}")
        except Exception as e:
            logger.error(f"Erro ao remover arquivo: {e}")

    def get_transcript_files(self):
        """Listar arquivos de transcrição"""
        if not self.output_dir.exists():
            return []
        
        return sorted([
            f for f in self.output_dir.iterdir() 
            if f.suffix == '.txt' and not f.name.startswith('.')
        ])

    def read_transcript(self, filename):
        """Ler conteúdo de transcrição"""
        filepath = self.output_dir / filename
        if filepath.exists():
            return filepath.read_text(encoding='utf-8')
        return None

    def get_stats(self):
        """Obter estatísticas"""
        transcript_files = self.get_transcript_files()
        
        return {
            'backend': self.whisper_backend,
            'model_path': self.model_path,
            'language': self.language,
            'total_transcripts': len(transcript_files),
            'last_counter': self.transcript_counter,
            'output_dir': str(self.output_dir),
            'model_exists': os.path.exists(self.model_path) if self.whisper_backend == 'pywhispercpp' else True
        }

    def test_transcription(self, test_audio_path=None):
        """Testar transcrição"""
        if test_audio_path and os.path.exists(test_audio_path):
            try:
                result = self.transcribe_audio(test_audio_path)
                return result is not None
            except Exception as e:
                logger.error(f"Erro no teste: {e}")
                return False
        else:
            logger.warning("Arquivo de teste não fornecido ou não existe")
            return self.whisper_model is not None

    def cleanup_old_transcripts(self, days_old=30):
        """Limpar transcrições antigas"""
        if not self.output_dir.exists():
            return 0
        
        cutoff_time = time.time() - (days_old * 24 * 60 * 60)
        removed_count = 0
        
        for file_path in self.output_dir.iterdir():
            if file_path.suffix == '.txt' and not file_path.name.startswith('.'):
                if file_path.stat().st_mtime < cutoff_time:
                    try:
                        file_path.unlink()
                        removed_count += 1
                    except Exception as e:
                        logger.error(f"Erro ao remover {file_path}: {e}")
        
        if removed_count > 0:
            logger.info(f"Removidas {removed_count} transcrições antigas")
        
        return removed_count