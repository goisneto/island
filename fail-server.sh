#!/bin/bash
action=""
last_rt () {
    local last_rt_=$?
    while [ "$#" -gt 0 ]; do
        if ( grep -E '^[0-9]*$' <<< "$1" &> /dev/null ); then
            last_rt_=$((( $1 || $last_rt_ )))
        fi
        shift
    done
    echo $last_rt_
    return $last_rt_
}
action_error () {
    local last_rt_=$(last_rt $? "$@")
    if [ -n "$action" ]; then
        if (( $last_rt_ )); then
            write-host echo "ERROR [ $last_rt_ ] at $action. EXITING..."
            exit 1
        else
            write-host echo "$action SUCCESS..."
        fi
        action=""
    fi
}
ch_action () {
    local last_rt_=$(last_rt $? "$@")
    if [ -z "$noexit" ]; then
        action_error $last_rt_
    fi
    if [ ! -n "$action" ]; then
        action="$1"
        write-host echo "${action}..."
    fi
}
if [ -z "${PASSWORD}" ] || [ -z "${ZEROTIER_NETWORKID}" ]; then
    write-host echo "Some required environment not setted. EXITING..."
    exit 1
fi

ch_action "Zerotier Install" $?
curl -s 'https://raw.githubusercontent.com/zerotier/ZeroTierOne/master/doc/contact%40zerotier.com.gpg' | gpg --import && \
if z=$(curl -s 'https://install.zerotier.com/' | gpg); then echo "$z" | write-host bash; fi

ch_action "Zerotier Join Network" $?
zerotier-cli join "${ZEROTIER_NETWORKID}"

ch_action "OpenSSH server Install" $?
write-host apt update -y && write-host apt upgrade -y && write-host apt install -y openssh-server

ch_action "Password Change" $?
chpasswd <<< "$(whoami):${PASSWORD}"

ch_action "Allow Root login SSH" $?
echo "PermitRootLogin yes" >> /etc/ssh/sshd_config

ch_action "Restarting SSHd" $?
service sshd restart || service ssh restart

ch_action "Preventing server die" $?
sleep infinity || tail -f /dev/null || while :; do :; done
action_error $?
