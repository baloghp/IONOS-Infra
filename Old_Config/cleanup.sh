#!/bin/bash

# Function to display script usage
show_usage() {
    echo "AI Hub Dev/Prod Cleanup Script"
    echo "------------------------------"
    echo "This script removes Dev and Prod instances (OpenWebUI) while preserving"
    echo "Infrastructure, Automation, and CVForge services."
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -h, --help                 Show this help message"
    echo "  -y, --yes                  Skip confirmation prompts"
    echo "  -d, --dry-run              Show what would be removed without actually removing"
    echo "  -v, --verbose              Show detailed output"
    echo ""
    echo "Examples:"
    echo "  $0                         # Interactive cleanup with confirmations"
    echo "  $0 -y                      # Non-interactive cleanup"
    echo "  $0 -d                      # Dry run - show what would be removed"
    echo "  $0 -v                      # Verbose output"
    echo ""
    echo "This script will remove:"
    echo "  - Dev containers and volumes (OpenWebUI Dev)"
    echo "  - Prod containers and volumes (OpenWebUI Prod, Ollama, Tika)"
    echo "  - Associated Docker images"
    echo ""
    echo "This script will preserve:"
    echo "  - Infrastructure (Caddy, Watchtower)"
    echo "  - Automation (N8N, PostgreSQL)"
    echo "  - CVForge services"
    echo "  - ai-hub-network"
    exit 1
}

# Initialize variables
SKIP_CONFIRM=false
DRY_RUN=false
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            ;;
        -y|--yes)
            SKIP_CONFIRM=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            ;;
    esac
done

# Function to log messages
log() {
    if [ "$VERBOSE" = true ] || [ "$1" = "ERROR" ] || [ "$1" = "WARNING" ]; then
        echo "[$1] $2"
    fi
}

# Function to confirm action
confirm() {
    if [ "$SKIP_CONFIRM" = true ]; then
        return 0
    fi
    
    read -p "$1 [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to display section header
section_header() {
    echo ""
    echo "=== $1 ==="
    echo "----------------------------------------"
}

# Function to execute command with dry-run support
execute() {
    local cmd="$1"
    local description="$2"
    
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Would execute: $cmd"
        echo "[DRY-RUN] Description: $description"
    else
        log "INFO" "$description"
        eval "$cmd"
    fi
}

# Check if we're in the right directory
if [ ! -f "aihub.sh" ]; then
    echo "ERROR: This script must be run from the AI Hub root directory"
    exit 1
fi

# Display current status
section_header "Current System Status"
echo "Running containers:"
docker ps --format "  - {{.Names}} ({{.Image}})" 2>/dev/null || echo "  No running containers"
echo ""
echo "All containers:"
docker ps -a --format "  - {{.Names}} ({{.Image}})" 2>/dev/null || echo "  No containers found"
echo ""
echo "Volumes:"
docker volume ls --format "  - {{.Name}}" 2>/dev/null || echo "  No volumes found"

# Define what to remove
DEV_CONTAINERS=("openwebui-dev")
PROD_CONTAINERS=("openwebui" "ollama" "tika")
DEV_VOLUMES=("openwebui_dev_data" "openwebui_dev_config" "openwebui_dev_uploads" "openwebui_dev_frontend")
PROD_VOLUMES=("openwebui_data" "openwebui_config" "openwebui_uploads" "openwebui_frontend" "ollama_data")
IMAGES_TO_REMOVE=("ghcr.io/open-webui/open-webui:main" "ollama/ollama:latest" "apache/tika:latest")

# Find containers to remove
containers_to_remove=()
for container in "${DEV_CONTAINERS[@]}" "${PROD_CONTAINERS[@]}"; do
    if docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
        containers_to_remove+=("$container")
    fi
done

# Find volumes to remove
volumes_to_remove=()
for volume in "${DEV_VOLUMES[@]}" "${PROD_VOLUMES[@]}"; do
    if docker volume ls --format "{{.Name}}" | grep -q "^${volume}$"; then
        volumes_to_remove+=("$volume")
    fi
done

# Find images to remove
images_to_remove=()
for image in "${IMAGES_TO_REMOVE[@]}"; do
    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${image}$"; then
        images_to_remove+=("$image")
    fi
done

# Display what will be removed
section_header "Items to be Removed"
if [ ${#containers_to_remove[@]} -gt 0 ]; then
    echo "Containers to remove:"
    for container in "${containers_to_remove[@]}"; do
        echo "  - $container"
    done
else
    echo "No containers to remove"
fi

if [ ${#volumes_to_remove[@]} -gt 0 ]; then
    echo ""
    echo "Volumes to remove:"
    for volume in "${volumes_to_remove[@]}"; do
        echo "  - $volume"
    done
else
    echo "No volumes to remove"
fi

if [ ${#images_to_remove[@]} -gt 0 ]; then
    echo ""
    echo "Images to remove:"
    for image in "${images_to_remove[@]}"; do
        echo "  - $image"
    done
else
    echo "No images to remove"
fi

# Check if there's anything to remove
if [ ${#containers_to_remove[@]} -eq 0 ] && [ ${#volumes_to_remove[@]} -eq 0 ] && [ ${#images_to_remove[@]} -eq 0 ]; then
    echo ""
    echo "No Dev/Prod instances found to remove."
    exit 0
fi

# Confirm cleanup
if ! confirm "Do you want to proceed with removing Dev/Prod instances?"; then
    echo "Cleanup cancelled."
    exit 0
fi

# Stop and remove containers
if [ ${#containers_to_remove[@]} -gt 0 ]; then
    section_header "Stopping and Removing Containers"
    for container in "${containers_to_remove[@]}"; do
        execute "docker stop $container" "Stopping container: $container"
        execute "docker rm $container" "Removing container: $container"
    done
fi

# Remove volumes
if [ ${#volumes_to_remove[@]} -gt 0 ]; then
    section_header "Removing Volumes"
    for volume in "${volumes_to_remove[@]}"; do
        execute "docker volume rm $volume" "Removing volume: $volume"
    done
fi

# Remove images
if [ ${#images_to_remove[@]} -gt 0 ]; then
    section_header "Removing Images"
    for image in "${images_to_remove[@]}"; do
        execute "docker rmi $image" "Removing image: $image"
    done
fi

# Clean up any dangling resources
section_header "Cleaning Up Dangling Resources"
execute "docker image prune -f" "Removing dangling images"
execute "docker volume prune -f" "Removing dangling volumes"

# Display final status
section_header "Cleanup Complete"
echo "Remaining containers:"
docker ps -a --format "  - {{.Names}} ({{.Image}})" 2>/dev/null || echo "  No containers found"
echo ""
echo "Remaining volumes:"
docker volume ls --format "  - {{.Name}}" 2>/dev/null || echo "  No volumes found"
echo ""
echo "Remaining images:"
docker images --format "  - {{.Repository}}:{{.Tag}}" 2>/dev/null || echo "  No images found"

echo ""
if [ "$DRY_RUN" = true ]; then
    echo "Dry run completed. No changes were made."
else
    echo "Dev/Prod cleanup completed successfully!"
    echo "Infrastructure, Automation, and CVForge services are preserved."
fi 