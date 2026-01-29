Debian/Ubuntu 系统清理

bash <(curl -sL https://raw.githubusercontent.com/adwzlad/AAcustom/main/clean-debian.sh)

更换系统语言、修改时区/密码/SSH

bash <(curl -sL https://raw.githubusercontent.com/adwzlad/AAcustom/main/Debian-Setting.sh)

bash <(curl -sL https://raw.githubusercontent.com/adwzlad/AAcustom/main/CentOS-Setting.sh)

CF通配符域名证书   申请失败/续签/重跑（不会再问任何问题） bash ssl.sh 如果你想换域名/Token  rm -f /root/.acme-auto/config && bash ssl.sh

bash <(curl -sL https://raw.githubusercontent.com/adwzlad/AAcustom/main/SSL_CF_DNS1.sh)

生成/usr/local/openresty/nginx/cloudflare_ips.conf，并定时更新

bash <(curl -sL https://raw.githubusercontent.com/adwzlad/AAcustom/main/arm_openresty_cloudflare_ips.sh)

在指定路径生成伪域名证书

bash <(curl -sL https://raw.githubusercontent.com/adwzlad/AAcustom/raw/main/fake_cert.sh)

如何安装 bash（如果未安装），如果 which bash 或 command -v bash 有输出，说明 bash 已安装

opkg update

opkg install bash
