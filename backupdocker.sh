#!/bin/bash

set -e

TIMESTAMP=$(date +%Y%m%d%H%M%S)
BACKUP_FILE="docker_backup_$TIMESTAMP.tar.gz"

echo "Iniciando backup completo do Docker..."

# Diretórios importantes do Docker
DOCKER_DIRS=("/var/lib/docker" "/etc/docker")

# Criar um diretório temporário para armazenar dados
TMP_DIR=$(mktemp -d)

echo "Copiando dados Docker..."

# Copiar os diretórios do Docker para TMP_DIR
for dir in "${DOCKER_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "Copiando $dir"
        mkdir -p "$TMP_DIR$(dirname "$dir")"
        cp -a "$dir" "$TMP_DIR$(dirname "$dir")"
    else
        echo "Aviso: diretório $dir não existe, pulando."
    fi
done

# Salvar containers ativos (nomes/ids)
docker ps -a --format '{{.Names}}' > "$TMP_DIR/docker_containers_list.txt"

echo "Compactando backup em $BACKUP_FILE..."

tar czf "$BACKUP_FILE" -C "$TMP_DIR" .

echo "Backup completo salvo em: $BACKUP_FILE"

# Limpar temporário
rm -rf "$TMP_DIR"
