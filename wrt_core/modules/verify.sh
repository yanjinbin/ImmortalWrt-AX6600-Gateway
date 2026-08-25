#!/usr/bin/env bash
# 构建树一致性检查。

verify_custom_feed_installed_paths() {
    local custom_feed_name
    local custom_feed_package_dir
    # install_feeds 后必须存在的 custom_feed 包路径。
    local required_package_dirs=(nikki luci-app-nikki luci-app-emmc-health)
    local missing_package_dirs=()

    custom_feed_name=$(get_custom_feed_name)
    custom_feed_package_dir=$(get_custom_feed_package_dir)

    collect_missing_directories "$custom_feed_package_dir" required_package_dirs missing_package_dirs

    if [ ${#missing_package_dirs[@]} -ne 0 ]; then
        printf '错误：%s 安装后缺少以下仓库依赖路径：\n' "$custom_feed_name" >&2
        printf '  - %s\n' "${missing_package_dirs[@]}" >&2
        return 1
    fi
}

excluded_package_config_names() {
    printf '%s\n' \
        luci-app-passwall luci-app-passwall2 \
        luci-app-adguardhome adguardhome \
        luci-app-appfilter luci-app-oaf open-app-filter \
        luci-app-mosdns mosdns \
        luci-app-lucky lucky \
        luci-app-cupsd cups p910nd kmod-usb-printer \
        luci-app-smartdns smartdns \
        luci-app-pbr pbr \
        luci-app-autoreboot \
        luci-app-wol wol etherwake \
        luci-app-samba4 samba4 samba4-server luci-app-ksmbd ksmbd luci-app-nfs nfs-utils \
        luci-app-upnp miniupnpd \
        luci-app-vlmcsd vlmcsd \
        luci-app-diskman luci-app-quickfile \
        luci-app-dockerman dockerman \
        luci-app-wireguard wireguard-tools kmod-wireguard \
        luci-app-openvpn openvpn-openssl \
        xl2tpd kmod-l2tp kmod-pppol2tp strongswan luci-app-strongswan ocserv luci-app-ocserv \
        luci-app-tailscale tailscale \
        luci-app-zerotier zerotier \
        luci-app-easytier easytier
}

assert_excluded_packages_disabled() {
    local config_path="$1"
    local package_name
    local enabled=()

    [ -f "$config_path" ] || {
        echo "错误：最终 .config 不存在：$config_path" >&2
        return 1
    }

    while IFS= read -r package_name; do
        if grep -Eq "^CONFIG_PACKAGE_${package_name//-/-}=([ym])$" "$config_path"; then
            enabled+=("$package_name")
        fi
    done < <(excluded_package_config_names)

    if [ ${#enabled[@]} -ne 0 ]; then
        printf '错误：最终 .config 仍启用了排除插件：%s\n' "${enabled[*]}" >&2
        return 1
    fi
}
