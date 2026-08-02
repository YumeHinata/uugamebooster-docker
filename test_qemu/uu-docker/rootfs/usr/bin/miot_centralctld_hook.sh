#!/bin/sh

export PATH="$PATH:/data/docker"

CONTAINER_NAME=miot_central
IMAGE_NAME=micr.cloud.mioffice.cn/central_software_pack/central_software_pack

# version utilities
centralctl_hook_parse_version(){
    # version format: [garbage]int.int.int[garbage]
    echo "$1" | sed -n 's/^[^0-9]*\([0-9]\+\.[0-9]\+\.[0-9]\+\).*$/\1/p'
}

centralctl_hook_version_get_major(){
    echo "$1" | sed -n 's/^\([0-9]\+\)\.[0-9]\+\.[0-9]\+$/\1/p'
}

centralctl_hook_version_get_minor(){
    echo "$1" | sed -n 's/^[0-9]\+\.\([0-9]\+\)\.[0-9]\+$/\1/p'
}

centralctl_hook_version_get_revision(){
    echo "$1" | sed -n 's/^[0-9]\+\.[0-9]\+\.\([0-9]\+\)$/\1/p'
}

centralctl_hook_compare_version(){
    version1_major=$(centralctl_hook_version_get_major "$1")
    version2_major=$(centralctl_hook_version_get_major "$2")
    [ $version1_major -gt $version2_major ] && echo "1" && return
    [ $version2_major -gt $version1_major ] && echo "-1" && return
    version1_minor=$(centralctl_hook_version_get_minor "$1")
    version2_minor=$(centralctl_hook_version_get_minor "$2")
    [ $version1_minor -gt $version2_minor ] && echo "1" && return
    [ $version2_minor -gt $version1_minor ] && echo "-1" && return
    version1_revision=$(centralctl_hook_version_get_revision "$1")
    version2_revision=$(centralctl_hook_version_get_revision "$2")
    [ $version1_revision -gt $version2_revision ] && echo "1" && return
    [ $version2_revision -gt $version1_revision ] && echo "-1" && return
    echo "0"
}

centralctl_hook_set_ui(){
    if [ -z "$1" ]; then
        echo "UI state not provided for set_ui"
        exit 1
    fi
    # do set ui, posible states are "normal", "unbind", "ota", "fault", "connecting", "offline" 
    if [ "$1" = "ota" ]; then
        /usr/sbin/xqled sys_ota > /dev/null 2>&1
    elif [ "$1" = "normal" ]; then
        /usr/sbin/xqled sys_ok > /dev/null 2>&1
    fi
}

centralctl_hook_update(){
# lock this operation
(
flock -x -n 200
if [ "$?" -eq "0" ]; then

    if [ -z "$1" ]; then
        echo "Package not provided for update"
        exit 1
    fi

    # Terminate central container check
    killall -9 02_check_central.sh 2>/dev/null

    # get the old version
    version_old=$(docker image ls "$IMAGE_NAME" | sed -n '2s/\S\+\s\+\(\S\+\)\s\+.*/\1/p')
    # load the new image
    package="$1"
    # convert path if the path is not labeled host path
    if [ "$2" != "host_path" ]; then
        package=$(echo "$1" | sed "s/^\/data\//\/data\/other\/central\//")
    fi
    result=$(docker load -i "$package" -q)
    if [ $? -ne 0 ]; then
        echo "Can not load docker image"
        exit 1
    fi
    echo "$result"
    version=$(echo "$result" | sed "s/^.*micr\.cloud\.mioffice\.cn\/central_software_pack\/central_software_pack://")
    # delete the image file if nost host path
    if [ "$2" != "host_path" ]; then
        rm -f "$package"
    fi
    # compare versions
    version_clean=$(centralctl_hook_parse_version "$version")
    version_old_clean=$(centralctl_hook_parse_version "$version_old")
    # only compare valid versions, invalid versions are for debugging
    if [ ! -z "$version_clean" ] && [ ! -z "$version_old_clean" ]; then
        compare_result=$(centralctl_hook_compare_version "$version_clean" "$version_old_clean")
        if [ ! $compare_result -gt 0 ]; then
            # This is only a basic check for the default image update purposes. 
            # The real check happends inside the container after downloading the image.
            echo "The image is not newer, abort."
            # remove the newly loaded image
            docker image rm "$IMAGE_NAME:$version"
            docker image prune -f
            exit 1
        fi
    fi
    # send reboot to container
    miotcentralctl reboot
    # wait 4 seconds for container to be ready
    sleep 4
    # stop the old container(s?)
    container_ids=$(docker ps -a --filter "name=$CONTAINER_NAME" -q)
    if [ ! -z "$container_ids" ]; then
        touch /tmp/central_normal_stop
        docker rm -f $container_ids
    fi
    # remove all the other image(s?)
    image_ids=$(docker image ls "$IMAGE_NAME" --filter "before=$IMAGE_NAME:$version" -q)
    if [ ! -z "$image_ids" ]; then
        docker image rm $image_ids
    fi
    image_ids=$(docker image ls "$IMAGE_NAME" --filter "since=$IMAGE_NAME:$version" -q)
    if [ ! -z "$image_ids" ]; then
        docker image rm $image_ids
    fi
    # mark as tried update, avoid nested update
    touch /tmp/.central_software_pack_tried_update
    # start the new container
    central_software_pack.sh start
    # set ui to normal only if the request is from the container
    if [ "$2" != "host_path" ]; then
        centralctl_hook_set_ui normal
    fi
    # prune dangling images, This will affect other images, use with causion!!!
    docker image prune -f
    rm -f /tmp/central_normal_stop

fi
) 200>/tmp/centralctl_update.lock
}

centralctl_hook_wait_update(){
(
    if [ ! -z "$1" ]; then
        # wait with timeout
        flock -s -w "$1" 200
    else
        # wait without timeout (non-block)
        flock -s -n 200
    fi
    if [ "$?" = "0" ]; then
        echo "Wait update lock aquired"
    else
        echo "Wiat update failed"
        exit 1
    fi
) 200>/tmp/centralctl_update.lock
}

if [ -z "$1" ]; then
    echo "Method not provided, Usage: miot_centralctl_hook.sh method [...args]"
    exit 1
fi

if [ "$1" = "set_ui" ]; then
    shift
    centralctl_hook_set_ui "$@"
elif [ "$1" = "update" ]; then
    shift
    centralctl_hook_update "$@"
elif [ "$1" = "wait_update" ]; then
    shift
    centralctl_hook_wait_update "$@"
else
    echo "Unsupported method $1"
    exit 1
fi

