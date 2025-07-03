#!/bin/bash
set -e

read -rp "Informe o diretório do backup: " BACKUP_DIR

if [ ! -d "$BACKUP_DIR" ]; then
  echo "Diretório de backup não encontrado!"
  exit 1
fi

IMAGES_FILE="$BACKUP_DIR/imagens.tar"
CONTAINERS_INFO="$BACKUP_DIR/containers_info.json"

if [ ! -f "$IMAGES_FILE" ] || [ ! -f "$CONTAINERS_INFO" ]; then
  echo "Arquivo de imagens ou containers_info.json não encontrado no backup."
  exit 1
fi

echo "Restaurando imagens..."
docker load -i "$IMAGES_FILE"

echo "Restaurando volumes..."
for voltar in "$BACKUP_DIR/volumes/"*.tar.gz; do
  volname=$(basename "$voltar" .tar.gz)
  echo "Restaurando volume $volname"
  docker volume create "$volname"
  docker run --rm -v "${volname}:/volume" -v "${BACKUP_DIR}/volumes:/backup" busybox \
    sh -c "cd /volume && tar xzf /backup/${volname}.tar.gz"
done

echo "Recriando containers..."
containers_count=$(jq length "$CONTAINERS_INFO")

for i in $(seq 0 $((containers_count - 1))); do
  c=$(jq ".[$i]" "$CONTAINERS_INFO")

  name=$(echo "$c" | jq -r '.Name' | sed 's|^/||')
  image=$(echo "$c" | jq -r '.Config.Image')
  echo "Recriando container: $name"

  # Remove container anterior se já existir
  docker rm -f "$name" >/dev/null 2>&1 || true

  # Portas
  port_args=""
  ports=$(echo "$c" | jq -r '
    .HostConfig.PortBindings // {} |
    to_entries[]? |
    select(.value != null and .value[0].HostPort != null) |
    "\(.value[0].HostPort):\(.key)"
  ')
  for p in $ports; do
    port_args+="-p $p "
  done

  # Volumes
  volume_args=""
  mounts=$(echo "$c" | jq -r '
    .Mounts // [] |
    map(select(.Type == "volume")) |
    map("\(.Name):\(.Destination)") |
    .[]
  ')
  for v in $mounts; do
    volume_args+="-v $v "
  done

  # Variáveis de ambiente
  env_args=""
  envs=$(echo "$c" | jq -r '.Config.Env // [] | .[]')
  for e in $envs; do
    env_args+="-e $e "
  done

  # Comando (tratando null)
  cmd=$(echo "$c" | jq -r '.Config.Cmd // [] | join(" ")')

  # Rede
  network=$(echo "$c" | jq -r '.HostConfig.NetworkMode')

  # Garantir que a rede existe
  if ! docker network ls --format '{{.Name}}' | grep -q "^$network$"; then
    echo "Criando rede $network"
    docker network create "$network"
  fi

  # Executa o container
  docker run -d --name "$name" $port_args $volume_args $env_args --network "$network" "$image" $cmd
done

echo "✅ Restauração completa!"
