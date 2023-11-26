# ROOT
if [ "$EUID" -ne 0 ]; then
    echo "RUN AS ROOT ^^!"
    exit 1
fi

# Update
sudo apt-get update && sudo apt-get upgrade

# Package requirement
sudo apt-get install -y g++ build-essential make net-tools git curl wget openssl gcc libssl-dev libpcre3 libpcre3-dev zlib1g-dev lua5.1-dev luarocks
luarocks install luafilesystem

# Varible 
nginx_ver='1.25.2'
NGX_DEVEL_KIT_VERSION='0.3.2'
LUA_NGINX_MODULE_VERSION='0.10.25'
PATH_DOWNLOAD='/opt/nginx-build'
NGX_DEVEL_KIT_PATH=$PATH_DOWNLOAD/ngx_devel_kit-${NGX_DEVEL_KIT_VERSION}
LUA_NGINX_MODULE_PATH=$PATH_DOWNLOAD/lua-nginx-module-${LUA_NGINX_MODULE_VERSION}

mkdir $PATH_DOWNLOAD
cd $PATH_DOWNLOAD

# Download LUAJIT
git clone https://github.com/openresty/luajit2.git
cd luajit2/
make && make install

cd $PATH_DOWNLOAD
# Download nginx
    wget http://nginx.org/download/nginx-${nginx_ver}.tar.gz

# Download ngx_devel_kit
    wget https://github.com/simpl/ngx_devel_kit/archive/v${NGX_DEVEL_KIT_VERSION}.tar.gz \
        -O ngx_devel_kit-${NGX_DEVEL_KIT_VERSION}.tar.gz

# Download lua-nginx-module
wget https://github.com/openresty/lua-nginx-module/archive/v${LUA_NGINX_MODULE_VERSION}.tar.gz \
        -O lua-nginx-module-${LUA_NGINX_MODULE_VERSION}.tar.gz

# Extract
find . -type f -name '*.tar.gz' -exec tar -xzf {} \;

## Config
cd /usr/local/include/luajit-2.1/
LUAJIT_LIB=/usr/local/lib LUAJIT_INC=/usr/local/include/luajit-2.1

cd $PATH_DOWNLOAD
cd nginx-${nginx_ver}
LUAJIT_LIB=/usr/local/lib LUAJIT_INC=/usr/local/include/luajit-2.1 \
     ./configure \
     --user=nginx                          \
     --group=nginx                         \
     --prefix=/opt/nginx                   \
     --sbin-path=/usr/sbin/nginx           \
     --conf-path=/opt/nginx/nginx.conf     \
     --pid-path=/run/nginx.pid         \
     --lock-path=/run/nginx.lock       \
     --error-log-path=/var/log/nginx/error.log \
     --http-log-path=/var/log/nginx/access.log \
     --with-http_gzip_static_module        \
     --with-http_stub_status_module        \
     --with-http_ssl_module                \
     --with-pcre-jit                           \
     --with-debug                           \
     --with-compat                           \
     --with-file-aio                       \
     --with-http_realip_module             \
     --without-http_scgi_module            \
     --without-http_uwsgi_module           \
     --without-http_fastcgi_module ${NGINX_DEBUG:+--debug} \
     --with-cc-opt=-O2 --with-ld-opt='-Wl,-rpath,/usr/local/lib' \
     --add-dynamic-module=/opt/nginx-build/ngx_devel_kit-${NGX_DEVEL_KIT_VERSION}	\
     --add-dynamic-module=/opt/nginx-build/lua-nginx-module-${LUA_NGINX_MODULE_VERSION}

#     --add-dynamic-module=/opt/nginx-build/ngx_devel_kit-0.3.2	\
#     --add-dynamic-module=/opt/nginx-build/lua-nginx-module-0.10.25

make && make modules && make install

# Config nginx
useradd -r -M -s /sbin/nologin -d /opt/nginx nginx
chown -R nginx:nginx /opt/nginx

# Add lua-resty-core and lua-resty-lrucache
cd $PATH_DOWNLOAD
git clone https://github.com/openresty/lua-resty-core.git
cd lua-resty-core
make install PREFIX=/opt/nginx

cd $PATH_DOWNLOAD
git clone https://github.com/openresty/lua-resty-lrucache.git
cd lua-resty-lrucache
make install PREFIX=/opt/nginx

# Path to the systemd configuration file for the Nginx service
systemd_service_file="/etc/systemd/system/nginx.service"

# Contents of the systemd configuration file
nginx_service_content="
[Unit]
Description=A high performance web server and a reverse proxy server
Documentation=man:nginx(8)
After=network.target nss-lookup.target

[Service]
Type=forking
PIDFile=/run/nginx.pid  
ExecStartPre=/usr/sbin/nginx -t -q -g 'daemon on; master_process on;'
ExecStart=/usr/sbin/nginx -g 'daemon on; master_process on;'
ExecReload=/usr/sbin/nginx -g 'daemon on; master_process on;' -s reload
ExecStop=-/sbin/start-stop-daemon --quiet --stop --retry QUIT/5 --pidfile /run/nginx.pid  
TimeoutStopSec=5
KillMode=mixed

[Install]
WantedBy=multi-user.target
"

# Create systemd configuration file
echo "$nginx_service_content" | sudo tee "$systemd_service_file"

# Add module
sed -i '1i\load_module /opt/nginx/modules/ngx_http_lua_module.so;' /opt/nginx/nginx.conf
sed -i '1i\load_module /opt/nginx/modules/ndk_http_module.so;' /opt/nginx/nginx.conf
sed -i '10i\pid /run/nginx.pid;' /opt/nginx/nginx.conf
sed -i '30i\lua_package_path "/opt/nginx/lib/lua/?.lua;;/opt/nginx/lua-nginx-script/?.lua;;";' /opt/nginx/nginx.conf

# Config services
systemctl daemon-reload
sudo systemctl start nginx
sudo systemctl restart nginx
sudo systemctl enable nginx
sudo systemctl status nginx
