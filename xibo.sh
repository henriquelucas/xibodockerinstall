#!/bin/bash

# -------- INTERAÇÃO INICIAL --------
read -p "Deseja utilizar um domínio para o Xibo CMS? (s/n): " USE_DOMAIN

if [[ "$USE_DOMAIN" == "s" ]]; then
    read -p "Digite o domínio (ex: painel.suaempresa.com.br): " DOMAIN
    read -p "Digite o e-mail para SSL (Certbot): " EMAIL
fi

# -------- FUNÇÃO PARA CHECAR EXISTÊNCIA DE CONTAINER XIBO --------
# Retorna o próximo índice para evitar conflito de nomes/portas
function get_next_instance_index() {
    base_name="xibo"
    index=0
    while true; do
        # Nome do container esperado
        if [[ $index -eq 0 ]]; then
            container_name="${base_name}_cms"
        else
            container_name="${base_name}${index}_cms"
        fi

        # Checa se container existe
        if docker ps -a --format '{{.Names}}' | grep -qw "$container_name"; then
            ((index++))
        else
            echo "$index"
            return
        fi
    done
}

# -------- CONFIGURAÇÕES INICIAIS --------
XIBO_DIR_BASE="/opt/xibo"
MYSQL_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16 ; echo '')

# Obtem índice incremental para evitar conflito de instância
INSTANCE_INDEX=$(get_next_instance_index)

# Define prefixo e porta base
if [[ "$INSTANCE_INDEX" -eq 0 ]]; then
    INSTANCE_SUFFIX=""
else
    INSTANCE_SUFFIX="$INSTANCE_INDEX"
fi

# Define nome da instância para arquivos, container e logs
if [[ "$USE_DOMAIN" == "s" ]]; then
    # Usa domínio para nomear, mas adiciona sufixo se for >0
    DOMAIN_SAFE=$(echo "$DOMAIN" | tr '.' '_')
    if [[ $INSTANCE_INDEX -eq 0 ]]; then
        INSTANCE_NAME="$DOMAIN_SAFE"
    else
        INSTANCE_NAME="${DOMAIN_SAFE}${INSTANCE_SUFFIX}"
    fi
else
    INSTANCE_NAME="xibo${INSTANCE_SUFFIX}"
fi

# Diretório da instância
XIBO_DIR="$XIBO_DIR_BASE$INSTANCE_SUFFIX"

# Define portas customizadas para evitar conflito (só quando usar domínio)
# Porta base 9505 para CMS, 8080 para HTTP (proxy)
PORT_CMS_BASE=9505
PORT_HTTP_BASE=8080

# Incrementa as portas conforme o índice da instância
PORT_CMS=$((PORT_CMS_BASE + INSTANCE_INDEX))
PORT_HTTP=$((PORT_HTTP_BASE + INSTANCE_INDEX))

echo "Instalando Xibo CMS na instância: $INSTANCE_NAME"
echo "Diretório: $XIBO_DIR"
echo "Porta CMS: $PORT_CMS"
echo "Porta HTTP: $PORT_HTTP"
echo

# -------- INSTALAÇÃO --------

echo "[1/14] Instalando dependências..."
apt update && apt install -y docker-compose apache2 snapd unzip curl ufw

echo "[2/14] Criando diretório do Xibo..."
mkdir -p "$XIBO_DIR"
cd "$XIBO_DIR"

echo "[3/14] Baixando e extraindo arquivos do Xibo..."
wget -O xibo-docker.tar.gz https://xibosignage.com/api/downloads/cms
tar --strip-components=1 -zxvf xibo-docker.tar.gz
rm xibo-docker.tar.gz

echo "[4/14] Criando arquivo config.env..."
cp config.env.template config.env
sed -i "s/^MYSQL_PASSWORD=.*/MYSQL_PASSWORD=$MYSQL_PASSWORD/" config.env

echo "[5/14] Configurando docker-compose e portas..."

if [[ "$USE_DOMAIN" == "s" ]]; then
    cp cms_custom-ports.yml.template cms_custom-ports.yml
    rm -f docker-compose.yml
    sed -i "s/65500:9505/$PORT_CMS:9505/" cms_custom-ports.yml
    sed -i "s/65501:80/127.0.0.1:$PORT_HTTP:80/" cms_custom-ports.yml
else
    echo "→ Usando docker-compose.yml padrão (portas padrão)"
fi

echo "[6/14] Subindo os containers Docker..."
if [[ "$USE_DOMAIN" == "s" ]]; then
    docker-compose -f cms_custom-ports.yml up -d
else
    docker-compose up -d
fi

if [[ "$USE_DOMAIN" == "s" ]]; then
    echo "[7/14] Configurando Apache com proxy reverso..."

    a2enmod proxy proxy_http headers

    cat <<EOF > /etc/apache2/sites-available/$INSTANCE_NAME.conf
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

    a2ensite "$INSTANCE_NAME.conf"
    systemctl reload apache2

    echo "[8/14] Abrindo portas no firewall UFW..."
    ufw allow OpenSSH
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow $PORT_CMS/tcp
    ufw --force enable

    echo "[9/14] Instalando Certbot..."
    snap install core && snap refresh core
    apt-get remove certbot -y
    snap install --classic certbot
    ln -sf /snap/bin/certbot /usr/bin/certbot

    echo "[10/14] Emitindo certificado SSL com Certbot..."
    certbot --apache --non-interactive --agree-tos -m "$EMAIL" -d "$DOMAIN"

    echo "[11/14] Criando regra de renovação automática para Certbot..."
    cat <<EOF > /etc/cron.daily/certbot-renew
#!/bin/bash
/usr/bin/certbot renew --quiet --deploy-hook "systemctl reload apache2"
EOF
    chmod +x /etc/cron.daily/certbot-renew

else
    echo "[7-11/14] Pulando configuração Apache e SSL, usando IP e portas padrão."
    echo "[8/14] Abrindo portas no firewall UFW..."
    ufw allow OpenSSH
    ufw allow $PORT_HTTP/tcp
    ufw allow $PORT_CMS/tcp
    ufw --force enable
fi

echo "[12/14] Instalação concluída!"
echo

if [[ "$USE_DOMAIN" == "s" ]]; then
    echo "✅ Acesse agora o Xibo CMS:"
    echo "   👉 http://$DOMAIN"
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
if [[ "$USE_DOMAIN" == "s" ]]; then
    echo "🔄 A renovação automática do certificado SSL está configurada."
fi
