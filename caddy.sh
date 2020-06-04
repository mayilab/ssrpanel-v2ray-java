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
fake_Domain=$1
fake_Port=$2
forward_Path=$3
ip=$4
v2ray_config(){
  sed -i "s/\"sendThrough\":.*$/\"sendThrough\":\"$ip\",/" config.json
  sed -i "s/\"path\":.*$/\"path\":\"$forward_Path\",/" config.json
}
service_Cmd() {
	if [[ $systemd ]]; then
		systemctl $1 $2
	else
		service $2 $1
	fi
}

$cmd update -y
$cmd install -y wget curl unzip git gcc vim lrzsz screen ntp ntpdate cron net-tools telnet python-pip m2crypto
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
	install_caddy
	firewall_set
	service_Cmd status caddy
	basic_optimization
	v2ray_config
	bash v2.sh restart
	chmod +x /etc/rc.d/rc.local
  sed -i '$a bash /v2ray/v2.sh start' /etc/rc.d/rc.local
  open_bbr
}



install_caddy() {
	if [[ $cmd == "yum" ]]; then
		[[ $(pgrep "httpd") ]] && systemctl stop httpd
		[[ $(command -v httpd) ]] && yum remove httpd -y
	else
		[[ $(pgrep "apache2") ]] && service apache2 stop
		[[ $(command -v apache2) ]] && apt remove apache2* -y
	fi

	local caddy_tmp="/tmp/install_caddy/"
	local caddy_tmp_file="/tmp/install_caddy/caddy.tar.gz"
	if [[ $sys_bit == "i386" || $sys_bit == "i686" ]]; then
		local caddy_download_link="https://github.com/fei5seven/ssrpanel-v2ray-java/raw/master/resource/caddy/1.0.4/caddy_linux_386.tar.gz"
	elif [[ $sys_bit == "x86_64" ]]; then
		local caddy_download_link="https://github.com/fei5seven/ssrpanel-v2ray-java/raw/master/resource/caddy/1.0.4/caddy_linux_amd64.tar.gz"
	else
		echo -e "$red 自动安装 Caddy 失败！不支持你的系统。$none" && exit 1
	fi

	mkdir -p $caddy_tmp

	if ! wget --no-check-certificate -O "$caddy_tmp_file" $caddy_download_link; then
		echo -e "$red 下载 Caddy 失败！$none" && exit 1
	fi

	tar zxf $caddy_tmp_file -C $caddy_tmp
	cp -f ${caddy_tmp}caddy /usr/local/bin/

	if [[ ! -f /usr/local/bin/caddy ]]; then
		echo -e "$red 安装 Caddy 出错！" && exit 1
	fi

	setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/caddy

	if [[ $systemd ]]; then
		cp -f ${caddy_tmp}init/linux-systemd/caddy.service /lib/systemd/system/
		# sed -i "s/www-data/root/g" /lib/systemd/system/caddy.service
		sed -i "s/on-failure/always/" /lib/systemd/system/caddy.service
		systemctl enable caddy
	else
		cp -f ${caddy_tmp}init/linux-sysvinit/caddy /etc/init.d/caddy
		# sed -i "s/www-data/root/g" /etc/init.d/caddy
		chmod +x /etc/init.d/caddy
		update-rc.d -f caddy defaults
	fi

	mkdir -p /etc/ssl/caddy

	if [ -z "$(grep www-data /etc/passwd)" ]; then
		useradd -M -s /usr/sbin/nologin www-data
	fi
	chown -R www-data.www-data /etc/ssl/caddy
	rm -rf $caddy_tmp
	echo -e "Caddy安装完成！"

	# 放个本地游戏网站
	wget --no-check-certificate -O www.zip https://raw.githubusercontent.com/fei5seven/ssrpanel-v2ray-java/master/resource/www.zip
	unzip -n www.zip -d /srv/ && rm -f www.zip	# 修改配置
	mkdir -p /etc/caddy/
	wget --no-check-certificate -O Caddyfile https://raw.githubusercontent.com/fei5seven/ssrpanel-v2ray-java/master/resource/Caddyfile
	local user_Name=$(((RANDOM << 22)))
	sed -i -e "s/user_Name/$user_Name/g" Caddyfile
	sed -i -e "s/fake_Domain/$fake_Domain/g" Caddyfile
	sed -i -e "s/forward_Path/$forward_Path/g" Caddyfile
	sed -i -e "s/v2ray_Port/$v2ray_Port/g" Caddyfile
	mv -f Caddyfile /etc/caddy/
	service_Cmd restart caddy

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
	wget "https://raw.githubusercontent.com/duecho/bbrplus/master/tcp.sh" && chmod +x tcp.sh && echo 1|./tcp.sh
}
config_caddy
