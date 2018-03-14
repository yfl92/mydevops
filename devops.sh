#!/bin/bash

FROM=$(date +%s)
ECHO="$(which echo) -e"

CREATE=$(dirname $BASH_SOURCE)/create_vms_2d.sh
BASE_IMAGES=$(dirname $BASH_SOURCE)/base_images
CHIWEN_LICENSE=$(dirname $BASH_SOURCE)/chiwen-license

SSHPASS="sshpass -p sihua!@#890"

# license file
LICENSE=$(dirname $BASH_SOURCE)/license.key

# Create, List or Remove
action=

# Apply action to all machines
all=

# default number of machine to create
number=1

# default os image
os=ubuntu16.04

# specify action applies to wchich pool(devops, night, developer)
pool=devops

# Node pool for devops
DEVOPS_NODES=(
    devops160
    devops161
    devops162
    devops163
    devops164
    devops165
    devops166
    devops167
    devops168
    devops169  
)

# Nodes pool for nightly test
NIGHT_NODES=(
    night170
    night171
    night172
    night173
    night174
    night175
    night176
    night177
    night178
    night179
)

# Nodes pool for developers
DEVELOPER_NODES=(
    developer180
    developer181
    developer182
    developer183
    developer184
    developer185
    developer186
    developer187
    developer188
    developer189
)

# default values
NODES=
NODE_PREFIX=

pre() {
    if [ "$pool" == "night" ]; then
        NODES=(${NIGHT_NODES[*]})
        NODE_PREFIX=night
    elif [ "$pool" == "developer" ]; then
        NODES=(${DEVELOPER_NODES[*]})
        NODE_PREFIX=developer
    else
        NODES=(${DEVOPS_NODES[*]})
        NODE_PREFIX=devops
    fi
}

do_create() {
    n=1
    names=($(virsh list --all --name))

    for node in "${NODES[@]}"
    do
        if (("$n" > "$number")); then
            break;
        fi

        found=
        for name in "${names[@]}"
        do
            if [ "$name" == "$node" ]; then
                found=0
            fi
        done

        if [ -z "$found" ]; then
            nodeIP=10.10.1.$(echo $node | awk -F "$NODE_PREFIX" '{print $2}')
            dataIP=172.16.88.$(echo $node | awk -F "$NODE_PREFIX" '{print $2}')
            $CREATE $node "br0#$nodeIP#255.255.255.0#10.10.1.254#8.8.8.8;br0#$dataIP#255.255.255.0" 8 64 0 $BASE_IMAGES/base-ubuntu16.04-docker17.12.1.qcow2
            n=$(( n + 1 ))
        fi
    done
}

do_list() {
    virsh list --all
}

do_license() {
    node=$1
    if [ -z "$node" ]; then
        exit 1
    fi

    $SSHPASS scp $CHIWEN_LICENSE $node:/root/

    $SSHPASS ssh $node << 'EOF'
        cw_path=/var/lib/docker/volumes/chiwen.config/_data
        test -d $chiwen_config_path || mkdir -p $cw_path
        mac=$(cat /sys/class/net/$(ip route show default|awk '/default/ {print $5}')/address)
        hw_sig=$(echo -n "${mac}HJLXZZ" | openssl dgst -md5 -binary | openssl enc -base64)
        /root/chiwen-license \
            -id dummy \
            -hw $hw_sig \
            -ia $(date -u +“%Y-%m-%d”) \
            -ib minhao.jin \
            -ea 2049-12-31 \
            -o devops@160 > $cw_path/license.key
EOF
}

do_remove() {
    names=$@
    if [ -n "$all" ]; then
        names=$NODES
    fi

    for name in "${names[@]}"
    do
        if [ -e "qcow2/$name.qcow2" ]; then
            virsh destroy $name
            virsh undefine $name
            rm qcow2/$name.qcow2
        fi
    done
}

at_exit() {
    ret=$?
    set +x
    if [ "$ret" == "0" ]; then
        $ECHO "\e[1;32m[SUCCESS $(expr $(date +%s) - $FROM)s]\e[0m"
    else
        $ECHO "\e[1;31m[FAILED $(expr $(date +%s) - $FROM)s]\e[0m"
    fi
    exit $ret
}

usage() {
    $ECHO "Usage: devops.sh [options] [COMMAND] [ARGS...]"
    $ECHO ""
    $ECHO "Options:"
    $ECHO "    --help        Print usage"
    $ECHO "    --all         All machines (default: false)"
    $ECHO "    --pool        Specify which pool(devops,night,developer) the action will apply to (default: devops)"
    $ECHO "    --number=NUM  Number(up to 20) of machines (default: 1)"
    $ECHO "    --os=OS       OS image (default: ubuntu16.04)"
    $ECHO ""
    $ECHO "Commands:"
    $ECHO "    create              create one or more machines"
    $ECHO "    license <address>   license"
    $ECHO "    list                list devops machines"
    $ECHO "    remove [Names]      remove one or more machines"
    $ECHO ""
    exit 0
}

trap 'at_exit' EXIT

while true; do
    case $1 in
        create|license|list|remove)
            action=$1
            shift
            break ;;
        --all)
            all=0
            shift ;;
        --pool=*)
            pool=$(echo $1 | awk -F "=" '{print $2}')
            shift ;;
        --number=*)
            number=$(echo $1 | awk -F "=" '{print $2}')
            shift ;;
        --os=*)
            os=$(echo $1 | awk -F "=" '{print $2}')
            shift ;;
        --help)
            usage
            break ;;
        *)  usage ;;
    esac
done

# pre processing on parameters
pre

do_$action $@

