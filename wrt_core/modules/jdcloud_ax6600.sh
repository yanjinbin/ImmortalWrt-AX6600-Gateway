#!/usr/bin/env bash
# 京东云 AX6600 雅典娜定制构建逻辑。

is_jdcloud_ax6600_build() {
    [[ "${WRT_DEVICE_CONFIG:-}" == jdcloud_ipq60xx_immwrt || \
       "${WRT_DEVICE_CONFIG:-}" == jdcloud_ipq60xx_libwrt ]]
}

jdcloud_shell_quote() {
    local value=${1//\'/\'\\\'\'}
    printf "'%s'" "$value"
}

jdcloud_effective_lan_ip() {
    if [[ -n "${LAN_IP:-}" ]]; then
        printf '%s\n' "$LAN_IP"
    elif [[ -n "${WRT_IP:-}" ]]; then
        printf '%s\n' "$WRT_IP"
    elif [[ "${NET_MODE:-dhcp}" == dhcp ]]; then
        printf '%s\n' '192.168.2.1'
    else
        printf '%s\n' '192.168.1.1'
    fi
}

jdcloud_validate_inputs() {
    local mode=${NET_MODE:-dhcp}
    case "$mode" in
        dhcp|router|pppoe) ;;
        *) echo "错误: NET_MODE=$mode 不是 dhcp/router/pppoe" >&2; return 1 ;;
    esac

    if [[ "$mode" == pppoe && ( -z "${PPPOE_ACCOUNT:-}" || -z "${PPPOE_PASSWORD:-}" ) ]]; then
        echo '错误: NET_MODE=pppoe 时必须同时填写 PPPOE_ACCOUNT 与 PPPOE_PASSWORD' >&2
        return 1
    fi

    local value
    for value in "${WRT_SSID:-ASUS395}" "${WRT_WORD:-yjb123456}" "${WRT_PW:-666666}" \
        "${PPPOE_ACCOUNT:-}" "${PPPOE_PASSWORD:-}"; do
        [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || {
            echo '错误: 登录/WiFi/PPPoE 输入不能包含换行' >&2
            return 1
        }
    done
}

jdcloud_write_settings() {
    local settings_path="$BUILD_DIR/package/base-files/files/etc/config/jdcloud-settings"
    local effective_lan_ip
    effective_lan_ip=$(jdcloud_effective_lan_ip)
    mkdir -p "${settings_path%/*}"
    {
        printf 'net_mode=%s\n' "$(jdcloud_shell_quote "${NET_MODE:-dhcp}")"
        printf 'lan_ip=%s\n' "$(jdcloud_shell_quote "$effective_lan_ip")"
        printf 'root_pw=%s\n' "$(jdcloud_shell_quote "${WRT_PW:-666666}")"
        printf 'wifi_ssid=%s\n' "$(jdcloud_shell_quote "${WRT_SSID:-ASUS395}")"
        printf 'wifi_word=%s\n' "$(jdcloud_shell_quote "${WRT_WORD:-yjb123456}")"
        printf 'pppoe_account=%s\n' "$(jdcloud_shell_quote "${PPPOE_ACCOUNT:-}")"
        printf 'pppoe_password=%s\n' "$(jdcloud_shell_quote "${PPPOE_PASSWORD:-}")"
    } >"$settings_path"
    chmod 600 "$settings_path"
}

jdcloud_install_extra_packages() {
    mkdir -p "$BUILD_DIR/package"
    jdcloud_clone_package 'https://github.com/sirpdboy/luci-app-partexp.git' main luci-app-partexp
    jdcloud_clone_package 'https://github.com/yanjinbin/uniwrt-luci.git' main luci-theme-uniwrt
    jdcloud_clone_package 'https://github.com/yanjinbin/luci-theme-footstrap.git' main luci-theme-footstrap
}

jdcloud_clone_package() {
    local repo_url=$1
    local branch=$2
    local package_name=$3
    local destination="$BUILD_DIR/package/$package_name"

    rm -rf "$destination"
    if ! git_retry clone --depth 1 -b "$branch" "$repo_url" "$destination"; then
        echo "错误：无法拉取 AX6600 软件包 $repo_url#$branch" >&2
        return 1
    fi
    rm -rf "$destination/.git"
}

jdcloud_download_mihomo() {
    local version=${MIHOMO_VERSION:-1.19.30}
    local platform=${MIHOMO_PLATFORM:-arm64}
    local url="https://github.com/MetaCubeX/mihomo/releases/download/v${version}/mihomo-linux-${platform}-v${version}.gz"
    local target="$BUILD_DIR/package/base-files/files/usr/libexec/mihomo"

    [[ "${MIHOMO_SKIP_DOWNLOAD:-0}" == 1 ]] && return 0
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "错误: mihomo 版本格式无效: $version" >&2; return 1; }
    [[ "$platform" =~ ^[a-z0-9._-]+$ ]] || { echo "错误: mihomo 平台格式无效: $platform" >&2; return 1; }

    mkdir -p "${target%/*}" "$BUILD_DIR/package/base-files/files/usr/bin"
    echo "下载 mihomo: $url"
    curl_retry -fsSL "$url" | gzip -dc >"$target"
    chmod 0755 "$target"
    ln -sfn /usr/libexec/mihomo "$BUILD_DIR/package/base-files/files/usr/bin/mihomo"
}

jdcloud_download_nikki_geodata() {
    [[ "${MIHOMO_SKIP_DOWNLOAD:-0}" == 1 ]] && return 0

    local target="$BUILD_DIR/package/base-files/files/etc/nikki/run"
    local base_url='https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest'
    local file source
    mkdir -p "$target"

    for file in GeoSite.dat GeoIP.dat ASN.mmdb geoip.metadb; do
        case "$file" in
            GeoSite.dat) source="$base_url/geosite.dat" ;;
            GeoIP.dat) source="$base_url/geoip.dat" ;;
            ASN.mmdb) source="$base_url/GeoLite2-ASN.mmdb" ;;
            geoip.metadb) source="$base_url/geoip.metadb" ;;
        esac
        echo "预装 Nikki Geo 数据: $file <- $source"
        curl_retry -fsSL -o "$target/$file" "$source"
        [ -s "$target/$file" ] || {
            echo "错误：Geo 数据为空：$target/$file" >&2
            return 1
        }
    done

    ln -sfn GeoSite.dat "$target/geosite.dat"
    ln -sfn GeoIP.dat "$target/geoip.dat"
}

jdcloud_update_nikki_geodata_urls() {
    local nikki_conf="$BUILD_DIR/feeds/custom_feed/nikki/files/nikki.conf"
    [ -f "$nikki_conf" ] || return 0

    local sed_in_place=(-i)
    if ! sed --version >/dev/null 2>&1; then
        sed_in_place=(-i '')
    fi
    sed "${sed_in_place[@]}" \
        -e "s|^[[:space:]]*option 'geosite_url'.*|\toption 'geosite_url' 'https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat'|" \
        -e "s|^[[:space:]]*option 'geoip_mmdb_url'.*|\toption 'geoip_mmdb_url' 'https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/Country.mmdb'|" \
        -e "s|^[[:space:]]*option 'geoip_dat_url'.*|\toption 'geoip_dat_url' 'https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat'|" \
        -e "s|^[[:space:]]*option 'geoip_asn_url'.*|\toption 'geoip_asn_url' 'https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/GeoLite2-ASN.mmdb'|" \
        "$nikki_conf"
}

install_jdcloud_ax6600_customization() {
    is_jdcloud_ax6600_build || return 0
    jdcloud_validate_inputs
    jdcloud_install_extra_packages
    install -Dm755 "$BASE_PATH/patches/jdcloud_ax6600/98-jdcloud-ax6600.sh" \
        "$BUILD_DIR/package/base-files/files/etc/uci-defaults/98-jdcloud-ax6600.sh"
    jdcloud_write_settings
    jdcloud_download_mihomo
    jdcloud_download_nikki_geodata
    jdcloud_update_nikki_geodata_urls
}
