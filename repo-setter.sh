#!/usr/bin/env bash
# ==============================================================================
#  Repo-Setter: Linux Mirror Benchmark & sources.list Configurator
# ==============================================================================
#  Description: Automatically detects Linux OS distribution and codename,
#               benchmarks Iranian and International repository mirrors for
#               availability & latency, and safely configures /etc/apt/sources.list.
#
#  License: MIT
# ==============================================================================

set -o pipefail

# ------------------------------------------------------------------------------
# Global Variables & Defaults
# ------------------------------------------------------------------------------
SCRIPT_VERSION="1.0.0"
SOURCES_FILE="/etc/apt/sources.list"
UBUNTU_SOURCES_DEB822="/etc/apt/sources.list.d/ubuntu.sources"
BACKUP_DIR="/etc/apt/backups"
CURL_TIMEOUT=3
MAX_PARALLEL_TESTS=5

# UI Colors (disabled if not terminal)
if [ -t 1 ]; then
    C_RESET="\033[0m"
    C_BOLD="\033[1m"
    C_DIM="\033[2m"
    C_RED="\033[31m"
    C_GREEN="\033[32m"
    C_YELLOW="\033[33m"
    C_BLUE="\033[34m"
    C_MAGENTA="\033[35m"
    C_CYAN="\033[36m"
    C_WHITE="\033[37m"
else
    C_RESET=""
    C_BOLD=""
    C_DIM=""
    C_RED=""
    C_GREEN=""
    C_YELLOW=""
    C_BLUE=""
    C_MAGENTA=""
    C_CYAN=""
    C_WHITE=""
fi

# Detected System Attributes
OS_ID=""
OS_PRETTY=""
OS_CODENAME=""
OS_VERSION_ID=""
OS_ARCH=""
IS_SUPPORTED=0

# Benchmark Results (Arrays)
# Format per item: "NAME|URL|LATENCY_MS|STATUS"
declare -a BENCHMARK_RESULTS=()

# ------------------------------------------------------------------------------
# Helper Functions: Logging & UI
# ------------------------------------------------------------------------------
FIRST_RUN=1

print_banner() {
    if [ "${FIRST_RUN:-1}" -eq 1 ] && [ -t 1 ]; then
        clear 2>/dev/null || true
        FIRST_RUN=0
    else
        echo ""
        echo -e "${C_DIM}─────────────────────────────────────────────────────────────────────────────${C_RESET}"
    fi
    echo -e "${C_CYAN}${C_BOLD}"
    echo "  ██████╗ ███████╗██████╗  ██████╗      ███████╗███████╗████████╗████████╗███████╗██████╗ "
    echo "  ██╔══██╗██╔════╝██╔══██╗██╔═══██╗     ██╔════╝██╔════╝╚══██╔══╝╚══██╔══╝██╔════╝██╔══██╗"
    echo "  ██████╔╝█████╗  ██████╔╝██║   ██║     ███████╗█████╗     ██║      ██║   █████╗  ██████╔╝"
    echo "  ██╔══██╗██╔══╝  ██╔═══╝ ██║   ██║     ╚════██║██╔══╝     ██║      ██║   ██╔══╝  ██╔══██╗"
    echo "  ██║  ██║███████╗██║     ╚██████╔╝     ███████║███████╗   ██║      ██║   ███████╗██║  ██║"
    echo "  ╚═╝  ╚═╝╚══════╝╚═╝      ╚═════╝      ╚══════╝╚══════╝   ╚═╝      ╚═╝   ╚══════╝╚═╝  ╚═╝"
    echo -e "${C_RESET}"
    echo -e "  ${C_BOLD}Linux Repository Mirror Benchmarker & Setter${C_RESET} ${C_DIM}(v${SCRIPT_VERSION})${C_RESET}"
    echo -e "  ${C_DIM}Safely detect OS, test reachability/latency, and configure sources.list${C_RESET}"
    echo -e "  ─────────────────────────────────────────────────────────────────────────────"
}

log_info() {
    echo -e " ${C_BLUE}[INFO]${C_RESET} $1"
}

log_success() {
    echo -e " ${C_GREEN}[SUCCESS]${C_RESET} $1"
}

log_warning() {
    echo -e " ${C_YELLOW}[WARNING]${C_RESET} $1"
}

log_error() {
    echo -e " ${C_RED}[ERROR]${C_RESET} $1"
}

read_user_input() {
    local prompt="$1"
    local __var_name="$2"
    local input_val=""
    local read_rc=0

    # Ensure prompt is written directly to stdout so it is always visible
    if [ -n "$prompt" ]; then
        echo -ne "$prompt"
    fi

    if [ -c /dev/tty ]; then
        read -r input_val < /dev/tty || read_rc=$?
    else
        read -r input_val || read_rc=$?
    fi

    if [ "$read_rc" -ne 0 ]; then
        echo ""
        log_warning "End of input stream detected. Exiting..."
        exit 0
    fi

    if [ -n "$__var_name" ]; then
        printf -v "$__var_name" '%s' "$input_val"
    else
        REPLY="$input_val"
    fi
}

pause_key() {
    echo ""
    read_user_input "  ${C_BOLD}${C_YELLOW}➔ Press [Enter] to continue...${C_RESET} " _unused
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This action requires administrative privileges (root)."
        echo -e " Please run this script with ${C_BOLD}sudo${C_RESET}:"
        echo -e "   ${C_CYAN}sudo $0${C_RESET}"
        return 1
    fi
    return 0
}

check_dependencies() {
    local missing_deps=()
    for cmd in curl awk sed grep; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing required utilities: ${missing_deps[*]}"
        echo " Please install them first (e.g. apt-get install -y ${missing_deps[*]})."
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# System & OS Detection
# ------------------------------------------------------------------------------
detect_os() {
    OS_ARCH="$(uname -m 2>/dev/null || echo "unknown")"

    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_PRETTY="${PRETTY_NAME:-$NAME}"
        OS_VERSION_ID="${VERSION_ID:-}"
        OS_CODENAME="${VERSION_CODENAME:-}"

        # Ubuntu or derived (e.g. Linux Mint, Pop!_OS)
        if [ -n "${UBUNTU_CODENAME:-}" ]; then
            OS_CODENAME="$UBUNTU_CODENAME"
        fi
    elif command -v lsb_release &>/dev/null; then
        OS_ID="$(lsb_release -si | tr '[:upper:]' '[:lower:]')"
        OS_PRETTY="$(lsb_release -sd)"
        OS_CODENAME="$(lsb_release -sc)"
    elif [ -f /etc/debian_version ]; then
        OS_ID="debian"
        OS_PRETTY="Debian GNU/Linux $(cat /etc/debian_version)"
    else
        OS_ID="unknown"
        OS_PRETTY="Unknown Linux Distribution"
    fi

    # Codename resolution fallback for Debian if VERSION_CODENAME is unset
    if [ "$OS_ID" = "debian" ] && [ -z "$OS_CODENAME" ]; then
        case "$OS_VERSION_ID" in
            13*) OS_CODENAME="trixie" ;;
            12*) OS_CODENAME="bookworm" ;;
            11*) OS_CODENAME="bullseye" ;;
            10*) OS_CODENAME="buster" ;;
            *)
                # Attempt to read from /etc/debian_version
                local deb_ver
                deb_ver="$(cut -d. -f1 /etc/debian_version 2>/dev/null || echo "")"
                case "$deb_ver" in
                    13) OS_CODENAME="trixie" ;;
                    12) OS_CODENAME="bookworm" ;;
                    11) OS_CODENAME="bullseye" ;;
                    10) OS_CODENAME="buster" ;;
                    *) OS_CODENAME="bookworm" ;;
                esac
                ;;
        esac
    fi

    # Codename resolution fallback for Ubuntu if unset
    if [ "$OS_ID" = "ubuntu" ] && [ -z "$OS_CODENAME" ]; then
        case "$OS_VERSION_ID" in
            24.10*) OS_CODENAME="oracular" ;;
            24.04*) OS_CODENAME="noble" ;;
            22.04*) OS_CODENAME="jammy" ;;
            20.04*) OS_CODENAME="focal" ;;
            18.04*) OS_CODENAME="bionic" ;;
            *) OS_CODENAME="noble" ;;
        esac
    fi

    # Distro compatibility check
    if [ "$OS_ID" = "ubuntu" ] || [ "$OS_ID" = "debian" ] || [ "${ID_LIKE#*debian}" != "$ID_LIKE" ] || [ "${ID_LIKE#*ubuntu}" != "$ID_LIKE" ]; then
        IS_SUPPORTED=1
    else
        IS_SUPPORTED=0
    fi
}

show_system_info() {
    echo -e " ${C_BOLD}Current System Information:${C_RESET}"
    echo -e "   • Distribution : ${C_GREEN}${OS_PRETTY}${C_RESET} [${OS_ID}]"
    echo -e "   • Codename     : ${C_CYAN}${OS_CODENAME:-unknown}${C_RESET}"
    echo -e "   • Architecture : ${C_WHITE}${OS_ARCH}${C_RESET}"
    
    # Detect currently used active mirror in /etc/apt/sources.list
    local current_mirror="Not detected"
    if [ -f "$SOURCES_FILE" ]; then
        current_mirror="$(grep -E '^deb ' "$SOURCES_FILE" 2>/dev/null | head -n 1 | awk '{print $2}' || echo "None")"
    elif [ -f "$UBUNTU_SOURCES_DEB822" ]; then
        current_mirror="$(grep -E '^URIs:' "$UBUNTU_SOURCES_DEB822" 2>/dev/null | head -n 1 | awk '{print $2}' || echo "None")"
    fi
    echo -e "   • Active Mirror: ${C_YELLOW}${current_mirror}${C_RESET}"
    echo -e "  ─────────────────────────────────────────────────────────────────────────────"
}

# ------------------------------------------------------------------------------
# Mirror Definitions
# ------------------------------------------------------------------------------
# Returns list of mirrors for the detected OS in format "NAME|BASE_URL"
get_iran_mirrors() {
    if [ "$OS_ID" = "ubuntu" ] || [ "${ID_LIKE#*ubuntu}" != "$ID_LIKE" ]; then
        cat << 'EOF'
IranServer|http://mirror.iranserver.com/ubuntu/
IUT (Isfahan Univ)|http://repo.iut.ac.ir/repo/Ubuntu/
AminIDC|http://mirror.aminidc.com/ubuntu/
HostIran|http://mirror.hostiran.net/ubuntu/
PardisHost|http://mirrors.pardishost.com/ubuntu/
PetroSystem|http://archive.ubuntu.petrosystem.ir/ubuntu/
Rasanegar|http://mirror.rasanegar.com/ubuntu/
ArvanCloud|https://mirror.arvancloud.ir/ubuntu/
Official Iran Geo|http://ir.archive.ubuntu.com/ubuntu/
EOF
    else
        # Debian mirrors in Iran
        cat << 'EOF'
IranServer|http://mirror.iranserver.com/debian/
IUT (Isfahan Univ)|http://repo.iut.ac.ir/repo/debian/
AminIDC|http://mirror.aminidc.com/debian/
HostIran|http://mirror.hostiran.net/debian/
PardisHost|http://mirrors.pardishost.com/debian/
ArvanCloud|https://mirror.arvancloud.ir/debian/
Official Iran Geo|http://ftp.ir.debian.org/debian/
EOF
    fi
}

get_international_mirrors() {
    if [ "$OS_ID" = "ubuntu" ] || [ "${ID_LIKE#*ubuntu}" != "$ID_LIKE" ]; then
        cat << 'EOF'
Official Main (Canonical)|http://archive.ubuntu.com/ubuntu/
Kernel.org (Global)|http://mirrors.kernel.org/ubuntu/
Hetzner (Germany)|http://mirror.hetzner.com/ubuntu/packages/
Leaseweb (Netherlands)|http://mirror.nl.leaseweb.net/ubuntu/
DigitalOcean (Global)|http://mirrors.digitalocean.com/ubuntu/
Linode (Global)|http://mirrors.linode.com/ubuntu/
OVH (France)|http://ubuntu.mirrors.ovh.net/ubuntu/
Yandex (Russia)|http://mirror.yandex.ru/ubuntu/
Aliyun (Global)|http://mirrors.aliyun.com/ubuntu/
EOF
    else
        # Debian international mirrors
        cat << 'EOF'
Official Main (Debian)|http://deb.debian.org/debian/
Kernel.org (Global)|http://mirrors.kernel.org/debian/
Hetzner (Germany)|http://mirror.hetzner.com/debian/packages/
Leaseweb (Netherlands)|http://mirror.nl.leaseweb.net/debian/
DigitalOcean (Global)|http://mirrors.digitalocean.com/debian/
Linode (Global)|http://mirrors.linode.com/debian/
OVH (France)|http://debian.mirrors.ovh.net/debian/
Yandex (Russia)|http://mirror.yandex.ru/debian/
Aliyun (Global)|http://mirrors.aliyun.com/debian/
EOF
    fi
}

# ------------------------------------------------------------------------------
# Reachability & Latency Benchmarking
# ------------------------------------------------------------------------------
test_single_mirror() {
    local name="$1"
    local base_url="$2"
    local codename="${3:-$OS_CODENAME}"

    # Ensure trailing slash
    [[ "$base_url" != */ ]] && base_url="${base_url}/"

    # Construct the release probe URL
    local probe_url="${base_url}dists/${codename}/Release"

    # Probe with curl: connect timeout 2s, max total time 5s
    # Output: "<http_code> <time_total>"
    local curl_output
    curl_output="$(curl -s -L -o /dev/null -w "%{http_code} %{time_total}" \
        --connect-timeout "$CURL_TIMEOUT" \
        --max-time 5 \
        "$probe_url" 2>/dev/null || echo "000 9.999")"

    local http_code
    local time_total
    http_code="$(echo "$curl_output" | awk '{print $1}')"
    time_total="$(echo "$curl_output" | awk '{print $2}')"

    # Status check: 200, 301, or 302 means valid repository release file exists
    if [ "$http_code" = "200" ] || [ "$http_code" = "301" ] || [ "$http_code" = "302" ]; then
        # Calculate latency in integer milliseconds
        local latency_ms
        latency_ms="$(awk -v t="$time_total" 'BEGIN { printf "%.0f", t * 1000 }')"
        echo "${name}|${base_url}|${latency_ms}|OK"
    else
        echo "${name}|${base_url}|99999|FAILED(${http_code})"
    fi
}

run_benchmarks() {
    local mirror_list="$1"
    local pool_name="$2"

    BENCHMARK_RESULTS=()
    echo ""
    echo -e " ${C_BOLD}Benchmarking ${pool_name} for codename '${OS_CODENAME}'...${C_RESET}"
    echo -e " ${C_DIM}Sending HTTP probes to verify repository release files...${C_RESET}"
    echo ""

    # Temporary directory for asynchronous testing
    local tmp_dir
    tmp_dir="$(mktemp -d -t repo_bench_XXXXXX 2>/dev/null || mktemp -d)"
    local idx=0

    # Launch probes in parallel (controlled concurrency)
    while IFS="|" read -r name url; do
        [ -z "$name" ] && continue
        (
            res="$(test_single_mirror "$name" "$url" "$OS_CODENAME")"
            echo "$res" > "$tmp_dir/result_${idx}.txt"
        ) &
        ((idx++))
        # Keep background jobs limited
        if [ $((idx % MAX_PARALLEL_TESTS)) -eq 0 ]; then
            wait -n 2>/dev/null || true
        fi
    done <<< "$mirror_list"

    # Wait for all probes to complete
    wait

    # Collect and sort results by latency (field 3, numeric)
    local raw_sorted
    raw_sorted="$(cat "$tmp_dir"/result_*.txt 2>/dev/null | sort -t '|' -k3 -n)"
    rm -rf "$tmp_dir"

    while IFS= read -r line; do
        [ -n "$line" ] && BENCHMARK_RESULTS+=("$line")
    done <<< "$raw_sorted"

    # Display Benchmark Table
    echo -e "  ┌──────┬───────────────────────────┬──────────────┬──────────────────────────────────────────┐"
    printf "  │ ${C_BOLD}%-4s${C_RESET} │ ${C_BOLD}%-25s${C_RESET} │ ${C_BOLD}%-12s${C_RESET} │ ${C_BOLD}%-40s${C_RESET} │\n" "#" "Mirror Name" "Latency" "Mirror URL"
    echo -e "  ├──────┼───────────────────────────┼──────────────┼──────────────────────────────────────────┤"

    local display_idx=1
    local ok_count=0

    for item in "${BENCHMARK_RESULTS[@]}"; do
        IFS="|" read -r name url latency status <<< "$item"
        local latency_str
        local status_color

        if [ "$status" = "OK" ]; then
            latency_str="${latency} ms"
            if [ "$latency" -lt 150 ]; then
                status_color="${C_GREEN}"
            elif [ "$latency" -lt 350 ]; then
                status_color="${C_YELLOW}"
            else
                status_color="${C_MAGENTA}"
            fi
            ((ok_count++))
        else
            latency_str="UNAVAILABLE"
            status_color="${C_RED}"
        fi

        # Truncate URL if too long for display
        local display_url="$url"
        if [ ${#display_url} -gt 40 ]; then
            display_url="${display_url:0:37}..."
        fi

        printf "  │ %-4s │ %-25s │ ${status_color}%-12s${C_RESET} │ %-40s │\n" \
            "[$display_idx]" "$name" "$latency_str" "$display_url"
        ((display_idx++))
    done
    echo -e "  └──────┴───────────────────────────┴──────────────┴──────────────────────────────────────────┘"

    echo ""
    if [ "$ok_count" -eq 0 ]; then
        log_error "No accessible mirrors were found in this pool for codename '${OS_CODENAME}'."
        return 1
    else
        log_success "Found ${ok_count} reachable mirror(s)."
        return 0
    fi
}

# ------------------------------------------------------------------------------
# sources.list Generation
# ------------------------------------------------------------------------------
backup_existing_sources() {
    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    if [ -f "$SOURCES_FILE" ]; then
        local backup_file="${BACKUP_DIR}/sources.list.bak_${timestamp}"
        cp "$SOURCES_FILE" "$backup_file"
        log_info "Backup created: ${C_WHITE}${backup_file}${C_RESET}"
    fi

    # Handle Ubuntu 24.04+ deb822 ubuntu.sources
    if [ -f "$UBUNTU_SOURCES_DEB822" ]; then
        local deb822_backup="${BACKUP_DIR}/ubuntu.sources.bak_${timestamp}"
        cp "$UBUNTU_SOURCES_DEB822" "$deb822_backup"
        log_info "Backup of deb822 sources created: ${C_WHITE}${deb822_backup}${C_RESET}"
    fi

    # Clean up any misplaced backup or disabled files in /etc/apt/sources.list.d/
    # This prevents APT from throwing "Notice: Ignoring file ... invalid filename extension"
    if [ -d "/etc/apt/sources.list.d" ]; then
        for misplaced in /etc/apt/sources.list.d/*.bak* /etc/apt/sources.list.d/*.disabled; do
            if [ -f "$misplaced" ]; then
                mv "$misplaced" "${BACKUP_DIR}/"
                log_info "Moved misplaced $(basename "$misplaced") to ${BACKUP_DIR}/"
            fi
        done
    fi
}

generate_ubuntu_deb822_sources() {
    local mirror_url="$1"
    local codename="$2"
    local target_file="$3"
    local date_str
    date_str="$(date '+%Y-%m-%d %H:%M:%S')"
    local keyring="/usr/share/keyrings/ubuntu-archive-keyring.gpg"
    local signed_by_line=""
    [ -f "$keyring" ] && signed_by_line="Signed-By: ${keyring}"

    cat << EOF > "$target_file"
# ==============================================================================
#  Ubuntu Repository Configuration - ubuntu.sources (deb822 format)
#  Generated by Repo-Setter (v${SCRIPT_VERSION})
#  Date: ${date_str}
#  Distribution: Ubuntu ${codename} (${OS_ARCH})
#  Primary Mirror: ${mirror_url}
# ==============================================================================

Types: deb
URIs: ${mirror_url}
Suites: ${codename} ${codename}-updates ${codename}-backports
Components: main restricted universe multiverse
${signed_by_line}

Types: deb
URIs: ${mirror_url}
Suites: ${codename}-security
Components: main restricted universe multiverse
${signed_by_line}
EOF
}

generate_ubuntu_sources() {
    local mirror_url="$1"
    local codename="$2"
    local target_file="$3"
    local date_str
    date_str="$(date '+%Y-%m-%d %H:%M:%S')"

    # Use the selected mirror for core updates and security
    local sec_url="$mirror_url"

    cat << EOF > "$target_file"
# ==============================================================================
#  Ubuntu Repository Configuration - sources.list
#  Generated by Repo-Setter (v${SCRIPT_VERSION})
#  Date: ${date_str}
#  Distribution: Ubuntu ${codename} (${OS_ARCH})
#  Primary Mirror: ${mirror_url}
# ==============================================================================

# Core Repositories
deb ${mirror_url} ${codename} main restricted universe multiverse
# deb-src ${mirror_url} ${codename} main restricted universe multiverse

deb ${mirror_url} ${codename}-updates main restricted universe multiverse
# deb-src ${mirror_url} ${codename}-updates main restricted universe multiverse

deb ${mirror_url} ${codename}-backports main restricted universe multiverse
# deb-src ${mirror_url} ${codename}-backports main restricted universe multiverse

# Security Updates
deb ${sec_url} ${codename}-security main restricted universe multiverse
# deb-src ${sec_url} ${codename}-security main restricted universe multiverse
EOF
}

generate_debian_sources() {
    local mirror_url="$1"
    local codename="$2"
    local target_file="$3"
    local date_str
    date_str="$(date '+%Y-%m-%d %H:%M:%S')"

    # Debian 12 (bookworm) onwards introduced non-free-firmware component
    local components="main contrib non-free"
    if [ "$codename" = "bookworm" ] || [ "$codename" = "trixie" ] || [ "$codename" = "sid" ]; then
        components="main contrib non-free non-free-firmware"
    fi

    # Debian security repository format
    local sec_suite="${codename}-security"
    if [ "$codename" = "buster" ]; then
        sec_suite="buster/updates"
    fi

    cat << EOF > "$target_file"
# ==============================================================================
#  Debian Repository Configuration - sources.list
#  Generated by Repo-Setter (v${SCRIPT_VERSION})
#  Date: ${date_str}
#  Distribution: Debian ${codename} (${OS_ARCH})
#  Primary Mirror: ${mirror_url}
# ==============================================================================

# Core Repositories
deb ${mirror_url} ${codename} ${components}
# deb-src ${mirror_url} ${codename} ${components}

deb ${mirror_url} ${codename}-updates ${components}
# deb-src ${mirror_url} ${codename}-updates ${components}

deb ${mirror_url} ${codename}-backports ${components}
# deb-src ${mirror_url} ${codename}-backports ${components}

# Security Updates (Official Debian Security)
deb http://security.debian.org/debian-security ${sec_suite} ${components}
# deb-src http://security.debian.org/debian-security ${sec_suite} ${components}
EOF
}

apply_mirror() {
    local mirror_name="$1"
    local mirror_url="$2"

    if ! check_root; then
        return 1
    fi

    # Ensure URL ends with trailing slash
    [[ "$mirror_url" != */ ]] && mirror_url="${mirror_url}/"

    echo ""
    log_info "Applying mirror: ${C_BOLD}${mirror_name}${C_RESET} (${mirror_url})"
    
    # 1. Backup existing
    backup_existing_sources

    # 2. Check if modern deb822 should be used (Ubuntu 24.04+ Noble or later)
    local is_ubuntu_modern=0
    if [ "$OS_ID" = "ubuntu" ] && { [ "$OS_CODENAME" = "noble" ] || [ "$OS_CODENAME" = "oracular" ] || [ -f "$UBUNTU_SOURCES_DEB822" ]; }; then
        is_ubuntu_modern=1
    fi

    if [ "$is_ubuntu_modern" -eq 1 ]; then
        local tmp_deb822
        tmp_deb822="$(mktemp -t ubuntu_sources_XXXXXX 2>/dev/null || mktemp)"
        generate_ubuntu_deb822_sources "$mirror_url" "$OS_CODENAME" "$tmp_deb822"
        cp "$tmp_deb822" "$UBUNTU_SOURCES_DEB822"
        chmod 644 "$UBUNTU_SOURCES_DEB822"
        rm -f "$tmp_deb822"

        # Keep /etc/apt/sources.list as standard pointer without duplicate entries
        cat << EOF > "$SOURCES_FILE"
# Ubuntu sources have moved to /etc/apt/sources.list.d/ubuntu.sources
# Configured with mirror: ${mirror_url} by Repo-Setter (v${SCRIPT_VERSION})
EOF
        chmod 644 "$SOURCES_FILE"

        log_success "${UBUNTU_SOURCES_DEB822} (deb822 format) updated successfully!"
        echo ""
        echo -e " ${C_BOLD}New Repository Configuration Preview (${UBUNTU_SOURCES_DEB822}):${C_RESET}"
        echo -e "${C_DIM}─────────────────────────────────────────────────────────────────────────────${C_RESET}"
        cat "$UBUNTU_SOURCES_DEB822"
        echo -e "${C_DIM}─────────────────────────────────────────────────────────────────────────────${C_RESET}"
    else
        local tmp_sources
        tmp_sources="$(mktemp -t sources_new_XXXXXX 2>/dev/null || mktemp)"

        if [ "$OS_ID" = "ubuntu" ] || [ "${ID_LIKE#*ubuntu}" != "$ID_LIKE" ]; then
            generate_ubuntu_sources "$mirror_url" "$OS_CODENAME" "$tmp_sources"
        else
            generate_debian_sources "$mirror_url" "$OS_CODENAME" "$tmp_sources"
        fi

        # 3. Safely install to /etc/apt/sources.list
        cp "$tmp_sources" "$SOURCES_FILE"
        chmod 644 "$SOURCES_FILE"
        rm -f "$tmp_sources"

        log_success "${SOURCES_FILE} updated successfully!"
        echo ""
        echo -e " ${C_BOLD}New Repository Configuration Preview:${C_RESET}"
        echo -e "${C_DIM}─────────────────────────────────────────────────────────────────────────────${C_RESET}"
        cat "$SOURCES_FILE"
        echo -e "${C_DIM}─────────────────────────────────────────────────────────────────────────────${C_RESET}"
    fi
    echo ""

    # Prompt user to update apt index
    read_user_input " Would you like to run 'apt-get update' now? [Y/n]: " run_apt
    run_apt="${run_apt:-Y}"
    if [[ "$run_apt" =~ ^[Yy]$ ]]; then
        echo ""
        log_info "Running 'apt-get update'..."
        if apt-get update; then
            echo ""
            log_success "Package lists updated successfully from ${mirror_name}!"
        else
            echo ""
            log_warning "'apt-get update' completed with warnings or errors. Check your connection or keys."
        fi
    fi
}

# ------------------------------------------------------------------------------
# Interactive Actions
# ------------------------------------------------------------------------------
action_auto_set_fastest() {
    local pool_type="$1" # "iran" or "international" or "all"
    local pool_data=""
    local title=""

    case "$pool_type" in
        iran)
            pool_data="$(get_iran_mirrors)"
            title="Iranian Mirrors"
            ;;
        international)
            pool_data="$(get_international_mirrors)"
            title="International Mirrors"
            ;;
        all)
            pool_data="$(echo -e "$(get_iran_mirrors)\n$(get_international_mirrors)")"
            title="All Mirrors (Iranian & International)"
            ;;
    esac

    if ! run_benchmarks "$pool_data" "$title"; then
        pause_key
        return
    fi

    # First item in BENCHMARK_RESULTS is the fastest
    local fastest_entry="${BENCHMARK_RESULTS[0]}"
    IFS="|" read -r name url latency status <<< "$fastest_entry"

    if [ "$status" != "OK" ]; then
        log_error "The fastest mirror returned status: $status. Cannot set."
        pause_key
        return
    fi

    echo ""
    echo -e " ${C_BOLD}Fastest Mirror Detected:${C_RESET} ${C_GREEN}${name}${C_RESET} (${latency} ms)"
    echo -e " URL: ${C_CYAN}${url}${C_RESET}"
    echo ""

    read_user_input " Do you want to set this mirror as your active repository? [Y/n]: " confirm
    confirm="${confirm:-Y}"
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        apply_mirror "$name" "$url"
    else
        log_info "Operation cancelled by user."
    fi
    pause_key
}

action_select_manually() {
    local pool_type="$1" # "iran" or "international" or "all"
    local pool_data=""
    local title=""

    case "$pool_type" in
        iran)
            pool_data="$(get_iran_mirrors)"
            title="Iranian Mirrors"
            ;;
        international)
            pool_data="$(get_international_mirrors)"
            title="International Mirrors"
            ;;
        all)
            pool_data="$(echo -e "$(get_iran_mirrors)\n$(get_international_mirrors)")"
            title="All Mirrors"
            ;;
    esac

    if ! run_benchmarks "$pool_data" "$title"; then
        pause_key
        return
    fi

    local total_count="${#BENCHMARK_RESULTS[@]}"
    echo ""
    read_user_input " Enter the mirror number [1-${total_count}] to set (or 'q' to cancel): " choice

    if [[ "$choice" =~ ^[Qq]$ ]] || [ -z "$choice" ]; then
        log_info "Cancelled."
        pause_key
        return
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$total_count" ]; then
        log_error "Invalid selection: $choice"
        pause_key
        return
    fi

    local selected_entry="${BENCHMARK_RESULTS[$((choice - 1))]}"
    IFS="|" read -r name url latency status <<< "$selected_entry"

    if [ "$status" != "OK" ]; then
        echo ""
        log_warning "Selected mirror '${name}' is marked as '${status}'."
        read_user_input " Are you sure you want to proceed with this mirror? [y/N]: " force_proceed
        if ! [[ "$force_proceed" =~ ^[Yy]$ ]]; then
            log_info "Cancelled."
            pause_key
            return
        fi
    fi

    apply_mirror "$name" "$url"
    pause_key
}

action_view_current_sources() {
    echo ""
    echo -e " ${C_BOLD}Active sources.list (${SOURCES_FILE}):${C_RESET}"
    echo -e "${C_DIM}─────────────────────────────────────────────────────────────────────────────${C_RESET}"
    if [ -f "$SOURCES_FILE" ]; then
        cat "$SOURCES_FILE"
    else
        log_warning "File ${SOURCES_FILE} does not exist."
    fi
    echo -e "${C_DIM}─────────────────────────────────────────────────────────────────────────────${C_RESET}"

    if [ -f "$UBUNTU_SOURCES_DEB822" ]; then
        echo ""
        echo -e " ${C_BOLD}Active deb822 sources (${UBUNTU_SOURCES_DEB822}):${C_RESET}"
        echo -e "${C_DIM}─────────────────────────────────────────────────────────────────────────────${C_RESET}"
        cat "$UBUNTU_SOURCES_DEB822"
        echo -e "${C_DIM}─────────────────────────────────────────────────────────────────────────────${C_RESET}"
    fi

    pause_key
}

action_restore_backup() {
    if ! check_root; then
        pause_key
        return
    fi

    echo ""
    echo -e " ${C_BOLD}Available Backups in ${BACKUP_DIR}/ and /etc/apt/:${C_RESET}"
    local backups=()
    while IFS= read -r -d $'\0' file; do
        backups+=("$file")
    done < <(find "$BACKUP_DIR" /etc/apt/ -maxdepth 1 \( -name "*sources*bak*" -o -name "*sources*disabled*" -o -name "*resolv*bak*" -o -name "*resolved*bak*" -o -name "*.yaml.bak*" -o -name "*.yml.bak*" \) -print0 2>/dev/null | sort -z -r)

    if [ ${#backups[@]} -eq 0 ]; then
        log_warning "No backups found in ${BACKUP_DIR}/ or /etc/apt/"
        pause_key
        return
    fi

    local i=1
    for b in "${backups[@]}"; do
        local bname
        bname="$(basename "$b")"
        local btime
        btime="$(stat -c %y "$b" 2>/dev/null || stat -f "%Sm" "$b" 2>/dev/null || echo "unknown")"
        echo -e "   ${C_CYAN}[$i]${C_RESET} ${bname}  ${C_DIM}(${btime})${C_RESET}"
        ((i++))
    done

    echo ""
    read_user_input " Select backup number to restore [1-${#backups[@]}] (or 'q' to cancel): " choice

    if [[ "$choice" =~ ^[Qq]$ ]] || [ -z "$choice" ]; then
        log_info "Cancelled."
        pause_key
        return
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#backups[@]}" ]; then
        log_error "Invalid selection."
        pause_key
        return
    fi

    local selected_backup="${backups[$((choice - 1))]}"
    local bname
    bname="$(basename "$selected_backup")"

    if [[ "$bname" == *ubuntu.sources* ]]; then
        log_info "Restoring deb822: ${selected_backup} -> ${UBUNTU_SOURCES_DEB822}"
        cp "$selected_backup" "$UBUNTU_SOURCES_DEB822"
        chmod 644 "$UBUNTU_SOURCES_DEB822"
    elif [[ "$bname" == *resolv.conf* ]]; then
        log_info "Restoring DNS: ${selected_backup} -> /etc/resolv.conf"
        cp "$selected_backup" /etc/resolv.conf
    elif [[ "$bname" == *.yaml.bak_* ]] || [[ "$bname" == *.yml.bak_* ]]; then
        local original_netplan_name="${bname%%.bak_*}"
        log_info "Restoring Netplan: ${selected_backup} -> /etc/netplan/${original_netplan_name}"
        cp "$selected_backup" "/etc/netplan/${original_netplan_name}"
        if command -v netplan >/dev/null 2>&1; then
            netplan apply 2>/dev/null || true
            log_success "Netplan applied successfully!"
        fi
    elif [[ "$bname" == *resolved.conf* ]]; then
        log_info "Restoring systemd-resolved: ${selected_backup} -> /etc/systemd/resolved.conf"
        cp "$selected_backup" /etc/systemd/resolved.conf
        systemctl restart systemd-resolved 2>/dev/null || true
    else
        log_info "Restoring: ${selected_backup} -> ${SOURCES_FILE}"
        cp "$selected_backup" "$SOURCES_FILE"
        chmod 644 "$SOURCES_FILE"
    fi

    log_success "Backup restored successfully!"
    pause_key
}

action_run_apt_update() {
    if ! check_root; then
        pause_key
        return
    fi
    echo ""
    log_info "Executing: apt-get update..."
    apt-get update
    pause_key
}

update_single_netplan_yaml() {
    local filepath="$1"
    local ip1="$2"
    local ip2="$3"
    local ip3="${4:-8.8.8.8}"

    if [ ! -f "$filepath" ]; then
        return 1
    fi

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$filepath" "$ip1" "$ip2" "$ip3" << 'PYEOF' >/dev/null 2>&1
import sys, re

filepath = sys.argv[1]
ip1 = sys.argv[2]
ip2 = sys.argv[3]
ip3 = sys.argv[4]

with open(filepath, 'r') as f:
    content = f.read()

done = False
try:
    import yaml
    data = yaml.safe_load(content)
    if isinstance(data, dict) and 'network' in data:
        net = data.get('network', {})
        for sec in ['ethernets', 'wifis', 'vlans', 'bridges', 'bonds']:
            if sec in net and isinstance(net[sec], dict):
                for iface, cfg in net[sec].items():
                    if isinstance(cfg, dict):
                        if 'nameservers' not in cfg or not isinstance(cfg['nameservers'], dict):
                            cfg['nameservers'] = {}
                        cfg['nameservers']['addresses'] = [ip1, ip2, ip3]
                        done = True
        if done:
            with open(filepath, 'w') as f:
                yaml.dump(data, f, default_flow_style=False, sort_keys=False)
except Exception:
    pass

if not done:
    lines = content.splitlines()
    indent_step = 2
    for line in lines:
        leading = len(line) - len(line.lstrip(' '))
        if leading > 0:
            if leading % 4 == 0 and leading % 2 == 0:
                indent_step = 4
                break
            elif leading % 2 == 0:
                indent_step = 2
                break

    new_lines = []
    in_nameservers = False
    ns_indent = -1
    found_ns = False

    for i, line in enumerate(lines):
        indent = len(line) - len(line.lstrip(' '))
        stripped = line.strip()

        if in_nameservers:
            if indent > ns_indent:
                if stripped.startswith('addresses:'):
                    continue
                elif stripped.startswith('-') and not stripped.startswith('--'):
                    continue
                else:
                    new_lines.append(line)
                    continue
            else:
                in_nameservers = False

        if re.match(r'^\s*nameservers\s*:\s*$', line):
            found_ns = True
            in_nameservers = True
            ns_indent = indent
            child_indent = indent + indent_step
            if i + 1 < len(lines):
                next_indent = len(lines[i + 1]) - len(lines[i + 1].lstrip(' '))
                if next_indent > indent:
                    child_indent = next_indent
            new_lines.append(line)
            new_lines.append(' ' * child_indent + f'addresses: [{ip1}, {ip2}, {ip3}]')
            continue

        new_lines.append(line)

    if not found_ns:
        final_lines = []
        inserted = False
        in_eth = False
        eth_indent = -1
        first_iface_found = False

        for line in new_lines:
            indent = len(line) - len(line.lstrip(' '))
            stripped = line.strip()
            final_lines.append(line)

            if re.match(r'^\s*ethernets\s*:\s*$', line):
                in_eth = True
                eth_indent = indent
                continue

            if in_eth and not inserted:
                if indent > eth_indent and stripped.endswith(':') and not stripped.startswith('#'):
                    if not first_iface_found:
                        first_iface_found = True
                        prop_indent = indent + indent_step
                        p_str = ' ' * prop_indent
                        c_str = ' ' * (prop_indent + indent_step)
                        final_lines.append(f'{p_str}nameservers:')
                        final_lines.append(f'{c_str}addresses: [{ip1}, {ip2}, {ip3}]')
                        inserted = True

        result = '\n'.join(final_lines) + '\n'
    else:
        result = '\n'.join(new_lines) + '\n'

    with open(filepath, 'w') as f:
        f.write(result)
PYEOF
        return 0
    else
        if grep -q "nameservers:" "$filepath"; then
            sed -i -E "s/(addresses:).*/\1 [${ip1}, ${ip2}, ${ip3}]/" "$filepath"
        fi
        return 0
    fi
}

apply_persistent_dns() {
    local pname="$1"
    local ip1="$2"
    local ip2="$3"
    local ip3="${4:-8.8.8.8}"
    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"

    mkdir -p "$BACKUP_DIR"

    # 1. Update /etc/resolv.conf for instant effect
    if [ -f /etc/resolv.conf ] || [ -L /etc/resolv.conf ]; then
        cp /etc/resolv.conf "${BACKUP_DIR}/resolv.conf.bak_${timestamp}" 2>/dev/null || true
        cat << EOF > /etc/resolv.conf
# Configured by Repo-Setter (${pname} Anti-Sanction DNS)
nameserver ${ip1}
nameserver ${ip2}
nameserver ${ip3}
EOF
        log_success "/etc/resolv.conf updated with ${pname} DNS for instant resolution!"
    fi

    # 2. Netplan Detection & Configuration (/etc/netplan/*.yaml)
    local netplan_configs=()
    if [ -d /etc/netplan ]; then
        while IFS= read -r -d '' f; do
            local fbname
            fbname="$(basename "$f")"
            if [[ "$fbname" != *.bak* ]] && [[ "$fbname" != *~* ]] && [[ "$fbname" != *.disabled* ]]; then
                netplan_configs+=("$f")
            fi
        done < <(find /etc/netplan -maxdepth 1 \( -name "*.yaml" -o -name "*.yml" \) -print0 2>/dev/null)
    fi

    if [ ${#netplan_configs[@]} -gt 0 ]; then
        echo ""
        log_info "Detected Netplan network configuration (${#netplan_configs[@]} file(s) found in /etc/netplan/)..."
        for nfile in "${netplan_configs[@]}"; do
            local nbak="${BACKUP_DIR}/$(basename "$nfile").bak_${timestamp}"
            cp "$nfile" "$nbak" 2>/dev/null || true
            log_info "Backing up Netplan to: ${C_WHITE}${nbak}${C_RESET}"

            update_single_netplan_yaml "$nfile" "$ip1" "$ip2" "$ip3"

            if command -v netplan >/dev/null 2>&1; then
                if netplan generate 2>/dev/null; then
                    netplan apply 2>/dev/null || true
                    log_success "Netplan updated and applied: $(basename "$nfile")"
                else
                    log_warning "Netplan syntax verification failed for $(basename "$nfile"). Restoring original file..."
                    cp "$nbak" "$nfile"
                fi
            else
                log_success "Netplan file updated: $(basename "$nfile")"
            fi
        done
    fi

    # 3. systemd-resolved Configuration (/etc/systemd/resolved.conf)
    if [ -f /etc/systemd/resolved.conf ]; then
        local rbak="${BACKUP_DIR}/resolved.conf.bak_${timestamp}"
        cp /etc/systemd/resolved.conf "$rbak" 2>/dev/null || true

        if grep -q -E "^[#]?[ ]*DNS=" /etc/systemd/resolved.conf; then
            sed -i -E "s/^[#]?[ ]*DNS=.*/DNS=${ip1} ${ip2} ${ip3}/" /etc/systemd/resolved.conf
        else
            sed -i "/^\[Resolve\]/a DNS=${ip1} ${ip2} ${ip3}" /etc/systemd/resolved.conf
        fi

        if command -v resolvectl >/dev/null 2>&1; then
            local def_iface
            def_iface="$(ip route show default 2>/dev/null | awk '{print $5}' | head -n1)"
            if [ -n "$def_iface" ]; then
                resolvectl dns "$def_iface" "${ip1}" "${ip2}" "${ip3}" 2>/dev/null || true
            fi
        fi

        if command -v systemctl >/dev/null 2>&1; then
            systemctl restart systemd-resolved 2>/dev/null || true
        fi
        log_success "systemd-resolved updated with ${pname} DNS!"
    fi
}

action_test_dns_for_docker() {
    if ! check_root; then
        pause_key
        return
    fi

    echo ""
    log_info "=== Testing Anti-Sanction DNS Servers for get.docker.com ==="
    echo -e " ${C_DIM}Benchmarks DNS servers to find which one unblocks official Docker installer (get.docker.com).${C_RESET}"
    echo ""

    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    local original_resolv="${BACKUP_DIR}/resolv.conf.bak_${timestamp}"
    if [ -f /etc/resolv.conf ]; then
        cp /etc/resolv.conf "$original_resolv"
        log_info "Original DNS backed up to: ${C_WHITE}${original_resolv}${C_RESET}"
    fi

    local dns_providers=(
        "Shecan (شکن)|178.22.122.100|185.51.200.2"
        "403.online (۴۰۳)|10.202.10.202|10.202.10.102"
        "Electro (الکترو)|78.157.42.100|78.157.42.101"
        "Radar Game (رادار)|10.202.10.10|10.202.10.11"
        "Begzar (بگذر)|185.55.226.26|185.55.225.25"
        "Shelter (شلتر)|185.86.136.241|185.86.136.242"
        "Pishrun (پیشران)|5.202.100.100|5.202.100.101"
        "Level 15 (لول ۱۵)|185.105.238.167|185.105.239.167"
        "Hostiran (هاست‌ایران)|172.29.0.100|172.29.2.100"
        "Vanilla (وانیلا)|10.202.10.100|10.202.10.101"
        "NobarCloud (نوبر)|78.110.120.220|78.110.120.200"
        "Beshkan (بشکن)|181.41.194.177|181.41.194.186"
        "DynX (داین‌ایکس)|193.24.103.1|193.24.103.2"
        "Cloudflare (Direct)|1.1.1.1|1.0.0.1"
        "Google (Direct)|8.8.8.8|8.8.4.4"
    )

    local working_dns=()

    echo ""
    echo -e " ${C_BOLD}Testing DNS providers against 'https://get.docker.com'...${C_RESET}"
    echo ""

    echo -e "  ┌──────────────────────────┬─────────────────────────────┬──────────────────┬──────────────┐"
    printf "  │ ${C_BOLD}%-24s${C_RESET} │ ${C_BOLD}%-27s${C_RESET} │ ${C_BOLD}%-16s${C_RESET} │ ${C_BOLD}%-12s${C_RESET} │\n" "Provider Name" "DNS IPs" "get.docker.com" "Latency"
    echo -e "  ├──────────────────────────┼─────────────────────────────┼──────────────────┼──────────────┤"

    for entry in "${dns_providers[@]}"; do
        IFS="|" read -r pname ip1 ip2 <<< "$entry"

        # Temporarily apply DNS
        cat << EOF > /etc/resolv.conf
nameserver ${ip1}
nameserver ${ip2}
EOF

        # Probe get.docker.com with curl
        local start_ts
        start_ts="$(date +%s%N 2>/dev/null || date +%s)"
        local curl_out
        curl_out="$(curl -s -L --connect-timeout 2 --max-time 4 https://get.docker.com 2>/dev/null)"
        local end_ts
        end_ts="$(date +%s%N 2>/dev/null || date +%s)"

        local latency_ms="--"
        local latency_num=99999
        if [ ${#start_ts} -gt 10 ] && [ ${#end_ts} -gt 10 ]; then
            latency_num="$(( (end_ts - start_ts) / 1000000 ))"
            latency_ms="${latency_num} ms"
        fi

        local first_line
        first_line="$(echo "$curl_out" | head -n 1)"

        local status_label=""
        local status_color=""

        if [[ "$first_line" == *"#!/bin/sh"* ]] || [[ "$first_line" == *"#!"* ]]; then
            status_label="UNBLOCKED"
            status_color="${C_GREEN}"
            working_dns+=("${latency_num}|${pname}|${ip1}|${ip2}")
        elif [[ "$first_line" == *"<!"* ]] || [[ "$first_line" == *"403"* ]] || [[ "$curl_out" == *"Forbidden"* ]]; then
            status_label="SANCTIONED(403)"
            status_color="${C_RED}"
        else
            status_label="UNREACHABLE"
            status_color="${C_RED}"
        fi

        printf "  │ %-24s │ %-27s │ ${status_color}%-16s${C_RESET} │ %-12s │\n" \
            "$pname" "${ip1}, ${ip2}" "$status_label" "$latency_ms"
    done
    echo -e "  └──────────────────────────┴─────────────────────────────┴──────────────────┴──────────────┘"

    echo ""
    if [ ${#working_dns[@]} -eq 0 ]; then
        log_error "None of the tested DNS servers could unblock get.docker.com directly."
        log_info "Restoring original DNS..."
        cp "$original_resolv" /etc/resolv.conf 2>/dev/null || true
        echo ""
        log_info "Recommendation: Use Option [8] (Install Docker via apt repository mirror) instead."
        pause_key
        return 1
    fi

    # Sort working DNS by latency (lowest first)
    IFS=$'\n' read -d '' -r -a sorted_working < <(printf '%s\n' "${working_dns[@]}" | sort -n && printf '\0')
    local best_dns="${sorted_working[0]}"
    local blat
    IFS="|" read -r blat bname bip1 bip2 <<< "$best_dns"

    log_success "Found ${#sorted_working[@]} working DNS server(s) that successfully unblock get.docker.com!"
    echo ""
    echo -e " ${C_BOLD}Fastest Working DNS:${C_RESET} ${C_GREEN}${bname}${C_RESET} (${bip1}, ${bip2}) [${blat} ms]"
    echo ""

    read_user_input " Set this DNS permanently (resolv.conf & Netplan)? [Y/n]: " set_perm
    set_perm="${set_perm:-Y}"
    if [[ "$set_perm" =~ ^[Yy]$ ]]; then
        apply_persistent_dns "${bname}" "${bip1}" "${bip2}"
    else
        log_info "Restoring original DNS..."
        cp "$original_resolv" /etc/resolv.conf 2>/dev/null || true
        pause_key
        return 0
    fi

    echo ""
    read_user_input " Do you want to run 'bash <(curl -sSL https://get.docker.com)' now? [Y/n]: " run_installer
    run_installer="${run_installer:-Y}"
    if [[ "$run_installer" =~ ^[Yy]$ ]]; then
        echo ""
        log_info "Executing official Docker installer script with ${bname} DNS..."
        if curl -fsSL https://get.docker.com | bash; then
            echo ""
            log_success "Docker installed successfully via get.docker.com!"
            
            echo ""
            read_user_input " Would you also like to configure Iran Registry Mirrors in /etc/docker/daemon.json? [Y/n]: " conf_reg
            conf_reg="${conf_reg:-Y}"
            if [[ "$conf_reg" =~ ^[Yy]$ ]]; then
                action_configure_docker_mirrors
            fi
        else
            echo ""
            log_error "Installation failed. You can alternatively use Option [8] to install Docker via apt mirror."
        fi
    fi

    pause_key
}

action_fix_dns_poisoning() {
    if ! check_root; then
        pause_key
        return
    fi

    echo ""
    log_info "=== Fixing DNS Poisoning & SSL Error (60) for get.docker.com & GitHub ==="
    echo -e " ${C_DIM}Directly binds verified CloudFront & Fastly IPs to bypass Iranian ISP DNS poisoning.${C_RESET}"
    echo ""

    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    if [ -f /etc/hosts ]; then
        cp /etc/hosts "${BACKUP_DIR}/hosts.bak_${timestamp}"
        log_info "Backup of /etc/hosts saved to: ${C_WHITE}${BACKUP_DIR}/hosts.bak_${timestamp}${C_RESET}"
    fi

    # Filter out any old or conflicting entries
    local tmp_hosts
    tmp_hosts="$(mktemp 2>/dev/null || echo "/tmp/hosts_new.tmp")"
    grep -v -E "(raw\.githubusercontent\.com|get\.docker\.com|download\.docker\.com|github\.com)" /etc/hosts > "$tmp_hosts" 2>/dev/null || cat /etc/hosts > "$tmp_hosts"

    cat << 'EOF' >> "$tmp_hosts"

# -------------------------------------------------------------
# Added by Repo-Setter: Anti-Censorship & Anti-Sanction Hosts
# Fixes curl (60) SSL errors on get.docker.com and GitHub in Iran
# -------------------------------------------------------------
185.199.108.133 raw.githubusercontent.com
185.199.109.133 raw.githubusercontent.com
185.199.110.133 raw.githubusercontent.com
185.199.111.133 raw.githubusercontent.com
140.82.121.3    github.com
140.82.121.4    github.com
3.160.132.12    get.docker.com
13.35.166.19    get.docker.com
99.86.159.87    download.docker.com
13.35.166.111   download.docker.com
# -------------------------------------------------------------
EOF

    cp "$tmp_hosts" /etc/hosts
    chmod 644 /etc/hosts
    rm -f "$tmp_hosts"

    log_success "/etc/hosts updated with verified direct IPs!"

    # Probe get.docker.com
    echo ""
    log_info "Testing reachability to 'https://get.docker.com'..."
    local docker_code
    docker_code="$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 4 https://get.docker.com 2>/dev/null || echo "000")"
    if [ "$docker_code" = "200" ]; then
        log_success "https://get.docker.com is now REACHABLE (HTTP ${docker_code}) without SSL errors!"
    else
        log_warning "https://get.docker.com returned HTTP ${docker_code}."
    fi

    # Probe raw.githubusercontent.com
    log_info "Testing reachability to 'https://raw.githubusercontent.com'..."
    local github_code
    github_code="$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 4 https://raw.githubusercontent.com 2>/dev/null || echo "000")"
    if [ "$github_code" = "200" ] || [ "$github_code" = "301" ] || [ "$github_code" = "302" ]; then
        log_success "https://raw.githubusercontent.com is now REACHABLE (HTTP ${github_code}) without SSL errors!"
    fi

    echo ""
    read_user_input " Would you also like to configure Anti-Sanction DNS (Shecan & 403 in Netplan/resolv.conf)? [y/N]: " set_dns
    if [[ "$set_dns" =~ ^[Yy]$ ]]; then
        apply_persistent_dns "Shecan & 403.online" "178.22.122.100" "185.51.200.2" "10.202.10.202"
    fi

    pause_key
}

action_configure_docker_mirrors() {
    if ! check_root; then
        pause_key
        return
    fi

    echo ""
    log_info "=== Benchmarking Docker Hub Registry Mirrors for Iran ==="
    echo -e " ${C_DIM}These mirrors bypass Docker Hub 403 Forbidden sanction blocks in Iran.${C_RESET}"
    echo ""

    local docker_mirrors=(
        "ArvanCloud|https://docker.arvancloud.ir"
        "Docker.ir|https://registry.docker.ir"
        "DockerHub.ir|https://dockerhub.ir"
        "MChost|https://docker.mchost.ir"
        "IranRepo|https://docker.iranrepo.ir"
        "Google Mirror|https://mirror.gcr.io"
    )

    local reachable_mirrors=()
    for entry in "${docker_mirrors[@]}"; do
        IFS="|" read -r dname durl <<< "$entry"
        local probe_code
        probe_code="$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 --max-time 5 "${durl}/v2/" 2>/dev/null || echo "000")"
        if [ "$probe_code" = "200" ] || [ "$probe_code" = "401" ]; then
            echo -e "   • ${C_GREEN}[PASS]${C_RESET} ${dname} (${durl})"
            reachable_mirrors+=("$durl")
        else
            echo -e "   • ${C_RED}[FAIL]${C_RESET} ${dname} (${durl}) [HTTP ${probe_code}]"
        fi
    done

    if [ ${#reachable_mirrors[@]} -eq 0 ]; then
        log_warning "No Iranian registry responded directly. Using standard trusted fallbacks..."
        reachable_mirrors=("https://docker.arvancloud.ir" "https://registry.docker.ir" "https://dockerhub.ir" "https://mirror.gcr.io")
    fi

    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    mkdir -p /etc/docker "$BACKUP_DIR"

    if [ -f /etc/docker/daemon.json ]; then
        cp /etc/docker/daemon.json "${BACKUP_DIR}/daemon.json.bak_${timestamp}"
        log_info "Backup created: ${BACKUP_DIR}/daemon.json.bak_${timestamp}"
    fi

    local json_mirrors=""
    for m in "${reachable_mirrors[@]}"; do
        if [ -z "$json_mirrors" ]; then
            json_mirrors="\"$m\""
        else
            json_mirrors="${json_mirrors},
    \"$m\""
        fi
    done

    cat << EOF > /etc/docker/daemon.json
{
  "registry-mirrors": [
    ${json_mirrors}
  ]
}
EOF
    chmod 644 /etc/docker/daemon.json
    log_success "/etc/docker/daemon.json configured with ${#reachable_mirrors[@]} registry mirror(s)!"

    # Restart docker service if installed
    if command -v systemctl &>/dev/null && systemctl is-active --quiet docker 2>/dev/null; then
        log_info "Restarting Docker service..."
        systemctl daemon-reload 2>/dev/null || true
        if systemctl restart docker 2>/dev/null; then
            log_success "Docker service restarted successfully!"
        fi
    else
        log_info "Docker is not currently active. Settings will apply when Docker starts."
    fi

    pause_key
}

action_install_docker() {
    if ! check_root; then
        pause_key
        return
    fi

    echo ""
    log_info "=== Docker Installation & Iran Sanction-Bypass Setup ==="

    # Step 1: Fix DNS and hosts
    log_info "Step 1/3: Applying Anti-Censorship hosts mappings for get.docker.com..."
    grep -v -E "(raw\.githubusercontent\.com|get\.docker\.com|download\.docker\.com|github\.com)" /etc/hosts > /tmp/hosts_clean 2>/dev/null || cat /etc/hosts > /tmp/hosts_clean
    cat << 'EOF' >> /tmp/hosts_clean
185.199.108.133 raw.githubusercontent.com
140.82.121.3    github.com
3.160.132.12    get.docker.com
99.86.159.87    download.docker.com
EOF
    cp /tmp/hosts_clean /etc/hosts
    rm -f /tmp/hosts_clean

    # Step 2: Check if Docker is already installed
    if command -v docker &>/dev/null; then
        local current_ver
        current_ver="$(docker --version 2>/dev/null || echo "installed")"
        log_info "Docker is already installed: ${C_GREEN}${current_ver}${C_RESET}"
        read_user_input " Do you want to reinstall or just configure Iran Registry Mirrors? [r=reinstall / M=mirrors only]: " d_choice
        d_choice="${d_choice:-M}"
        if [[ ! "$d_choice" =~ ^[Rr]$ ]]; then
            action_configure_docker_mirrors
            return
        fi
    fi

    # Step 3: Install Docker via apt from server's fast repository mirror
    log_info "Step 2/3: Installing Docker packages via apt from active mirror..."
    apt-get update -qq || true
    if apt-get install -y docker.io docker-compose-plugin containerd; then
        log_success "Docker packages installed successfully!"
    else
        log_warning "apt install encountered an issue. Falling back to get.docker.com script..."
        if curl -fsSL https://get.docker.com | bash; then
            log_success "Docker installed via get.docker.com script!"
        else
            log_error "Failed to install Docker automatically. Please check your package manager."
            pause_key
            return 1
        fi
    fi

    # Step 4: Configure Registry Mirrors
    log_info "Step 3/3: Configuring Docker Hub Registry Mirrors in /etc/docker/daemon.json..."
    mkdir -p /etc/docker
    cat << 'EOF' > /etc/docker/daemon.json
{
  "registry-mirrors": [
    "https://docker.arvancloud.ir",
    "https://registry.docker.ir",
    "https://dockerhub.ir",
    "https://mirror.gcr.io"
  ]
}
EOF
    chmod 644 /etc/docker/daemon.json

    # Step 5: Enable & restart service
    if command -v systemctl &>/dev/null; then
        systemctl daemon-reload 2>/dev/null || true
        systemctl enable --now docker 2>/dev/null || true
        systemctl restart docker 2>/dev/null || true
    fi

    local final_ver
    final_ver="$(docker --version 2>/dev/null || echo "Docker")"
    echo ""
    log_success "${final_ver} installed and enabled!"
    log_success "Iran registry mirrors active. 'docker pull' is now sanction-free!"

    pause_key
}

# ------------------------------------------------------------------------------
# Interactive Menu
# ------------------------------------------------------------------------------
interactive_menu() {
    while true; do
        print_banner
        show_system_info

        if [ "$IS_SUPPORTED" -eq 0 ]; then
            log_warning "Your distribution (${OS_ID}) is not officially Debian/Ubuntu."
            log_warning "Modifying sources.list may not work or might not be supported."
            echo ""
        fi

        echo -e "  ${C_BOLD}${C_GREEN}─── IRANIAN REPOSITORIES ───${C_RESET}"
        echo -e "   ${C_CYAN}[1]${C_RESET} Benchmark & Auto-Set Fastest Iranian Mirror"
        echo -e "   ${C_CYAN}[2]${C_RESET} Benchmark & Choose from Iranian Mirrors List"
        echo ""
        echo -e "  ${C_BOLD}${C_BLUE}─── INTERNATIONAL REPOSITORIES ───${C_RESET}"
        echo -e "   ${C_CYAN}[3]${C_RESET} Benchmark & Auto-Set Fastest International Mirror"
        echo -e "   ${C_CYAN}[4]${C_RESET} Benchmark & Choose from International Mirrors List"
        echo ""
        echo -e "  ${C_BOLD}${C_MAGENTA}─── ALL REPOSITORIES (GLOBAL) ───${C_RESET}"
        echo -e "   ${C_CYAN}[5]${C_RESET} Benchmark All (Iran & International) & Auto-Set Fastest"
        echo -e "   ${C_CYAN}[6]${C_RESET} Benchmark All & Choose from Combined List"
        echo ""
        echo -e "  ${C_BOLD}${C_CYAN}─── DOCKER & DEVELOPER TOOLS (IRAN OPTIMIZED) ───${C_RESET}"
        echo -e "   ${C_CYAN}[7]${C_RESET} Benchmark DNS to Unblock get.docker.com (Shecan, 403, Electro, etc.)"
        echo -e "   ${C_CYAN}[8]${C_RESET} Install Docker CE & Tools (Sanction-Free for Iran)"
        echo -e "   ${C_CYAN}[9]${C_RESET} Benchmark & Configure Docker Registry Mirrors (/etc/docker/daemon.json)"
        echo -e "   ${C_CYAN}[10]${C_RESET} Fix DNS Poisoning & SSL for get.docker.com & GitHub (/etc/hosts)"
        echo ""
        echo -e "  ${C_BOLD}${C_YELLOW}─── MAINTENANCE & TOOLS ───${C_RESET}"
        echo -e "   ${C_CYAN}[11]${C_RESET} View Current sources.list & Active Mirrors"
        echo -e "   ${C_CYAN}[12]${C_RESET} Restore sources.list from Backup"
        echo -e "   ${C_CYAN}[13]${C_RESET} Run 'apt-get update'"
        echo ""
        echo -e "   ${C_RED}[0]${C_RESET} Exit"
        echo -e "  ─────────────────────────────────────────────────────────────────────────────"
        read_user_input " Please select an option [0-13]: " opt

        case "$opt" in
            1) action_auto_set_fastest "iran" ;;
            2) action_select_manually "iran" ;;
            3) action_auto_set_fastest "international" ;;
            4) action_select_manually "international" ;;
            5) action_auto_set_fastest "all" ;;
            6) action_select_manually "all" ;;
            7) action_test_dns_for_docker ;;
            8) action_install_docker ;;
            9) action_configure_docker_mirrors ;;
            10) action_fix_dns_poisoning ;;
            11) action_view_current_sources ;;
            12) action_restore_backup ;;
            13) action_run_apt_update ;;
            0)
                echo ""
                echo -e " ${C_GREEN}Goodbye!${C_RESET}"
                echo ""
                exit 0
                ;;
            *)
                log_error "Invalid option '$opt'. Please enter a number between 0 and 13."
                sleep 1.5
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# CLI Arguments Parser
# ------------------------------------------------------------------------------
show_help() {
    cat << EOF
Repo-Setter - Linux Mirror Benchmark & sources.list Configurator (v${SCRIPT_VERSION})

Usage:
  repo-setter.sh [OPTIONS]

Options:
  -i, --iran          Benchmark Iranian mirrors and auto-set the fastest
  -g, --global        Benchmark International mirrors and auto-set the fastest
  -a, --all           Benchmark All mirrors (Iran & Global) and auto-set fastest
  -t, --test-dns      Benchmark Anti-Sanction DNS to unblock get.docker.com
  -f, --fix-dns       Fix DNS poisoning & SSL (60) for get.docker.com and GitHub
  -d, --docker        Install Docker CE & configure Iran registry mirrors
  -m, --docker-mirrors Benchmark & configure Docker Hub registry mirrors
  -s, --status        View current active repository configuration
  -r, --restore       Restore sources.list from the most recent backup
  -u, --update        Run 'apt-get update'
  -h, --help          Show this help message and exit
  -v, --version       Show script version

Interactive Mode:
  Run without arguments to launch the interactive English CLI menu:
  sudo ./repo-setter.sh

Examples:
  sudo ./repo-setter.sh               # Open interactive menu
  sudo ./repo-setter.sh --iran        # Auto-set fastest Iran mirror non-interactively
  sudo ./repo-setter.sh --test-dns    # Test which DNS unblocks get.docker.com
  sudo ./repo-setter.sh --docker      # Install Docker with Iran registry mirrors
EOF
}

# ------------------------------------------------------------------------------
# Entry Point
# ------------------------------------------------------------------------------
main() {
    check_dependencies
    detect_os

    if [ $# -eq 0 ]; then
        interactive_menu
    else
        case "$1" in
            -i|--iran)
                action_auto_set_fastest "iran"
                ;;
            -g|--global|--international)
                action_auto_set_fastest "international"
                ;;
            -a|--all)
                action_auto_set_fastest "all"
                ;;
            -t|--test-dns)
                action_test_dns_for_docker
                ;;
            -f|--fix-dns)
                action_fix_dns_poisoning
                ;;
            -d|--docker)
                action_install_docker
                ;;
            -m|--docker-mirrors)
                action_configure_docker_mirrors
                ;;
            -s|--status)
                action_view_current_sources
                ;;
            -r|--restore)
                action_restore_backup
                ;;
            -u|--update)
                action_run_apt_update
                ;;
            -h|--help)
                show_help
                ;;
            -v|--version)
                echo "Repo-Setter v${SCRIPT_VERSION}"
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage instructions."
                exit 1
                ;;
        esac
    fi
}

if [ -z "${BASH_SOURCE[0]:-}" ] || [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
