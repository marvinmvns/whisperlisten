FROM node:18-bullseye-slim

# Instalar dependências do sistema
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    wget \
    curl \
    portaudio19-dev \
    libsdl2-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Criar usuário não-root
RUN useradd -m -s /bin/bash transcriber

# Diretório de trabalho
WORKDIR /app

# Copiar package.json primeiro para cache de dependências
COPY package*.json ./
RUN npm ci --only=production

# Copiar código da aplicação
COPY . .

# Criar diretórios necessários
RUN mkdir -p data/temp data/transcripts data/queue logs models

# Compilar whisper.cpp
RUN git clone https://github.com/ggerganov/whisper.cpp.git && \
    cd whisper.cpp && \
    make && \
    chmod +x main

# Download do modelo base (pode ser sobrescrito via volume)
RUN cd models && \
    wget -q https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin

# Ajustar permissões
RUN chown -R transcriber:transcriber /app

# Mudar para usuário não-root
USER transcriber

# Configurar variáveis de ambiente padrão
ENV NODE_ENV=production
ENV WHISPER_PATH=/app/whisper.cpp/main
ENV MODEL_PATH=/app/models/ggml-base.en.bin
ENV LANG=en

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD node index.js status || exit 1

# Volumes para persistência
VOLUME ["/app/data", "/app/logs", "/app/models"]

# Porta (se necessário para API)
EXPOSE 3000

# Comando padrão
CMD ["node", "index.js", "start"]