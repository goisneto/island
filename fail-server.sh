#!/bin/bash
trap "true && exit 0" SIGHUP SIGINT SIGQUIT SIGTSTP SIGKILL SIGILL SIGTERM SIGSTOP 142
if [ "$(whoami)" != "root" ]; then
    write-host sudo -E bash "${BASH_SOURCE[1]}" || sudo -E bash "${BASH_SOURCE[0]}"
    exit 0
fi
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
            exit 0
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

alias apt='write-host apt -o Acquire::AllowInsecureRepositories=true -o APT::Get::AllowUnauthenticated=true'
alias apt-get='write-host apt-get -o Acquire::AllowInsecureRepositories=true -o APT::Get::AllowUnauthenticated=true'

mkdir -p /etc/apt/apt.conf.d/ /etc/apt/keyrings/ /etc/apt/trusted.gpg.d/
chmod -R +rwx /etc/apt/apt.conf.d/ /etc/apt/keyrings/ /etc/apt/trusted.gpg.d/
cat <<EOF > /etc/apt/apt.conf.d/99insecure
APT::Get::AllowUnauthenticated "true";
APT{Ignore {"gpg-pubkey"; }};
Acquire::Check-Valid-Until false;
Acquire::AllowInsecureRepositories "true";
EOF

if [ -n "${PASSWORD}" ]; then
    ch_action "Password Change" $?
    chpasswd <<< "$(whoami):${PASSWORD}"
fi

if [ -n "${ZEROTIER_NETWORKID}" ]; then
    ch_action "Zerotier Install" $?
    write-host curl -kfsSL 'https://raw.githubusercontent.com/zerotier/ZeroTierOne/master/doc/contact%40zerotier.com.gpg' -o zerotier.gpg
    curl -kfsSL 'https://install.zerotier.com/' -o zerotier.sh
    chmod +x zerotier.sh
    cat zerotier.gpg | write-host gpg --dearmor -o zerotier-debian-package-key.gpg
    cp $(pwd)/zerotier-debian-package-key.gpg /etc/apt/keyrings/
    cp $(pwd)/zerotier-debian-package-key.gpg /etc/apt/trusted.gpg.d/
    rm zerotier-debian-package-key.gpg
    write-host apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 1657198823E52A61
    cat zerotier.gpg | write-host gpg --import && \
    if z=$(cat zerotier.sh | gpg); then echo "$z" | write-host bash; fi
    if (( $(last_rt $?) )); then
        write-host echo "Force run apt in insecure mode."
        cat ./zerotier.sh | sed -r 's/(apt-get |apt )/\1 -o Acquire::AllowInsecureRepositories=true -o APT::Get::AllowUnauthenticated=true /g' | write-host bash
    fi
    rm zerotier.gpg

    ch_action "Zerotier Join Network" $?
    zerotier-cli join "${ZEROTIER_NETWORKID}"
fi

if [ -n "${NGROK_TOKEN}" ]; then
    ch_action "Ngrok Install" $?
    curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null && echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list
    apt update -y
    apt install -y ngrok
    ngrok config add-authtoken "${NGROK_TOKEN}"
    nohup ngrok tcp 22 &>/dev/null &
fi

if [ -n "${NGROK_TOKEN}" ] || [ -n "${ZEROTIER_NETWORKID}" ]; then
    ch_action "OpenSSH server Install" $?
    apt update -y
    apt upgrade -y
    apt install -y openssh-server

    ch_action "Allow Root login SSH" $?
    sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
    cat <<EOF >>/etc/ssh/sshd_config
    PermitRootLogin yes
    AddressFamily any
    ListenAddress 0.0.0.0
    ListenAddress ::
    Port 22
    AllowAgentForwarding yes
    AllowTcpForwarding yes
    X11UseLocalhost yes
EOF
    ufw allow ssh

    ch_action "Restarting SSHd" $?
    service sshd restart || service ssh restart
fi

ch_action "Preventing server die" $?
sleep infinity || tail -f /dev/null || while :; do :; done
action_error $?
exit 0
