#!/bin/sh

# 京东云 AX6600 雅典娜定制版首启设置。
BOARD_NAME=$(cat /tmp/sysinfo/board_name 2>/dev/null)
case "$BOARD_NAME" in
	jdcloud,ax6600|jdcloud,re-cs-02) ;;
	*) exit 0 ;;
esac

SETTINGS_FILE=/etc/config/jdcloud-settings
[ -f "$SETTINGS_FILE" ] && . "$SETTINGS_FILE"

net_mode=${net_mode:-dhcp}
lan_ip=${lan_ip:-192.168.2.1}
root_pw=${root_pw:-666666}
wifi_ssid=${wifi_ssid:-ASUS395}
wifi_word=${wifi_word:-yjb123456}

uci set network.lan.proto='static'
uci set network.lan.ipaddr="$lan_ip"
uci set network.lan.netmask='255.255.255.0'
if [ "$net_mode" = 'pppoe' ] && [ -n "$pppoe_account" ] && [ -n "$pppoe_password" ]; then
	uci set network.wan.proto='pppoe'
	uci set network.wan.username="$pppoe_account"
	uci set network.wan.password="$pppoe_password"
	uci set network.wan.peerdns='1'
	uci set network.wan.auto='1'
	uci set network.wan6.proto='none'
else
	uci set network.wan.proto='dhcp'
	uci set network.wan6.proto='dhcpv6'
fi

for radio in 0 1 2; do
	section="wireless.default_radio${radio}"
	if uci -q get "$section.ssid" >/dev/null 2>&1; then
		uci set "$section.ssid=$wifi_ssid"
		uci set "$section.encryption=psk2+ccmp"
		uci set "$section.key=$wifi_word"
	fi
done

# 默认主题为 OpenWrt；UniWRT/Footstrap 保留为可切换主题。
uci -q set luci.main='core'
uci set luci.main.mediaurlbase='/luci-static/openwrt'
uci -q set luci.sauth='sauth'
uci set luci.sauth.cookie_days='365'
uci set luci.sauth.sessiontime='604800'

# WAN 入站长期保持 ACCEPT，便于从上级网络访问 AX6600 的 WAN 地址。
WAN_ZONE=$(uci show firewall 2>/dev/null | sed -n "s/^firewall\.@zone\[\([0-9][0-9]*\)\]\.name='wan'$/\1/p" | head -n1)
[ -n "$WAN_ZONE" ] && uci set "firewall.@zone[$WAN_ZONE].input=ACCEPT"

# SSH/ttyd 不限制接口，保持上级网络和 LAN 均可管理。
uci -q delete ttyd.@ttyd[0].interface
uci set dropbear.@dropbear[0].Interface=''

printf '%s\n%s\n' "$root_pw" "$root_pw" | passwd root >/dev/null 2>&1 || true
uci commit
rm -f "$SETTINGS_FILE"
exit 0
