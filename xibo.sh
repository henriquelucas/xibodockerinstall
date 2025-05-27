#!/bin/bash

# -------- Pergunta inicial: domínio ou IP --------
read -p "Deseja usar um domínio para o Xibo CMS? (s/n): " USAR_DOMINIO

if [[ "$USAR_DOMINIO" =~ ^[Ss]$ ]]; then
    read -p "Digite o domínio (ex: painel.suaempresa.com.br): " DOMAIN
    read -p "Digite o e-mail para SSL (Certbot): " EMAIL
else
    DOMAIN=""
    EMAIL=""
fi

# -------- Verificar quantas instâncias já existem --------
NUM_INSTANCES=$(docker ps -a --filter "name=xibo" --format "{{.Names}}" | grep -c '^xibo[0-9]\+')
if [[ -z "$NUM_INSTANCES" ]]; then
    NUM_INSTANCES=0
fi
INSTANCE_INDEX=$((NUM_INSTANCES + 1))
INSTANCE_NAME="xibo${INSTANCE_INDEX}"

# -------- Definições de portas baseadas no índice --------
# HTTP padrão: 8080 + (INSTANCE_INDEX -1)*10  (ex: xibo1=8080, xibo2=8090)
# XMR padrão: 9505 + (INSTANCE_INDEX -1)*10   (ex: xibo1=9505, xibo2=9515)
PORT_HTTP=$((8080 + (INSTANCE_INDEX - 1) * 10))
PORT_XMR=$((9505 + (INSTANCE_INDEX - 1) * 10))

# -------- Diretório da instância --------
XIBO_DIR="/opt/$INSTANCE_NAME"

echo "[0/15] Instância detectada: $INSTANCE_NAME"
echo "Portas configuradas: HTTP $PORT_HTTP, XMR $PORT_XMR"
echo "Diretório: $XIBO_DIR"
echo

# -------- Começar instalação --------
echo "[1/15] Instalando dependências..."
apt update && apt install -y docker-compose apache2 snapd unzip curl ufw

echo "[2/15] Criando diretório do Xibo..."
mkdir -p "$XIBO_DIR"
cd "$XIBO_DIR" || { echo "Erro ao acessar diretório $XIBO_DIR"; exit 1; }

echo "[3/15] Baixando e extraindo arquivos do Xibo..."
wget -O xibo-docker.tar.gz https://xibosignage.com/api/downloads/cms
tar --strip-components=1 -zxvf xibo-docker.tar.gz
rm xibo-docker.tar.gz

echo "[4/15] Criando arquivo config.env..."
cp config.env.template config.env

# Gerar senha aleatória para MySQL
MYSQL_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16 ; echo '')
sed -i "s/^MYSQL_PASSWORD=.*/MYSQL_PASSWORD=$MYSQL_PASSWORD/" config.env

# -------- Criar docker-compose customizado para as portas --------
echo "[5/15] Criando docker-compose customizado com portas personalizadas..."

cat > docker-compose.custom.yml <<EOF
version: "3.7"

services:
  cms-db:
    image: mysql:8.0
    volumes:
      - ./mysql:/var/lib/mysql
    environment:
      MYSQL_ROOT_PASSWORD: $MYSQL_PASSWORD
      MYSQL_DATABASE: xibo
      MYSQL_USER: xibo
      MYSQL_PASSWORD: $MYSQL_PASSWORD
    restart: always

  cms-web:
    image: ghcr.io/xibosignage/xibo-cms:release-4.2.3
    ports:
      - "$PORT_HTTP:80"
    environment:
      XMR_HOST: cms-xmr
      MYSQL_HOST: cms-db
      MYSQL_PASSWORD: $MYSQL_PASSWORD
    depends_on:
      - cms-db
    restart: always

  cms-xmr:
    image: ghcr.io/xibosignage/xibo-xmr:1.0
    ports:
      - "$PORT_XMR:9505"
    restart: always
  cms-memcached:
        image: memcached:alpine
        command: memcached -m 15
        restart: always
        mem_limit: 100M

  cms-quickchart:
    image: ianw/quickchart
    restart: always
EOF

echo "[6/15] Subindo os containers Docker..."
docker-compose -f docker-compose.custom.yml up -d

# -------- Configurar firewall --------
echo "[7/15] Configurando firewall (UFW)..."
ufw allow OpenSSH
ufw allow "$PORT_HTTP"/tcp
ufw allow "$PORT_XMR"/tcp
ufw --force enable

# -------- Configuração do Apache e Certificado (se domínio) --------
if [[ "$USAR_DOMINIO" =~ ^[Ss]$ ]]; then
    echo "[8/15] Configurando Apache com proxy reverso para $DOMAIN..."

    a2enmod proxy proxy_http headers

    cat > /etc/apache2/sites-available/$INSTANCE_NAME.conf <<EOF
<VirtualHost *:80>
    ServerAdmin $EMAIL
    ServerName $DOMAIN
    DocumentRoot /var/www/html

    ProxyPreserveHost On
    RequestHeader set X-Forwarded-Proto expr=%{REQUEST_SCHEME}

    ProxyPass / http://127.0.0.1:$PORT_HTTP/
    ProxyPassReverse / http://127.0.0.1:$PORT_HTTP/

    ErrorLog \${APACHE_LOG_DIR}/$INSTANCE_NAME-error.log
    CustomLog \${APACHE_LOG_DIR}/$INSTANCE_NAME-access.log combined
</VirtualHost>
EOF

    a2ensite $INSTANCE_NAME.conf
    systemctl reload apache2

    echo "[9/15] Instalando Certbot..."
    snap install core && snap refresh core
    apt-get remove certbot -y
    snap install --classic certbot
    ln -sf /snap/bin/certbot /usr/bin/certbot

    echo "[10/15] Emitindo certificado SSL com Certbot para $DOMAIN..."
    certbot --apache --non-interactive --agree-tos -m "$EMAIL" -d "$DOMAIN"

    echo "[11/15] Criando regra de renovação automática para Certbot..."
    cat > /etc/cron.daily/certbot-renew <<EOF
#!/bin/bash
/usr/bin/certbot renew --quiet --deploy-hook "systemctl reload apache2"
EOF
    chmod +x /etc/cron.daily/certbot-renew

else
    echo "[8/15] Pulando configuração Apache e SSL, usando IP e portas padrão."
fi

echo "[12/15] Instalação concluída!"

if [[ "$USAR_DOMINIO" =~ ^[Ss]$ ]]; then
    echo "✅ Acesse agora o Xibo CMS:"
    echo "   👉 https://$DOMAIN"
else
    IP_ADDR=$(hostname -I | awk '{print $1}')
    echo "✅ Acesse agora o Xibo CMS pelo IP:"
    echo "   👉 http://$IP_ADDR:$PORT_HTTP"
fi

echo
echo "🔐 Credenciais padrão:"
echo "   Usuário: xibo_admin"
echo "   Senha:   passwd"
echo
echo "🔑 Senha do banco MYSQL gerada automaticamente:"
echo "   $MYSQL_PASSWORD"
echo
echo "🔄 A renovação automática do certificado SSL está configurada (se configurado)."
