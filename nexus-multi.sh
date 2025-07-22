#!/usr/bin/env bash

# Nexus Multi-Node Manager v2.0
# Enhanced multi-node management with advanced features
# Version: 2.0 (Updated: 2025-07-21)
# Author: ROKHANZ
# Repository: https://github.com/rokhanz/nexus-multi-docker

# Colors untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Node colors for multi-node support
declare -A NODE_COLORS=(
    [1]="\033[1;31m"  # Red
    [2]="\033[1;32m"  # Green  
    [3]="\033[1;33m"  # Yellow
    [4]="\033[1;34m"  # Blue
    [5]="\033[1;35m"  # Magenta
    [6]="\033[1;36m"  # Cyan
    [7]="\033[1;37m"  # White
    [8]="\033[1;91m"  # Bright Red
    [9]="\033[1;92m"  # Bright Green
    [10]="\033[1;93m" # Bright Yellow
)

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Get node color
get_node_color() {
    local node_id=$1
    echo "${NODE_COLORS[$node_id]:-\033[1;37m}"
}

# Print colored node message
print_node_message() {
    local node_id=$1
    local message=$2
    local color
    color=$(get_node_color $node_id)
    echo -e "${color}[Node $node_id]${NC} $message"
}

# Deteksi existing Nexus containers
detect_existing_nodes() {
    log_info "🔍 Mendeteksi Nexus containers yang ada..."
    
    local existing_containers
    existing_containers=$(docker ps -a --filter "name=nexus-node-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "")
    
    if [ -n "$existing_containers" ] && [ "$existing_containers" != "NAMES	STATUS	PORTS" ]; then
        echo -e "${YELLOW}📦 Nexus containers terdeteksi di VPS ini:${NC}"
        echo "$existing_containers"
        echo ""
        
        local container_count
        container_count=$(docker ps -a --filter "name=nexus-node-" --format "{{.Names}}" 2>/dev/null | wc -l)
        
        if [ "$container_count" -gt 0 ]; then
            echo -e "${CYAN}Total Nexus containers: $container_count${NC}"
            echo -e "${YELLOW}⚠️  Pastikan tidak ada konflik port atau Node ID${NC}"
            echo ""
        fi
    else
        log_success "Tidak ada Nexus containers existing - VPS bersih"
    fi
}

# Deploy single node (for adding new nodes)
deploy_single_node() {
    local node_num=$1
    local node_id=$2
    local port=$3
    local proxy_url=$4
    
    local node_name="nexus-node-$node_num"
    local proxy_env=""
    local proxy_info=""
    
    # Setup proxy environment if provided
    if [[ -n "$proxy_url" ]]; then
        proxy_env="-e HTTP_PROXY=$proxy_url -e HTTPS_PROXY=$proxy_url -e http_proxy=$proxy_url -e https_proxy=$proxy_url"
        proxy_info=" via proxy: ${proxy_url}"
    fi
    
    # Check port availability
    if ! is_port_free "$port"; then
        print_node_message "$node_num" "Port $port is busy"
        return 1
    fi
    
    # Remove existing container
    if docker ps -a --format "{{.Names}}" | grep -q "^$node_name$"; then
        print_node_message "$node_num" "Removing existing container..."
        docker stop "$node_name" >/dev/null 2>&1 || true
        docker rm "$node_name" >/dev/null 2>&1 || true
    fi
    
    # Create data directory
    mkdir -p "$CONFIG_DIR/node$node_num"
    
    # Setup config.json for this node
    cat > "$CONFIG_DIR/node$node_num/config.json" << EOF
{
    "node_id": "$node_id",
    "created_at": "$(date -Iseconds)",
    "wallet_address": "$WALLET_ADDRESS"
}
EOF
    
    # Check device capabilities
    local DEVICE_ARGS
    if [ -e /dev/net/tun ]; then
        DEVICE_ARGS="--device /dev/net/tun --cap-add NET_ADMIN"
    else
        DEVICE_ARGS="--cap-add NET_ADMIN"
    fi
    
    # Start container
    if docker run -d --name "$node_name" \
        --network host \
        $DEVICE_ARGS \
        $proxy_env \
        -p "$port:10000" \
        -v "$CONFIG_DIR/node$node_num":/nexus-config \
        -v /etc/resolv.conf:/etc/resolv.conf:ro \
        --restart unless-stopped \
        --entrypoint /bin/sh \
        nexus-cli:latest -c "
            # Copy config files if they exist
            if [ -f /nexus-config/config.json ]; then
                cp /nexus-config/config.json /root/.nexus/
            fi
            # Run nexus-network
            exec /root/.nexus/bin/nexus-network start --headless --node-id $node_id
        " >/dev/null 2>&1; then
        
        sleep 3
        if docker ps --format "{{.Names}}" | grep -q "^$node_name$"; then
            # Create screen session for this node
            screen -dmS "nexus-node-$node_num" bash -c "
                echo '=== Nexus Node $node_num Monitor ==='
                echo 'Container: $node_name'
                echo 'NODE_ID: $node_id'
                echo 'Port: $port'
                echo 'Proxy: $proxy_info'
                echo \"Time: \$(date)\"
                echo '=========================='
                echo 'Following Docker logs...'
                echo
                docker logs -f $node_name
            " 2>/dev/null || true
            
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

# Tambah Node ID baru (untuk existing deployment)
add_new_node_id() {
    while true; do  # Loop untuk menu
        log_info "➕ Menambah Node ID baru..."
        
        # Create .env file if doesn't exist
        if [ ! -f "$ENV_FILE" ]; then
            log_info "📁 File environment tidak ditemukan, membuat konfigurasi baru..."
            mkdir -p "$WORKDIR" 2>/dev/null || true
            
            # Create basic .env structure
            cat > "$ENV_FILE" << EOF
# Nexus Node configuration - Generated $(date)
NODE_COUNT=0
DEBUG=false

# Individual Node IDs will be added when nodes are deployed
EOF
            chmod 600 "$ENV_FILE"
            log_success "✅ File $ENV_FILE berhasil dibuat"
        fi
        
        # Load existing config (global loading ensures environment is loaded)
        load_existing_env
        
        # Check and setup WALLET_ADDRESS if missing
        if [[ -z "${WALLET_ADDRESS:-}" ]]; then
            log_info "🔑 WALLET_ADDRESS belum dikonfigurasi"
            echo ""
            
            while true; do
                echo -n "Masukkan WALLET_ADDRESS (0x...): "
                read -r WALLET_ADDRESS
                if [[ $WALLET_ADDRESS =~ ^0x[a-fA-F0-9]{40}$ ]]; then
                    log_success "✅ Format wallet address valid"
                    
                    # Add WALLET_ADDRESS to .env
                    if grep -q "^WALLET_ADDRESS=" "$ENV_FILE"; then
                        sed -i "s/^WALLET_ADDRESS=.*/WALLET_ADDRESS=$WALLET_ADDRESS/" "$ENV_FILE"
                    else
                        echo "WALLET_ADDRESS=$WALLET_ADDRESS" >> "$ENV_FILE"
                    fi
                    
                    # Export for current session
                    export WALLET_ADDRESS
                    log_success "✅ WALLET_ADDRESS disimpan ke $ENV_FILE"
                    break
                else
                    log_error "❌ Format wallet address tidak valid. Harus 40 karakter hex dimulai dengan 0x"
                fi
            done
            echo ""
        else
            log_success "✅ WALLET_ADDRESS sudah dikonfigurasi: ${WALLET_ADDRESS:0:10}..."
        fi
        
        # Check if Docker image exists
        local docker_available=false
        if docker image inspect nexus-cli:latest >/dev/null 2>&1; then
            docker_available=true
            log_success "✅ Docker image nexus-cli:latest tersedia"
        else
            log_warning "⚠️  Docker image nexus-cli:latest tidak ditemukan"
            log_info "Node ID akan ditambahkan ke konfigurasi, tapi tidak akan langsung di-deploy"
            log_info "Silakan jalankan 'Install Nexus' dulu untuk build image jika ingin deploy langsung"
        fi
        
        # Display current configuration summary
        echo ""
        echo -e "${CYAN}📋 Konfigurasi Saat Ini:${NC}"
        echo -e "WALLET_ADDRESS: ${WALLET_ADDRESS:0:10}...${WALLET_ADDRESS: -4}"
        echo ""
        
        # Hitung node yang ada berdasarkan .env
        local existing_nodes
        existing_nodes=$(grep -c "^NODE_ID_[0-9]*=" "$ENV_FILE" 2>/dev/null | head -1 | tr -d '\n' || echo "0")
        
        if [ "$existing_nodes" -gt 0 ]; then
            echo -e "${CYAN}📋 NODE_ID yang sudah dikonfigurasi ($existing_nodes):${NC}"
            # Cari semua NODE_ID yang ada di .env file
            for node_entry in $(grep "^NODE_ID_[0-9]*=" "$ENV_FILE" | sort -V); do
                local node_num=$(echo "$node_entry" | cut -d'_' -f3 | cut -d'=' -f1)
                local node_id=$(echo "$node_entry" | cut -d'=' -f2)
                if [[ -n "$node_id" ]]; then
                    print_node_message "$node_num" "NODE_ID: $node_id"
                fi
            done
            echo ""
            
            echo "Pilihan:"
            echo "1. Tambah NODE_ID baru"
            echo "2. Edit NODE_ID yang sudah ada"
            echo "3. Hapus NODE_ID"
            echo "4. Edit WALLET_ADDRESS"
            echo "5. Kembali ke menu utama"
            echo -n "Pilih opsi (1-5): "
            read -r config_choice
            
            case "$config_choice" in
                "1")
                    # Tambah NODE_ID baru - continue to add logic below
                    ;;
                "2")
                    # Edit NODE_ID yang ada
                    while true; do
                        echo -e "${YELLOW}📋 NODE_ID yang tersedia untuk diedit:${NC}"
                        # Tampilkan semua NODE_ID yang ada
                        local available_edit_nodes=()
                        for node_entry in $(grep "^NODE_ID_[0-9]*=" "$ENV_FILE" | sort -V); do
                            local node_num=$(echo "$node_entry" | cut -d'_' -f3 | cut -d'=' -f1)
                            local node_id=$(echo "$node_entry" | cut -d'=' -f2)
                            if [[ -n "$node_id" ]]; then
                                print_node_message "$node_num" "NODE_ID: $node_id"
                                available_edit_nodes+=("$node_num")
                            fi
                        done
                        echo ""
                        
                        # Buat wording untuk edit
                        local edit_node_options=""
                        for i in "${!available_edit_nodes[@]}"; do
                            if [ $i -eq 0 ]; then
                                edit_node_options="${available_edit_nodes[i]}"
                            else
                                edit_node_options="$edit_node_options atau ${available_edit_nodes[i]}"
                            fi
                        done
                        
                        echo -n "Masukkan nomor NODE yang ingin diedit ($edit_node_options, atau 'cancel' untuk batal): "
                        read -r edit_node
                        
                        # Check untuk cancel
                        if [[ "$edit_node" =~ ^[Cc]ancel$ ]]; then
                            log_info "Edit NODE_ID dibatalkan"
                            break  # Back to main menu
                        fi
                        
                        # Validasi apakah nomor node yang dipilih ada dalam available_edit_nodes
                        local valid_edit_choice=false
                        for node_num in "${available_edit_nodes[@]}"; do
                            if [[ "$edit_node" == "$node_num" ]]; then
                                valid_edit_choice=true
                                break
                            fi
                        done
                        
                        if [[ "$valid_edit_choice" == true ]]; then
                            local current_node_id
                            current_node_id=$(get_node_id_from_env "$edit_node")
                            
                            echo -e "${YELLOW}Node $edit_node saat ini: $current_node_id${NC}"
                            echo ""
                            
                            local edit_success=false
                            while true; do
                                echo -n "Masukkan NODE_ID baru untuk Node $edit_node (atau 'cancel' untuk batal): "
                                read -r new_node_id
                                
                                # Check untuk cancel
                                if [[ "$new_node_id" =~ ^[Cc]ancel$ ]]; then
                                    log_info "Edit NODE_ID dibatalkan"
                                    break  # Break from inner while loop
                                fi
                                
                                if [[ -n "$new_node_id" ]]; then
                                    # Check duplikasi
                                    local duplicate=false
                                    for ((j=1; j<=10; j++)); do
                                        if [ "$j" -ne "$edit_node" ]; then
                                            local existing_id
                                            existing_id=$(get_node_id_from_env "$j")
                                            if [[ "$existing_id" == "$new_node_id" ]]; then
                                                log_error "NODE_ID '$new_node_id' sudah digunakan oleh Node $j"
                                                duplicate=true
                                                break
                                            fi
                                        fi
                                    done
                                    
                                    if [[ "$duplicate" == false ]]; then
                                        sed -i "s/^NODE_ID_$edit_node=.*/NODE_ID_$edit_node=$new_node_id/" "$ENV_FILE"
                                        log_success "✅ NODE_ID Node $edit_node diupdate: $new_node_id"
                                        edit_success=true
                                        break  # Break from inner while loop
                                    fi
                                else
                                    log_error "NODE_ID tidak boleh kosong"
                                fi
                            done
                            
                            if [[ "$edit_success" == true ]]; then
                                # Show updated summary
                                echo ""
                                echo -e "${CYAN}📋 Summary NODE_IDs (updated):${NC}"
                                for node_entry in $(grep "^NODE_ID_[0-9]*=" "$ENV_FILE" | sort -V); do
                                    local node_num=$(echo "$node_entry" | cut -d'_' -f3 | cut -d'=' -f1)
                                    local node_id=$(echo "$node_entry" | cut -d'=' -f2)
                                    if [[ -n "$node_id" ]]; then
                                        print_node_message "$node_num" "NODE_ID: $node_id"
                                    fi
                                done
                                echo ""
                                
                                # Konfirmasi untuk melanjutkan atau kembali ke menu
                                echo "Edit NODE_ID berhasil!"
                                echo "1. Edit NODE_ID lagi"
                                echo "2. Kembali ke menu utama"
                                echo -n "Pilihan (1/2): "
                                read -r edit_choice
                                
                                if [[ "$edit_choice" == "1" ]]; then
                                    continue  # Continue edit loop
                                else
                                    break  # Break to main menu
                                fi
                            fi
                        else
                            log_error "Nomor node tidak valid"
                            echo ""
                            echo "Tekan Enter untuk mencoba lagi atau ketik 'cancel' untuk kembali..."
                            read -r retry_choice
                            if [[ "$retry_choice" =~ ^[Cc]ancel$ ]]; then
                                break  # Back to main menu
                            fi
                        fi
                    done
                    ;;
                "3")
                    # Hapus NODE_ID
                    while true; do
                        echo -e "${YELLOW}📋 NODE_ID yang tersedia untuk dihapus:${NC}"
                        # Cari semua NODE_ID yang ada di .env file (sama seperti main display)
                        local available_nodes=()
                        for node_entry in $(grep "^NODE_ID_[0-9]*=" "$ENV_FILE" | sort -V); do
                            local node_num=$(echo "$node_entry" | cut -d'_' -f3 | cut -d'=' -f1)
                            local node_id=$(echo "$node_entry" | cut -d'=' -f2)
                            if [[ -n "$node_id" ]]; then
                                print_node_message "$node_num" "NODE_ID: $node_id"
                                available_nodes+=("$node_num")
                            fi
                        done
                        echo ""
                        
                        # Check jika tidak ada node yang tersedia
                        if [ ${#available_nodes[@]} -eq 0 ]; then
                            echo -e "${RED}❌ Tidak ada NODE_ID yang tersedia untuk dihapus${NC}"
                            break
                        fi
                        
                        # Buat wording yang sesuai dengan node yang tersedia
                        local node_options=""
                        for i in "${!available_nodes[@]}"; do
                            if [ $i -eq 0 ]; then
                                node_options="${available_nodes[i]}"
                            else
                                node_options="$node_options atau ${available_nodes[i]}"
                            fi
                        done
                        
                        echo -n "Masukkan nomor NODE yang ingin dihapus ($node_options, atau 'cancel' untuk batal): "
                        read -r delete_node
                        
                        # Check untuk cancel
                        if [[ "$delete_node" =~ ^[Cc]ancel$ ]]; then
                            log_info "Penghapusan NODE_ID dibatalkan"
                            break  # Back to main menu
                        fi
                        
                        # Validasi apakah nomor node yang dipilih ada dalam available_nodes
                        local valid_choice=false
                        for node_num in "${available_nodes[@]}"; do
                            if [[ "$delete_node" == "$node_num" ]]; then
                                valid_choice=true
                                break
                            fi
                        done
                    
                    if [[ "$valid_choice" == true ]]; then
                        local current_node_id
                        current_node_id=$(get_node_id_from_env "$delete_node")
                        
                        echo -e "${RED}⚠️  PERINGATAN: Akan menghapus Node $delete_node dengan NODE_ID: $current_node_id${NC}"
                        echo -e "${RED}   - Container Docker akan dihentikan dan dihapus${NC}"
                        echo -e "${RED}   - Konfigurasi NODE_ID akan dihapus permanen${NC}"
                        echo ""
                        echo -n "Apakah Anda yakin ingin menghapus Node $delete_node? (y/n): "
                        read -r confirm_delete
                        
                        if [[ $confirm_delete =~ ^[Yy]$ ]]; then
                            # Stop dan hapus container Docker jika ada
                            local container_name="nexus-node-$delete_node"
                            if docker ps -a --format "{{.Names}}" | grep -q "^$container_name$"; then
                                log_info "🛑 Menghentikan container: $container_name"
                                docker stop "$container_name" >/dev/null 2>&1 || true
                                docker rm "$container_name" >/dev/null 2>&1 || true
                                log_success "✅ Container $container_name berhasil dihapus"
                            fi
                            
                            # Hapus screen session jika ada
                            screen -S "$container_name" -X quit 2>/dev/null || true
                            
                            # Hapus dari .env file
                            sed -i "/^NODE_ID_$delete_node=/d" "$ENV_FILE"
                            
                            # Update NODE_COUNT
                            local new_count
                            new_count=$(grep -c "^NODE_ID_[0-9]*=" "$ENV_FILE" 2>/dev/null | head -1 | tr -d '\n' || echo "0")
                            sed -i "s/^NODE_COUNT=.*/NODE_COUNT=$new_count/" "$ENV_FILE"
                            
                            # Hapus direktori konfigurasi node jika ada
                            rm -rf "$CONFIG_DIR/node$delete_node" 2>/dev/null || true
                            
                            log_success "✅ Node $delete_node berhasil dihapus!"
                            
                            # Show updated summary
                            echo ""
                            if [ "$new_count" -gt 0 ]; then
                                echo -e "${CYAN}📋 NODE_ID yang tersisa ($new_count):${NC}"
                                for node_entry in $(grep "^NODE_ID_[0-9]*=" "$ENV_FILE" | sort -V); do
                                    local node_num=$(echo "$node_entry" | cut -d'_' -f3 | cut -d'=' -f1)
                                    local node_id=$(echo "$node_entry" | cut -d'=' -f2)
                                    if [[ -n "$node_id" ]]; then
                                        print_node_message "$node_num" "NODE_ID: $node_id"
                                    fi
                                done
                            else
                                echo -e "${YELLOW}📋 Tidak ada NODE_ID yang tersisa${NC}"
                            fi
                            echo ""
                            
                            # Konfirmasi untuk melanjutkan atau kembali ke menu
                            echo "Penghapusan NODE_ID berhasil!"
                            echo "1. Hapus NODE_ID lagi"
                            echo "2. Kembali ke menu utama"
                            echo -n "Pilihan (1/2): "
                            read -r delete_choice
                            
                            if [[ "$delete_choice" == "1" ]]; then
                                continue  # Continue delete loop
                            else
                                break  # Break to main menu
                            fi
                        else
                            log_info "Penghapusan Node $delete_node dibatalkan"
                        fi
                    else
                        log_error "Nomor node tidak valid. Pilihan yang tersedia: $node_options"
                        echo ""
                        echo "Tekan Enter untuk mencoba lagi atau ketik 'cancel' untuk kembali..."
                        read -r retry_choice
                        if [[ "$retry_choice" =~ ^[Cc]ancel$ ]]; then
                            break  # Back to main menu
                        fi
                    fi
                done
                ;;
                "4")
                    # Edit WALLET_ADDRESS
                    echo -e "${YELLOW}WALLET_ADDRESS saat ini: ${WALLET_ADDRESS}${NC}"
                    echo ""
                    echo "Konfirmasi edit WALLET_ADDRESS"
                    echo "Perhatian: Mengubah WALLET_ADDRESS akan mempengaruhi semua NODE yang sudah dikonfigurasi"
                    echo -n "Lanjutkan edit WALLET_ADDRESS? (y/n): "
                    read -r confirm_wallet_edit
                    
                    if [[ "$confirm_wallet_edit" =~ ^[Yy]$ ]]; then
                        while true; do
                            echo -n "Masukkan WALLET_ADDRESS baru (0x... atau 'cancel' untuk batal): "
                            read -r new_wallet
                            
                            # Check untuk cancel
                            if [[ "$new_wallet" =~ ^[Cc]ancel$ ]]; then
                                log_info "Edit WALLET_ADDRESS dibatalkan"
                                break
                            fi
                            
                            if [[ $new_wallet =~ ^0x[a-fA-F0-9]{40}$ ]]; then
                                sed -i "s/^WALLET_ADDRESS=.*/WALLET_ADDRESS=$new_wallet/" "$ENV_FILE"
                                export WALLET_ADDRESS="$new_wallet"
                                log_success "✅ WALLET_ADDRESS diupdate: ${new_wallet:0:10}...${new_wallet: -4}"
                                echo ""
                                log_success "✅ WALLET_ADDRESS berhasil diperbarui!"
                                break
                            else
                                log_error "Format wallet address tidak valid"
                                echo "Format yang benar: 0x diikuti 40 karakter hexadecimal"
                            fi
                        done
                    else
                        log_info "Edit WALLET_ADDRESS dibatalkan"
                    fi
                    ;;
                "5")
                    log_info "Kembali ke menu utama"
                    return 0
                    ;;
                *)
                    log_error "Pilihan tidak valid"
                    continue  # Back to menu
                    ;;
            esac
        else
            echo -e "${YELLOW}📋 Belum ada NODE_ID yang dikonfigurasi${NC}"
            echo ""
        fi
        
        if [ "$existing_nodes" -ge 10 ]; then
            log_error "Maksimal 10 nodes sudah tercapai!"
            continue  # Back to menu
        fi
        
        # Cari slot kosong untuk node baru (bukan berdasarkan existing_nodes count)
        local next_available_slot=""
        for ((slot=1; slot<=10; slot++)); do
            local existing_id
            existing_id=$(get_node_id_from_env "$slot")
            if [[ -z "$existing_id" ]]; then
                next_available_slot=$slot
                break
            fi
        done
        
        if [[ -z "$next_available_slot" ]]; then
            log_error "Tidak ada slot kosong yang tersedia!"
            continue  # Back to menu
        fi
        
        local additional_nodes
        
        # Determine how many nodes to add
        if [ "$existing_nodes" -eq 0 ]; then
            echo -n "Berapa NODE_ID yang ingin dikonfigurasi? (1-10): "
            read -r additional_nodes
            
            if ! [[ "$additional_nodes" =~ ^[1-9]$|^10$ ]]; then
                log_error "Input tidak valid. Harus antara 1-10"
                continue  # Back to menu
            fi
        else
            echo -n "Berapa node tambahan yang ingin ditambah? (max: $((10 - existing_nodes))): "
            read -r additional_nodes
            
            if ! [[ "$additional_nodes" =~ ^[1-9]$ ]] || [ "$additional_nodes" -gt $((10 - existing_nodes)) ]; then
                log_error "Input tidak valid atau melebihi batas maksimal"
                continue  # Back to menu
            fi
        fi
        
        log_info "🚀 Menambah $additional_nodes node(s) baru..."
        
        # Konfirmasi sebelum melanjutkan
        echo ""
        echo -e "${YELLOW}⚠️  Konfirmasi penambahan NODE_ID:${NC}"
        echo "   • Akan menambah: $additional_nodes node(s) baru"
        echo "   • Slot yang akan diisi: mulai dari slot kosong pertama"
        echo "   • WALLET_ADDRESS: ${WALLET_ADDRESS:0:10}...${WALLET_ADDRESS: -4} (shared)"
        echo ""
        echo -n "Lanjutkan proses penambahan NODE_ID? (y/n): "
        read -r confirm_add
        
        if [[ ! $confirm_add =~ ^[Yy]$ ]]; then
            log_info "Penambahan NODE_ID dibatalkan, kembali ke menu sebelumnya"
            continue  # Back to menu
        fi
        
        # Setup NODE_IDs untuk nodes tambahan dengan menggunakan slot kosong
        if [ "$existing_nodes" -eq 0 ]; then
            log_info "🆔 Setup NODE_ID untuk $additional_nodes node(s) pertama..."
        else
            log_info "🆔 Setup NODE_ID untuk $additional_nodes node(s) baru..."
        fi
        echo "Tips: NODE_ID berupa angka unik yang akan divalidasi oleh Nexus server"
        echo "Contoh: 1234567, 9876543, 5555555"
        echo "Note: Semua node akan menggunakan WALLET_ADDRESS yang sama"
        echo ""
        
        # Cari dan gunakan slot kosong
        local slots_filled=0
        for ((slot=1; slot<=10 && slots_filled<additional_nodes; slot++)); do
            local existing_id
            existing_id=$(get_node_id_from_env "$slot")
            
            # Skip jika slot sudah terisi
            if [[ -n "$existing_id" ]]; then
                continue
            fi
            
            echo -e "${CYAN}=== Konfigurasi Node $slot ===${NC}"
            
            # Pilihan untuk batal di tengah proses
            echo -n "Lanjutkan konfigurasi Node $slot? (y/n/q untuk quit): "
            read -r continue_config
            
            if [[ $continue_config =~ ^[Qq]$ ]]; then
                log_info "Proses dibatalkan, kembali ke menu sebelumnya"
                continue  # Back to main menu loop
            elif [[ ! $continue_config =~ ^[Yy]$ ]]; then
                log_info "Skip Node $slot, lanjut ke slot berikutnya"
                continue  # Skip this slot, continue to next
            fi
            
            # Input NODE_ID
            while true; do
                echo -n "Masukkan NODE_ID untuk Node $slot (atau 'cancel' untuk batal): "
                read -r node_id
                
                # Check untuk cancel
                if [[ "$node_id" =~ ^[Cc]ancel$ ]]; then
                    log_info "Input NODE_ID dibatalkan, kembali ke menu sebelumnya"
                    continue 2  # Break from both while and for loop, back to main menu
                fi
                
                if [[ -n "$node_id" ]]; then
                    # Check untuk duplikasi dengan semua nodes yang sudah ada
                    local duplicate=false
                    for ((j=1; j<=10; j++)); do
                        local existing_id
                        existing_id=$(get_node_id_from_env "$j")
                        if [[ "$existing_id" == "$node_id" ]]; then
                            log_error "NODE_ID '$node_id' sudah digunakan oleh Node $j"
                            duplicate=true
                            break
                        fi
                    done
                    
                    if [[ "$duplicate" == false ]]; then
                        break
                    fi
                else
                    log_error "NODE_ID tidak boleh kosong"
                fi
            done
            
            # Simpan ke .env (tanpa parameter wallet karena menggunakan main wallet)
            add_node_to_env "$slot" "$node_id"
            log_success "Node $slot dikonfigurasi:"
            log_success "  NODE_ID: $node_id"
            log_success "  WALLET_ADDRESS: ${WALLET_ADDRESS:0:10}...${WALLET_ADDRESS: -4} (shared)"
            echo ""
            
            ((slots_filled++))
        done
        echo ""
        
        # Konfirmasi setelah input semua NODE_ID
        echo -e "${GREEN}✅ Selesai input $slots_filled NODE_ID baru!${NC}"
        echo ""
        echo -n "Lanjutkan ke deployment atau kembali ke menu? (d/m): "
        read -r next_action
        
        if [[ $next_action =~ ^[Mm]$ ]]; then
            log_info "Kembali ke menu tanpa deployment"
            continue  # Back to menu
        fi
        
        # Show summary
        local total_nodes
        total_nodes=$(grep -c "^NODE_ID_[0-9]*=" "$ENV_FILE" 2>/dev/null | head -1 | tr -d '\n' || echo "0")
        echo -e "${CYAN}📋 Summary NODE_IDs (Total: $total_nodes):${NC}"
        echo -e "WALLET_ADDRESS: ${WALLET_ADDRESS:0:10}...${WALLET_ADDRESS: -4}"
        echo ""
        # Tampilkan semua NODE_ID yang ada dengan urutan slot
        for ((i=1; i<=10; i++)); do
            local node_id
            node_id=$(get_node_id_from_env "$i")
            if [[ -n "$node_id" ]]; then
                print_node_message $i "NODE_ID: $node_id"
            fi
        done
        echo ""
        
        # Deploy additional nodes (jika Docker image tersedia)
        if [ "$docker_available" = true ]; then
            log_info "🚀 Deploying $additional_nodes node(s) baru..."
            # Deploy hanya slot yang baru diisi
            local deployed_count=0
            for ((slot=1; slot<=10 && deployed_count<additional_nodes; slot++)); do
                local node_id
                node_id=$(get_node_id_from_env "$slot")
                
                # Skip jika slot kosong atau sudah ada dari sebelumnya
                if [[ -z "$node_id" ]]; then
                    continue
                fi
                
                # Check apakah ini node baru (untuk deployment)
                # Kita deploy semua yang ada karena sulit tracking mana yang baru
                local node_name="nexus-node-$slot"
                local port=$((10000 + slot))
                local proxy=""
                
                # Check apakah container sudah running
                if docker ps --format "{{.Names}}" | grep -q "^$node_name$"; then
                    print_node_message $slot "Already running, skipping deployment"
                    continue
                fi
                
                # Get proxy if available
                if [ -f "$PROXY_FILE" ]; then
                    proxy=$(get_proxy_for_node $slot)
                fi
                
                print_node_message $slot "Deploying dengan NODE_ID: $node_id, Port: $port..."
                
                if deploy_single_node $slot "$node_id" "$port" "$proxy"; then
                    print_node_message $slot "✅ Berhasil di-deploy"
                    ((deployed_count++))
                else
                    print_node_message $slot "❌ Gagal deploy"
                fi
            done
            
            log_success "✅ Selesai menambah dan deploy nodes!"
        else
            log_warning "⚠️  NODE_ID ditambahkan ke konfigurasi tanpa deployment"
            log_info "Untuk deploy nodes, jalankan 'Install Nexus' terlebih dahulu"
            log_success "✅ Selesai menambah NODE_ID ke konfigurasi!"
        fi
        
        # Show final configuration
        echo ""
        echo -e "${GREEN}📋 Konfigurasi Final:${NC}"
        echo -e "📁 File konfigurasi: $ENV_FILE"
        echo -e "🔑 WALLET_ADDRESS: ${WALLET_ADDRESS:0:10}...${WALLET_ADDRESS: -4}"
        echo -e "📊 Total NODE_IDs: $(grep -c "^NODE_ID_[0-9]*=" "$ENV_FILE" 2>/dev/null || echo "0")"
        echo ""
        echo -e "${CYAN}📋 Detail konfigurasi per node:${NC}"
        # Tampilkan semua NODE_ID yang ada dengan urutan slot
        for ((i=1; i<=10; i++)); do
            local node_id
            node_id=$(get_node_id_from_env "$i")
            if [[ -n "$node_id" ]]; then
                print_node_message $i "NODE_ID: $node_id"
            fi
        done
        echo ""
        
        # Pilihan setelah selesai semua operasi
        echo -e "${GREEN}🎉 Operasi penambahan NODE_ID selesai!${NC}"
        echo ""
        echo "Pilihan selanjutnya:"
        echo "1. Tambah NODE_ID lagi"
        echo "2. Kembali ke menu utama"
        echo -n "Pilih opsi (1-2): "
        read -r final_choice
        
        case "$final_choice" in
            "1")
                log_info "Melanjutkan untuk tambah NODE_ID lagi..."
                continue  # Continue to add more nodes
                ;;
            "2")
                log_info "Kembali ke menu utama"
                return 0
                ;;
            *)
                log_info "Pilihan tidak valid, kembali ke menu utama"
                return 0
                ;;
        esac
        
        # Continue menu loop untuk operasi berikutnya
        continue
    done
}

# Banner
show_banner() {
    clear
    echo -e "${BLUE}"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                NEXUS CLI DOCKER MANAGER                      ║
║                                                               ║
║  ██████╗  ██████╗ ██╗  ██╗██╗  ██╗ █████╗ ███╗   ██╗███████╗ ║
║  ██╔══██╗██╔═══██╗██║ ██╔╝██║  ██║██╔══██╗████╗  ██║╚══███╔╝ ║
║  ██████╔╝██║   ██║█████╔╝ ███████║███████║██╔██╗ ██║  ███╔╝  ║
║  ██╔══██╗██║   ██║██╔═██╗ ██╔══██║██╔══██║██║╚██╗██║ ███╔╝   ║
║  ██║  ██║╚██████╔╝██║  ██╗██║  ██║██║  ██║██║ ╚████║███████╗ ║
║  ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝ ║
║                                                               ║
║                🚀 ALL-IN-ONE NEXUS MANAGER 🚀                ║
║                                                               ║
║              Install | Uninstall | Manage | Monitor          ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Setup direktori dan variabel
setup_environment() {
    WORKDIR="$HOME/nexus-multi-docker"
    ENV_FILE="$WORKDIR/.env"
    CONFIG_DIR="$HOME/.nexus"
    BASHRC="$HOME/.bashrc"
    SCREEN_SESSION="nexus"
    PROXY_FILE="$WORKDIR/proxy_list.txt"
    
    # Buat direktori jika belum ada dengan validasi
    if [ ! -d "$WORKDIR" ]; then
        log_info "📁 Creating working directory: $WORKDIR"
        mkdir -p "$WORKDIR" 2>/dev/null || {
            log_error "Failed to create directory: $WORKDIR"
            exit 1
        }
        log_success "Working directory created successfully"
    else
        log_info "Working directory already exists: $WORKDIR"
    fi
    
    mkdir -p "$CONFIG_DIR" 2>/dev/null || true
    
    # Load existing .env if available (global loading)
    load_existing_env
}

# Load existing environment variables globally
load_existing_env() {
    if [ -f "$ENV_FILE" ]; then
        log_info "📋 Loading existing environment from $ENV_FILE"
        set -a
        # shellcheck source=/dev/null
        source "$ENV_FILE"
        set +a
        
        # Validate critical variables
        if [[ -n "${WALLET_ADDRESS:-}" ]]; then
            log_success "✅ WALLET_ADDRESS loaded: ${WALLET_ADDRESS:0:10}..."
        fi
        
        local node_count
        node_count=$(grep -c "^NODE_ID_[0-9]*=" "$ENV_FILE" 2>/dev/null | head -1 | tr -d '\n' || echo "0")
        if [ "$node_count" -gt 0 ]; then
            log_success "✅ Found $node_count existing NODE_ID(s)"
        fi
        
        return 0
    else
        log_info "No existing .env file found"
        return 1
    fi
}

# Validasi sistem
validate_system() {
    log_info "Memvalidasi sistem..."
    
    # Check OS
    if [[ ! -f /etc/os-release ]]; then
        log_error "Tidak dapat mendeteksi OS. Script ini membutuhkan Linux."
        exit 1
    fi
    
    source /etc/os-release
    log_info "Terdeteksi OS: $PRETTY_NAME"
    
    # Check available space (minimal 10GB)
    local available_space
    available_space=$(df / | awk 'NR==2 {print $4}')
    local required_space=$((10 * 1024 * 1024))  # 10GB in KB
    
    if [[ $available_space -lt $required_space ]]; then
        log_error "Ruang disk tidak cukup. Dibutuhkan minimal 10GB, tersedia: $((available_space / 1024 / 1024))GB"
        exit 1
    fi
    
    # Check memory (minimal 2GB)
    local available_memory
    available_memory=$(free -k | awk 'NR==2{print $2}')
    local required_memory=$((2 * 1024 * 1024))  # 2GB in KB
    
    if [[ $available_memory -lt $required_memory ]]; then
        log_warning "Memory kurang dari 2GB. Performa mungkin terdampak."
    fi
    
    log_success "Validasi sistem berhasil"
}

# Install Docker
install_docker() {
    log_info "🐳 Menginstall Docker secara otomatis..."
    
    if command -v apt-get &> /dev/null; then
        # Ubuntu/Debian
        log_info "Terdeteksi sistem berbasis Debian/Ubuntu"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
        
    elif command -v yum &> /dev/null; then
        # CentOS/RHEL
        log_info "Terdeteksi sistem berbasis RedHat/CentOS"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
        
    elif command -v pacman &> /dev/null; then
        # Arch Linux
        log_info "Terdeteksi Arch Linux"
        sudo pacman -Sy --noconfirm docker
        
    else
        log_error "Package manager tidak didukung."
        exit 1
    fi
    
    # Start dan enable Docker service
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Add current user to docker group (if not root)
    if [[ $EUID -ne 0 ]]; then
        sudo usermod -aG docker $USER
        log_warning "Logout dan login kembali untuk menggunakan Docker tanpa sudo"
    fi
    
    log_success "✅ Docker berhasil diinstall"
}

# Install Screen
install_screen() {
    if ! command -v screen &> /dev/null; then
        log_info "Installing screen..."
        
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y screen
        elif command -v yum &> /dev/null; then
            sudo yum install -y screen
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y screen
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm screen
        else
            log_error "Tidak dapat menginstall screen. Silakan install manual."
            exit 1
        fi
        
        log_success "Screen berhasil diinstall"
    else
        log_success "Screen sudah terinstall"
    fi
}

# Setup environment variables
setup_env() {
    # Setup auto-load .env di ~/.bashrc
    LOAD_SNIPPET="# Auto-load Nexus env
if [ -f \"$ENV_FILE\" ]; then 
    set -a
    source \"$ENV_FILE\"
    set +a
fi"

    if ! grep -q "Auto-load Nexus env" "$BASHRC" 2>/dev/null; then
        echo "" >> "$BASHRC"
        echo "$LOAD_SNIPPET" >> "$BASHRC"
        log_success "Menambahkan auto-load .env ke $BASHRC"
    fi

    # Check if .env already exists and is valid
    if [ -f "$ENV_FILE" ] && [[ -n "${WALLET_ADDRESS:-}" ]]; then
        log_success "✅ Using existing environment configuration"
        log_info "WALLET_ADDRESS: ${WALLET_ADDRESS:0:10}..."
        
        local existing_nodes
        existing_nodes=$(grep -c "^NODE_ID_[0-9]*=" "$ENV_FILE" 2>/dev/null | head -1 | tr -d '\n' || echo "0")
        if [ "$existing_nodes" -gt 0 ]; then
            log_info "Existing NODE_IDs: $existing_nodes"
            echo -e "${CYAN}📋 Existing NODE_IDs:${NC}"
            for ((i=1; i<=existing_nodes; i++)); do
                local node_id
                node_id=$(get_node_id_from_env "$i")
                if [[ -n "$node_id" ]]; then
                    print_node_message $i "$node_id"
                fi
            done
            echo ""
        fi
        return 0
    fi

    # Create new .env if doesn't exist or invalid
    if [ ! -f "$ENV_FILE" ] || [[ -z "${WALLET_ADDRESS:-}" ]]; then
        log_info "Setup konfigurasi environment baru..."
        
        # Validasi wallet address
        while true; do
            echo -n "Masukkan WALLET_ADDRESS (0x...): "
            read -r WALLET_ADDRESS
            if [[ $WALLET_ADDRESS =~ ^0x[a-fA-F0-9]{40}$ ]]; then
                log_success "Format wallet address valid"
                break
            else
                log_error "Format wallet address tidak valid. Harus 40 karakter hex dimulai dengan 0x"
            fi
        done
        
        # Buat file .env dengan struktur sederhana
        cat > "$ENV_FILE" << EOF
# Nexus Node configuration - Generated $(date)
WALLET_ADDRESS=$WALLET_ADDRESS
NODE_COUNT=0
DEBUG=false

# Individual Node IDs will be added when nodes are deployed
EOF
        chmod 600 "$ENV_FILE"
        
        # Export variables
        export WALLET_ADDRESS
        log_success "File $ENV_FILE berhasil dibuat"
    fi
}

# Add node ID to .env file
add_node_to_env() {
    local node_num=$1
    local node_id=$2
    
    # Check if NODE_ID already exists for this node
    if grep -q "^NODE_ID_$node_num=" "$ENV_FILE"; then
        # Update existing entry
        sed -i "s/^NODE_ID_$node_num=.*/NODE_ID_$node_num=$node_id/" "$ENV_FILE"
    else
        # Add new entry
        echo "NODE_ID_$node_num=$node_id" >> "$ENV_FILE"
    fi
    
    # Update NODE_COUNT
    local current_count
    current_count=$(grep -c "^NODE_ID_[0-9]*=" "$ENV_FILE" 2>/dev/null | head -1 | tr -d '\n' || echo "0")
    
    if grep -q "^NODE_COUNT=" "$ENV_FILE"; then
        sed -i "s/^NODE_COUNT=.*/NODE_COUNT=$current_count/" "$ENV_FILE"
    else
        echo "NODE_COUNT=$current_count" >> "$ENV_FILE"
    fi
}

# Get node ID from .env file
get_node_id_from_env() {
    local node_num=$1
    grep "^NODE_ID_$node_num=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2
}

# Get wallet address for specific node from .env file  
get_wallet_address_from_env() {
    local node_num=$1
    # Always return the main WALLET_ADDRESS since we use one wallet for all nodes
    grep "^WALLET_ADDRESS=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2
}

# Setup multiple node IDs
setup_node_ids() {
    local num_nodes=$1
    
    log_info "🆔 Setup NODE_ID untuk $num_nodes node(s)..."
    echo "Tips: NODE_ID berupa angka unik yang akan divalidasi oleh Nexus server"
    echo "Contoh: 1234567, 9876543, 5555555"
    echo "Note: Validasi format akan dilakukan oleh Nexus, bukan script"
    echo ""
    
    for ((i=1; i<=num_nodes; i++)); do
        local existing_node_id
        existing_node_id=$(get_node_id_from_env "$i")
        
        if [[ -n "$existing_node_id" ]]; then
            echo -e "${CYAN}Node $i sudah ada: $existing_node_id${NC}"
            echo -n "Gunakan yang ada atau ganti? (y/n): "
            read -r use_existing
            if [[ $use_existing =~ ^[Yy]$ ]]; then
                continue
            fi
        fi
        
        while true; do
            echo -n "Masukkan NODE_ID untuk Node $i (angka): "
            read -r node_id
            
            if [[ -n "$node_id" ]]; then
                # Check untuk duplikasi saja
                local duplicate=false
                for ((j=1; j<i; j++)); do
                    local existing_id
                    existing_id=$(get_node_id_from_env "$j")
                    if [[ "$existing_id" == "$node_id" ]]; then
                        log_error "NODE_ID '$node_id' sudah digunakan oleh Node $j"
                        duplicate=true
                        break
                    fi
                done
                
                if [[ "$duplicate" == false ]]; then
                    add_node_to_env "$i" "$node_id"
                    log_success "Node $i: $node_id (akan divalidasi oleh Nexus server)"
                    break
                fi
            else
                log_error "NODE_ID tidak boleh kosong"
            fi
        done
    done
    echo ""
    
    # Show summary
    echo -e "${CYAN}📋 Summary NODE_IDs:${NC}"
    for ((i=1; i<=num_nodes; i++)); do
        local node_id
        node_id=$(get_node_id_from_env "$i")
        print_node_message $i "$node_id"
    done
    echo ""
}

# Validate node count
validate_node_count() {
    local input="$1"
    [[ "$input" =~ ^[1-9]$|^10$ ]]
}

# Setup proxy configuration
setup_proxy() {
    log_info "🔗 Setup konfigurasi proxy..."
    
    # Enhanced auto detect proxy file with priority order
    local proxy_files=(
        "$PROXY_FILE"                    # 1. workdir/proxy_list.txt (primary)
        "/root/proxy_list.txt"           # 2. /root/proxy_list.txt (auto-copy source)
        "$CONFIG_DIR/proxy_list.txt"     # 3. ~/.nexus/proxy_list.txt (alternative)
        "./proxy_list.txt"               # 4. current directory
        "$HOME/proxy_list.txt"           # 5. home directory
    )
    local found_proxy_file=""
    
    for proxy_file in "${proxy_files[@]}"; do
        if [ -f "$proxy_file" ] && [ -s "$proxy_file" ]; then
            found_proxy_file="$proxy_file"
            log_success "🎯 Auto-detected proxy file: $found_proxy_file"
            break
        fi
    done
    
    # Auto-copy logic: if found in /root/ but not in workdir, copy it
    if [[ "$found_proxy_file" == "/root/proxy_list.txt" && ! -f "$PROXY_FILE" ]]; then
        log_info "📋 Auto-copying proxy_list.txt from /root/ to workdir..."
        cp "/root/proxy_list.txt" "$PROXY_FILE" && {
            log_success "✅ Proxy file copied to $PROXY_FILE"
            found_proxy_file="$PROXY_FILE"  # Update to use the copied file
        } || {
            log_warning "⚠️  Failed to copy proxy file, using original location"
        }
    fi
    
    if [[ -n "$found_proxy_file" ]]; then
        # Validate and process proxy file
        log_info "📋 Validating proxies dari $found_proxy_file..."
        
        local valid_proxies=0
        local total_proxies=0
        
        # Create temp file for valid proxies
        local temp_proxy_file="/tmp/nexus_valid_proxies.txt"
        true > "$temp_proxy_file"
        
        while IFS= read -r proxy || [[ -n "$proxy" ]]; do
            # Skip empty lines and comments
            [[ -z "$proxy" || "$proxy" =~ ^[[:space:]]*# ]] && continue
            
            proxy=$(echo "$proxy" | xargs) # trim whitespace
            ((total_proxies++))
            
            # Basic proxy format validation
            if [[ "$proxy" =~ ^https?://[^:]+:[0-9]+$ ]] || 
               [[ "$proxy" =~ ^https?://[^:]+:[^@]+@[^:]+:[0-9]+$ ]] ||
               [[ "$proxy" =~ ^socks5?://[^:]+:[0-9]+$ ]]; then
                echo "$proxy" >> "$temp_proxy_file"
                ((valid_proxies++))
            else
                log_warning "⚠️  Proxy format tidak valid: $proxy"
            fi
        done < "$found_proxy_file"
        
        if [ "$valid_proxies" -gt 0 ]; then
            # Always ensure primary location has the proxies
            if [[ "$found_proxy_file" != "$PROXY_FILE" ]]; then
                cp "$temp_proxy_file" "$PROXY_FILE"
                log_info "📁 Copied validated proxies to primary location: $PROXY_FILE"
            else
                cp "$temp_proxy_file" "$PROXY_FILE"
            fi
            
            # Always copy to alternative location for backup/compatibility
            local alt_proxy_file="$CONFIG_DIR/proxy_list.txt"
            cp "$temp_proxy_file" "$alt_proxy_file"
            log_info "📁 Copied proxy list to alternative location: $alt_proxy_file"
            
            rm -f "$temp_proxy_file"
            
            log_success "✅ Loaded $valid_proxies/$total_proxies valid proxies"
            echo -e "${CYAN}📊 Proxy Summary:${NC}"
            echo "   Total proxies: $valid_proxies"
            echo "   Primary location: $PROXY_FILE"
            echo "   Alternative location: $alt_proxy_file"
            
            # Show first 3 proxies as preview
            echo -e "${CYAN}📝 Preview (first 3):${NC}"
            head -n 3 "$PROXY_FILE" | while read -r proxy; do
                echo "   → $proxy"
            done
            
            return 0
        else
            log_error "❌ Tidak ada proxy valid ditemukan!"
            rm -f "$temp_proxy_file"
        fi
    fi
    
    # Manual setup jika auto-detect gagal
    echo -n "Tidak ada proxy file ditemukan. Setup manual? (y/n): "
    read -r setup_manual
    
    if [[ $setup_manual =~ ^[Yy]$ ]]; then
        echo "Format proxy: http://username:password@ip:port atau http://ip:port"
        echo "Masukkan satu proxy per baris, tekan Enter kosong untuk selesai:"
        
        true > "$PROXY_FILE"  # Clear file
        local proxy_count=0
        
        while true; do
            echo -n "Proxy $((proxy_count + 1)): "
            read -r proxy
            
            if [[ -z "$proxy" ]]; then
                break
            fi
            
            # Basic validation
            if [[ "$proxy" =~ ^https?://[^:]+:[0-9]+$ ]] || 
               [[ "$proxy" =~ ^https?://[^:]+:[^@]+@[^:]+:[0-9]+$ ]]; then
                echo "$proxy" >> "$PROXY_FILE"
                ((proxy_count++))
                log_success "Proxy $proxy_count added"
            else
                log_error "Format proxy tidak valid"
            fi
        done
        
        if [ "$proxy_count" -gt 0 ]; then
            # Copy to alternative location for backup/compatibility
            local alt_proxy_file="$CONFIG_DIR/proxy_list.txt"
            cp "$PROXY_FILE" "$alt_proxy_file"
            
            log_success "✅ $proxy_count proxy berhasil dikonfigurasi"
            log_info "📁 Proxy list tersimpan di:"
            log_info "   Primary: $PROXY_FILE"
            log_info "   Alternative: $alt_proxy_file"
            return 0
        fi
    fi
    
    log_info "Melanjutkan tanpa proxy configuration"
    return 1
}

# Get proxy for node
get_proxy_for_node() {
    local node_id=$1
    
    if [[ -f "$PROXY_FILE" ]]; then
        local total_proxies
        total_proxies=$(wc -l < "$PROXY_FILE")
        
        if [ $total_proxies -gt 0 ]; then
            local proxy_index=$(( (node_id - 1) % total_proxies + 1 ))
            sed -n "${proxy_index}p" "$PROXY_FILE"
        fi
    fi
}

# Build Docker image
build_docker_image() {
    log_info "Building nexus-cli:latest..."
    
    # Buat inline Dockerfile yang stabil
    cat > "$WORKDIR/Dockerfile" << 'EOF'
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/root/.nexus/bin:$PATH"

RUN apt-get update && \
    apt-get install -y \
        curl \
        ca-certificates \
        wget \
        gnupg \
        lsb-release \
        iputils-ping \
        dnsutils && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN for i in 1 2 3; do \
        curl -sSf https://cli.nexus.xyz/ -o install.sh && break || sleep 10; \
    done && \
    chmod +x install.sh && \
    NONINTERACTIVE=1 ./install.sh && \
    rm install.sh

RUN mkdir -p /root/.nexus

WORKDIR /root

ENTRYPOINT ["nexus-network"]
CMD ["--help"]
EOF
    
    # Build image
    if docker build --pull --no-cache -t nexus-cli:latest "$WORKDIR"; then
        log_success "nexus-cli:latest berhasil dibuild"
    else
        log_error "Gagal build Docker image"
        exit 1
    fi
}

# Install Nexus
install_nexus() {
    show_banner
    log_info "🚀 Memulai instalasi Nexus CLI Docker..."
    
    # Deteksi existing containers dulu
    detect_existing_nodes
    
    validate_system
    setup_environment
    
    # Install dependencies
    install_screen
    
    # Check Docker installation
    if ! command -v docker &> /dev/null; then
        log_warning "Docker tidak terinstall, akan diinstall secara otomatis..."
        install_docker
        log_info "Docker telah diinstall. Silakan logout dan login kembali, lalu jalankan script ini lagi."
        exit 0
    else
        log_success "Docker sudah terinstall"
    fi
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon tidak berjalan. Mencoba start Docker..."
        sudo systemctl start docker
        sleep 5
        
        if ! docker info >/dev/null 2>&1; then
            log_error "Gagal menjalankan Docker daemon."
            exit 1
        fi
    fi
    
    # Setup environment
    setup_env
    
    # Clean up old containers (hanya nexus-node related)
    log_info "🧹 Membersihkan container lama..."
    docker rm -f nexus-node 2>/dev/null || true
    for i in {1..10}; do
        docker rm -f "nexus-node-$i" 2>/dev/null || true
    done
    screen -S $SCREEN_SESSION -X quit 2>/dev/null || true
    
    # Build Docker image
    build_docker_image
    
    # Register wallet
    log_info "Registering wallet $WALLET_ADDRESS..."
    docker run --rm -v "$CONFIG_DIR":/root/.nexus nexus-cli:latest \
        register-user --wallet-address "$WALLET_ADDRESS" 2>/dev/null || \
        log_warning "Wallet mungkin sudah terdaftar"
    
    # Setup config.json (base config - akan diupdate per node)
    cat > "$CONFIG_DIR/config.json" << EOF
{
    "created_at": "$(date -Iseconds)",
    "wallet_address": "$WALLET_ADDRESS"
}
EOF
    
    log_success "✅ Instalasi Nexus CLI Docker berhasil!"
    log_info "Node akan langsung dimulai..."
    start_nexus
}

# Start Nexus Multi-Node
start_nexus() {
    log_info "🚀 Memulai Nexus node(s)..."
    
    # Check prerequisites
    if [ ! -f "$ENV_FILE" ]; then
        log_error "File .env tidak ditemukan. Jalankan install terlebih dahulu."
        return 1
    fi
    
    # Load environment (already loaded globally, but ensure it's current)
    if [[ -z "${WALLET_ADDRESS:-}" ]]; then
        load_existing_env
    fi
    
    log_info "Loaded WALLET_ADDRESS: ${WALLET_ADDRESS:0:10}..."
    
    # Check if NODE_IDs already exist
    local existing_nodes
    existing_nodes=$(grep -c "^NODE_ID_[0-9]*=" "$ENV_FILE" 2>/dev/null | head -1 | tr -d '\n' || echo "0")
    
    local num_nodes
    if [ "$existing_nodes" -gt 0 ]; then
        echo -e "${CYAN}Found $existing_nodes existing NODE_ID(s):${NC}"
        for ((i=1; i<=existing_nodes; i++)); do
            local node_id
            node_id=$(get_node_id_from_env "$i")
            if [[ -n "$node_id" ]]; then
                print_node_message $i "$node_id"
            fi
        done
        echo ""
        
        echo "1. Deploy existing NODE_IDs ($existing_nodes nodes)"
        echo "2. Setup new NODE_IDs"
        echo -n "Choose option (1-2): "
        read -r choice
        
        case "$choice" in
            "1")
                num_nodes=$existing_nodes
                log_info "Using existing $num_nodes NODE_ID(s)"
                ;;
            "2")
                while true; do
                    echo -n "Masukkan jumlah node yang ingin dijalankan (1-10): "
                    read -r num_nodes
                    if validate_node_count "$num_nodes"; then
                        setup_node_ids "$num_nodes"
                        break
                    else
                        log_error "Jumlah node harus antara 1-10"
                    fi
                done
                ;;
            *)
                log_error "Pilihan tidak valid"
                return 1
                ;;
        esac
    else
        # No existing NODE_IDs, ask for number of nodes
        while true; do
            echo -n "Masukkan jumlah node yang ingin dijalankan (1-10): "
            read -r num_nodes
            if validate_node_count "$num_nodes"; then
                # Setup individual NODE_IDs
                setup_node_ids "$num_nodes"
                break
            else
                log_error "Jumlah node harus antara 1-10"
            fi
        done
    fi
    
    # Warning for high node count (automation risk)
    if [ "$num_nodes" -gt 5 ]; then
        echo -e "${RED}🚨 HIGH RISK: Menjalankan lebih dari 5 nodes${NC}"
        echo -e "${RED}   - Automation detection risk sangat tinggi${NC}"
        echo -e "${RED}   - Butuh proxy berkualitas tinggi${NC}"
        echo -n "Tetap lanjutkan? Risiko sangat tinggi (y/n): "
        read -r confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            log_info "Operasi dibatalkan - bijak!"
            return 0
        fi
    elif [ "$num_nodes" -gt 2 ]; then
        echo -e "${YELLOW}⚠️  MEDIUM RISK: Menjalankan $num_nodes nodes${NC}"
        echo -e "${YELLOW}   - Balance antara efisiensi dan keamanan${NC}"
        echo -e "${YELLOW}   - Sangat disarankan menggunakan proxy${NC}"
    else
        echo -e "${GREEN}✅ LOW RISK: Menjalankan $num_nodes node(s)${NC}"
        echo -e "${GREEN}   - Mirip user biasa, sulit terdeteksi${NC}"
    fi
    
    log_success "Akan menjalankan $num_nodes node(s)"
    
    # Setup proxy if needed
    local use_proxy=false
    if setup_proxy; then
        use_proxy=true
        local proxy_count
        proxy_count=$(wc -l < "$PROXY_FILE")
        log_info "🔗 Akan menggunakan $proxy_count proxy untuk rotasi"
    else
        log_warning "⚠️  Melanjutkan tanpa proxy - semua node akan menggunakan IP yang sama"
        if [ "$num_nodes" -gt 1 ]; then
            echo -e "${RED}   - TANPA PROXY dengan multiple nodes = Risiko deteksi tinggi!${NC}"
        fi
    fi
    
    echo -e "\nMemulai $num_nodes node(s)..."
    
    local success=0
    local failed=0
    
    for ((i=1; i<=num_nodes; i++)); do
        local port=$((10000+i))
        local node_name="nexus-node-$i"
        local node_id
        node_id=$(get_node_id_from_env "$i")
        local proxy_env=""
        local proxy_info=""
        
        # Validate node_id exists
        if [[ -z "$node_id" ]]; then
            print_node_message $i "❌ NODE_ID tidak ditemukan, skip..."
            ((failed++))
            continue
        fi
        
        # Get proxy for this node if available
        if [ "$use_proxy" = true ]; then
            local node_proxy
            node_proxy=$(get_proxy_for_node "$i")
            if [[ -n "$node_proxy" ]]; then
                proxy_env="-e HTTP_PROXY=$node_proxy -e HTTPS_PROXY=$node_proxy -e http_proxy=$node_proxy -e https_proxy=$node_proxy"
                proxy_info=" via proxy: ${node_proxy}"
            fi
        fi
        
        print_node_message $i "Initializing$proxy_info..."
        
        # Remove existing container
        if docker ps -a --format "{{.Names}}" | grep -q "^$node_name$"; then
            print_node_message $i "Removing existing container..."
            docker stop "$node_name" >/dev/null 2>&1 || true
            docker rm "$node_name" >/dev/null 2>&1 || true
        fi
        
        # Check port availability
        if ! is_port_free $port; then
            print_node_message $i "Port $port is busy, skipping..."
            ((failed++))
            continue
        fi
        
        # Create data directory
        mkdir -p "$CONFIG_DIR/node$i"
        
        # Setup config.json for this node
        cat > "$CONFIG_DIR/node$i/config.json" << EOF
{
    "node_id": "$node_id",
    "created_at": "$(date -Iseconds)",
    "wallet_address": "$WALLET_ADDRESS"
}
EOF
        
        # Check device capabilities
        if [ -e /dev/net/tun ]; then
            DEVICE_ARGS="--device /dev/net/tun --cap-add NET_ADMIN"
        else
            DEVICE_ARGS="--cap-add NET_ADMIN"
        fi
        
        # Start container
        print_node_message $i "Starting on port $port..."
        
        if docker run -d --name "$node_name" \
            --network host \
            $DEVICE_ARGS \
            $proxy_env \
            -p "$port:10000" \
            -v "$CONFIG_DIR/node$i":/nexus-config \
            -v /etc/resolv.conf:/etc/resolv.conf:ro \
            --restart unless-stopped \
            --entrypoint /bin/sh \
            nexus-cli:latest -c "
                # Copy config files if they exist
                if [ -f /nexus-config/config.json ]; then
                    cp /nexus-config/config.json /root/.nexus/
                fi
                # Run nexus-network
                exec /root/.nexus/bin/nexus-network start --headless --node-id $node_id
            " >/dev/null 2>&1; then
            
            sleep 3
            if docker ps --format "{{.Names}}" | grep -q "^$node_name$"; then
                if [[ -n "$proxy_info" ]]; then
                    print_node_message $i "✓ Started successfully on port $port$proxy_info"
                else
                    print_node_message $i "✓ Started successfully on port $port (no proxy)"
                fi
                ((success++))
                
                # Create screen session for this node
                screen -dmS "nexus-node-$i" bash -c "
                    echo '=== Nexus Node $i Monitor ==='
                    echo 'Container: $node_name'
                    echo 'NODE_ID: $node_id'
                    echo 'Port: $port'
                    echo 'Proxy: $proxy_info'
                    echo \"Time: \$(date)\"
                    echo '=========================='
                    echo 'Following Docker logs...'
                    echo
                    docker logs -f $node_name
                " 2>/dev/null || true
                
            else
                print_node_message $i "✗ Container exited"
                ((failed++))
            fi
        else
            print_node_message $i "✗ Failed to start"
            ((failed++))
        fi
    done
    
    echo
    log_success "🎉 Summary: $success nodes started, $failed failed"
    
    if [ $success -gt 0 ]; then
        echo
        log_info "📊 Container status: docker ps | grep nexus-node"
        log_info "📋 Logs untuk node tertentu: docker logs -f nexus-node-[1-$num_nodes]"
        log_info "📺 Screen sessions: screen -r nexus-node-[1-$num_nodes]"
        log_info "🔗 Port range: 10001-$((10000+num_nodes))"
        echo
    fi
}

# Check port availability
is_port_free() {
    local port=$1
    # Try netstat first, fallback to ss if netstat not available
    if command -v netstat >/dev/null 2>&1; then
        ! netstat -tuln 2>/dev/null | grep -q ":$port "
    elif command -v ss >/dev/null 2>&1; then
        ! ss -tuln 2>/dev/null | grep -q ":$port "
    else
        # If neither available, try lsof or just return true
        if command -v lsof >/dev/null 2>&1; then
            ! lsof -i :$port >/dev/null 2>&1
        else
            # Last resort: assume port is free
            true
        fi
    fi
}

# Stop Nexus Multi-Node
stop_nexus() {
    log_info "⏹️  Menghentikan Nexus node(s)..."
    
    # Find all running nexus nodes
    local running_nodes
    running_nodes=$(docker ps --filter "name=nexus-node-" --format "{{.Names}}" | sort -V)
    
    if [[ -z "$running_nodes" ]]; then
        log_warning "Tidak ada node yang berjalan"
        return 0
    fi
    
    echo "Running nodes:"
    echo "$running_nodes" | while read -r container; do
        local node_id=${container#nexus-node-}
        print_node_message "$node_id" "Running"
    done
    
    echo
    echo "1. Stop all nodes"
    echo "2. Stop specific nodes"
    echo "3. Cancel"
    
    while true; do
        echo -n "Choose option (1-3): "
        read -r choice
        
        case "$choice" in
            "1")
                log_info "Stopping all nodes..."
                for container in $running_nodes; do
                    local node_id=${container#nexus-node-}
                    print_node_message "$node_id" "Stopping..."
                    docker stop "$container" >/dev/null 2>&1
                    docker rm "$container" >/dev/null 2>&1
                    screen -S "$container" -X quit 2>/dev/null || true
                    print_node_message "$node_id" "✓ Stopped"
                done
                log_success "✅ All nodes stopped"
                break
                ;;
            "2")
                echo -n "Enter node numbers (comma-separated, e.g. 1,2,3): "
                read -r nodes_input
                IFS=',' read -ra node_ids <<< "$nodes_input"
                
                for node_id in "${node_ids[@]}"; do
                    node_id=$(echo "$node_id" | xargs)
                    local container="nexus-node-$node_id"
                    
                    if docker ps --format "{{.Names}}" | grep -q "^$container$"; then
                        print_node_message "$node_id" "Stopping..."
                        docker stop "$container" >/dev/null 2>&1
                        docker rm "$container" >/dev/null 2>&1
                        screen -S "$container" -X quit 2>/dev/null || true
                        print_node_message "$node_id" "✓ Stopped"
                    else
                        print_node_message "$node_id" "Not running"
                    fi
                done
                break
                ;;
            "3")
                log_info "Operation cancelled"
                return 0
                ;;
            *)
                log_error "Invalid option. Please choose 1, 2, or 3."
                ;;
        esac
    done
}

# Show status Multi-Node
show_status() {
    show_banner
    log_info "📊 Status Nexus Nodes:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Docker containers status
    local running_nodes
    running_nodes=$(docker ps --filter "name=nexus-node-" --format "{{.Names}}\t{{.Status}}\t{{.Ports}}")
    
    if [[ -n "$running_nodes" ]]; then
        echo -e "${BLUE}🟢 Running Nodes:${NC}"
        echo "$running_nodes" | while IFS=$'\t' read -r name status ports; do
            local node_id=${name#nexus-node-}
            local port
            port=$(echo "$ports" | grep -o '[0-9]*->10000' | cut -d'-' -f1)
            local color
            color=$(get_node_color "$node_id")
            echo -e "${color}Node $node_id:${NC} $status | Port: $port"
        done
        echo
    else
        echo -e "${YELLOW}No nodes running${NC}"
        echo
    fi
    
    # All containers (including stopped)
    local all_nodes
    all_nodes=$(docker ps -a --filter "name=nexus-node-" --format "{{.Names}}\t{{.Status}}")
    
    if [[ -n "$all_nodes" ]]; then
        echo -e "${BLUE}📋 All Nodes Status:${NC}"
        echo "$all_nodes" | while IFS=$'\t' read -r name status; do
            local node_id=${name#nexus-node-}
            local color
            color=$(get_node_color "$node_id")
            
            if echo "$status" | grep -q "Up"; then
                echo -e "${color}Node $node_id:${NC} ${GREEN}$status${NC}"
            else
                echo -e "${color}Node $node_id:${NC} ${RED}$status${NC}"
            fi
        done
        echo
    fi
    
    # Screen sessions status
    local screen_sessions
    screen_sessions=$(screen -list 2>/dev/null | grep "nexus-node-" || true)
    
    if [[ -n "$screen_sessions" ]]; then
        echo -e "${BLUE}📺 Screen Sessions:${NC}"
        echo "$screen_sessions" | while read -r session; do
            local session_name
            session_name=$(echo "$session" | awk '{print $1}' | cut -d'.' -f2)
            if [[ "$session_name" =~ nexus-node-([0-9]+) ]]; then
                local node_id="${BASH_REMATCH[1]}"
                local color
                color=$(get_node_color "$node_id")
                echo -e "${color}Node $node_id:${NC} ${GREEN}Active${NC} (screen -r $session_name)"
            fi
        done
        echo
    else
        echo -e "${YELLOW}No active screen sessions${NC}"
        echo
    fi
    
    # Environment info
    if [ -f "$ENV_FILE" ]; then
        echo -e "${BLUE}Environment:${NC}"
        cat "$ENV_FILE" | grep -v "^#" | grep -v "^$"
        
        # Show individual NODE_IDs
        echo -e "${BLUE}Individual NODE_IDs:${NC}"
        local node_ids
        node_ids=$(grep "^NODE_ID_[0-9]*=" "$ENV_FILE" 2>/dev/null || echo "")
        if [[ -n "$node_ids" ]]; then
            echo "$node_ids" | while IFS='=' read -r key value; do
                local node_num=${key#NODE_ID_}
                local color
                color=$(get_node_color "$node_num")
                echo -e "${color}Node $node_num:${NC} $value"
            done
        else
            echo "Belum ada NODE_ID individual yang dikonfigurasi"
        fi
        echo
    fi
    
    # Proxy info
    if [ -f "$PROXY_FILE" ]; then
        echo -e "${BLUE}Proxy Configuration:${NC}"
        local proxy_count
        proxy_count=$(wc -l < "$PROXY_FILE")
        echo "Total proxies: $proxy_count"
        echo "Proxy rotation: Enabled"
        echo "Proxy list:"
        cat "$PROXY_FILE" | nl -w2 -s'. '
        echo
    else
        echo -e "${YELLOW}Proxy: Not configured${NC}"
        echo
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Show recent logs from running containers
    local running_count
    running_count=$(docker ps --filter "name=nexus-node-" --format "{{.Names}}" | wc -l)
    
    if [ "$running_count" -gt 0 ]; then
        echo
        log_info "📋 Recent logs (last 5 lines from each running node):"
        docker ps --filter "name=nexus-node-" --format "{{.Names}}" | while read -r container; do
            local node_id=${container#nexus-node-}
            local color
            color=$(get_node_color "$node_id")
            echo -e "${color}=== Node $node_id Logs ===${NC}"
            docker logs --tail 5 "$container" 2>/dev/null || echo "No logs available"
            echo
        done
    fi
    
    echo -n "Tekan Enter untuk kembali ke menu..."
    read -r
}

# Uninstall Nexus
uninstall_nexus() {
    show_banner
    log_warning "🗑️  Memulai uninstall semua Nexus Nodes..."
    
    # Deteksi containers yang ada
    detect_existing_nodes
    
    echo -e "${RED}WARNING: Ini akan menghapus SEMUA nodes Nexus dan data terkait!${NC}"
    echo -n "Apakah Anda yakin ingin menghapus semua data Nexus? (y/n): "
    read -r REPLY
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Uninstall dibatalkan"
        return 0
    fi
    
    # Stop all nodes
    stop_nexus
    
    # Stop all screen sessions
    log_info "🛑 Menghentikan semua screen sessions..."
    screen -list 2>/dev/null | grep "nexus-node-" | cut -d. -f1 | awk '{print $1}' | while read -r session; do
        screen -S "$session" -X quit 2>/dev/null || true
    done
    
    # Remove all Docker containers (detect all nexus-node containers)
    log_info "🗑️  Menghapus semua Nexus Docker containers..."
    local nexus_containers
    nexus_containers=$(docker ps -a --filter "name=nexus-node-" --format "{{.Names}}" 2>/dev/null || echo "")
    
    if [ -n "$nexus_containers" ]; then
        echo "$nexus_containers" | while read -r container; do
            if [ -n "$container" ]; then
                log_info "Menghapus container: $container"
                docker rm -f "$container" 2>/dev/null || true
            fi
        done
    fi
    
    # Fallback removal untuk format lama (hanya nexus-node related)
    for i in {1..10}; do
        docker rm -f "nexus-node-$i" 2>/dev/null || true
    done
    docker rm -f nexus-node 2>/dev/null || true
    
    # Remove images (hanya nexus related)
    log_info "🗑️  Menghapus Nexus Docker images..."
    docker rmi nexus-cli:latest 2>/dev/null || true
    docker rmi nexus-node 2>/dev/null || true
    
    # Remove directories
    log_info "Menghapus direktori konfigurasi..."
    rm -rf "$WORKDIR" 2>/dev/null || true
    rm -rf "$CONFIG_DIR" 2>/dev/null || true
    
    # Note: ENV_FILE dan PROXY_FILE sudah terhapus dengan $WORKDIR
    
    # Remove auto-load from bashrc
    if grep -q "Auto-load Nexus env" "$BASHRC" 2>/dev/null; then
        log_info "Menghapus auto-load dari $BASHRC..."
        sed -i '/# Auto-load Nexus env/,+4d' "$BASHRC"
    fi
    
    # Clean up Docker system
    docker system prune -f 2>/dev/null || true
    
    log_success "✅ Uninstall semua Nexus nodes berhasil!"
    
    echo
    echo -n "Tekan Enter untuk keluar..."
    read -r
    exit 0
}

# Show main menu
show_menu() {
    show_banner
    echo -e "${CYAN}MENU UTAMA:${NC}"
    echo
    echo -e "  ${GREEN}1.${NC} Install Nexus"
    echo -e "  ${GREEN}2.${NC} Status & Logs"
    echo -e "  ${GREEN}3.${NC} Add Node ID"
    echo -e "  ${GREEN}4.${NC} Uninstall Nexus"
    echo -e "  ${GREEN}5.${NC} Exit"
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
}

# Main function
main() {
    # Setup environment variables
    setup_environment
    
    while true; do
        show_menu
        
        echo -n "Pilih menu (1-5): "
        read -r choice
        
        case "$choice" in
            "1")
                install_nexus
                ;;
            "2")
                show_status
                ;;
            "3")
                add_new_node_id
                ;;
            "4")
                uninstall_nexus
                ;;
            "5")
                log_info "Keluar dari Nexus Multi-Node Manager..."
                exit 0
                ;;
            *)
                log_error "Pilihan tidak valid: '$choice'"
                echo -n "Tekan Enter untuk melanjutkan..."
                read -r
                ;;
        esac
    done
}

# Run main function
main "$@"
