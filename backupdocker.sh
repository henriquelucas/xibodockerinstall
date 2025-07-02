#!/bin/bash
set -e

read -rp "Informe o nome de um container base para identificar o sistema: " BASE_CONTAINER

if [ -z "$BASE_CONTAINER" ]; then
  echo "Nome do container base é obrigatório."
  exit 1
fi

# Extrai prefixo do nome (até primeiro underscore)
PREFIX=$(echo "$BASE_CONTAINER" | cut -d'_' -f1)

if [ -z "$PREFIX" ]; then
  echo "Não consegui extrair prefixo do container $BASE_CONTAINER"
  exit 1
fi

BACKUP_DIR="docker_backup_$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP_DIR/volumes"

echo "Criando backup para containers com prefixo: $PREFIX*"

# Lista containers com o prefixo
CONTAINERS=$(docker ps -a --format '{{.Names}}' | grep "^${PREFIX}_")

if [ -z "$CONTAINERS" ]; then
  echo "Nenhum container encontrado com prefixo $PREFIX"
  exit 1
fi

# Arquivo info containers
CONTAINERS_INFO="$BACKUP_DIR/containers_info.txt"
: > "$CONTAINERS_INFO"

IMAGES_TO_SAVE=()

# Backup containers info e imagens
for c in $CONTAINERS; do
  echo "Processando container $c"
  image=$(docker inspect --format '{{.Config.Image}}' "$c")
  cmd=$(docker inspect --format '{{json .Config.Cmd}}' "$c")
  ports=$(docker inspect --format '{{range $p, $conf := .HostConfig.PortBindings}}{{$p}}{{end}}' "$c")
  status=$(docker inspect --format '{{.State.Status}}' "$c")

  # Salva linha no arquivo de info (pipe separado)
  echo "${c}|${image}|${cmd}|${ports}|${status}" >> "$CONTAINERS_INFO"

  IMAGES_TO_SAVE+=("$image")
done

# Remove duplicatas de imagens
IMAGES_TO_SAVE=($(echo "${IMAGES_TO_SAVE[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

echo "Salvando imagens Docker..."
docker save "${IMAGES_TO_SAVE[@]}" -o "$BACKUP_DIR/imagens.tar"

echo "Salvando volumes usados pelos containers..."

# Pega volumes usados pelos containers
for c in $CONTAINERS; do
  vols=$(docker inspect --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}} {{end}}{{end}}' "$c")
  for vol in $vols; do
    echo "Salvando volume $vol"
    docker run --rm -v "${vol}:/volume" -v "$(pwd)/$BACKUP_DIR/volumes:/backup" busybox \
      sh -c "cd /volume && tar czf /backup/${vol}.tar.gz ."
  done
done

echo "Backup completo salvo em $BACKUP_DIR"
