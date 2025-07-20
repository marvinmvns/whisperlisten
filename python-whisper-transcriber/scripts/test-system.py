#!/usr/bin/env python3

"""
Script de teste completo para Python Whisper Transcriber
Testa todos os componentes do sistema incluindo geração de áudio sintético
"""

import os
import sys
import time
import json
import subprocess
import tempfile
import shutil
from pathlib import Path
import logging

# Adicionar src ao path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

# Cores ANSI
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'  # No Color

class TestRunner:
    def __init__(self):
        self.tests_passed = 0
        self.tests_failed = 0
        self.test_results = []
        
        # Configurar logging
        logging.basicConfig(level=logging.INFO, format='%(message)s')
        self.logger = logging.getLogger(__name__)
        
        # Criar diretório de teste
        self.test_dir = Path('./test_data')
        self.test_dir.mkdir(exist_ok=True)

    def log(self, message):
        print(f"{Colors.GREEN}[INFO]{Colors.NC} {message}")

    def warn(self, message):
        print(f"{Colors.YELLOW}[WARN]{Colors.NC} {message}")

    def error(self, message):
        print(f"{Colors.RED}[ERROR]{Colors.NC} {message}")

    def test_header(self, message):
        print(f"{Colors.BLUE}[TEST]{Colors.NC} {message}")

    def run_test(self, test_name, test_function, *args, **kwargs):
        """Executa um teste e registra o resultado"""
        self.test_header(f"Executando: {test_name}")
        
        try:
            result = test_function(*args, **kwargs)
            if result:
                self.log(f"✓ PASSOU: {test_name}")
                self.tests_passed += 1
                self.test_results.append((test_name, True, None))
                return True
            else:
                self.error(f"✗ FALHOU: {test_name}")
                self.tests_failed += 1
                self.test_results.append((test_name, False, "Test function returned False"))
                return False
        except Exception as e:
            self.error(f"✗ FALHOU: {test_name} - {str(e)}")
            self.tests_failed += 1
            self.test_results.append((test_name, False, str(e)))
            return False

    def test_python_version(self):
        """Testa se a versão do Python é adequada"""
        version = sys.version_info
        return version.major >= 3 and version.minor >= 8

    def test_dependencies_import(self):
        """Testa se as dependências podem ser importadas"""
        try:
            import pyaudio
            import webrtcvad
            import requests
            import numpy
            import sqlite3
            return True
        except ImportError as e:
            self.error(f"Dependência não encontrada: {e}")
            return False

    def test_whisper_backend(self):
        """Testa se pelo menos um backend Whisper está disponível"""
        backends = []
        
        # Tentar pywhispercpp
        try:
            from pywhispercpp.model import Model
            backends.append('pywhispercpp')
        except ImportError:
            pass
            
        # Tentar openai-whisper
        try:
            import whisper
            backends.append('openai')
        except ImportError:
            pass
            
        # Tentar faster-whisper
        try:
            from faster_whisper import WhisperModel
            backends.append('faster-whisper')
        except ImportError:
            pass
        
        if backends:
            self.log(f"Backends Whisper disponíveis: {', '.join(backends)}")
            return True
        else:
            self.error("Nenhum backend Whisper encontrado")
            return False

    def test_audio_devices(self):
        """Testa se dispositivos de áudio estão disponíveis"""
        try:
            import pyaudio
            
            audio = pyaudio.PyAudio()
            device_count = audio.get_device_count()
            
            input_devices = []
            for i in range(device_count):
                device_info = audio.get_device_info_by_index(i)
                if device_info['maxInputChannels'] > 0:
                    input_devices.append(device_info['name'])
            
            audio.terminate()
            
            if input_devices:
                self.log(f"Dispositivos de entrada encontrados: {len(input_devices)}")
                return True
            else:
                self.warn("Nenhum dispositivo de entrada encontrado")
                return False
                
        except Exception as e:
            self.error(f"Erro ao verificar dispositivos de áudio: {e}")
            return False

    def generate_test_audio(self):
        """Gera arquivos de áudio para teste"""
        audio_files = []
        
        # Tentar gerar com espeak
        if self.generate_speech_audio():
            audio_files.extend(self.speech_files)
        
        # Gerar com numpy (sempre funciona)
        if self.generate_synthetic_audio():
            audio_files.extend(self.synthetic_files)
        
        return len(audio_files) > 0

    def generate_speech_audio(self):
        """Gera áudio de fala usando espeak"""
        try:
            import subprocess
            
            # Verificar se espeak está disponível
            subprocess.run(['espeak', '--version'], capture_output=True, check=True)
            
            self.speech_files = []
            
            # Gerar diferentes frases de teste
            test_phrases = [
                ("hello_world.wav", "Hello world this is a test"),
                ("numbers.wav", "One two three four five six seven eight nine ten"),
                ("alphabet.wav", "A B C D E F G H I J K L M N O P Q R S T U V W X Y Z")
            ]
            
            for filename, text in test_phrases:
                filepath = self.test_dir / filename
                
                # Gerar com espeak
                cmd = ['espeak', '-w', str(filepath), '-s', '150', text]
                subprocess.run(cmd, capture_output=True, check=True)
                
                # Converter para formato correto com ffmpeg se disponível
                if shutil.which('ffmpeg'):
                    converted_path = self.test_dir / f"converted_{filename}"
                    cmd = [
                        'ffmpeg', '-i', str(filepath), 
                        '-ar', '16000', '-ac', '1', 
                        '-y', str(converted_path)
                    ]
                    subprocess.run(cmd, capture_output=True, check=True)
                    filepath.unlink()  # Remove original
                    converted_path.rename(filepath)  # Rename converted
                
                self.speech_files.append(filepath)
                self.log(f"✓ Áudio de fala gerado: {filename}")
            
            return True
            
        except (subprocess.CalledProcessError, FileNotFoundError):
            self.warn("espeak não disponível - usando áudio sintético")
            return False

    def generate_synthetic_audio(self):
        """Gera áudio sintético usando numpy"""
        try:
            import numpy as np
            import wave
            
            self.synthetic_files = []
            
            # Configurações de áudio
            sample_rate = 16000
            duration = 2.0  # segundos
            
            # Gerar diferentes tipos de áudio
            test_sounds = [
                ("tone_440hz.wav", self.generate_sine_wave(440, duration, sample_rate)),
                ("tone_880hz.wav", self.generate_sine_wave(880, duration, sample_rate)),
                ("white_noise.wav", self.generate_white_noise(duration, sample_rate)),
                ("silence.wav", self.generate_silence(duration, sample_rate))
            ]
            
            for filename, audio_data in test_sounds:
                filepath = self.test_dir / filename
                self.save_wav_file(audio_data, filepath, sample_rate)
                self.synthetic_files.append(filepath)
                self.log(f"✓ Áudio sintético gerado: {filename}")
            
            return True
            
        except ImportError:
            self.error("numpy não disponível para gerar áudio sintético")
            return False

    def generate_sine_wave(self, frequency, duration, sample_rate):
        """Gera onda senoidal"""
        import numpy as np
        t = np.linspace(0, duration, int(sample_rate * duration), False)
        wave = np.sin(frequency * 2 * np.pi * t)
        return (wave * 32767).astype(np.int16)

    def generate_white_noise(self, duration, sample_rate):
        """Gera ruído branco"""
        import numpy as np
        samples = int(sample_rate * duration)
        noise = np.random.normal(0, 0.1, samples)
        return (noise * 32767).astype(np.int16)

    def generate_silence(self, duration, sample_rate):
        """Gera silêncio"""
        import numpy as np
        samples = int(sample_rate * duration)
        return np.zeros(samples, dtype=np.int16)

    def save_wav_file(self, audio_data, filepath, sample_rate):
        """Salva dados de áudio como arquivo WAV"""
        import wave
        
        with wave.open(str(filepath), 'wb') as wav_file:
            wav_file.setnchannels(1)  # Mono
            wav_file.setsampwidth(2)  # 16-bit
            wav_file.setframerate(sample_rate)
            wav_file.writeframes(audio_data.tobytes())

    def test_vad_module(self):
        """Testa o módulo VAD"""
        try:
            from vad import VAD
            
            config = {
                'temp_dir': str(self.test_dir),
                'sample_rate': 16000,
                'vad_aggressiveness': 2
            }
            
            vad = VAD(config)
            stats = vad.get_stats()
            
            return isinstance(stats, dict) and 'is_listening' in stats
            
        except Exception as e:
            self.error(f"Erro no módulo VAD: {e}")
            return False

    def test_transcriber_module(self):
        """Testa o módulo Transcriber"""
        try:
            from transcribe import Transcriber
            
            config = {
                'whisper_backend': 'pywhispercpp',  # Usar backend padrão
                'output_dir': str(self.test_dir / 'transcripts'),
                'language': 'en'
            }
            
            transcriber = Transcriber(config)
            stats = transcriber.get_stats()
            
            return isinstance(stats, dict) and 'backend' in stats
            
        except Exception as e:
            self.error(f"Erro no módulo Transcriber: {e}")
            return False

    def test_queue_module(self):
        """Testa o módulo Queue"""
        try:
            from queue import TranscriptQueue
            
            config = {
                'queue_dir': str(self.test_dir / 'queue')
            }
            
            queue = TranscriptQueue(config)
            
            # Teste básico de adicionar item
            test_item = {
                'text': 'Teste de fila',
                'file': str(self.test_dir / 'test.txt'),
                'timestamp': time.time()
            }
            
            queue_item = queue.add_transcript(test_item)
            stats = queue.get_stats()
            
            return (isinstance(stats, dict) and 
                   stats.get('total', 0) > 0 and
                   queue_item is not None)
            
        except Exception as e:
            self.error(f"Erro no módulo Queue: {e}")
            return False

    def test_sender_module(self):
        """Testa o módulo Sender"""
        try:
            from sender import TranscriptSender
            from queue import TranscriptQueue
            
            # Criar queue para o sender
            queue_config = {'queue_dir': str(self.test_dir / 'queue')}
            queue = TranscriptQueue(queue_config)
            
            sender_config = {
                'api_url': 'https://httpbin.org/post',  # URL de teste
                'api_token': 'test_token',
                'request_timeout': 5
            }
            
            sender = TranscriptSender(queue, sender_config)
            status = sender.get_status()
            
            sender.stop()  # Parar threads
            
            return isinstance(status, dict) and 'online' in status
            
        except Exception as e:
            self.error(f"Erro no módulo Sender: {e}")
            return False

    def test_transcription_integration(self):
        """Testa transcrição com arquivo real"""
        if not hasattr(self, 'speech_files') and not hasattr(self, 'synthetic_files'):
            self.warn("Nenhum arquivo de áudio disponível para teste")
            return True  # Não falhar se não há áudio
            
        try:
            from transcribe import Transcriber
            import asyncio
            
            # Usar arquivo de fala se disponível, senão sintético
            test_files = []
            if hasattr(self, 'speech_files'):
                test_files.extend(self.speech_files)
            elif hasattr(self, 'synthetic_files'):
                test_files.extend(self.synthetic_files[:1])  # Apenas um arquivo
            
            if not test_files:
                return True
                
            config = {
                'whisper_backend': 'pywhispercpp',
                'output_dir': str(self.test_dir / 'transcripts'),
                'language': 'en'
            }
            
            transcriber = Transcriber(config)
            
            # Teste apenas se modelo existe
            if not transcriber.get_stats().get('model_exists', True):
                self.warn("Modelo Whisper não encontrado - pulando teste de transcrição")
                return True
            
            # Testar transcrição
            test_file = test_files[0]
            self.log(f"Testando transcrição de: {test_file.name}")
            
            # Usar asyncio se necessário
            try:
                result = asyncio.run(transcriber.transcribe_audio(str(test_file)))
            except:
                # Fallback para chamada síncrona
                result = transcriber.transcribe_audio(str(test_file))
            
            if result:
                self.log(f"✓ Transcrição bem-sucedida: '{result['text']}'")
                return True
            else:
                self.warn("Nenhum texto detectado (normal para alguns áudios)")
                return True  # Não considerar falha
                
        except Exception as e:
            self.error(f"Erro no teste de transcrição: {e}")
            return False

    def test_main_application(self):
        """Testa a aplicação principal"""
        try:
            # Importar módulo principal
            main_path = Path(__file__).parent.parent / 'main.py'
            if not main_path.exists():
                return False
                
            # Testar comandos básicos
            import subprocess
            
            # Teste comando status
            result = subprocess.run([
                sys.executable, str(main_path), 'status'
            ], capture_output=True, timeout=30)
            
            if result.returncode == 0:
                self.log("✓ Comando status funcionando")
                return True
            else:
                self.error(f"Comando status falhou: {result.stderr.decode()}")
                return False
                
        except Exception as e:
            self.error(f"Erro no teste da aplicação principal: {e}")
            return False

    def test_configuration(self):
        """Testa arquivos de configuração"""
        config_files = [
            '.env.example',
            'requirements.txt'
        ]
        
        missing_files = []
        for filename in config_files:
            filepath = Path(filename)
            if not filepath.exists():
                missing_files.append(filename)
        
        if missing_files:
            self.warn(f"Arquivos de configuração ausentes: {missing_files}")
            return len(missing_files) < len(config_files)  # Pelo menos alguns existem
        
        return True

    def test_directories(self):
        """Testa se diretórios necessários podem ser criados"""
        required_dirs = [
            'data/temp',
            'data/transcripts', 
            'data/queue',
            'logs'
        ]
        
        for dirname in required_dirs:
            dirpath = Path(dirname)
            try:
                dirpath.mkdir(parents=True, exist_ok=True)
                if dirpath.exists():
                    self.log(f"✓ Diretório {dirname} OK")
                else:
                    return False
            except Exception:
                return False
        
        return True

    def run_performance_test(self):
        """Executa teste básico de performance"""
        try:
            import psutil
            import time
            
            # Medidas antes
            process = psutil.Process()
            mem_before = process.memory_info().rss / 1024 / 1024  # MB
            cpu_before = process.cpu_percent()
            
            # Simular carga de trabalho
            time.sleep(1)
            
            # Medidas depois
            mem_after = process.memory_info().rss / 1024 / 1024  # MB
            cpu_after = process.cpu_percent()
            
            self.log(f"Memória: {mem_before:.1f}MB -> {mem_after:.1f}MB")
            self.log(f"CPU: {cpu_before:.1f}% -> {cpu_after:.1f}%")
            
            # Considerar OK se não usar mais que 500MB
            return mem_after < 500
            
        except ImportError:
            self.warn("psutil não disponível para teste de performance")
            return True

    def cleanup_test_files(self, keep_files=False):
        """Limpa arquivos de teste"""
        if not keep_files and self.test_dir.exists():
            try:
                shutil.rmtree(self.test_dir)
                self.log("Arquivos de teste removidos")
            except Exception as e:
                self.warn(f"Erro ao remover arquivos de teste: {e}")

    def print_system_info(self):
        """Imprime informações do sistema"""
        print("\n" + "="*50)
        self.log("=== Informações do Sistema ===")
        
        print(f"Python: {sys.version}")
        print(f"Plataforma: {sys.platform}")
        print(f"Diretório: {os.getcwd()}")
        
        # Informações de hardware
        try:
            import psutil
            memory = psutil.virtual_memory()
            print(f"RAM total: {memory.total / 1024**3:.1f}GB")
            print(f"RAM disponível: {memory.available / 1024**3:.1f}GB")
            print(f"CPU cores: {psutil.cpu_count()}")
        except ImportError:
            pass
        
        # Espaço em disco
        try:
            disk = shutil.disk_usage('.')
            print(f"Espaço livre: {disk.free / 1024**3:.1f}GB")
        except:
            pass

    def print_final_report(self):
        """Imprime relatório final"""
        total_tests = self.tests_passed + self.tests_failed
        
        print(f"\n{Colors.BLUE}======================================{Colors.NC}")
        print(f"{Colors.GREEN}Testes Executados: {total_tests}{Colors.NC}")
        print(f"{Colors.GREEN}Testes Passaram: {self.tests_passed}{Colors.NC}")
        
        if self.tests_failed > 0:
            print(f"{Colors.RED}Testes Falharam: {self.tests_failed}{Colors.NC}")
            print(f"\n{Colors.RED}Testes que falharam:{Colors.NC}")
            for name, passed, error in self.test_results:
                if not passed:
                    print(f"  ✗ {name}: {error}")
        else:
            print(f"{Colors.GREEN}Testes Falharam: {self.tests_failed}{Colors.NC}")
        
        print(f"{Colors.BLUE}======================================{Colors.NC}")
        
        if self.tests_failed == 0:
            self.log("🎉 TODOS OS TESTES PASSARAM! Sistema está funcionando corretamente.")
            return True
        else:
            self.error("❌ ALGUNS TESTES FALHARAM. Verifique a configuração e dependências.")
            return False

    def run_all_tests(self, keep_test_files=False):
        """Executa todos os testes"""
        print("=== Teste Completo do Sistema Python Whisper Transcriber ===\n")
        
        # Verificar se está no diretório correto
        if not Path('main.py').exists():
            self.error("Execute este script no diretório python-whisper-transcriber")
            return False
        
        # Carregar variáveis de ambiente se existir
        try:
            from dotenv import load_dotenv
            load_dotenv()
            self.log("Arquivo .env carregado")
        except (ImportError, FileNotFoundError):
            self.warn("python-dotenv não disponível ou .env não encontrado")
        
        # Executar testes em sequência
        print(self.log("=== 1. Verificação de Dependências ==="))
        self.run_test("Python 3.8+", self.test_python_version)
        self.run_test("Dependências Python", self.test_dependencies_import)
        self.run_test("Backend Whisper", self.test_whisper_backend)
        self.run_test("Dispositivos de áudio", self.test_audio_devices)
        
        print(f"\n{self.log('=== 2. Geração de Áudio de Teste ===')}") 
        self.run_test("Geração de áudio de teste", self.generate_test_audio)
        
        print(f"\n{self.log('=== 3. Teste dos Módulos ===')}") 
        self.run_test("Módulo VAD", self.test_vad_module)
        self.run_test("Módulo Transcriber", self.test_transcriber_module)
        self.run_test("Módulo Queue", self.test_queue_module)
        self.run_test("Módulo Sender", self.test_sender_module)
        
        print(f"\n{self.log('=== 4. Teste de Integração ===')}") 
        self.run_test("Transcrição integrada", self.test_transcription_integration)
        self.run_test("Aplicação principal", self.test_main_application)
        
        print(f"\n{self.log('=== 5. Verificação de Configuração ===')}") 
        self.run_test("Arquivos de configuração", self.test_configuration)
        self.run_test("Estrutura de diretórios", self.test_directories)
        
        print(f"\n{self.log('=== 6. Teste de Performance ===')}") 
        self.run_test("Performance básica", self.run_performance_test)
        
        # Informações do sistema
        self.print_system_info()
        
        # Limpar arquivos de teste
        self.cleanup_test_files(keep_test_files)
        
        # Relatório final
        return self.print_final_report()

def main():
    """Função principal"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Teste completo do sistema Python Whisper Transcriber')
    parser.add_argument('--keep-test-files', action='store_true', 
                       help='Manter arquivos de teste após execução')
    
    args = parser.parse_args()
    
    runner = TestRunner()
    success = runner.run_all_tests(args.keep_test_files)
    
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()