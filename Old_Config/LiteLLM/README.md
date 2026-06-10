# LiteLLM Service

LiteLLM is a unified API for accessing various AI models through a single endpoint. This service provides a web UI for easy model management.

## Features

- **Web UI Management**: Add, edit, and remove models through the web interface
- **Database-driven**: Models and API keys stored securely in PostgreSQL
- **Unified API**: Access multiple AI providers through one endpoint
- **Built-in Testing**: Test models directly in the web interface

## Quick Start

### 1. Start the Service

```bash
# Start LiteLLM (includes PostgreSQL)
./aihub.sh up litellm

# Check status
./aihub.sh show litellm
```

### 2. Access the Web UI

Open your browser and go to: **https://proxy.ittd.app**

### 3. Add Models

1. Navigate to the **Models** section in the web UI
2. Click **Add Model** to configure your AI models
3. Enter your API keys securely
4. Test your models using the built-in interface

## Web UI Features

- **Model Management**: Add, edit, delete models
- **API Key Storage**: Securely store provider API keys
- **Model Testing**: Test models before using them
- **Usage Monitoring**: Track API usage and costs
- **API Documentation**: Built-in documentation

## Access Points

- **Web Interface**: https://proxy.ittd.app
- **API Documentation**: https://proxy.ittd.app/docs
- **Health Check**: https://proxy.ittd.app/health

## API Usage

After setting up your models through the web UI, you can use the chat completion API:

```bash
curl -X POST "https://proxy.ittd.app/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-3.5-turbo",
    "messages": [
      {"role": "user", "content": "Hello, how are you?"}
    ]
  }'
```

**Note**: No API key needed in the request - authentication is handled by the web UI configuration.

## Troubleshooting

### Check Service Status

```bash
# View service status
./aihub.sh show litellm

# View logs
docker logs litellm
docker logs litellm-postgres
```

### Reset Database

```bash
# Stop service
./aihub.sh down litellm

# Remove volume
docker volume rm litellm_litellm-postgres-data

# Start service (will recreate database)
./aihub.sh up litellm
```

## Configuration

The service uses:
- **PostgreSQL**: For storing models and configurations
- **Web UI**: For all model management
- **Persistent Storage**: Database survives container restarts

No manual configuration files or environment variables needed - everything is managed through the web interface!
