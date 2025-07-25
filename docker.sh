#!/bin/bash

usage_message() {
    cat << EOF
    Usage: $0 {run|stop|build|rebuild|clean_container|clean_image} [options]
        run             - Run the Docker container
        stop            - Stop the Docker container if running
        build           - Build the Docker image
        rebuild         - Rebuild the Docker image without cache
        clean_container - Stop and remove the Docker container
        clean_image     - Remove the Docker image

    Options:
        --username | -u    USERNAME                  Set the username for the container (default: user)
        --image-name | -i  IMAGE_NAME                Set the name of the Docker image (required for run/build)
        --cont-name | -c   CONTAINER_NAME            Set the name of the Docker container (required for run)
        --mount | -m       HOST_PATH:CONTAINER_PATH  Mount a host directory into the container (can be used multiple times)
EOF
}
# default values
USERNAME=""
IMAGE_NAME=""
CONT_NAME=""
CONTAINER_NAME=""
MOUNTS=()
# Check if command is provided
if [ $# -lt 1 ]; then
    usage_message
    exit 1
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed. Please install Docker first."
    exit 1
fi

COMMAND=$1
shift

while [ $# -gt 0 ]; do
    case $1 in
        --username|-u)
            USERNAME=$2
            shift 2
            ;;
        --image-name|-i)
            IMAGE_NAME=$2
            shift 2
            ;;
        --cont-name|-c)
            CONT_NAME=$2
            shift 2
            ;;
        --mount|-m)
            MOUNTS+=("$2")
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            usage_message
            exit 1
            ;;
    esac
done

# Detect architecture
detect_arch() {
    case $(uname -m) in
        x86_64)
            echo "x86_64"
            ;;
        aarch64)
            echo "aarch64"
            ;;
        *)
            echo "Unsupported architecture: $(uname -m)" >&2
            exit 1
            ;;
    esac
}

# Handle commands
case $COMMAND in
    build)
        if [ -z "$IMAGE_NAME" ]; then
            echo "Error: --image-name is required for build"
            usage_message
            exit 1
        fi
        ARCH=$(detect_arch)
        if [ -z "$USERNAME" ]; then
            USERNAME="user"
        fi
        docker build --build-arg ARCH=$ARCH --build-arg USERNAME=$USERNAME -t $IMAGE_NAME .
        ;;

    rebuild)
        if [ -z "$IMAGE_NAME" ]; then
            echo "Error: --image-name is required for rebuild"
            usage_message
            exit 1
        fi
        ARCH=$(detect_arch)
        if [ -z "$USERNAME" ]; then
            USERNAME="user"
        fi
        docker build --no-cache --build-arg ARCH=$ARCH --build-arg USERNAME=$USERNAME -t $IMAGE_NAME .
        ;;

    run)
        if [ -z "$IMAGE_NAME" ]; then
            echo "Error: --image-name is required for run"
            usage_message
            exit 1
        fi
        if [ -z "$CONT_NAME" ]; then
            echo "Error: --cont-name is required for run"
            usage_message
            exit 1
        fi

        # Check if image exists, if not, build it
        if ! docker image inspect $IMAGE_NAME > /dev/null 2>&1; then
            echo "Image $IMAGE_NAME does not exist, building it..."
            ARCH=$(detect_arch)
            if [ -z "$USERNAME" ]; then
                USERNAME="user"
            fi
            docker build --build-arg ARCH=$ARCH --build-arg USERNAME=$USERNAME -t $IMAGE_NAME .
        fi

        # Check if container exists
        if docker ps -a --format '{{.Names}}' | grep -q "^$CONT_NAME$"; then
            echo "Container $CONT_NAME already exists. Please use clean_container first."
            exit 1
        else
            # Set user
            if [ -z "$USERNAME" ]; then
                RUN_USER=$(id -u):$(id -g)
            else
                RUN_USER=$USERNAME
            fi

            # Set mount options
            MOUNT_OPTS=()
            for mount in "${MOUNTS[@]}"; do
                if [ -d "${mount%%:*}" ]; then
                    MOUNT_OPTS+=("-v" "$mount")
                else
                    echo "Warning: Mount path '${mount%%:*}' does not exist, skipping."
                fi
            done

            # Run the container
            docker run -it --name $CONT_NAME -u $RUN_USER "${MOUNT_OPTS[@]}" $IMAGE_NAME
        fi
        ;;

    stop)
        if [ -z "$CONT_NAME" ]; then
            echo "Error: --cont-name is required for stop"
            usage_message
            exit 1
        fi
        if docker ps --format '{{.Names}}' | grep -q "^$CONT_NAME$"; then
            docker stop $CONT_NAME
        else
            echo "Container $CONT_NAME is not running"
        fi
        ;;

    clean_container)
        if [ -z "$CONT_NAME" ]; then
            echo "Error: --cont-name is required for clean_container"
            usage_message
            exit 1
        fi
        if docker ps -a --format '{{.Names}}' | grep -q "^$CONT_NAME$"; then
            docker rm -f $CONT_NAME
        else
            echo "Container $CONT_NAME does not exist"
        fi
        ;;

    clean_image)
        if [ -z "$IMAGE_NAME" ]; then
            echo "Error: --image-name is required for clean_image"
            usage_message
            exit 1
        fi
        if docker images -q $IMAGE_NAME | grep -q .; then
            docker rmi $IMAGE_NAME
        else
            echo "Image $IMAGE_NAME does not exist"
        fi
        ;;

    *)
        echo "Unknown command: $COMMAND"
        usage_message
        exit 1
        ;;
esac