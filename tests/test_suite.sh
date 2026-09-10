#!/usr/bin/env bash
# ==============================================================================
#  Test Suite for Repo-Setter
# ==============================================================================

C_GREEN="\033[32m"
C_RED="\033[31m"
C_BLUE="\033[34m"
C_RESET="\033[0m"

PASS_COUNT=0
FAIL_COUNT=0

# Source the main script without running main
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/repo-setter.sh"

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"

    if grep -qF -e "$needle" <<< "$haystack"; then
        echo -e " ${C_GREEN}[PASS]${C_RESET} ${test_name}"
        ((PASS_COUNT++))
    else
        echo -e " ${C_RED}[FAIL]${C_RESET} ${test_name}"
        echo "   Expected to contain: '$needle'"
        ((FAIL_COUNT++))
    fi
}

assert_equals() {
    local actual="$1"
    local expected="$2"
    local test_name="$3"

    if [ "$actual" = "$expected" ]; then
        echo -e " ${C_GREEN}[PASS]${C_RESET} ${test_name}"
        ((PASS_COUNT++))
    else
        echo -e " ${C_RED}[FAIL]${C_RESET} ${test_name}"
        echo "   Expected: '$expected', Got: '$actual'"
        ((FAIL_COUNT++))
    fi
}

# ------------------------------------------------------------------------------
# Test 1: CLI Flags
# ------------------------------------------------------------------------------
test_cli_flags() {
    echo -e "\n${C_BLUE}--- Testing CLI Flags ---${C_RESET}"
    local help_out
    help_out="$(bash "${SCRIPT_DIR}/repo-setter.sh" --help)"
    assert_contains "$help_out" "Usage:" "Help output contains Usage"
    assert_contains "$help_out" "--iran" "Help output mentions --iran"
    assert_contains "$help_out" "--global" "Help output mentions --global"
    assert_contains "$help_out" "--test-dns" "Help output mentions --test-dns"
    assert_contains "$help_out" "(v${SCRIPT_VERSION})" "Help output contains correct script version v${SCRIPT_VERSION}"

    local ver_out
    ver_out="$(bash "${SCRIPT_DIR}/repo-setter.sh" --version)"
    assert_contains "$ver_out" "Repo-Setter v${SCRIPT_VERSION}" "Version output matches 'Repo-Setter v${SCRIPT_VERSION}'"
}

# ------------------------------------------------------------------------------
# Test 2: Ubuntu sources.list generation
# ------------------------------------------------------------------------------
test_ubuntu_sources_gen() {
    echo -e "\n${C_BLUE}--- Testing Ubuntu sources.list Generation ---${C_RESET}"
    local tmp_target
    tmp_target="$(mktemp 2>/dev/null || echo "tmp_ubuntu_test.txt")"
    OS_ARCH="x86_64"

    generate_ubuntu_sources "http://mirror.iranserver.com/ubuntu/" "jammy" "$tmp_target"
    local content
    content="$(cat "$tmp_target")"
    rm -f "$tmp_target"

    assert_contains "$content" "deb http://mirror.iranserver.com/ubuntu/ jammy main restricted universe multiverse" "Ubuntu jammy main repo"
    assert_contains "$content" "deb http://mirror.iranserver.com/ubuntu/ jammy-updates main restricted universe multiverse" "Ubuntu jammy-updates repo"
    assert_contains "$content" "deb http://mirror.iranserver.com/ubuntu/ jammy-backports main restricted universe multiverse" "Ubuntu jammy-backports repo"
    assert_contains "$content" "deb http://mirror.iranserver.com/ubuntu/ jammy-security main restricted universe multiverse" "Ubuntu jammy-security repo"
}

# ------------------------------------------------------------------------------
# Test 2.5: Ubuntu 24.04 deb822 generation
# ------------------------------------------------------------------------------
test_ubuntu_deb822_gen() {
    echo -e "\n${C_BLUE}--- Testing Ubuntu deb822 Generation ---${C_RESET}"
    local tmp_target
    tmp_target="$(mktemp 2>/dev/null || echo "tmp_deb822_test.txt")"
    OS_ARCH="x86_64"

    generate_ubuntu_deb822_sources "http://mirror.iranserver.com/ubuntu/" "noble" "$tmp_target"
    local content
    content="$(cat "$tmp_target")"
    rm -f "$tmp_target"

    assert_contains "$content" "Types: deb" "deb822 Types: deb"
    assert_contains "$content" "URIs: http://mirror.iranserver.com/ubuntu/" "deb822 URIs"
    assert_contains "$content" "Suites: noble noble-updates noble-backports" "deb822 core suites"
    assert_contains "$content" "Suites: noble-security" "deb822 security suite"
    assert_contains "$content" "Components: main restricted universe multiverse" "deb822 components"
}

# ------------------------------------------------------------------------------
# Test 3: Debian sources.list generation (Bookworm vs Bullseye vs Buster)
# ------------------------------------------------------------------------------
test_debian_sources_gen() {
    echo -e "\n${C_BLUE}--- Testing Debian sources.list Generation ---${C_RESET}"
    local tmp_target
    tmp_target="$(mktemp 2>/dev/null || echo "tmp_debian_test.txt")"
    OS_ARCH="x86_64"

    # Debian 12 Bookworm (must include non-free-firmware)
    generate_debian_sources "http://mirror.iranserver.com/debian/" "bookworm" "$tmp_target"
    local content_bookworm
    content_bookworm="$(cat "$tmp_target")"

    assert_contains "$content_bookworm" "deb http://mirror.iranserver.com/debian/ bookworm main contrib non-free non-free-firmware" "Debian 12 includes non-free-firmware"
    assert_contains "$content_bookworm" "http://security.debian.org/debian-security bookworm-security" "Debian 12 security format"

    # Debian 11 Bullseye (standard main contrib non-free)
    generate_debian_sources "http://deb.debian.org/debian/" "bullseye" "$tmp_target"
    local content_bullseye
    content_bullseye="$(cat "$tmp_target")"

    assert_contains "$content_bullseye" "deb http://deb.debian.org/debian/ bullseye main contrib non-free" "Debian 11 components"
    assert_contains "$content_bullseye" "http://security.debian.org/debian-security bullseye-security" "Debian 11 security format"

    # Debian 10 Buster (buster/updates)
    generate_debian_sources "http://deb.debian.org/debian/" "buster" "$tmp_target"
    local content_buster
    content_buster="$(cat "$tmp_target")"
    assert_contains "$content_buster" "http://security.debian.org/debian-security buster/updates" "Debian 10 security format"

    rm -f "$tmp_target"
}

# ------------------------------------------------------------------------------
# Test 4: Live Probe reachability
# ------------------------------------------------------------------------------
test_live_probe() {
    echo -e "\n${C_BLUE}--- Testing Live Mirror Probe Function ---${C_RESET}"
    CURL_TIMEOUT=4

    # Test Canonical Official Mirror
    local probe_res
    probe_res="$(test_single_mirror "Canonical Main" "http://archive.ubuntu.com/ubuntu/" "jammy")"
    echo "  Probe Canonical Main: $probe_res"
    assert_contains "$probe_res" "OK" "Canonical archive.ubuntu.com Reachable"

    # Test an invalid/bogus mirror URL (must report FAILED)
    local dead_res
    dead_res="$(test_single_mirror "Fake Mirror" "http://invalid-mirror-does-not-exist-xyz123.com/ubuntu/" "jammy")"
    echo "  Probe Dead Mirror: $dead_res"
    assert_contains "$dead_res" "FAILED" "Non-existent mirror correctly detected as FAILED"
}

# ------------------------------------------------------------------------------
# Test 5: Mirror lists for Ubuntu and Debian
# ------------------------------------------------------------------------------
test_mirror_lists() {
    echo -e "\n${C_BLUE}--- Testing Mirror Lists Structure ---${C_RESET}"
    OS_ID="ubuntu"
    local iran_ub
    iran_ub="$(get_iran_mirrors)"
    assert_contains "$iran_ub" "mirror.iranserver.com/ubuntu" "Ubuntu Iran mirrors include IranServer"
    assert_contains "$iran_ub" "repo.iut.ac.ir/repo/Ubuntu" "Ubuntu Iran mirrors include IUT"

    OS_ID="debian"
    local iran_deb
    iran_deb="$(get_iran_mirrors)"
    assert_contains "$iran_deb" "mirror.iranserver.com/debian" "Debian Iran mirrors include IranServer"
    assert_contains "$iran_deb" "repo.iut.ac.ir/repo/debian" "Debian Iran mirrors include IUT"
}

# ------------------------------------------------------------------------------
# Test 7: Netplan DNS Configuration
# ------------------------------------------------------------------------------
test_netplan_dns_configuration() {
    echo -e "\n${C_BLUE}--- Testing Netplan DNS Configuration ---${C_RESET}"
    local tmp_yaml
    tmp_yaml="$(mktemp 2>/dev/null || echo "/tmp/test_netplan_$$.yaml")"

    # Case 1: Netplan without nameservers
    cat << 'EOF' > "$tmp_yaml"
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
EOF
    update_single_netplan_yaml "$tmp_yaml" "178.22.122.100" "185.51.200.2" "8.8.8.8"
    local c1_out
    c1_out="$(cat "$tmp_yaml")"
    assert_contains "$c1_out" "nameservers:" "Netplan adds nameservers block when missing"
    assert_contains "$c1_out" "178.22.122.100" "Netplan sets primary DNS"
    assert_contains "$c1_out" "185.51.200.2" "Netplan sets secondary DNS"

    # Case 2: Netplan with existing nameservers
    cat << 'EOF' > "$tmp_yaml"
network:
  version: 2
  ethernets:
    ens3:
      dhcp4: true
      nameservers:
        addresses: [1.1.1.1, 8.8.4.4]
EOF
    update_single_netplan_yaml "$tmp_yaml" "10.202.10.202" "10.202.10.102" "8.8.8.8"
    local c2_out
    c2_out="$(cat "$tmp_yaml")"
    assert_contains "$c2_out" "10.202.10.202" "Netplan updates existing nameserver addresses (403.online primary)"
    assert_contains "$c2_out" "10.202.10.102" "Netplan updates existing nameserver addresses (403.online secondary)"

    rm -f "$tmp_yaml"
}

# ------------------------------------------------------------------------------
# Run all tests
# ------------------------------------------------------------------------------
main() {
    test_cli_flags
    test_ubuntu_sources_gen
    test_ubuntu_deb822_gen
    test_debian_sources_gen
    test_live_probe
    test_mirror_lists
    test_netplan_dns_configuration

    echo ""
    echo "========================================"
    echo " Test Summary: $PASS_COUNT passed, $FAIL_COUNT failed"
    echo "========================================"

    if [ "$FAIL_COUNT" -gt 0 ]; then
        exit 1
    fi
}

main "$@"
