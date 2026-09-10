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
print_banner() {
    clear 2>/dev/null || true
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

    if [ -c /dev/tty ]; then
        read -r -p "$prompt" input_val < /dev/tty 2>/dev/null || read -r -p "$prompt" input_val
    else
        read -r -p "$prompt" input_val
    fi

    if [ -n "$__var_name" ]; then
        printf -v "$__var_name" '%s' "$input_val"
    else
        REPLY="$input_val"
    fi
}

pause_key() {
    echo ""
    read_user_input " Press [Enter] to continue..." _unused
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

    if [ -f "$SOURCES_FILE" ]; then
        local backup_file="${SOURCES_FILE}.bak_${timestamp}"
        cp "$SOURCES_FILE" "$backup_file"
        log_info "Backup created: ${C_WHITE}${backup_file}${C_RESET}"
    fi

    # Handle Ubuntu 24.04+ deb822 ubuntu.sources
    if [ -f "$UBUNTU_SOURCES_DEB822" ]; then
        local deb822_backup="${UBUNTU_SOURCES_DEB822}.bak_${timestamp}"
        cp "$UBUNTU_SOURCES_DEB822" "$deb822_backup"
        log_info "Backup of deb822 sources created: ${C_WHITE}${deb822_backup}${C_RESET}"

        # Disable ubuntu.sources to avoid duplicate package repository warnings
        mv "$UBUNTU_SOURCES_DEB822" "${UBUNTU_SOURCES_DEB822}.disabled"
        log_info "Disabled conflicting ${C_YELLOW}${UBUNTU_SOURCES_DEB822}${C_RESET} (renamed to .disabled)."
    fi
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

    # 2. Write new sources.list to temporary file first
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
    echo -e " ${C_BOLD}Available Backups in /etc/apt/:${C_RESET}"
    local backups=()
    while IFS= read -r -d $'\0' file; do
        backups+=("$file")
    done < <(find /etc/apt/ -maxdepth 1 -name "sources.list.bak_*" -print0 2>/dev/null | sort -z -r)

    if [ ${#backups[@]} -eq 0 ]; then
        log_warning "No backups found matching /etc/apt/sources.list.bak_*"
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
    log_info "Restoring: ${selected_backup} -> ${SOURCES_FILE}"

    cp "$selected_backup" "$SOURCES_FILE"
    chmod 644 "$SOURCES_FILE"

    # Also restore disabled deb822 if available
    local disabled_deb822="${UBUNTU_SOURCES_DEB822}.disabled"
    if [ -f "$disabled_deb822" ]; then
        read_user_input " A disabled deb822 file (${disabled_deb822}) was found. Re-enable it? [y/N]: " ren_deb822
        if [[ "$ren_deb822" =~ ^[Yy]$ ]]; then
            mv "$disabled_deb822" "$UBUNTU_SOURCES_DEB822"
            log_success "Re-enabled ${UBUNTU_SOURCES_DEB822}"
        fi
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
        echo -e "  ${C_BOLD}${C_YELLOW}─── MAINTENANCE & TOOLS ───${C_RESET}"
        echo -e "   ${C_CYAN}[7]${C_RESET} View Current sources.list & Active Mirrors"
        echo -e "   ${C_CYAN}[8]${C_RESET} Restore sources.list from Backup"
        echo -e "   ${C_CYAN}[9]${C_RESET} Run 'apt-get update'"
        echo ""
        echo -e "   ${C_RED}[0]${C_RESET} Exit"
        echo -e "  ─────────────────────────────────────────────────────────────────────────────"
        read_user_input " Please select an option [0-9]: " opt

        case "$opt" in
            1) action_auto_set_fastest "iran" ;;
            2) action_select_manually "iran" ;;
            3) action_auto_set_fastest "international" ;;
            4) action_select_manually "international" ;;
            5) action_auto_set_fastest "all" ;;
            6) action_select_manually "all" ;;
            7) action_view_current_sources ;;
            8) action_restore_backup ;;
            9) action_run_apt_update ;;
            0)
                echo ""
                echo -e " ${C_GREEN}Goodbye!${C_RESET}"
                echo ""
                exit 0
                ;;
            *)
                log_error "Invalid option '$opt'. Please enter a number between 0 and 9."
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
  sudo ./repo-setter.sh --global      # Auto-set fastest international mirror
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

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
