#!/usr/bin/env node

/**
 * Servidor de API Mock para testar o Whisper Transcriber
 * Execute este servidor para simular uma API real durante desenvolvimento/testes
 */

const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3001;
const LOG_FILE = path.join(__dirname, 'api_logs.json');

// Middleware
app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// Logging middleware
app.use((req, res, next) => {
    const timestamp = new Date().toISOString();
    console.log(`${timestamp} ${req.method} ${req.path}`);
    
    // Log to file
    const logEntry = {
        timestamp,
        method: req.method,
        path: req.path,
        headers: req.headers,
        body: req.body,
        query: req.query
    };
    
    // Append to log file
    try {
        let logs = [];
        if (fs.existsSync(LOG_FILE)) {
            const content = fs.readFileSync(LOG_FILE, 'utf8');
            logs = JSON.parse(content);
        }
        logs.push(logEntry);
        
        // Keep only last 100 entries
        if (logs.length > 100) {
            logs = logs.slice(-100);
        }
        
        fs.writeFileSync(LOG_FILE, JSON.stringify(logs, null, 2));
    } catch (err) {
        console.error('Error writing to log file:', err);
    }
    
    next();
});

// Simular autenticação
const authenticateToken = (req, res, next) => {
    const authHeader = req.headers['authorization'];
    const apiKey = req.headers['x-api-key'];
    
    // Aceitar qualquer token para testes (em produção, validar adequadamente)
    if (authHeader && authHeader.startsWith('Bearer ')) {
        req.token = authHeader.substring(7);
        next();
    } else if (apiKey) {
        req.token = apiKey;
        next();
    } else {
        return res.status(401).json({
            error: 'Access denied',
            message: 'Token or API key required',
            timestamp: new Date().toISOString()
        });
    }
};

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({
        status: 'healthy',
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
        version: '1.0.0',
        service: 'Mock Whisper API'
    });
});

// Status endpoint
app.get('/status', authenticateToken, (req, res) => {
    res.json({
        api_status: 'online',
        accepting_transcriptions: true,
        queue_size: Math.floor(Math.random() * 10),
        last_processed: new Date(Date.now() - Math.random() * 60000).toISOString(),
        timestamp: new Date().toISOString()
    });
});

// Main transcription endpoint
app.post('/transcripts', authenticateToken, (req, res) => {
    const { id, timestamp, text, queued_at, attempt } = req.body;
    
    console.log(`📝 Received transcription: "${text}"`);
    
    // Validar campos obrigatórios
    if (!id || !timestamp || !text) {
        return res.status(400).json({
            error: 'Missing required fields',
            required: ['id', 'timestamp', 'text'],
            received: Object.keys(req.body),
            timestamp: new Date().toISOString()
        });
    }
    
    // Simular diferentes cenários baseado no conteúdo
    const textLower = text.toLowerCase();
    
    // Simular erro de servidor
    if (textLower.includes('error') || textLower.includes('fail')) {
        return res.status(500).json({
            error: 'Internal server error',
            message: 'Simulated error for testing',
            timestamp: new Date().toISOString()
        });
    }
    
    // Simular timeout
    if (textLower.includes('timeout') || textLower.includes('slow')) {
        setTimeout(() => {
            res.status(408).json({
                error: 'Request timeout',
                message: 'Simulated timeout for testing',
                timestamp: new Date().toISOString()
            });
        }, 10000);
        return;
    }
    
    // Simular rate limiting
    if (textLower.includes('rate') || textLower.includes('limit')) {
        return res.status(429).json({
            error: 'Too many requests',
            message: 'Rate limit exceeded',
            retry_after: 60,
            timestamp: new Date().toISOString()
        });
    }
    
    // Simular resposta de sucesso
    const response = {
        success: true,
        message: 'Transcription received successfully',
        data: {
            id,
            received_at: new Date().toISOString(),
            processed: true,
            status: 'accepted',
            length: text.length,
            word_count: text.split(' ').length,
            processing_time_ms: Math.floor(Math.random() * 1000) + 100
        },
        metadata: {
            attempt,
            queued_at,
            server_id: 'mock-server-001',
            version: '1.0.0'
        }
    };
    
    // Adicionar delay realista
    setTimeout(() => {
        res.status(201).json(response);
    }, Math.random() * 500 + 100);
});

// Batch endpoint
app.post('/transcripts/batch', authenticateToken, (req, res) => {
    const { transcriptions } = req.body;
    
    if (!Array.isArray(transcriptions)) {
        return res.status(400).json({
            error: 'Invalid batch format',
            message: 'Expected array of transcriptions',
            timestamp: new Date().toISOString()
        });
    }
    
    console.log(`📦 Received batch of ${transcriptions.length} transcriptions`);
    
    const results = transcriptions.map((trans, index) => ({
        id: trans.id,
        status: 'accepted',
        index,
        received_at: new Date().toISOString()
    }));
    
    res.status(201).json({
        success: true,
        message: `Batch of ${transcriptions.length} transcriptions processed`,
        results,
        total: transcriptions.length,
        timestamp: new Date().toISOString()
    });
});

// Analytics endpoint
app.get('/analytics', authenticateToken, (req, res) => {
    const { start_date, end_date } = req.query;
    
    res.json({
        summary: {
            total_transcriptions: Math.floor(Math.random() * 1000) + 500,
            avg_length: Math.floor(Math.random() * 50) + 20,
            success_rate: 0.95 + Math.random() * 0.05,
            avg_processing_time_ms: Math.floor(Math.random() * 500) + 200
        },
        period: {
            start: start_date || new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString(),
            end: end_date || new Date().toISOString()
        },
        timestamp: new Date().toISOString()
    });
});

// Get logs endpoint
app.get('/logs', authenticateToken, (req, res) => {
    try {
        if (fs.existsSync(LOG_FILE)) {
            const logs = JSON.parse(fs.readFileSync(LOG_FILE, 'utf8'));
            res.json({
                logs: logs.slice(-50), // Last 50 entries
                total: logs.length,
                timestamp: new Date().toISOString()
            });
        } else {
            res.json({
                logs: [],
                total: 0,
                timestamp: new Date().toISOString()
            });
        }
    } catch (err) {
        res.status(500).json({
            error: 'Error reading logs',
            message: err.message,
            timestamp: new Date().toISOString()
        });
    }
});

// Clear logs endpoint
app.delete('/logs', authenticateToken, (req, res) => {
    try {
        if (fs.existsSync(LOG_FILE)) {
            fs.unlinkSync(LOG_FILE);
        }
        res.json({
            success: true,
            message: 'Logs cleared',
            timestamp: new Date().toISOString()
        });
    } catch (err) {
        res.status(500).json({
            error: 'Error clearing logs',
            message: err.message,
            timestamp: new Date().toISOString()
        });
    }
});

// Webhook simulation endpoint
app.post('/webhook', (req, res) => {
    console.log('🔔 Webhook received:', req.body);
    
    res.json({
        success: true,
        message: 'Webhook processed',
        timestamp: new Date().toISOString()
    });
});

// 404 handler
app.use('*', (req, res) => {
    res.status(404).json({
        error: 'Endpoint not found',
        available_endpoints: [
            'GET /health',
            'GET /status',
            'POST /transcripts',
            'POST /transcripts/batch', 
            'GET /analytics',
            'GET /logs',
            'DELETE /logs',
            'POST /webhook'
        ],
        timestamp: new Date().toISOString()
    });
});

// Error handler
app.use((err, req, res, next) => {
    console.error('Error:', err);
    
    res.status(500).json({
        error: 'Internal server error',
        message: err.message,
        timestamp: new Date().toISOString()
    });
});

// Start server
app.listen(PORT, () => {
    console.log('🚀 Mock API Server started');
    console.log(`📡 Listening on http://localhost:${PORT}`);
    console.log('📝 Available endpoints:');
    console.log(`   GET  http://localhost:${PORT}/health`);
    console.log(`   GET  http://localhost:${PORT}/status`);
    console.log(`   POST http://localhost:${PORT}/transcripts`);
    console.log(`   POST http://localhost:${PORT}/transcripts/batch`);
    console.log(`   GET  http://localhost:${PORT}/analytics`);
    console.log(`   GET  http://localhost:${PORT}/logs`);
    console.log('');
    console.log('💡 Example usage:');
    console.log(`   curl -X POST http://localhost:${PORT}/transcripts \\`);
    console.log(`     -H "Authorization: Bearer test-token" \\`);
    console.log(`     -H "Content-Type: application/json" \\`);
    console.log(`     -d '{"id":"test","timestamp":"2025-01-20T10:00:00Z","text":"Hello world"}'`);
    console.log('');
    console.log('🔧 Configuration:');
    console.log(`   API_URL=http://localhost:${PORT}/transcripts`);
    console.log(`   API_TOKEN=any-test-token`);
    console.log('');
    console.log('📊 Logs will be saved to:', LOG_FILE);
});

// Graceful shutdown
process.on('SIGINT', () => {
    console.log('\n🛑 Gracefully shutting down...');
    process.exit(0);
});

process.on('SIGTERM', () => {
    console.log('\n🛑 Received SIGTERM, shutting down...');
    process.exit(0);
});