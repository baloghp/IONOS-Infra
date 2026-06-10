# ITTD AI Hub

A comprehensive AI chat and automation platform using OpenWebUI, Ollama, and N8N.

## Prerequisites

- Docker and Docker Compose
- SSL certificates for HTTPS (see SSL Setup section)
- OpenRouter API key
- Gmail account for N8N notifications (optional)

## SSL Setup

The platform requires SSL certificates for secure HTTPS connections. Place your SSL certificates in the `Infra` directory:

- `bundle.pem`: Your SSL certificate chain
- `private.key`: Your private key

These files are required for the Caddy reverse proxy to handle HTTPS connections.

### Caddy Configuration

1. Copy the sample Caddyfile:

   ```bash
   cp Infra/Caddyfile.sample Infra/Caddyfile
   ```

2. Review and modify the Caddyfile as needed:
   - Update domain names
   - Adjust security headers
   - Modify logging configuration
   - Enable/disable debug mode

The Caddyfile includes:

- HTTPS configuration with custom certificates
- Reverse proxy settings for all services
- Security headers
- Health checks
- Logging configuration

## Environment Setup

1. Copy the sample environment file:

   ```bash
   cp .env.sample .env
   ```

2. Edit the `.env` file with your configuration:
   - Database credentials
   - OpenRouter API key
   - N8N settings
   - SMTP configuration (if using email notifications)

## Directory Structure

```
.
├── Automation/     # N8N automation workflows
├── Dev/           # Development environment
├── Infra/         # Infrastructure (Caddy, SSL)
└── Prod/          # Production environment
```

## Services

- **OpenWebUI**: AI chat interface
- **Ollama**: Local AI model hosting and RAG
- **N8N**: Workflow automation
- **Caddy**: Reverse proxy with SSL
- **PostgreSQL**: Database for N8N

## Service Management

The platform includes a management script (`aihub.sh`) for secure and consistent service operations.

### Basic Usage

```bash
./aihub.sh [up|down|show] [infra|prod|dev|automation] [service_name]
```

### Examples

1. Start all production services:

   ```bash
   ./aihub.sh up prod
   ```

2. Stop development environment:

   ```bash
   ./aihub.sh down dev
   ```

3. Start specific service (e.g., Ollama):

   ```bash
   ./aihub.sh up prod ollama
   ```

4. Stop specific service (e.g., N8N):

   ```bash
   ./aihub.sh down automation n8n
   ```

5. Show status of all services:

   ```bash
   ./aihub.sh show
   ```

6. Show status of specific subsystem:

   ```bash
   ./aihub.sh show prod
   ```

### Security Features

The script includes several security measures:

- Sets secure permissions on sensitive files
- Creates isolated Docker network
- Validates SSL certificates
- Manages environment variables securely

## Security Notes

- SSL certificates and private keys are not tracked in git
- Environment variables should be kept secure
- Regular backups of the database are recommended
- Use the provided `aihub.sh` script for service management
- Review and customize Caddyfile security headers

## Maintenance

- Use `./aihub.sh show` to check service status
- Monitor disk space for Docker volumes
- Keep SSL certificates up to date
- Use the management script for all service operations
- Review Caddy logs for security issues

## Support

For issues or questions, please contact the system administrator.