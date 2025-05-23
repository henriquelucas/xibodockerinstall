#!/bin/bash

# -------- INTERAÇÃO INICIAL --------
read -p "Digite o domínio (ex: painel.suaempresa.com.br): " DOMAIN
read -p "Digite o e-mail para SSL (Certbot): " EMAIL

# -------- CONFIGURAÇÕES --------
XIBO_DIR="/opt/xibo"
MYSQL_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16 ; echo '')

echo "[1/13] Instalando dependências..."
apt update && apt install -y docker-compose apache2 snapd unzip curl ufw

echo "[2/13] Criando diretório do Xibo..."
mkdir -p "$XIBO_DIR"
cd "$XIBO_DIR"

echo "[3/13] Baixando e extraindo arquivos do Xibo..."
wget -O xibo-docker.tar.gz https://xibosignage.com/api/downloads/cms
tar --strip-components=1 -zxvf xibo-docker.tar.gz
rm xibo-docker.tar.gz

echo "[4/13] Criando arquivo config.env..."
cp config.env.template config.env
sed -i "s/^MYSQL_PASSWORD=.*/MYSQL_PASSWORD=$MYSQL_PASSWORD/" config.env

echo "[5/13] Configurando custom ports (loopback HTTP)..."
cp cms_custom-ports.yml.template cms_custom-ports.yml
rm docker-compose.yml
sed -i 's/65500:9505/9505:9505/' cms_custom-ports.yml
sed -i 's/65501:80/127.0.0.1:8080:80/' cms_custom-ports.yml

echo "[6/13] Subindo os containers Docker..."
docker compose -f cms_custom-ports.yml up -d

echo "[7/13] Configurando Apache com proxy reverso..."
a2enmod proxy proxy_http headers
cat <<EOF > /etc/apache2/sites-available/000-default.conf
<VirtualHost *:80>
    ServerAdmin $EMAIL
    ServerName $DOMAIN
    DocumentRoot /var/www/html

    ProxyPreserveHost On
    RequestHeader set X-Forwarded-Proto expr=%{REQUEST_SCHEME}

    ProxyPass / http://127.0.0.1:8080/
    ProxyPassReverse / http://127.0.0.1:8080/

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

echo "[8/13] Reiniciando Apache..."
systemctl restart apache2

echo "[9/13] Abrindo portas no firewall UFW..."
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 9505/tcp
ufw --force enable

echo "[10/13] Instalando Certbot..."
snap install core && snap refresh core
apt-get remove certbot -y
snap install --classic certbot
ln -sf /snap/bin/certbot /usr/bin/certbot

echo "[11/13] Emitindo certificado SSL com Certbot..."
certbot --apache --non-interactive --agree-tos -m "$EMAIL" -d "$DOMAIN"

echo "[12/13] Criando regra de renovação automática para Certbot..."
cat <<EOF > /etc/cron.daily/certbot-renew
#!/bin/bash
/usr/bin/certbot renew --quiet --deploy-hook "systemctl reload apache2"
EOF

chmod +x /etc/cron.daily/certbot-renew

echo "[13/13] Instalação concluída!"
echo
echo "✅ Acesse agora o Xibo CMS:"
echo "   👉 http://$DOMAIN"
echo "   👉 https://$DOMAIN"
echo
echo "🔐 Credenciais padrão:"
echo "   Usuário: xibo_admin"
echo "   Senha:   passwd"
echo
echo "🔑 Senha do banco MYSQL gerada automaticamente:"
echo "   $MYSQL_PASSWORD"
echo
echo "🔄 A renovação automática do certificado SSL está configurada."
