更换系统语言、修改时区/密码

bash <(curl -sL https://github.com/adwzlad/AAcustom/raw/main/debian11-setting.sh)

bash <(curl -sL https://testingcf.jsdelivr.net/gh/adwzlad/AAcustom@main/debian11-setting.sh)

Oracle自动获取IPV6

bash <(curl -sL https://github.com/adwzlad/AAcustom/raw/main/oracle_ipv6_checker.sh)

bash <(curl -sL https://testingcf.jsdelivr.net/gh/adwzlad/AAcustom@main/oracle_ipv6_checker.sh)

生成/etc/nginx/cloudflare_ips.conf，并定时每天凌晨 2 点更新

bash <(curl -sL https://github.com/adwzlad/AAcustom/raw/main/nginx-cloudflare_ips.sh)

bash <(curl -sL https://testingcf.jsdelivr.net/gh/adwzlad/AAcustom@main/nginx-cloudflare_ips.sh)

生成/usr/local/openresty/nginx/cloudflare_ips.conf，并定时更新

bash <(curl -sL https://github.com/adwzlad/AAcustom/raw/main/arm_openresty_cloudflare_ips.sh)

bash <(curl -sL https://testingcf.jsdelivr.net/gh/adwzlad/AAcustom@main/arm_openresty_cloudflare_ips.sh)

在指定路径生成伪域名证书

bash <(curl -sL https://github.com/adwzlad/AAcustom/raw/main/fake_cert.sh)

bash <(curl -sL https://testingcf.jsdelivr.net/gh/adwzlad/AAcustom@main/fake_cert.sh)

UFW防火墙规则配置，并定时每天凌晨 4 点更新关于cloudflare_ip的规则

bash <(curl -sL https://github.com/adwzlad/AAcustom/raw/main/manage_ufw.sh)

bash <(curl -sL https://testingcf.jsdelivr.net/gh/adwzlad/AAcustom@main/manage_ufw.sh)

Openwrt裸核运行sing-box,并添加防火墙规则

bash <(curl -sL https://github.com/adwzlad/AAcustom/raw/main/setup_singbox_tun.sh)

bash <(curl -sL https://testingcf.jsdelivr.net/gh/adwzlad/AAcustom@main/setup_singbox_tun.sh)

Openwrt删除相关防火墙规则，并停止运行sing-box

bash <(curl -sL https://github.com/adwzlad/AAcustom/raw/main/stop_singbox_tun.sh)

bash <(curl -sL https://testingcf.jsdelivr.net/gh/adwzlad/AAcustom@main/stop_singbox_tun.sh)
