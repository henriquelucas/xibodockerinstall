#!/bin/bash
set -e

TIMESTAMP=$(date +%Y%m%d%H%M%S)
BACKUP_DIR="docker_backup_$TIMESTAMP"
mkdir -p "$BACKUP_DIR"

echo "Salvando todas as imagens Docker..."
docker images -q | sort | uniq > "$BACKUP_DIR/imagens_ids.txt"
docker save -o "$BACKUP_DIR/imagens.tar" $(cat "$BACKUP_DIR/imagens_ids.txt")

echo "Salvando lista de containers (nome, imagem, comando, portas)..."
docker ps -a --format '{{.Names}}|{{.Image}}|{{.Command}}|{{.Ports}}|{{.Status}}' > "$BACKUP_DIR/containers_info.txt"

echo "Salvando volumes Docker..."
mkdir -p "$BACKUP_DIR/volumes"

volumes=$(docker volume ls -q)
for vol in $volumes; do
    echo "Backup do volume: $vol"
    docker run --rm -v "${vol}:/volume" -v "$(pwd)/$BACKUP_DIR/volumes:/backup" busybox \
        tar czf "/backup/${vol}.tar.gz" -C /volume .
done

echo "Salvando configurações do Docker (se houver)..."
if [ -d /etc/docker ]; then
    tar czf "$BACKUP_DIR/docker_configs.tar.gz" /etc/docker
else
    echo "Pasta /etc/docker não encontrada, pulando configs."
fi

echo "Compactando todo backup..."
tar czf "${BACKUP_DIR}.tar.gz" "$BACKUP_DIR"

echo "Limpando arquivos temporários..."
rm -rf "$BACKUP_DIR"

echo "Backup criado com sucesso: ${BACKUP_DIR}.tar.gz"
