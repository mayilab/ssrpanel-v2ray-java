#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
#=================================================================#
#   System Required:  CentOS7, Ubuntu, Root Permission            #
#   Description: panel node deploy script                         #
#   Version: 1.1.0                                                #
#   Author: fei5seven                                             #
#   Intro:                               #
#==================================================================

[ $(id -u) != "0" ] && { echo "错误: 请用root执行"; exit 1; }
sys_bit=$(uname -m)
if [[ -f /usr/bin/apt ]] || [[ -f /usr/bin/yum && -f /bin/systemctl ]]; then
	if [[ -f /usr/bin/yum ]]; then
		cmd="yum"
		$cmd -y install epel-release
	fi
	if [[ -f /usr/bin/apt ]]; then
		cmd="apt"
	fi
	if [[ -f /bin/systemctl ]]; then
		systemd=true
	fi

else
	echo -e " 哈哈……这个 ${red}辣鸡脚本${none} 只支持CentOS7+及Ubuntu14+ ${yellow}(-_-) ${none}" && exit 1
fi
v2ray_config(){
  sed -i "s/\"sendThrough\":.*$/\"sendThrough\":\"$ip\",/" config.json
}
get_ip() {
	ip=$(curl -s https://ipinfo.io/ip)
	[[ -z $ip ]] && ip=$(curl -s https://api.ip.sb/ip)
	[[ -z $ip ]] && ip=$(curl -s https://api.ipify.org)
	[[ -z $ip ]] && ip=$(curl -s https://ip.seeip.org)
	[[ -z $ip ]] && ip=$(curl -s https://ifconfig.co/ip)
	[[ -z $ip ]] && ip=$(curl -s https://api.myip.com | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}")
	[[ -z $ip ]] && ip=$(curl -s icanhazip.com)
	[[ -z $ip ]] && ip=$(curl -s myip.ipip.net | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}")
	[[ -z $ip ]] && echo -e "\n$red 这小鸡鸡还是割了吧！$none\n" && exit
}
service_Cmd() {
	if [[ $systemd ]]; then
		systemctl $1 $2
	else
		service $2 $1
	fi
}

$cmd update -y
$cmd install -y wget curl unzip git gcc   ntp ntpdate cron
# 设置时区为CST
echo yes | cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
ntpdate cn.pool.ntp.org
hwclock -w
sed -i '/^.*ntpdate*/d' /etc/crontab
sed -i '$a\* * * * 1 ntpdate cn.pool.ntp.org >> /dev/null 2>&1' /etc/crontab
service_Cmd restart crond

error() {

	echo -e "\n$red 输入错误！$none\n"

}
pause() {

	read -rsp "$(echo -e "按$green Enter 回车键 $none继续....或按$red Ctrl + C $none取消.")" -d $'\n'
	echo
}
config_caddy() {
	v2ray_Port="10086"
	firewall_set
	basic_optimization
	get_ip
	v2ray_config
	bash v2.sh restart
	chmod +x /etc/rc.d/rc.local
  sed -i '$a bash /v2ray/v2.sh start' /etc/rc.d/rc.local
  install_caddy
  systemctl restart tls-shunt-proxy
  open_bbr
}



install_caddy() {
	wget --no-check-certificate -O www.zip https://raw.githubusercontent.com/fei5seven/ssrpanel-v2ray-java/master/resource/www.zip
	unzip -n www.zip -d /srv/ && rm -f www.zip	# 修改配置
}

# Firewall
firewall_set(){
	echo -e "[${green}Info${plain}] firewall set start..."
	if command -v firewall-cmd >/dev/null 2>&1; then
		systemctl status firewalld > /dev/null 2>&1
		if [ $? -eq 0 ]; then
			firewall-cmd --permanent --zone=public --remove-port=400-500/tcp
			firewall-cmd --permanent --zone=public --remove-port=80/tcp
			firewall-cmd --permanent --zone=public --remove-port=400-500/udp
			firewall-cmd --permanent --zone=public --remove-port=80/udp
			firewall-cmd --permanent --zone=public --add-port=400-500/tcp
			firewall-cmd --permanent --zone=public --add-port=80/tcp
			firewall-cmd --permanent --zone=public --add-port=400-500/udp
			firewall-cmd --permanent --zone=public --add-port=80/udp
			firewall-cmd --reload
			if [[ $v2ray_Port ]]; then
				firewall-cmd --permanent --zone=public --remove-port=${v2ray_Port}/tcp
				firewall-cmd --permanent --zone=public --remove-port=${v2ray_Port}/udp
				firewall-cmd --permanent --zone=public --add-port=${v2ray_Port}/tcp
				firewall-cmd --permanent --zone=public --add-port=${v2ray_Port}/udp
				firewall-cmd --reload
			fi
			if [[ $single_Port_Num ]]; then
				firewall-cmd --permanent --zone=public --remove-port=${single_Port_Num}/tcp
				firewall-cmd --permanent --zone=public --remove-port=${single_Port_Num}/udp
				firewall-cmd --permanent --zone=public --add-port=${single_Port_Num}/tcp
				firewall-cmd --permanent --zone=public --add-port=${single_Port_Num}/udp
				firewall-cmd --reload
			fi
		else
			echo -e "[${yellow}Warning${plain}] firewalld looks like not running or not installed, please manually set it if necessary."
		fi
	elif command -v iptables >/dev/null 2>&1; then
		/etc/init.d/iptables status > /dev/null 2>&1
		if [ $? -eq 0 ]; then
			iptables -D INPUT -p tcp --dport 400:500 -j ACCEPT
			iptables -D INPUT -p tcp --dport 80 -j ACCEPT
			iptables -A INPUT -p udp --dport 400:500 -j ACCEPT
			iptables -A INPUT -pudcp --dport 80 -j ACCEPT
			ip6tables -D INPUT -p tcp --dport 400:500 -j ACCEPT
			ip6tables -D INPUT -p tcp --dport 80 -j ACCEPT
			ip6tables -A INPUT -p udp --dport 400:500 -j ACCEPT
			ip6tables -A INPUT -p udp --dport 80 -j ACCEPT
			iptables -L -n | grep -i ${v2ray_Port} > /dev/null 2>&1
			if [ $? -ne 0 ]; then
				iptables -D INPUT -p tcp --dport ${v2ray_Port} -j ACCEPT
				iptables -A INPUT -p tcp --dport ${v2ray_Port} -j ACCEPT
				iptables -D INPUT -p udp --dport ${v2ray_Port} -j ACCEPT
				iptables -A INPUT -p udp --dport ${v2ray_Port} -j ACCEPT
				ip6tables -D INPUT -p tcp --dport ${v2ray_Port} -j ACCEPT
				ip6tables -A INPUT -p tcp --dport ${v2ray_Port} -j ACCEPT
				ip6tables -D INPUT -p udp --dport ${v2ray_Port} -j ACCEPT
				ip6tables -A INPUT -p udp --dport ${v2ray_Port} -j ACCEPT
				/etc/init.d/iptables save
				/etc/init.d/iptables restart
				/etc/init.d/ip6tables save
				/etc/init.d/ip6tables restart
			else
				echo -e "[${green}Info${plain}] port 80, 443, ${v2ray_Port} has been set up."
			fi
			iptables -L -n | grep -i ${single_Port_Num} > /dev/null 2>&1
			if [ $? -ne 0 ]; then
				iptables -D INPUT -p tcp --dport ${single_Port_Num} -j ACCEPT
				iptables -A INPUT -p tcp --dport ${single_Port_Num} -j ACCEPT
				iptables -D INPUT -p udp --dport ${single_Port_Num} -j ACCEPT
				iptables -A INPUT -p udp --dport ${single_Port_Num} -j ACCEPT
				ip6tables -D INPUT -p tcp --dport ${single_Port_Num} -j ACCEPT
				ip6tables -A INPUT -p tcp --dport ${single_Port_Num} -j ACCEPT
				ip6tables -D INPUT -p udp --dport ${single_Port_Num} -j ACCEPT
				ip6tables -A INPUT -p udp --dport ${single_Port_Num} -j ACCEPT
				/etc/init.d/iptables save
				/etc/init.d/iptables restart
				/etc/init.d/ip6tables save
				/etc/init.d/ip6tables restart
			else
				echo -e "[${green}Info${plain}] port 80, 443, ${single_Port_Num} has been set up."
			fi
		else
			echo -e "[${yellow}Warning${plain}] iptables looks like shutdown or not installed, please manually set it if necessary."
		fi
	fi
	echo -e "[${green}Info${plain}] firewall set completed..."
}


basic_optimization() {
    # 最大文件打开数
    sed -i '/^\*\ *soft\ *nofile\ *[[:digit:]]*/d' /etc/security/limits.conf
    sed -i '/^\*\ *hard\ *nofile\ *[[:digit:]]*/d' /etc/security/limits.conf
    echo '* soft nofile 65536' >>/etc/security/limits.conf
    echo '* hard nofile 65536' >>/etc/security/limits.conf
    sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
        setenforce 0

}
open_bbr(){
	echo 2|bash tcp.sh
}
config_caddy
