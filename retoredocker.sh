#!/bin/bash
set -e

function instalar_docker_ubuntu() {
    echo "Instalando Docker no Ubuntu/Debian..."
    sudo apt update
    sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io
    echo "Docker instalado."
}

function verificar_docker() {
    if ! command -v docker &>/dev/null; then
        echo "Docker não está instalado."
        read -p "Quer instalar o Docker agora? (s/n): " resposta
        if [[ "$resposta" =~ ^[Ss]$ ]]; then
            if [ -f /etc/debian_version ]; then
                instalar_docker_ubuntu
            else
                echo "Sistema não suportado para instalação automática."
                exit 1
            fi
        else
            echo "Docker é necessário para continuar. Abortando."
            exit 1
        fi
    else
        echo "Docker já instalado."
    fi
}

function recriar_containers() {
    CONTAINERS_FILE="$1"

    if [ ! -f "$CONTAINERS_FILE" ]; then
        echo "Arquivo de containers não encontrado: $CONTAINERS_FILE"
        return
    fi

    echo "Iniciando recriação automática dos containers..."

    while IFS='|' read -r name image cmd ports status; do
        echo "Recriando container: $name"

        # Remove container se existir
        if docker ps -a --format '{{.Names}}' | grep -qw "$name"; then
            echo "Removendo container existente: $name"
            docker rm -f "$name"
        fi

        # Montar args de portas
        PORT_ARGS=()
        if [ -n "$ports" ]; then
            IFS=',' read -ra port_array <<< "$ports"
            for p in "${port_array[@]}"; do
                host_port="${p%%/*}"
                PORT_ARGS+=("-p" "$host_port:$host_port")
            done
        fi

        # Remover aspas do comando
        cmd=$(echo "$cmd" | sed -e 's/^"//' -e 's/"$//')

        echo "Executando: docker run -d --name $name ${PORT_ARGS[*]} $image $cmd"
        docker run -d --name "$name" "${PORT_ARGS[@]}" "$image" sh -c "$cmd"
    done < "$CONTAINERS_FILE"

    echo "Recriação dos containers concluída."
}

read -rp "Informe o caminho para o arquivo de backup (.tar.gz): " BACKUP_ARQUIVO

if [ ! -f "$BACKUP_ARQUIVO" ]; then
    echo "Arquivo não encontrado: $BACKUP_ARQUIVO"
    exit 1
fi

verificar_docker

TMP_RESTORE_DIR=$(mktemp -d)
echo "Extraindo backup..."
tar xzf "$BACKUP_ARQUIVO" -C "$TMP_RESTORE_DIR"

echo "Restaurando imagens Docker..."
docker load -i "$TMP_RESTORE_DIR/imagens.tar"

echo "Restaurando volumes Docker..."
if [ -d "$TMP_RESTORE_DIR/volumes" ]; then
    for vol_tar in "$TMP_RESTORE_DIR"/volumes/*.tar.gz; do
        vol_name=$(basename "$vol_tar" .tar.gz)
        echo "Restaurando volume $vol_name..."
        docker volume create "$vol_name"
        docker run --rm -v "${vol_name}:/volume" -v "$TMP_RESTORE_DIR/volumes:/backup" busybox \
            sh -c "cd /volume && tar xzf /backup/${vol_name}.tar.gz"
    done
else
    echo "Nenhum volume encontrado para restaurar."
fi

echo "Configurações do Docker..."
if [ -f "$TMP_RESTORE_DIR/docker_configs.tar.gz" ]; then
    echo "As configurações foram salvas. Para restaurar, execute manualmente:"
    echo "sudo tar xzf $TMP_RESTORE_DIR/docker_configs.tar.gz -C /"
fi

recriar_containers "$TMP_RESTORE_DIR/containers_info.txt"

rm -rf "$TMP_RESTORE_DIR"

echo "Restauração e recriação concluídas!"
