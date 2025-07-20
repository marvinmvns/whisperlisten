import requests
import time
import threading
import logging
import socket
from datetime import datetime

logger = logging.getLogger(__name__)

class TranscriptSender:
    def __init__(self, queue, config=None):
        self.queue = queue
        self.config = config or {}
        
        # Configurações da API
        self.api_url = self.config.get('api_url')
        self.api_token = self.config.get('api_token')
        
        # Configurações de conectividade
        self.connectivity_check_interval = self.config.get('connectivity_check_interval', 5)  # segundos
        self.send_check_interval = self.config.get('send_check_interval', 2)  # segundos
        self.request_timeout = self.config.get('request_timeout', 10)  # segundos
        self.max_concurrent_sends = self.config.get('max_concurrent_sends', 3)
        
        # Estado
        self.is_online = False
        self.sending_active = False
        self.active_sends = 0
        
        # Threading
        self.stop_flag = threading.Event()
        self.connectivity_thread = None
        self.sender_thread = None
        
        # Configurar session HTTP
        self._setup_http_session()
        
        # Iniciar monitoramento
        self.start()

    def _setup_http_session(self):
        """Configurar sessão HTTP com retry e timeout"""
        self.session = requests.Session()
        
        # Headers padrão
        headers = {
            'Content-Type': 'application/json',
            'User-Agent': 'Python-Whisper-Transcriber/1.0'
        }
        
        if self.api_token:
            headers['Authorization'] = f'Bearer {self.api_token}'
            
        self.session.headers.update(headers)
        
        # Configurar retry strategy
        from requests.adapters import HTTPAdapter
        from urllib3.util.retry import Retry
        
        retry_strategy = Retry(
            total=3,
            backoff_factor=1,
            status_forcelist=[429, 500, 502, 503, 504],
        )
        
        adapter = HTTPAdapter(max_retries=retry_strategy)
        self.session.mount("http://", adapter)
        self.session.mount("https://", adapter)

    def check_connectivity(self):
        """Verificar conectividade com internet e API"""
        try:
            # Teste básico de DNS
            socket.create_connection(('8.8.8.8', 53), timeout=3)
            
            # Teste da API se configurada
            if self.api_url:
                response = self.session.get(
                    f"{self.api_url.rstrip('/')}/health",
                    timeout=3
                )
                return response.status_code < 400
            
            return True
            
        except Exception as e:
            logger.debug(f"Teste de conectividade falhou: {e}")
            return False

    def start(self):
        """Iniciar monitoramento de conectividade e envio"""
        if self.connectivity_thread and self.connectivity_thread.is_alive():
            return
            
        self.stop_flag.clear()
        
        # Thread de monitoramento de conectividade
        self.connectivity_thread = threading.Thread(
            target=self._connectivity_loop, 
            daemon=True
        )
        self.connectivity_thread.start()
        
        # Thread de envio
        self.sender_thread = threading.Thread(
            target=self._sender_loop, 
            daemon=True
        )
        self.sender_thread.start()
        
        logger.info("TranscriptSender iniciado")

    def _connectivity_loop(self):
        """Loop de monitoramento de conectividade"""
        while not self.stop_flag.is_set():
            try:
                was_online = self.is_online
                self.is_online = self.check_connectivity()
                
                if self.is_online != was_online:
                    status = "ONLINE" if self.is_online else "OFFLINE"
                    logger.info(f"Status de conectividade: {status}")
                
                time.sleep(self.connectivity_check_interval)
                
            except Exception as e:
                logger.error(f"Erro no loop de conectividade: {e}")
                time.sleep(self.connectivity_check_interval)

    def _sender_loop(self):
        """Loop principal de envio"""
        while not self.stop_flag.is_set():
            try:
                if self.is_online and self.api_url:
                    self._process_pending_items()
                
                time.sleep(self.send_check_interval)
                
            except Exception as e:
                logger.error(f"Erro no loop de envio: {e}")
                time.sleep(self.send_check_interval)

    def _process_pending_items(self):
        """Processar itens pendentes na fila"""
        # Limitar envios concorrentes
        if self.active_sends >= self.max_concurrent_sends:
            return
            
        # Processar próximo item pendente
        next_item = self.queue.get_next_pending()
        if next_item:
            threading.Thread(
                target=self._send_transcript_thread,
                args=(next_item,),
                daemon=True
            ).start()
        
        # Processar itens para retry
        retry_items = self.queue.get_retryable_items()
        for item in retry_items[:self.max_concurrent_sends - self.active_sends]:
            threading.Thread(
                target=self._send_transcript_thread,
                args=(item,),
                daemon=True
            ).start()

    def _send_transcript_thread(self, item):
        """Thread para envio individual"""
        self.active_sends += 1
        try:
            self._send_transcript(item)
        finally:
            self.active_sends -= 1

    def _send_transcript(self, item):
        """Enviar transcrição individual"""
        if not self.api_url:
            logger.error("API_URL não configurada")
            return
            
        item_id = item['id']
        
        try:
            logger.info(f"Enviando: {item_id}")
            
            # Marcar como enviando
            if not self.queue.mark_as_sending(item_id):
                logger.warning(f"Falha ao marcar como enviando: {item_id}")
                return
            
            # Preparar payload
            payload = {
                'id': item['id'],
                'timestamp': item['transcript_timestamp'],
                'text': item['text'],
                'queued_at': item['timestamp'],
                'attempt': item['attempts']
            }
            
            # Enviar request
            response = self.session.post(
                self.api_url,
                json=payload,
                timeout=self.request_timeout
            )
            
            # Verificar resposta
            response.raise_for_status()
            
            # Sucesso
            response_data = {
                'status': response.status_code,
                'data': response.json() if response.content else None,
                'headers': dict(response.headers)
            }
            
            self.queue.mark_as_sent(item_id, response_data)
            logger.info(f"✓ Enviado: {item_id} ({response.status_code})")
            
        except requests.exceptions.ConnectionError as e:
            logger.warning(f"✗ Erro de conexão: {item_id} - {e}")
            self.is_online = False  # Forçar re-check de conectividade
            self.queue.mark_as_failed(item_id, {
                'type': 'connection_error',
                'message': str(e),
                'timestamp': datetime.now().isoformat()
            })
            
        except requests.exceptions.Timeout as e:
            logger.warning(f"✗ Timeout: {item_id} - {e}")
            self.queue.mark_as_failed(item_id, {
                'type': 'timeout',
                'message': str(e),
                'timestamp': datetime.now().isoformat()
            })
            
        except requests.exceptions.HTTPError as e:
            logger.error(f"✗ Erro HTTP: {item_id} - {e}")
            error_data = {
                'type': 'http_error',
                'status_code': e.response.status_code if e.response else None,
                'message': str(e),
                'timestamp': datetime.now().isoformat()
            }
            
            # Para erros 4xx, não fazer retry (erro permanente)
            if e.response and 400 <= e.response.status_code < 500:
                # Marcar como falha permanente
                for _ in range(self.queue.max_retries):
                    self.queue.mark_as_failed(item_id, error_data)
            else:
                self.queue.mark_as_failed(item_id, error_data)
                
        except Exception as e:
            logger.error(f"✗ Erro inesperado: {item_id} - {e}")
            self.queue.mark_as_failed(item_id, {
                'type': 'unexpected_error',
                'message': str(e),
                'timestamp': datetime.now().isoformat()
            })

    def force_send(self, item_id):
        """Forçar envio de item específico"""
        item = self.queue.get_item(item_id)
        if item and self.is_online:
            threading.Thread(
                target=self._send_transcript_thread,
                args=(item,),
                daemon=True
            ).start()
            return True
        else:
            logger.warning(f"Item {item_id} não encontrado ou sistema offline")
            return False

    def retry_item(self, item_id):
        """Resetar e tentar novamente um item"""
        if self.queue.reset_attempts(item_id):
            logger.info(f"Tentativas resetadas para: {item_id}")
            # Processar imediatamente se online
            if self.is_online:
                item = self.queue.get_item(item_id)
                if item:
                    threading.Thread(
                        target=self._send_transcript_thread,
                        args=(item,),
                        daemon=True
                    ).start()
            return True
        return False

    def get_status(self):
        """Obter status do sender"""
        queue_stats = self.queue.get_stats()
        
        return {
            'online': self.is_online,
            'sending_active': self.sending_active,
            'active_sends': self.active_sends,
            'queue': queue_stats,
            'config': {
                'api_url': self.api_url,
                'has_token': bool(self.api_token),
                'request_timeout': self.request_timeout,
                'max_concurrent_sends': self.max_concurrent_sends
            }
        }

    def test_connection(self):
        """Testar conexão com API"""
        if not self.api_url:
            return {
                'success': False,
                'error': 'API_URL não configurada'
            }
        
        try:
            response = self.session.get(
                f"{self.api_url.rstrip('/')}/health",
                timeout=self.request_timeout
            )
            
            return {
                'success': True,
                'status': response.status_code,
                'data': response.json() if response.content else None,
                'response_time': response.elapsed.total_seconds()
            }
            
        except Exception as e:
            return {
                'success': False,
                'error': str(e)
            }

    def stop(self):
        """Parar sender"""
        logger.info("Parando TranscriptSender...")
        
        self.stop_flag.set()
        
        # Aguardar threads terminarem
        for thread in [self.connectivity_thread, self.sender_thread]:
            if thread and thread.is_alive():
                thread.join(timeout=2)
        
        # Fechar sessão HTTP
        if hasattr(self, 'session'):
            self.session.close()
        
        logger.info("TranscriptSender parado")