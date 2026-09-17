#!/usr/bin/env bash
# 生成自签名 TLS 证书（固定 IP、无域名场景）——服务端 HTTPS 用。
#
# 用法:
#   ./generate_tls_cert.sh [选项]
#     --ip <IP>            写入 SAN 的 IP（默认取本机第一个 IP；生产即 47.112.20.32）
#     --dns <name>         额外写入一个 DNS SAN（可选；将来有域名时用）
#     --days <N>           有效期天数（默认 3650 = 10 年；自签名无法自动续期，故给长）
#     --cert <path>        证书输出路径（默认 ./certs/server.crt）
#     --key <path>         私钥输出路径（默认 ./certs/server.key）
#     --force              已存在时覆盖（默认拒绝，防误覆盖导致已装 App 失联）
#
# 关键约束（改了会导致 App 无法连接）:
#   1. SAN 必须含客户端连接的写法——App 用 IP 直连，就必须有 IP SAN
#      （现代 TLS 栈不看 CN，只认 SAN；IP 不能写进 DNS SAN）。
#   2. 证书一旦装进 App，重新生成会让旧 App 全面失联——重生成后必须
#      同步更新 android/app/src/main/res/raw/contexta_server.crt 并重新打包。
#
# 生成后由部署流程拷贝到服务器 /opt/contexta/server/certs/（私钥不提交仓库）。
set -euo pipefail

CERT_PATH="./certs/server.crt"
KEY_PATH="./certs/server.key"
IP=""
DNS=""
DAYS=3650
FORCE=0

die() { echo "错误: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --ip)    IP="$2"; shift 2 ;;
    --dns)   DNS="$2"; shift 2 ;;
    --days)  DAYS="$2"; shift 2 ;;
    --cert)  CERT_PATH="$2"; shift 2 ;;
    --key)   KEY_PATH="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) die "未知参数: $1（--help 查看用法）" ;;
  esac
done

command -v openssl >/dev/null || die "未安装 openssl"

# 默认 SAN 取本机第一个 IP（服务器上执行即公网 IP；若不符请显式 --ip）
[ -n "$IP" ] || IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
[ -n "$IP" ] || die "无法自动探测本机 IP，请用 --ip 指定"

SAN="IP:$IP"
[ -n "$DNS" ] && SAN="$SAN,DNS:$DNS"

if [ -e "$CERT_PATH" ] || [ -e "$KEY_PATH" ]; then
  [ "$FORCE" = 1 ] || die "$CERT_PATH 或 $KEY_PATH 已存在——覆盖会使已装 App 失联；确认要重签请加 --force"
fi

mkdir -p "$(dirname "$CERT_PATH")" "$(dirname "$KEY_PATH")"

# 临时配置：仅供 -subj 的 DN 占位（真正的扩展经 -addext 传，跨 OpenSSL 1.1/3.x 一致）
TMP_CNF="$(mktemp)"
trap 'rm -f "$TMP_CNF"' EXIT
cat > "$TMP_CNF" <<'EOF'
[req]
distinguished_name = dn
[dn]
EOF

# EC P-256（Android 9+ / iOS 12+ 原生支持，体积小）；自签名 leaf 带 CA:TRUE，
# 客户端（含 Android network security config 的锚点校验：编码一致 + 自签）直接把它当信任锚。
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
  -keyout "$KEY_PATH" -out "$CERT_PATH" \
  -days "$DAYS" -nodes -sha256 \
  -subj "/CN=$IP" \
  -addext "subjectAltName=$SAN" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,digitalSignature,keyEncipherment,keyCertSign" \
  -addext "extendedKeyUsage=serverAuth" \
  -config "$TMP_CNF" 2>/dev/null

chmod 644 "$CERT_PATH"
chmod 600 "$KEY_PATH"

echo "已生成自签名证书:"
echo "  证书: $CERT_PATH"
echo "  私钥: $KEY_PATH"
echo "  SAN : $SAN"
openssl x509 -in "$CERT_PATH" -noout -subject -dates -ext subjectAltName | sed 's/^/  /'
