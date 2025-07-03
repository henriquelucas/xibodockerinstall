#!/bin/bash
set -e

read -rp "Informe o nome de um container base para identificar o sistema: " BASE_CONTAINER

if [ -z "$BASE_CONTAINER" ]; then
  echo "Nome do container base é obrigatório."
  exit 1
fi

PREFIX=$(echo "$BASE_CONTAINER" | cut -d'_' -f1)

if [ -z "$PREFIX" ]; then
  echo "Não consegui extrair prefixo do container $BASE_CONTAINER"
  exit 1
fi

BACKUP_DIR="docker_backup_$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP_DIR/volumes"

echo "Criando backup para containers com prefixo: $PREFIX*"

CONTAINERS=$(docker ps -a --format '{{.Names}}' | grep "^${PREFIX}_")

if [ -z "$CONTAINERS" ]; then
  echo "Nenhum container encontrado com prefixo $PREFIX"
  exit 1
fi

CONTAINERS_INFO="$BACKUP_DIR/containers_info.json"
IMAGES_TO_SAVE=()
VOLUMES_TO_SAVE=()

# Criar um JSON com todas informações relevantes dos containers
echo "[" > "$CONTAINERS_INFO"

for c in $CONTAINERS; do
  echo "Processando container $c"
  
  # Inspeciona o container em JSON
  info=$(docker inspect "$c")

  # Extrai a imagem
  image=$(docker inspect --format '{{.Config.Image}}' "$c")
  IMAGES_TO_SAVE+=("$image")

  # Extrai volumes tipo "volume"
  vols=$(docker inspect --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}} {{end}}{{end}}' "$c")
  for vol in $vols; do
    VOLUMES_TO_SAVE+=("$vol")
  done

  # Append do JSON (retirando colchetes para concatenar)
  # Remove primeiro e último caractere do JSON array para concatenar corretamente
  stripped=$(echo "$info" | sed '1d;$d')

  echo "$stripped," >> "$CONTAINERS_INFO"
done

# Fecha JSON removendo última vírgula
sed -i '$ s/,$//' "$CONTAINERS_INFO"
echo "]" >> "$CONTAINERS_INFO"

# Remove duplicatas de imagens e volumes
IMAGES_TO_SAVE=($(echo "${IMAGES_TO_SAVE[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
VOLUMES_TO_SAVE=($(echo "${VOLUMES_TO_SAVE[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

echo "Salvando imagens Docker..."
docker save "${IMAGES_TO_SAVE[@]}" -o "$BACKUP_DIR/imagens.tar"

echo "Salvando volumes usados pelos containers..."
for vol in "${VOLUMES_TO_SAVE[@]}"; do
  echo "Salvando volume $vol"
  docker run --rm -v "${vol}:/volume" -v "$(pwd)/$BACKUP_DIR/volumes:/backup" busybox \
    sh -c "cd /volume && tar czf /backup/${vol}.tar.gz ."
done

echo "Backup completo salvo em $BACKUP_DIR"
