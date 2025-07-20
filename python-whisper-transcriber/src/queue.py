import sqlite3
import json
import time
import threading
import logging
from datetime import datetime, timedelta
from pathlib import Path

logger = logging.getLogger(__name__)

class TranscriptQueue:
    def __init__(self, config=None):
        self.config = config or {}
        
        # Configurações
        self.queue_dir = Path(self.config.get('queue_dir', './data/queue'))
        self.queue_dir.mkdir(parents=True, exist_ok=True)
        
        self.db_path = self.queue_dir / 'queue.db'
        self.lock = threading.RLock()
        
        # Configurações de retry
        self.max_retries = self.config.get('max_retries', 5)
        self.base_retry_delay = self.config.get('base_retry_delay', 1)  # segundos
        self.max_retry_delay = self.config.get('max_retry_delay', 300)  # 5 minutos
        
        # Inicializar banco
        self._init_database()

    def _init_database(self):
        """Inicializar banco de dados SQLite"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.execute('''
                    CREATE TABLE IF NOT EXISTS transcript_queue (
                        id TEXT PRIMARY KEY,
                        timestamp TEXT NOT NULL,
                        text TEXT NOT NULL,
                        file_path TEXT NOT NULL,
                        transcript_timestamp TEXT NOT NULL,
                        status TEXT NOT NULL DEFAULT 'pending',
                        attempts INTEGER DEFAULT 0,
                        last_attempt TEXT,
                        last_error TEXT,
                        next_retry TEXT,
                        created_at TEXT NOT NULL,
                        sent_at TEXT,
                        response TEXT
                    )
                ''')
                
                conn.execute('''
                    CREATE INDEX IF NOT EXISTS idx_status ON transcript_queue(status)
                ''')
                
                conn.execute('''
                    CREATE INDEX IF NOT EXISTS idx_next_retry ON transcript_queue(next_retry)
                ''')
                
                conn.commit()
                logger.info("Banco de dados inicializado")
                
        except Exception as e:
            logger.error(f"Erro ao inicializar banco: {e}")
            raise

    def add_transcript(self, transcript_data):
        """Adicionar transcrição à fila"""
        item_id = self._generate_id()
        now = datetime.now().isoformat()
        
        queue_item = {
            'id': item_id,
            'timestamp': now,
            'text': transcript_data['text'],
            'file_path': transcript_data['file'],
            'transcript_timestamp': transcript_data['timestamp'],
            'status': 'pending',
            'attempts': 0,
            'created_at': now
        }
        
        try:
            with self.lock, sqlite3.connect(self.db_path) as conn:
                conn.execute('''
                    INSERT INTO transcript_queue 
                    (id, timestamp, text, file_path, transcript_timestamp, status, attempts, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ''', (
                    queue_item['id'],
                    queue_item['timestamp'],
                    queue_item['text'],
                    queue_item['file_path'],
                    queue_item['transcript_timestamp'],
                    queue_item['status'],
                    queue_item['attempts'],
                    queue_item['created_at']
                ))
                conn.commit()
                
            logger.info(f"Adicionado à fila: {item_id}")
            return queue_item
            
        except Exception as e:
            logger.error(f"Erro ao adicionar à fila: {e}")
            raise

    def _generate_id(self):
        """Gerar ID único"""
        import uuid
        return str(uuid.uuid4())[:8]

    def get_next_pending(self):
        """Obter próximo item pendente (FIFO)"""
        try:
            with self.lock, sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.execute('''
                    SELECT * FROM transcript_queue 
                    WHERE status = 'pending' 
                    ORDER BY created_at ASC 
                    LIMIT 1
                ''')
                row = cursor.fetchone()
                return dict(row) if row else None
                
        except Exception as e:
            logger.error(f"Erro ao buscar próximo pendente: {e}")
            return None

    def get_all_pending(self):
        """Obter todos os itens pendentes"""
        try:
            with self.lock, sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.execute('''
                    SELECT * FROM transcript_queue 
                    WHERE status = 'pending' 
                    ORDER BY created_at ASC
                ''')
                return [dict(row) for row in cursor.fetchall()]
                
        except Exception as e:
            logger.error(f"Erro ao buscar pendentes: {e}")
            return []

    def get_retryable_items(self):
        """Obter itens prontos para retry"""
        now = datetime.now().isoformat()
        
        try:
            with self.lock, sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.execute('''
                    SELECT * FROM transcript_queue 
                    WHERE status = 'pending' 
                    AND attempts > 0 
                    AND attempts < ?
                    AND (next_retry IS NULL OR next_retry <= ?)
                    ORDER BY created_at ASC
                ''', (self.max_retries, now))
                return [dict(row) for row in cursor.fetchall()]
                
        except Exception as e:
            logger.error(f"Erro ao buscar retryable: {e}")
            return []

    def mark_as_sending(self, item_id):
        """Marcar item como sendo enviado"""
        now = datetime.now().isoformat()
        
        try:
            with self.lock, sqlite3.connect(self.db_path) as conn:
                cursor = conn.execute('''
                    UPDATE transcript_queue 
                    SET status = 'sending', 
                        attempts = attempts + 1,
                        last_attempt = ?
                    WHERE id = ?
                ''', (now, item_id))
                
                if cursor.rowcount > 0:
                    conn.commit()
                    logger.debug(f"Marcado como enviando: {item_id}")
                    return True
                else:
                    logger.warning(f"Item não encontrado para marcar como enviando: {item_id}")
                    return False
                    
        except Exception as e:
            logger.error(f"Erro ao marcar como enviando: {e}")
            return False

    def mark_as_sent(self, item_id, response=None):
        """Marcar item como enviado com sucesso"""
        now = datetime.now().isoformat()
        response_json = json.dumps(response) if response else None
        
        try:
            with self.lock, sqlite3.connect(self.db_path) as conn:
                cursor = conn.execute('''
                    UPDATE transcript_queue 
                    SET status = 'sent',
                        sent_at = ?,
                        response = ?
                    WHERE id = ?
                ''', (now, response_json, item_id))
                
                if cursor.rowcount > 0:
                    conn.commit()
                    logger.info(f"Item enviado com sucesso: {item_id}")
                    return True
                else:
                    logger.warning(f"Item não encontrado para marcar como enviado: {item_id}")
                    return False
                    
        except Exception as e:
            logger.error(f"Erro ao marcar como enviado: {e}")
            return False

    def mark_as_failed(self, item_id, error=None):
        """Marcar item como falhado"""
        now = datetime.now().isoformat()
        error_json = json.dumps(error) if error else None
        
        try:
            with self.lock, sqlite3.connect(self.db_path) as conn:
                # Obter tentativas atuais
                cursor = conn.execute('SELECT attempts FROM transcript_queue WHERE id = ?', (item_id,))
                row = cursor.fetchone()
                
                if not row:
                    logger.warning(f"Item não encontrado para marcar como falhado: {item_id}")
                    return False
                
                attempts = row[0]
                
                # Calcular próximo retry com backoff exponencial
                delay = min(self.base_retry_delay * (2 ** (attempts - 1)), self.max_retry_delay)
                next_retry = (datetime.now() + timedelta(seconds=delay)).isoformat()
                
                # Atualizar status
                if attempts >= self.max_retries:
                    # Falha permanente
                    conn.execute('''
                        UPDATE transcript_queue 
                        SET status = 'failed_permanent',
                            last_error = ?
                        WHERE id = ?
                    ''', (error_json, item_id))
                    logger.error(f"Item falhou permanentemente: {item_id} (tentativas: {attempts})")
                else:
                    # Retry disponível
                    conn.execute('''
                        UPDATE transcript_queue 
                        SET status = 'pending',
                            last_error = ?,
                            next_retry = ?
                        WHERE id = ?
                    ''', (error_json, next_retry, item_id))
                    logger.warning(f"Item falhado, retry em {delay}s: {item_id} (tentativa {attempts})")
                
                conn.commit()
                return True
                
        except Exception as e:
            logger.error(f"Erro ao marcar como falhado: {e}")
            return False

    def get_stats(self):
        """Obter estatísticas da fila"""
        try:
            with self.lock, sqlite3.connect(self.db_path) as conn:
                cursor = conn.execute('''
                    SELECT 
                        status,
                        COUNT(*) as count
                    FROM transcript_queue 
                    GROUP BY status
                ''')
                
                stats = {}
                for row in cursor.fetchall():
                    stats[row[0]] = row[1]
                
                # Garantir que todas as categorias existam
                return {
                    'pending': stats.get('pending', 0),
                    'sending': stats.get('sending', 0),
                    'sent': stats.get('sent', 0),
                    'failed_permanent': stats.get('failed_permanent', 0),
                    'total': sum(stats.values())
                }
                
        except Exception as e:
            logger.error(f"Erro ao obter estatísticas: {e}")
            return {'pending': 0, 'sending': 0, 'sent': 0, 'failed_permanent': 0, 'total': 0}

    def reset_attempts(self, item_id):
        """Resetar tentativas de um item"""
        try:
            with self.lock, sqlite3.connect(self.db_path) as conn:
                cursor = conn.execute('''
                    UPDATE transcript_queue 
                    SET attempts = 0,
                        status = 'pending',
                        last_error = NULL,
                        next_retry = NULL
                    WHERE id = ?
                ''', (item_id,))
                
                if cursor.rowcount > 0:
                    conn.commit()
                    logger.info(f"Tentativas resetadas: {item_id}")
                    return True
                else:
                    logger.warning(f"Item não encontrado para reset: {item_id}")
                    return False
                    
        except Exception as e:
            logger.error(f"Erro ao resetar tentativas: {e}")
            return False

    def cleanup_old_items(self, days_old=30):
        """Limpar itens antigos"""
        cutoff_date = (datetime.now() - timedelta(days=days_old)).isoformat()
        
        try:
            with self.lock, sqlite3.connect(self.db_path) as conn:
                cursor = conn.execute('''
                    DELETE FROM transcript_queue 
                    WHERE status = 'sent' 
                    AND sent_at < ?
                ''', (cutoff_date,))
                
                removed_count = cursor.rowcount
                conn.commit()
                
                if removed_count > 0:
                    logger.info(f"Removidos {removed_count} itens enviados antigos")
                
                return removed_count
                
        except Exception as e:
            logger.error(f"Erro na limpeza: {e}")
            return 0

    def list_all(self, limit=100):
        """Listar todos os itens (para debug)"""
        try:
            with self.lock, sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.execute('''
                    SELECT * FROM transcript_queue 
                    ORDER BY created_at DESC 
                    LIMIT ?
                ''', (limit,))
                return [dict(row) for row in cursor.fetchall()]
                
        except Exception as e:
            logger.error(f"Erro ao listar todos: {e}")
            return []

    def get_item(self, item_id):
        """Obter item específico"""
        try:
            with self.lock, sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.execute('''
                    SELECT * FROM transcript_queue WHERE id = ?
                ''', (item_id,))
                row = cursor.fetchone()
                return dict(row) if row else None
                
        except Exception as e:
            logger.error(f"Erro ao obter item: {e}")
            return None