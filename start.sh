#!/bin/bash
set -e

echo "🚀 Starting 3x-ui + nginx reverse proxy on Railway..."

# ============================================
# Railway پورت رو از طریق $PORT میده
# ============================================
if [ -z "$PORT" ]; then
    echo "⚠️  PORT is not set! Using default 3000"
    export PORT=3000
fi

# Nginx روی پورتی که Railway داده گوش میده
export NGINX_PORT=$PORT

# دامنه (برای SSL و Host)
export DOMAIN=${DOMAIN:-"localhost"}

cd /usr/local/x-ui

# ============================================
# تنظیمات X-UI Panel
# ============================================
echo "🔧 Applying panel settings via x-ui CLI..."
./x-ui setting -port 2053 -webBasePath /managepanel/ || true

# ============================================
# ایجاد دایرکتوری SSL
# ============================================
mkdir -p /etc/nginx/ssl

# ============================================
# تولید سرتیفیکیت خودامضا (برای Railway)
# ============================================
if [ ! -f "/etc/nginx/ssl/fullchain.pem" ] || [ ! -f "/etc/nginx/ssl/privkey.pem" ]; then
    echo "🔑 Generating self-signed SSL certificate for $DOMAIN..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/privkey.pem \
        -out /etc/nginx/ssl/fullchain.pem \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=${DOMAIN}" 2>/dev/null
    echo "✅ Self-signed certificate generated."
fi

# ============================================
# تولید کانفیگ Nginx با متغیرهای محیطی
# ============================================
echo "🔧 Building nginx.conf for port: $NGINX_PORT"
envsubst '${NGINX_PORT} ${DOMAIN}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

# نمایش کانفیگ برای دیباگ
echo "📄 Nginx configuration generated on port $NGINX_PORT"

# ============================================
# اجرای X-UI در پس‌زمینه
# ============================================
echo "▶️  Starting x-ui in background..."
./x-ui &
X_UI_PID=$!

# ============================================
# انتظار برای آماده‌شدن X-UI
# ============================================
echo "⏳ Waiting for X-UI to be ready on port 2053..."
TIMEOUT=30
while ! nc -z localhost 2053 2>/dev/null; do
    sleep 1
    TIMEOUT=$((TIMEOUT - 1))
    if [ $TIMEOUT -le 0 ]; then
        echo "❌ X-UI failed to start after 30 seconds!"
        kill $X_UI_PID 2>/dev/null || true
        exit 1
    fi
done
echo "✅ X-UI is ready!"

# ============================================
# تست و اجرای Nginx
# ============================================
echo "▶️  Testing nginx configuration..."
nginx -t

echo "▶️  Starting nginx in foreground on port $NGINX_PORT..."
exec nginx -g "daemon off;"
