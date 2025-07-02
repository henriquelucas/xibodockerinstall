#!/bin/bash

set -e

# Função para verificar se o Docker está instalado
function check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Docker não encontrado. Instalando Docker..."

        # Detectar SO (supondo Ubuntu/Debian)
        if [ -f /etc/debian_version ]; then
            sudo apt update
            sudo apt install -y apt-transport-https ca-certificates curl software-properties-common

            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

            sudo apt update
            sudo apt install -y docker-ce docker-ce-cli containerd.io
        else
            echo "Sistema não suportado para instalação automática do Docker."
            exit 1
        fi
        echo "Docker instalado com sucesso."
    else
        echo "Docker já está instalado."
    fi
}

echo "Verificando Docker..."
check_docker

read -rp "Informe o caminho completo do arquivo de backup Docker (.tar.gz): " BACKUP_PATH

if [ ! -f "$BACKUP_PATH" ]; then
    echo "Arquivo não encontrado: $BACKUP_PATH"
    exit 1
fi

echo "Preparando para restaurar o backup..."

# Criar diretório temporário para extrair o backup
TMP_RESTORE_DIR=$(mktemp -d)

echo "Extraindo backup..."
tar xzf "$BACKUP_PATH" -C "$TMP_RESTORE_DIR"

echo "Parando Docker para restaurar dados..."
sudo systemctl stop docker

echo "Restaurando diretórios Docker..."

# Restaurar os diretórios do Docker
for dir in /var/lib/docker /etc/docker; do
    if [ -d "$TMP_RESTORE_DIR$dir" ]; then
        echo "Restaurando $dir..."
        sudo rm -rf "$dir"
        sudo cp -a "$TMP_RESTORE_DIR$dir" "$dir"
    else
        echo "Aviso: backup não contém $dir, pulando."
    fi
done

echo "Iniciando Docker..."
sudo systemctl start docker

echo "Restaurando containers (se aplicável)..."

CONTAINERS_LIST="$TMP_RESTORE_DIR/docker_containers_list.txt"
if [ -f "$CONTAINERS_LIST" ]; then
    while read -r container_name; do
        if [ -n "$container_name" ]; then
            echo "Tentando iniciar container $container_name..."
            sudo docker start "$container_name" || echo "Falha ao iniciar container $container_name"
        fi
    done < "$CONTAINERS_LIST"
else
    echo "Lista de containers não encontrada, não será possível iniciar containers automaticamente."
fi

echo "Backup restaurado com sucesso."

rm -rf "$TMP_RESTORE_DIR"
