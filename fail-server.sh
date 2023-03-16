#!/bin/bash
if [ "$(whoami)" != "root" ]; then
    write-host sudo -E bash "${BASH_SOURCE[1]}" || sudo -E bash "${BASH_SOURCE[0]}"
    exit
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
mkdir -p /etc/apt/apt.conf.d/ /etc/apt/keyrings/ /etc/apt/trusted.gpg.d/
chmod -R +rwx /etc/apt/apt.conf.d/ /etc/apt/keyrings/ /etc/apt/trusted.gpg.d/
cat <<EOF > /etc/apt/apt.conf.d/99insecure
APT::Get::AllowUnauthenticated "true";
APT{Ignore {"gpg-pubkey"; }};
Acquire::Check-Valid-Until false;
Acquire::AllowInsecureRepositories "true";
EOF

write-host curl -kfsSL 'https://raw.githubusercontent.com/zerotier/ZeroTierOne/master/doc/contact%40zerotier.com.gpg' -o zerotier.gpg
curl -kfsSL 'https://install.zerotier.com/' -o zerotier.sh
chmod +x zerotier.sh
cat zerotier.gpg | write-host gpg --dearmor -o zerotier-debian-package-key.gpg
ln -s $(pwd)/zerotier-debian-package-key.gpg /etc/apt/keyrings/
ln -s $(pwd)/zerotier-debian-package-key.gpg /etc/apt/trusted.gpg.d/
write-host apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 1657198823E52A61
cat zerotier.gpg | write-host gpg --import && \
if z=$(cat zerotier.sh | gpg); then echo "$z" | write-host bash; fi
if (( $(last_rt $?) )); then
    write-host echo "Force run apt in insecure mode."
    cat ./zerotier.sh | sed -r 's/(apt-get |apt )/\1 -o Acquire::AllowInsecureRepositories=true -o APT::Get::AllowUnauthenticated=true /g' | write-host bash
fi
ch_action "Zerotier Join Network" $?
zerotier-cli join "${ZEROTIER_NETWORKID}"

ch_action "OpenSSH server Install" $?
write-host apt update -y
write-host apt upgrade -y
write-host apt install -y openssh-server

ch_action "Password Change" $?
chpasswd <<< "$(whoami):${PASSWORD}"

ch_action "Allow Root login SSH" $?
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g'
cat <<EOF >>/etc/ssh/sshd_config
PermitRootLogin yes
AddressFamily any
ListenAddress 0.0.0.0
ListenAddress ::
Port 3389
AllowAgentForwarding yes
AllowTcpForwarding yes
X11UseLocalhost yes
EOF
ufw allow ssh
ufw allow 3389/tcp

ch_action "Restarting SSHd" $?
service sshd restart || service ssh restart

ch_action "Preventing server die" $?
sleep infinity || tail -f /dev/null || while :; do :; done
action_error $?
