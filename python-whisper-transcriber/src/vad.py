import pyaudio
import webrtcvad
import wave
import time
import os
import threading
import queue
from collections import deque
import logging

logger = logging.getLogger(__name__)

class VAD:
    def __init__(self, config=None):
        self.config = config or {}
        
        # Configurações de áudio
        self.sample_rate = self.config.get('sample_rate', 16000)
        self.channels = 1
        self.chunk_duration_ms = self.config.get('chunk_duration_ms', 30)  # 30ms chunks para webrtcvad
        self.chunk_size = int(self.sample_rate * self.chunk_duration_ms / 1000)
        
        # Configurações VAD
        self.vad_aggressiveness = self.config.get('vad_aggressiveness', 2)  # 0-3
        self.silence_duration_ms = self.config.get('silence_duration_ms', 1000)
        self.min_recording_duration_ms = self.config.get('min_recording_duration_ms', 500)
        
        # Estado
        self.is_recording = False
        self.is_listening = False
        self.audio_counter = 0
        self.current_audio_file = None
        self.recording_start_time = None
        
        # Buffers
        self.silence_chunks = int(self.silence_duration_ms / self.chunk_duration_ms)
        self.voice_buffer = deque(maxlen=self.silence_chunks)
        self.audio_buffer = deque()
        
        # Threading
        self.audio_queue = queue.Queue()
        self.stop_flag = threading.Event()
        self.recording_thread = None
        
        # Callbacks
        self.on_audio_ready = None
        
        # Diretórios
        self.temp_dir = self.config.get('temp_dir', './data/temp')
        os.makedirs(self.temp_dir, exist_ok=True)
        
        # Inicializar componentes
        self.vad = webrtcvad.Vad(self.vad_aggressiveness)
        self.audio = None
        self.stream = None

    def setup_audio(self):
        """Configurar interface de áudio"""
        try:
            self.audio = pyaudio.PyAudio()
            
            # Encontrar dispositivo de entrada padrão
            device_info = self.audio.get_default_input_device_info()
            logger.info(f"Usando dispositivo: {device_info['name']}")
            
            self.stream = self.audio.open(
                format=pyaudio.paInt16,
                channels=self.channels,
                rate=self.sample_rate,
                input=True,
                frames_per_buffer=self.chunk_size,
                input_device_index=device_info['index']
            )
            
            return True
            
        except Exception as e:
            logger.error(f"Erro ao configurar áudio: {e}")
            return False

    def start_listening(self):
        """Iniciar escuta contínua"""
        if self.is_listening:
            logger.warning("VAD já está escutando")
            return
            
        if not self.setup_audio():
            logger.error("Falha ao configurar áudio")
            return False
            
        self.is_listening = True
        self.stop_flag.clear()
        
        # Iniciar thread de gravação
        self.recording_thread = threading.Thread(target=self._recording_loop, daemon=True)
        self.recording_thread.start()
        
        logger.info("VAD iniciado - aguardando voz...")
        return True

    def _recording_loop(self):
        """Loop principal de gravação"""
        try:
            while not self.stop_flag.is_set():
                # Ler chunk de áudio
                try:
                    data = self.stream.read(self.chunk_size, exception_on_overflow=False)
                    self._process_audio_chunk(data)
                except Exception as e:
                    logger.error(f"Erro na leitura de áudio: {e}")
                    break
                    
        except Exception as e:
            logger.error(f"Erro no loop de gravação: {e}")
        finally:
            self._cleanup_audio()

    def _process_audio_chunk(self, audio_chunk):
        """Processar chunk de áudio para VAD"""
        # Verificar se é voz
        is_speech = self.vad.is_speech(audio_chunk, self.sample_rate)
        
        if is_speech:
            logger.debug("Voz detectada")
            
            # Se não estava gravando, iniciar
            if not self.is_recording:
                self._start_recording()
                
                # Adicionar chunks de voz anteriores (pre-buffer)
                for buffered_chunk in self.voice_buffer:
                    self.audio_buffer.append(buffered_chunk)
                    
            # Adicionar chunk atual
            self.audio_buffer.append(audio_chunk)
            
            # Resetar contador de silêncio
            self.voice_buffer.clear()
            
        else:
            # Silêncio detectado
            if self.is_recording:
                # Adicionar ao buffer de silêncio
                self.voice_buffer.append(audio_chunk)
                self.audio_buffer.append(audio_chunk)
                
                # Se buffer de silêncio estiver cheio, parar gravação
                if len(self.voice_buffer) >= self.silence_chunks:
                    self._stop_recording()
            else:
                # Manter buffer circular para pre-recording
                self.voice_buffer.append(audio_chunk)

    def _start_recording(self):
        """Iniciar nova gravação"""
        if self.is_recording:
            return
            
        self.is_recording = True
        self.recording_start_time = time.time()
        self.audio_counter += 1
        
        filename = f"audio_{self.audio_counter:04d}.wav"
        self.current_audio_file = os.path.join(self.temp_dir, filename)
        
        # Limpar buffer de áudio
        self.audio_buffer.clear()
        
        logger.info(f"Iniciando gravação: {filename}")

    def _stop_recording(self):
        """Parar gravação atual"""
        if not self.is_recording:
            return
            
        recording_duration = (time.time() - self.recording_start_time) * 1000
        
        # Verificar duração mínima
        if recording_duration < self.min_recording_duration_ms:
            logger.info(f"Gravação muito curta ({recording_duration:.0f}ms), descartando")
            self._discard_recording()
            return
            
        # Salvar arquivo de áudio
        self._save_audio_file()
        
        logger.info(f"Gravação concluída: {os.path.basename(self.current_audio_file)} ({recording_duration:.0f}ms)")
        
        # Notificar callback
        if self.on_audio_ready and self.current_audio_file:
            try:
                self.on_audio_ready(self.current_audio_file)
            except Exception as e:
                logger.error(f"Erro no callback: {e}")
        
        # Reset
        self.is_recording = False
        self.current_audio_file = None
        self.audio_buffer.clear()

    def _save_audio_file(self):
        """Salvar buffer de áudio como arquivo WAV"""
        if not self.current_audio_file or not self.audio_buffer:
            return
            
        try:
            with wave.open(self.current_audio_file, 'wb') as wav_file:
                wav_file.setnchannels(self.channels)
                wav_file.setsampwidth(2)  # 16-bit
                wav_file.setframerate(self.sample_rate)
                
                # Escrever todos os chunks
                for chunk in self.audio_buffer:
                    wav_file.writeframes(chunk)
                    
        except Exception as e:
            logger.error(f"Erro ao salvar arquivo: {e}")
            self._discard_recording()

    def _discard_recording(self):
        """Descartar gravação atual"""
        if self.current_audio_file and os.path.exists(self.current_audio_file):
            try:
                os.remove(self.current_audio_file)
            except Exception as e:
                logger.error(f"Erro ao remover arquivo: {e}")
                
        self.is_recording = False
        self.current_audio_file = None
        self.audio_buffer.clear()

    def _cleanup_audio(self):
        """Limpar recursos de áudio"""
        try:
            if self.stream:
                self.stream.stop_stream()
                self.stream.close()
                
            if self.audio:
                self.audio.terminate()
                
        except Exception as e:
            logger.error(f"Erro na limpeza de áudio: {e}")

    def stop(self):
        """Parar VAD"""
        if not self.is_listening:
            return
            
        logger.info("Parando VAD...")
        
        # Parar thread
        self.stop_flag.set()
        
        # Finalizar gravação se ativa
        if self.is_recording:
            self._stop_recording()
            
        # Aguardar thread terminar
        if self.recording_thread and self.recording_thread.is_alive():
            self.recording_thread.join(timeout=2)
            
        self.is_listening = False
        logger.info("VAD parado")

    def get_stats(self):
        """Obter estatísticas"""
        return {
            'is_listening': self.is_listening,
            'is_recording': self.is_recording,
            'audio_counter': self.audio_counter,
            'current_file': os.path.basename(self.current_audio_file) if self.current_audio_file else None,
            'buffer_size': len(self.audio_buffer),
            'config': {
                'sample_rate': self.sample_rate,
                'vad_aggressiveness': self.vad_aggressiveness,
                'silence_duration_ms': self.silence_duration_ms,
                'min_recording_duration_ms': self.min_recording_duration_ms
            }
        }

    def test_microphone(self, duration_seconds=3):
        """Testar microfone"""
        logger.info(f"Testando microfone por {duration_seconds} segundos...")
        
        if not self.setup_audio():
            return False
            
        try:
            # Gravar por alguns segundos
            frames = []
            for _ in range(int(self.sample_rate / self.chunk_size * duration_seconds)):
                data = self.stream.read(self.chunk_size)
                frames.append(data)
                
            # Verificar se há sinal
            audio_data = b''.join(frames)
            if len(audio_data) > 0:
                logger.info("✓ Microfone funcionando")
                return True
            else:
                logger.error("✗ Nenhum sinal detectado")
                return False
                
        except Exception as e:
            logger.error(f"✗ Erro no teste: {e}")
            return False
        finally:
            self._cleanup_audio()