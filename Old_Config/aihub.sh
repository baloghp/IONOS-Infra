#!/bin/bash

# Function to display usage
show_usage() {
    echo "Usage: $0 [up|down|show] [infra|automation|cvforge|aiacc|litellm] [service_name]"
    echo ""
    echo "# Infrastructure"
    echo "./aihub.sh up infra"
    echo "./aihub.sh down infra"
    echo "./aihub.sh show infra"
    echo ""
    echo "# Automation (N8N + PostgreSQL)"
    echo "./aihub.sh up automation"
    echo "./aihub.sh down automation"
    echo "./aihub.sh up automation n8n"
    echo "./aihub.sh down automation n8n"
    echo "./aihub.sh show automation"
    echo ""
    echo "# CVForge (CV Processing)"
    echo "./aihub.sh up cvforge"
    echo "./aihub.sh down cvforge"
    echo "./aihub.sh show cvforge"
    echo ""
    echo "# AIACC (AI Act Compliance)"
    echo "./aihub.sh up aiacc"
    echo "./aihub.sh down aiacc"
    echo "./aihub.sh show aiacc"
    echo ""
    echo "# LiteLLM (AI Model Proxy)"
    echo "./aihub.sh up litellm"
    echo "./aihub.sh down litellm"
    echo "./aihub.sh show litellm"
    echo ""
    echo "# Show all services"
    echo "./aihub.sh show"
    echo ""
    echo "Important Notes:"
    echo "  - Infra environment must be running for automation, cvforge, aiacc, and litellm environments"
    echo "  - The script will automatically start Infra if needed when using 'up'"
    exit 1
}

# Function to check if a service is healthy
check_service_health() {
    local service=$1
    local max_attempts=30
    local attempt=1
    local wait_time=2

    echo "Checking health of $service..."
    while [ $attempt -le $max_attempts ]; do
        if docker-compose ps $service | grep -q "healthy"; then
            echo "$service is healthy"
            return 0
        fi
        echo "Attempt $attempt/$max_attempts: Waiting for $service to be healthy..."
        sleep $wait_time
        attempt=$((attempt + 1))
    done
    echo "Error: $service failed to become healthy after $max_attempts attempts"
    return 1
}

# Check if correct number of arguments is provided
if [ $# -lt 1 ]; then
    show_usage
fi

# Parse arguments
ACTION=$1
SUBSYSTEM=$2
SERVICE=$3

# Validate action
if [ "$ACTION" != "up" ] && [ "$ACTION" != "down" ] && [ "$ACTION" != "show" ]; then
    echo "Error: First argument must be 'up', 'down', or 'show'"
    show_usage
fi

# Function to show service status
show_status() {
    local dir=$1
    local subsystem=$2
    
    echo "=== $subsystem Services Status ==="
    cd $dir
    docker-compose ps
    cd ..
    echo "--------------------------------"
}

# If show action, display status and exit
if [ "$ACTION" = "show" ]; then
    if [ -n "$SUBSYSTEM" ]; then
        # Show specific subsystem
        case $SUBSYSTEM in
            "infra")
                show_status "Infra" "Infrastructure"
                ;;
            "automation")
                show_status "Automation" "Automation"
                ;;
            "cvforge")
                show_status "CVForge" "CVForge"
                ;;
            "aiacc")
                show_status "AIACC" "AIACC"
                ;;
            "litellm")
                show_status "LiteLLM" "LiteLLM"
                ;;
            *)
                echo "Error: Invalid subsystem specified"
                show_usage
                ;;
        esac
    else
        # Show all subsystems
        show_status "Infra" "Infrastructure"
        show_status "Automation" "Automation"
        show_status "CVForge" "CVForge"
        show_status "AIACC" "AIACC"
        show_status "LiteLLM" "LiteLLM"
    fi
    exit 0
fi

# Validate subsystem for up/down actions
if [ "$ACTION" != "show" ]; then
    case $SUBSYSTEM in
        "infra"|"automation"|"cvforge"|"aiacc"|"litellm")
            ;;
        *)
            echo "Error: Second argument must be one of: infra, automation, cvforge, aiacc, litellm"
            show_usage
            ;;
    esac
fi

# First, ensure all required directories exist
echo "Creating necessary directories..."
mkdir -p Infra Automation CVForge AIACC LiteLLM

# Check if .env exists
if [ ! -f .env ]; then
    echo "Error: .env file not found"
    exit 1
fi

# Check if SSL certificate files exist
if [ ! -f "Infra/bundle.pem" ]; then
    echo "Error: SSL certificate file (Infra/bundle.pem) not found"
    exit 1
fi
if [ ! -f "Infra/private.key" ]; then
    echo "Error: SSL private key file (Infra/private.key) not found"
    exit 1
fi

# Set permissions on .env file
echo "Setting secure permissions on .env file..."
sudo chown root:988 .env
sudo chmod 640 .env

# Set permissions on SSL certificate files
echo "Setting secure permissions on SSL certificate files..."
sudo chown root:988 Infra/bundle.pem
sudo chmod 600 Infra/bundle.pem
sudo chown root:988 Infra/private.key
sudo chmod 600 Infra/private.key

# Create symbolic links to .env file in each subsystem folder
echo "Creating symbolic links to .env file..."
ln -sf ../.env Infra/.env
ln -sf ../.env Automation/.env
ln -sf ../.env CVForge/.env
ln -sf ../.env AIACC/.env
ln -sf ../.env LiteLLM/.env

# Set permissions on symlinks
echo "Setting secure permissions on .env symlinks..."
sudo chown root:988 */\.env
sudo chmod 640 */\.env

# Create the Docker network if bringing up services
if [ "$ACTION" = "up" ]; then
    echo "Creating Docker network..."
    if ! docker network inspect ai-hub-network >/dev/null 2>&1; then
        docker network create --driver bridge --ipv6 --subnet=172.20.0.0/16 ai-hub-network || {
            echo "Error: Failed to create Docker network"
            exit 1
        }
        echo "Network ai-hub-network created successfully"
    else
        echo "Network ai-hub-network already exists"
    fi
fi

# Function to manage services
manage_services() {
    local dir=$1
    local action=$2
    local service=$3
    
    cd $dir
    if [ -n "$service" ]; then
        echo "$action service $service in $dir..."
        if [ "$action" = "up" ]; then
            docker-compose $action -d $service
        else
            docker-compose $action $service
        fi
    else
        echo "$action all services in $dir..."
        if [ "$action" = "up" ]; then
            docker-compose $action -d
        else
            docker-compose $action
        fi
    fi
    cd ..
}

# For 'up' action, ensure Infra is running first
if [ "$ACTION" = "up" ] && [ "$SUBSYSTEM" != "infra" ]; then
    echo "Checking Infra environment..."
    cd Infra
    if ! docker-compose ps | grep -q "Up"; then
        echo "Starting Infra environment first..."
        docker-compose up -d
        # Wait for Caddy to be healthy
        check_service_health "caddy" || {
            echo "Error: Infra environment failed to start properly"
            exit 1
        }
    fi
    cd ..
fi

# Manage services based on subsystem
case $SUBSYSTEM in
    "infra")
        manage_services "Infra" "$ACTION" "$SERVICE"
        ;;
    "automation")
        manage_services "Automation" "$ACTION" "$SERVICE"
        ;;
    "cvforge")
        manage_services "CVForge" "$ACTION" "$SERVICE"
        ;;
    "aiacc")
        manage_services "AIACC" "$ACTION" "$SERVICE"
        ;;
    "litellm")
        manage_services "LiteLLM" "$ACTION" "$SERVICE"
        ;;
esac

echo "Operation completed!"