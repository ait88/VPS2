#!/bin/bash

# --- CONFIGURABLE DEFAULTS ---
DEFAULT_WP_USER="wpuser"
DEFAULT_WP_WEBROOT="/var/www/wordpress"
DEFAULT_WP_DB_NAME="wordpress_db"
DEFAULT_WP_DB_USER="wp_db_user"
DEFAULT_PHP_VERSION="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
DEFAULT_DOMAIN="yourdomain.com"
DEFAULT_EMAIL="admin@$DEFAULT_DOMAIN"

# --- PRE-FLIGHT CHECKS ---
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root."
    exit 1
fi

# --- COLLECT VARIABLES ---
read -p "WordPress system username [$DEFAULT_WP_USER]: " WP_USER
WP_USER="${WP_USER:-$DEFAULT_WP_USER}"

read -p "WordPress web root [$DEFAULT_WP_WEBROOT]: " WP_WEBROOT
WP_WEBROOT="${WP_WEBROOT:-$DEFAULT_WP_WEBROOT}"

read -p "WordPress DB name [$DEFAULT_WP_DB_NAME]: " WP_DB_NAME
WP_DB_NAME="${WP_DB_NAME:-$DEFAULT_WP_DB_NAME}"

read -p "WordPress DB user [$DEFAULT_WP_DB_USER]: " WP_DB_USER
WP_DB_USER="${WP_DB_USER:-$DEFAULT_WP_DB_USER}"

read -s -p "WordPress DB password [random]: " WP_DB_PASS
echo
if [ -z "$WP_DB_PASS" ]; then
    WP_DB_PASS="$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9!@#$%^&*_' | head -c 24)"
    echo "Generated DB password: $WP_DB_PASS"
fi

read -p "PHP version [$DEFAULT_PHP_VERSION]: " PHP_VERSION
PHP_VERSION="${PHP_VERSION:-$DEFAULT_PHP_VERSION}"

read -p "Domain for this site [$DEFAULT_DOMAIN]: " DOMAIN
DOMAIN="${DOMAIN:-$DEFAULT_DOMAIN}"

read -p "Email for SSL cert [$DEFAULT_EMAIL]: " EMAIL
EMAIL="${EMAIL:-$DEFAULT_EMAIL}"

read -p "Include www. alias? [Y/n]: " INC_WWW
INC_WWW="${INC_WWW:-Y}"
WWW_DOMAIN=""
[ "$INC_WWW" != "n" ] && WWW_DOMAIN="www.$DOMAIN"

# --- ENSURE REQUIRED PACKAGES ---
echo "Ensuring nginx, PHP-FPM, MariaDB, curl, unzip, and certbot are installed..."
apt update
apt install -y nginx php$PHP_VERSION-fpm mariadb-server php$PHP_VERSION-mysql php$PHP_VERSION-xml php$PHP_VERSION-curl php$PHP_VERSION-gd php$PHP_VERSION-mbstring php$PHP_VERSION-zip php$PHP_VERSION-xmlrpc php$PHP_VERSION-intl php$PHP_VERSION-bcmath curl unzip certbot python3-certbot-nginx

# --- CREATE SYSTEM USER & WEBROOT ---
id "$WP_USER" &>/dev/null || adduser --disabled-login --gecos "" "$WP_USER"
mkdir -p "$WP_WEBROOT"
chown "$WP_USER:$WP_USER" "$WP_WEBROOT"
chmod 750 "$WP_WEBROOT"

# --- CONFIGURE PHP-FPM POOL ---
POOL_CONF="/etc/php/$PHP_VERSION/fpm/pool.d/$WP_USER.conf"
cat > "$POOL_CONF" <<EOF
[$WP_USER]
user = $WP_USER
group = $WP_USER
listen = /run/php/php$PHP_VERSION-fpm-$WP_USER.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
php_admin_value[open_basedir] = $WP_WEBROOT:/tmp
php_admin_value[disable_functions] = exec,passthru,shell_exec,system,proc_open,popen,curl_exec,curl_multi_exec,parse_ini_file,show_source
php_admin_flag[expose_php] = off
php_admin_value[error_log] = /var/log/php-fpm/${WP_USER}_error.log
php_admin_flag[log_errors] = on
chdir = /
clear_env = yes
EOF

systemctl reload php$PHP_VERSION-fpm

# --- DATABASE SETUP ---
mysql -u root <<MYSQL_EOF
CREATE DATABASE IF NOT EXISTS $WP_DB_NAME DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$WP_DB_USER'@'localhost' IDENTIFIED BY '$WP_DB_PASS';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER, REFERENCES ON $WP_DB_NAME.* TO '$WP_DB_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_EOF

# --- NGINX CONFIGURATION ---
NGINX_SITE="/etc/nginx/sites-available/wordpress"
cat > "$NGINX_SITE" <<EOF
server {
    listen 80;
    server_name $DOMAIN $WWW_DOMAIN;

    root $WP_WEBROOT;
    index index.php index.html;

    if (\$request_method !~ ^(GET|POST|HEAD)\$ ) {
        return 444;
    }

    location ~ /\.(?!well-known).* {
        deny all;
        access_log off;
        log_not_found off;
    }

    location = /xmlrpc.php {
        deny all;
        access_log off;
        log_not_found off;
    }

    location = /wp-config.php {
        deny all;
    }

    location ~* /(?:uploads|files|wp-content|wp-includes)/.*\.php\$ {
        deny all;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php$PHP_VERSION-fpm-$WP_USER.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
    gzip_min_length 256;

    client_max_body_size 32M;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    access_log /var/log/nginx/wordpress_access.log;
    error_log /var/log/nginx/wordpress_error.log;
}
EOF

ln -sf "$NGINX_SITE" /etc/nginx/sites-enabled/wordpress
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# --- DOWNLOAD & CONFIGURE WORDPRESS ---
sudo -u "$WP_USER" curl -o /tmp/wordpress.tar.gz https://wordpress.org/latest.tar.gz
sudo -u "$WP_USER" tar -xzf /tmp/wordpress.tar.gz -C /tmp
sudo -u "$WP_USER" rsync -avP /tmp/wordpress/ "$WP_WEBROOT/"
sudo -u "$WP_USER" cp "$WP_WEBROOT/wp-config-sample.php" "$WP_WEBROOT/wp-config.php"

# Generate WP salts
SALTS="$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)"

# Configure wp-config.php
sudo -u "$WP_USER" sed -i "s/database_name_here/$WP_DB_NAME/" "$WP_WEBROOT/wp-config.php"
sudo -u "$WP_USER" sed -i "s/username_here/$WP_DB_USER/" "$WP_WEBROOT/wp-config.php"
sudo -u "$WP_USER" sed -i "s/password_here/$WP_DB_PASS/" "$WP_WEBROOT/wp-config.php"
sudo -u "$WP_USER" sed -i "s/localhost/localhost/" "$WP_WEBROOT/wp-config.php"
sudo -u "$WP_USER" sed -i "/AUTH_KEY/d;/SECURE_AUTH_KEY/d;/LOGGED_IN_KEY/d;/NONCE_KEY/d;/AUTH_SALT/d;/SECURE_AUTH_SALT/d;/LOGGED_IN_SALT/d;/NONCE_SALT/d" "$WP_WEBROOT/wp-config.php"
sudo -u "$WP_USER" sed -i "/^define('DB_COLLATE'/a $SALTS" "$WP_WEBROOT/wp-config.php"
sudo -u "$WP_USER" sed -i "/^define('DB_COLLATE'/a define('DISALLOW_FILE_EDIT', true);" "$WP_WEBROOT/wp-config.php"
sudo -u "$WP_USER" sed -i "/^define('DB_COLLATE'/a define('FS_METHOD', 'direct');" "$WP_WEBROOT/wp-config.php"

# --- PERMISSIONS LOCKDOWN ---
chown -R "$WP_USER:$WP_USER" "$WP_WEBROOT"
find "$WP_WEBROOT" -type d -exec chmod 750 {} \;
find "$WP_WEBROOT" -type f -exec chmod 640 {} \;
chmod 600 "$WP_WEBROOT/wp-config.php"
chmod -R 750 "$WP_WEBROOT/wp-content"
chmod -R 750 "$WP_WEBROOT/wp-content/uploads"

# --- LET'S ENCRYPT SSL ---
echo
echo "Would you like to request an SSL certificate now? (domain must resolve here)"
read -p "Run certbot? [y/N]: " RUN_CERT
if [[ "$RUN_CERT" =~ ^[Yy]$ ]]; then
    certbot --nginx -d "$DOMAIN" ${WWW_DOMAIN:+-d $WWW_DOMAIN} --email "$EMAIL" --agree-tos --redirect
    systemctl reload nginx
    echo "SSL certificate installed!"
else
    echo "Skipping SSL setup for now. You can run 'certbot --nginx -d $DOMAIN -d $WWW_DOMAIN' later."
fi

# --- FINAL OUTPUT ---
echo
echo "WordPress stack setup is complete!"
echo "--------------------------------------------------"
echo "Site URL: http://$DOMAIN"
echo "Admin: Complete browser setup at http://$DOMAIN/wp-admin/"
echo "Database: $WP_DB_NAME"
echo "DB User: $WP_DB_USER"
echo "DB Password: $WP_DB_PASS"
echo "Site files: $WP_WEBROOT (owned by $WP_USER)"
echo "PHP-FPM pool: $POOL_CONF"
echo "nginx conf: $NGINX_SITE"
echo "SSL: Use certbot later if not done now."
echo
echo "For best security, take a VPS snapshot now before import or site customization."
echo "--------------------------------------------------"

