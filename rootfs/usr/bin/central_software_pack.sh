#!/bin/sh

export PATH="$PATH:/data/docker"

CONTAINER_NAME=miot_central
IMAGE_NAME=micr.cloud.mioffice.cn/central_software_pack/central_software_pack
DEFAULT_IMAGE=/data/central/default_image.tar.xz
PLATFORM_CONFIG=/etc/central_software_pack/platform.conf
EXTERNAL_SOCK_DIR=/tmp/miot_central
CONTAINER_DATA_DIR=/data/other/central
FIRST_START_AFTER_OTA=$([ -f /tmp/.post_ota_boot ] && [ ! -f /tmp/.central_software_pack_tried_update ] && echo "Y")
EXTRA_CONTINAER_OPTIONS="--memory=256m --cpus=1"

central_software_pack_start(){
    # if $1 is present, delay for $1 seconds, this is used for waiting dockerd auto-restart
    if [ ! -z "$1" ]; then
        sleep "$1"
    fi
    # prepare directories
    mkdir -p "$EXTERNAL_SOCK_DIR"
    mkdir -p "$CONTAINER_DATA_DIR"
    # if this start is the first one after ota reboot, try update from the default image
    if [ ! -z "$FIRST_START_AFTER_OTA" ]; then
        touch /tmp/.central_software_pack_tried_update
        echo "Try update image after ota reboot"
        # try update, if update is successful, the image will be running, exit
        miot_centralctld_hook.sh update "$DEFAULT_IMAGE" host_path && exit 0
    fi
    # check if the container is already running
    container_id=$(docker ps --filter "name=$CONTAINER_NAME" -q)
    if [ ! -z "$container_id" ]; then
        echo "Central software pack is already running"
        exit 1
    fi
    # check if there is any stopped container (there should not be)
    container_id=$(docker ps -a --filter "name=$CONTAINER_NAME" -q -l)
    if [ ! -z "$container_id" ]; then
        echo "Restart stopped central software pack"
        docker restart "$container_id"
        exit 0
    fi
    # check if there is any image
    image_id=$(docker image ls "$IMAGE_NAME" -q)
    if [ -z "$image_id" ]; then
        # load the default image
        docker load -i "$DEFAULT_IMAGE"
        if [ $? -ne 0 ]; then
            echo "Can not load the default image"
            exit 1
        fi
    fi
    image_id=$(docker image ls "$IMAGE_NAME" -q | head -n 1)
    echo "Start image: $image_id"
    docker run -d $EXTRA_CONTINAER_OPTIONS --restart=unless-stopped --network=host --tmpfs /tmp --tmpfs /run -v /etc/timezone:/etc/timezone:ro -v /etc/localtime:/etc/localtime:ro -v "$PLATFORM_CONFIG:/etc/platform.conf:ro" -v "$EXTERNAL_SOCK_DIR:/tmp/external" -v /var/run/mdnsd:/var/run/mdnsd -v "$CONTAINER_DATA_DIR:/data" --name "$CONTAINER_NAME"  "$image_id" busybox init
}

central_software_pack_stop(){
    container_id=$(docker ps --filter "name=$CONTAINER_NAME" -q)
    if [ ! -z "$container_id" ]; then
        docker stop "$container_id"
    fi
}

central_software_pack_rm(){
    # remove the container
    container_id=$(docker ps --filter "name=$CONTAINER_NAME" -a -q)
    if [ ! -z "$container_id" ]; then
        docker rm -f "$container_id"
    fi
    # remove container data
    rm -rf "$CONTAINER_DATA_DIR"
}

if [ -z "$1" ]; then
    echo "Method not provided, Usage: central_software_pack.sh method"
    exit 1
fi

if [ "$1" = "start" ]; then
    shift
    central_software_pack_start "$@"
elif [ "$1" = "stop" ]; then
    shift
    central_software_pack_stop "$@"
elif [ "$1" = "rm" ]; then
    shift
    central_software_pack_rm "$@"
else
    echo "Unsupported method $1"
    exit 1
fi

