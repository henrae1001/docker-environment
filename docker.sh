#!/bin/bash

# Default values
IMAGE_NAME="aoc2026-env"
CONTAINER_NAME="aoc2026-container"
USERNAME="user"
HOSTNAME="aoc2026"
# MOUNT_PATHS=()

# Print usage information
usage() {
    echo "Usage: $0 {run|clean|rebuild} [options]"
    echo "Options:"
    echo "  --image-name NAME     Specify Docker image name (default: $IMAGE_NAME)"
    echo "  --cont-name NAME      Specify Docker container name (default: $CONTAINER_NAME)"
    echo "  --username NAME       Specify username for container (default: $USERNAME)"
    echo "  --hostname NAME       Specify hostname for container (default: $HOSTNAME)"
    echo "  --mount PATH          Specify directory path to mount (can be used multiple times)"
    echo "Examples:"
    echo "  $0 run --username user --mount /path1 --mount /path2 --image-name myimage --cont-name mycont"
    echo "  $0 clean"
    echo "  $0 rebuild"
    exit 1
}

# Check if Docker is installed
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker is not installed. Please install Docker first."
        exit 1
    fi
}

# Check if image exists
check_image() {
    docker image inspect "$IMAGE_NAME" &> /dev/null
    return $?
}

# Build Docker image
build_image() {
    if check_image; then
        echo "Image '$IMAGE_NAME' already exists."
        echo "To delete it, run: docker image rm $IMAGE_NAME"
        return 1
    else
        echo "Building Docker image '$IMAGE_NAME'..."
        if docker build -t "$IMAGE_NAME" .; then
            echo "Image '$IMAGE_NAME' built successfully."
            return 0
        else
            echo "Failed to build image '$IMAGE_NAME'."
            exit 1
        fi
    fi
}

# Check container status
check_container_status() {
    if docker ps -q -f name="$CONTAINER_NAME" | grep -q .; then
        echo "running"
    elif docker ps -aq -f name="$CONTAINER_NAME" | grep -q .; then
        echo "stopped"
    else
        echo "not_existed"
    fi
}

# Run or manage container
run_container() {
    local status=$(check_container_status)
    local mount_args=""

    # Prepare mount arguments
    for path in "${MOUNT_PATHS[@]}"; do
        if [ -d "$path" ]; then
            mount_args="$mount_args -v $(realpath "$path"):/mnt/$(basename "$path")"
        else
            echo "Warning: Mount path '$path' does not exist, skipping."
        fi
    done

    case $status in
        "running")
            echo "Container '$CONTAINER_NAME' is already running. Entering container..."
            docker exec -it -u "$USERNAME" "$CONTAINER_NAME" bash
            ;;
        "stopped")
            echo "Container '$CONTAINER_NAME' is stopped. Starting container..."
            docker start "$CONTAINER_NAME"
            docker exec -it -u "$USERNAME" "$CONTAINER_NAME" bash
            ;;
        "not_existed")
            echo "Container '$CONTAINER_NAME' does not exist. Creating and starting container..."
            docker run -it --name "$CONTAINER_NAME" --hostname "$HOSTNAME" -u "$USERNAME" $mount_args "$IMAGE_NAME" bash
            ;;
    esac
}

# Clean containers and image
clean() {
    echo "Cleaning up containers and image..."
    # Stop and remove container if it exists
    if docker ps -aq -f name="$CONTAINER_NAME" | grep -q .; then
        docker stop "$CONTAINER_NAME" &> /dev/null
        docker rm "$CONTAINER_NAME" &> /dev/null
        echo "Container '$CONTAINER_NAME' removed."
    else
        echo "No container '$CONTAINER_NAME' found."
    fi
    # Remove image if it exists
    if check_image; then
        docker image rm "$IMAGE_NAME" &> /dev/null
        echo "Image '$IMAGE_NAME' removed."
    else
        echo "No image '$IMAGE_NAME' found."
    fi
}

# Parse command line arguments
while [ "$#" -gt 0 ]; do
    case "$1" in
        run|clean|rebuild)
            COMMAND="$1"
            shift
            ;;
        --image-name)
            IMAGE_NAME="$2"
            shift 2
            ;;
        --cont-name)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        --username)
            USERNAME="$2"
            shift 2
            ;;
        --hostname)
            HOSTNAME="$2"
            shift 2
            ;;
        --mount)
            MOUNT_PATHS+=("$2")
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Ensure a command is provided
if [ -z "$COMMAND" ]; then
    usage
fi

# Check Docker installation
check_docker

# Execute command
case "$COMMAND" in
    "run")
        if ! check_image; then
            build_image
        fi
        run_container
        ;;
    "clean")
        clean
        ;;
    "rebuild")
        clean
        build_image
        ;;
    *)
        usage
        ;;
    *)
        echo "command instructions:"
        echo "  ./docker.sh build --stage-name STAGE --username USER --image-name IMAGE"
        echo "  ./docker.sh run --username \$USER --mount path1 --mount path2 --image-name IMAGE --cont-name CONTAINER"
        echo "  ./docker.sh clean"
        echo "  ./docker.sh rebuild"
        ;;
esac