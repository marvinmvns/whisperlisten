#!/usr/bin/env python3

"""
Servidor de API Mock para testar o Whisper Transcriber (versão Python)
Execute este servidor para simular uma API real durante desenvolvimento/testes
"""

import json
import time
import random
import logging
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional

from flask import Flask, request, jsonify
from flask_cors import CORS

# Configurar logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

# Configurações
LOG_FILE = Path(__file__).parent / 'api_logs.json'
MAX_LOG_ENTRIES = 100

class MockAPI:
    def __init__(self):
        self.start_time = datetime.now()
        self.request_count = 0
        self.logs = []
        
    def log_request(self, method: str, path: str, headers: Dict, body: Dict, query: Dict):
        """Log da requisição"""
        self.request_count += 1
        
        log_entry = {
            'timestamp': datetime.now().isoformat(),
            'method': method,
            'path': path,
            'headers': dict(headers),
            'body': body,
            'query': query,
            'request_id': self.request_count
        }
        
        self.logs.append(log_entry)
        
        # Manter apenas as últimas N entradas
        if len(self.logs) > MAX_LOG_ENTRIES:
            self.logs = self.logs[-MAX_LOG_ENTRIES:]
        
        # Salvar em arquivo
        try:
            with open(LOG_FILE, 'w') as f:
                json.dump(self.logs, f, indent=2, default=str)
        except Exception as e:
            logger.error(f"Erro ao salvar logs: {e}")
    
    def authenticate_request(self, headers: Dict) -> Optional[str]:
        """Simular autenticação"""
        auth_header = headers.get('Authorization', '')
        api_key = headers.get('X-API-Key', '')
        
        if auth_header.startswith('Bearer '):
            return auth_header[7:]
        elif api_key:
            return api_key
        
        return None

# Instância global
mock_api = MockAPI()

@app.before_request
def before_request():
    """Middleware para logging"""
    mock_api.log_request(
        method=request.method,
        path=request.path,
        headers=request.headers,
        body=request.get_json(silent=True) or {},
        query=request.args.to_dict()
    )
    
    logger.info(f"{request.method} {request.path}")

def require_auth(f):
    """Decorator para autenticação"""
    def decorated_function(*args, **kwargs):
        token = mock_api.authenticate_request(request.headers)
        if not token:
            return jsonify({
                'error': 'Access denied',
                'message': 'Token or API key required',
                'timestamp': datetime.now().isoformat()
            }), 401
        
        request.token = token
        return f(*args, **kwargs)
    
    decorated_function.__name__ = f.__name__
    return decorated_function

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    uptime = (datetime.now() - mock_api.start_time).total_seconds()
    
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'uptime': uptime,
        'version': '1.0.0',
        'service': 'Mock Whisper API (Python)',
        'requests_processed': mock_api.request_count
    })

@app.route('/status', methods=['GET'])
@require_auth
def api_status():
    """Status endpoint"""
    return jsonify({
        'api_status': 'online',
        'accepting_transcriptions': True,
        'queue_size': random.randint(0, 10),
        'last_processed': (datetime.now() - timedelta(seconds=random.randint(0, 60))).isoformat(),
        'timestamp': datetime.now().isoformat(),
        'uptime': (datetime.now() - mock_api.start_time).total_seconds(),
        'total_requests': mock_api.request_count
    })

@app.route('/transcripts', methods=['POST'])
@require_auth
def receive_transcription():
    """Endpoint principal para receber transcrições"""
    data = request.get_json()
    
    if not data:
        return jsonify({
            'error': 'No JSON data provided',
            'timestamp': datetime.now().isoformat()
        }), 400
    
    # Extrair campos
    transcript_id = data.get('id')
    timestamp = data.get('timestamp')
    text = data.get('text')
    queued_at = data.get('queued_at')
    attempt = data.get('attempt', 1)
    
    logger.info(f"📝 Received transcription: \"{text}\"")
    
    # Validar campos obrigatórios
    if not all([transcript_id, timestamp, text]):
        return jsonify({
            'error': 'Missing required fields',
            'required': ['id', 'timestamp', 'text'],
            'received': list(data.keys()),
            'timestamp': datetime.now().isoformat()
        }), 400
    
    # Simular diferentes cenários baseado no conteúdo
    text_lower = text.lower()
    
    # Simular erro de servidor
    if 'error' in text_lower or 'fail' in text_lower:
        return jsonify({
            'error': 'Internal server error',
            'message': 'Simulated error for testing',
            'timestamp': datetime.now().isoformat()
        }), 500
    
    # Simular timeout (não implementado em Flask, mas retornamos erro)
    if 'timeout' in text_lower or 'slow' in text_lower:
        time.sleep(2)  # Simular lentidão
        return jsonify({
            'error': 'Request timeout',
            'message': 'Simulated timeout for testing',
            'timestamp': datetime.now().isoformat()
        }), 408
    
    # Simular rate limiting
    if 'rate' in text_lower or 'limit' in text_lower:
        return jsonify({
            'error': 'Too many requests',
            'message': 'Rate limit exceeded',
            'retry_after': 60,
            'timestamp': datetime.now().isoformat()
        }), 429
    
    # Simular resposta de sucesso
    processing_time = random.randint(100, 1000)
    
    response = {
        'success': True,
        'message': 'Transcription received successfully',
        'data': {
            'id': transcript_id,
            'received_at': datetime.now().isoformat(),
            'processed': True,
            'status': 'accepted',
            'length': len(text),
            'word_count': len(text.split()),
            'processing_time_ms': processing_time
        },
        'metadata': {
            'attempt': attempt,
            'queued_at': queued_at,
            'server_id': 'mock-server-python-001',
            'version': '1.0.0',
            'request_id': mock_api.request_count
        }
    }
    
    # Adicionar delay realista
    time.sleep(random.uniform(0.1, 0.5))
    
    return jsonify(response), 201

@app.route('/transcripts/batch', methods=['POST'])
@require_auth
def receive_batch():
    """Endpoint para receber lote de transcrições"""
    data = request.get_json()
    
    if not data or 'transcriptions' not in data:
        return jsonify({
            'error': 'Invalid batch format',
            'message': 'Expected object with transcriptions array',
            'timestamp': datetime.now().isoformat()
        }), 400
    
    transcriptions = data['transcriptions']
    
    if not isinstance(transcriptions, list):
        return jsonify({
            'error': 'Invalid batch format',
            'message': 'transcriptions must be an array',
            'timestamp': datetime.now().isoformat()
        }), 400
    
    logger.info(f"📦 Received batch of {len(transcriptions)} transcriptions")
    
    results = []
    for index, trans in enumerate(transcriptions):
        results.append({
            'id': trans.get('id', f'batch_item_{index}'),
            'status': 'accepted',
            'index': index,
            'received_at': datetime.now().isoformat()
        })
    
    return jsonify({
        'success': True,
        'message': f'Batch of {len(transcriptions)} transcriptions processed',
        'results': results,
        'total': len(transcriptions),
        'timestamp': datetime.now().isoformat()
    }), 201

@app.route('/analytics', methods=['GET'])
@require_auth
def analytics():
    """Endpoint de analytics"""
    start_date = request.args.get('start_date')
    end_date = request.args.get('end_date')
    
    # Dados simulados
    return jsonify({
        'summary': {
            'total_transcriptions': random.randint(500, 1000),
            'avg_length': random.randint(20, 70),
            'success_rate': round(0.95 + random.random() * 0.05, 3),
            'avg_processing_time_ms': random.randint(200, 700)
        },
        'period': {
            'start': start_date or (datetime.now() - timedelta(days=7)).isoformat(),
            'end': end_date or datetime.now().isoformat()
        },
        'timestamp': datetime.now().isoformat()
    })

@app.route('/logs', methods=['GET'])
@require_auth
def get_logs():
    """Obter logs das requisições"""
    limit = int(request.args.get('limit', 50))
    
    return jsonify({
        'logs': mock_api.logs[-limit:],
        'total': len(mock_api.logs),
        'timestamp': datetime.now().isoformat()
    })

@app.route('/logs', methods=['DELETE'])
@require_auth
def clear_logs():
    """Limpar logs"""
    mock_api.logs.clear()
    
    try:
        if LOG_FILE.exists():
            LOG_FILE.unlink()
    except Exception as e:
        logger.error(f"Erro ao remover arquivo de log: {e}")
    
    return jsonify({
        'success': True,
        'message': 'Logs cleared',
        'timestamp': datetime.now().isoformat()
    })

@app.route('/webhook', methods=['POST'])
def webhook():
    """Simular endpoint de webhook"""
    data = request.get_json()
    logger.info(f"🔔 Webhook received: {data}")
    
    return jsonify({
        'success': True,
        'message': 'Webhook processed',
        'timestamp': datetime.now().isoformat()
    })

@app.errorhandler(404)
def not_found(error):
    """Handler para 404"""
    return jsonify({
        'error': 'Endpoint not found',
        'available_endpoints': [
            'GET /health',
            'GET /status', 
            'POST /transcripts',
            'POST /transcripts/batch',
            'GET /analytics',
            'GET /logs',
            'DELETE /logs',
            'POST /webhook'
        ],
        'timestamp': datetime.now().isoformat()
    }), 404

@app.errorhandler(500)
def internal_error(error):
    """Handler para erros 500"""
    logger.error(f"Internal error: {error}")
    
    return jsonify({
        'error': 'Internal server error',
        'message': str(error),
        'timestamp': datetime.now().isoformat()
    }), 500

def main():
    """Função principal"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Mock API Server para Whisper Transcriber')
    parser.add_argument('--host', default='localhost', help='Host para bind (padrão: localhost)')
    parser.add_argument('--port', type=int, default=3001, help='Porta para bind (padrão: 3001)')
    parser.add_argument('--debug', action='store_true', help='Executar em modo debug')
    
    args = parser.parse_args()
    
    print("🚀 Mock API Server (Python) started")
    print(f"📡 Listening on http://{args.host}:{args.port}")
    print("📝 Available endpoints:")
    print(f"   GET  http://{args.host}:{args.port}/health")
    print(f"   GET  http://{args.host}:{args.port}/status")
    print(f"   POST http://{args.host}:{args.port}/transcripts")
    print(f"   POST http://{args.host}:{args.port}/transcripts/batch")
    print(f"   GET  http://{args.host}:{args.port}/analytics")
    print(f"   GET  http://{args.host}:{args.port}/logs")
    print("")
    print("💡 Example usage:")
    print(f"   curl -X POST http://{args.host}:{args.port}/transcripts \\")
    print(f"     -H \"Authorization: Bearer test-token\" \\")
    print(f"     -H \"Content-Type: application/json\" \\")
    print(f"     -d '{{\"id\":\"test\",\"timestamp\":\"2025-01-20T10:00:00Z\",\"text\":\"Hello world\"}}'")
    print("")
    print("🔧 Configuration:")
    print(f"   API_URL=http://{args.host}:{args.port}/transcripts")
    print(f"   API_TOKEN=any-test-token")
    print("")
    print(f"📊 Logs will be saved to: {LOG_FILE}")
    print("")
    
    try:
        app.run(host=args.host, port=args.port, debug=args.debug)
    except KeyboardInterrupt:
        print("\n🛑 Gracefully shutting down...")

if __name__ == '__main__':
    main()