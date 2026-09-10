# Repo-Setter 🚀

A high-performance, interactive Linux Bash utility that benchmarks **Iranian** and **International** package repository mirrors, tests their availability and latency, and automatically configures `/etc/apt/sources.list` with the optimal mirror for your distribution.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/Bash-5.0+-4EAA25.svg?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Linux](https://img.shields.io/badge/Platform-Debian%20%7C%20Ubuntu-E95420.svg?logo=linux&logoColor=white)](https://kernel.org)

---

## ✨ Features

- **🔍 Automatic OS Detection**:
  - Automatically identifies Linux distribution (`Ubuntu`, `Debian`, etc.), release codename (e.g., `noble`, `jammy`, `focal`, `bookworm`, `bullseye`), and architecture (`x86_64`, `aarch64`, etc.).
  - Distro-tailored repository templates.
- **⚡ Reachability & Latency Benchmarking**:
  - Sends direct HTTP probes to the repository's `Release` file.
  - Measures real-world network latency in milliseconds.
  - Automatically flags and filters dead or inaccessible mirrors (`FAILED` / `UNAVAILABLE`).
- **🇮🇷 Separated Iranian & International Repositories**:
  - **Iranian Mirrors Pool**: IranServer, IUT, AminIDC, HostIran, PardisHost, PetroSystem, ArvanCloud, Rasanegar, and Official Iran Geo.
  - **International Mirrors Pool**: Official Canonical/Debian, Kernel.org, Hetzner, Leaseweb, DigitalOcean, Linode, OVH, Yandex, and Aliyun.
  - Dedicated menu options to auto-select the fastest mirror or choose interactively from a benchmarked table.
- **📝 Full `sources.list` Generation**:
  - Populates complete repository components: `main`, `restricted`, `universe`, `multiverse` (for Ubuntu) and `main`, `contrib`, `non-free`, `non-free-firmware` (for Debian 12+).
  - Configures standard updates, backports, and security suites.
- **🛡️ Safe Backup & Restore**:
  - Creates a timestamped backup before touching `/etc/apt/sources.list` (e.g., `/etc/apt/sources.list.bak_20260910_120000`).
  - Seamlessly handles **Ubuntu 24.04 (Noble)** `deb822` format (`/etc/apt/sources.list.d/ubuntu.sources`) by safely disabling conflicting files to avoid duplicate repository warnings.
  - Built-in one-click restore menu.
- **🖥️ Clean English CLI UI**:
  - Color-coded latency indicators (Green < 150ms, Yellow < 350ms, Magenta > 350ms, Red for unreachable).
  - Works both **interactively** and **non-interactively** via CLI flags for scripts and CI/CD pipelines.

---

## 🚀 Quick Start (One-Liner Execution)

You can run `repo-setter` immediately on any Linux server with a single command without git cloning:

### 🌟 1. Interactive Menu (Recommended)
Run the full interactive menu directly with a single command:

#### Direct from GitHub:
```bash
curl -sSL https://raw.githubusercontent.com/samaelleo/repo-setter/main/repo-setter.sh | sudo bash
```

#### 🇮🇷 High-Speed CDN (Bypasses `raw.githubusercontent.com` SSL/DNS restrictions in Iran):
```bash
curl -sSL https://cdn.jsdelivr.net/gh/samaelleo/repo-setter@main/repo-setter.sh | sudo bash
```

Or download and execute in one line:
```bash
curl -sSL https://cdn.jsdelivr.net/gh/samaelleo/repo-setter@main/repo-setter.sh -o repo-setter.sh && sudo bash repo-setter.sh
```

Or using `wget`:
```bash
wget -qO- https://cdn.jsdelivr.net/gh/samaelleo/repo-setter@main/repo-setter.sh | sudo bash
```

### ⚡ 2. Automated Non-Interactive One-Liners
Benchmark and automatically set the fastest mirror directly with a one-liner:

- **Auto-Set Fastest Iranian Mirror**:
  ```bash
  curl -sSL https://raw.githubusercontent.com/samaelleo/repo-setter/main/repo-setter.sh | sudo bash -s -- --iran
  ```

- **Auto-Set Fastest International Mirror**:
  ```bash
  curl -sSL https://raw.githubusercontent.com/samaelleo/repo-setter/main/repo-setter.sh | sudo bash -s -- --global
  ```

- **Auto-Set Fastest Overall (Iran & Global)**:
  ```bash
  curl -sSL https://raw.githubusercontent.com/samaelleo/repo-setter/main/repo-setter.sh | sudo bash -s -- --all
  ```

- **Inspect Current Active Repositories**:
  ```bash
  curl -sSL https://raw.githubusercontent.com/samaelleo/repo-setter/main/repo-setter.sh | bash -s -- --status
  ```

---

## 📥 Manual Installation & Usage

1. **Clone or download the repository**:
   ```bash
   git clone https://github.com/samaelleo/repo-setter.git
   cd repo-setter
   ```

2. **Make the script executable**:
   ```bash
   chmod +x repo-setter.sh
   ```

3. **Launch the interactive menu**:
   ```bash
   sudo ./repo-setter.sh
   ```

---

## 📋 Interactive Menu Overview

When executed without flags, `repo-setter` greets you with an intuitive terminal UI:

```text
  ██████╗ ███████╗██████╗  ██████╗      ███████╗███████╗████████╗████████╗███████╗██████╗ 
  ██╔══██╗██╔════╝██╔══██╗██╔═══██╗     ██╔════╝██╔════╝╚══██╔══╝╚══██╔══╝██╔════╝██╔══██╗
  ██████╔╝█████╗  ██████╔╝██║   ██║     ███████╗█████╗     ██║      ██║   █████╗  ██████╔╝
  ██╔══██╗██╔══╝  ██╔═══╝ ██║   ██║     ╚════██║██╔══╝     ██║      ██║   ██╔══╝  ██╔══██╗
  ██║  ██║███████╗██║     ╚██████╔╝     ███████║███████╗   ██║      ██║   ███████╗██║  ██║
  ╚═╝  ╚═╝╚══════╝╚═╝      ╚═════╝      ╚══════╝╚══════╝   ╚═╝      ╚═╝   ╚══════╝╚═╝  ╚═╝

  Linux Repository Mirror Benchmarker & Setter (v1.0.0)
  Safely detect OS, test reachability/latency, and configure sources.list
  ─────────────────────────────────────────────────────────────────────────────
 Current System Information:
   • Distribution : Ubuntu 24.04.3 LTS [ubuntu]
   • Codename     : noble
   • Architecture : x86_64
   • Active Mirror: http://archive.ubuntu.com/ubuntu/
  ─────────────────────────────────────────────────────────────────────────────
  ─── IRANIAN REPOSITORIES ───
   [1] Benchmark & Auto-Set Fastest Iranian Mirror
   [2] Benchmark & Choose from Iranian Mirrors List

  ─── INTERNATIONAL REPOSITORIES ───
   [3] Benchmark & Auto-Set Fastest International Mirror
   [4] Benchmark & Choose from International Mirrors List

  ─── ALL REPOSITORIES (GLOBAL) ───
   [5] Benchmark All (Iran & International) & Auto-Set Fastest
   [6] Benchmark All & Choose from Combined List

  ─── DOCKER & DEVELOPER TOOLS (IRAN OPTIMIZED) ───
   [7] Benchmark DNS to Unblock get.docker.com (Shecan, 403, Electro, etc.)
   [8] Install Docker CE & Tools (Sanction-Free for Iran)
   [9] Benchmark & Configure Docker Registry Mirrors (/etc/docker/daemon.json)
   [10] Fix DNS Poisoning & SSL for get.docker.com & GitHub (/etc/hosts)

  ─── MAINTENANCE & TOOLS ───
   [11] View Current sources.list & Active Mirrors
   [12] Restore sources.list from Backup
   [13] Run 'apt-get update'

   [0] Exit
  ─────────────────────────────────────────────────────────────────────────────
 Please select an option [0-13]:
```

---

## ⚡ Non-Interactive (CLI Flags)

`repo-setter` can be automated in shell scripts or provisioning tools (such as Ansible, Cloud-init, Docker, or bash automation):

| Flag | Description |
|---|---|
| `-i`, `--iran` | Benchmark Iranian mirrors and auto-set the fastest |
| `-g`, `--global` | Benchmark International mirrors and auto-set the fastest |
| `-a`, `--all` | Benchmark All mirrors (Iran & Global) and auto-set the fastest |
| `-t`, `--test-dns` | Benchmark Anti-Sanction DNS providers to unblock `get.docker.com` |
| `-f`, `--fix-dns` | Fix DNS poisoning & SSL (60) for get.docker.com & GitHub (/etc/hosts) |
| `-d`, `--docker` | Install Docker CE & configure Iran registry mirrors |
| `-m`, `--docker-mirrors` | Benchmark & configure Docker Hub registry mirrors |
| `-s`, `--status` | View currently active repository configuration |
| `-r`, `--restore` | Interactively select and restore a previous backup |
| `-u`, `--update` | Execute `apt-get update` |
| `-h`, `--help` | Show command-line help and usage |
| `-v`, `--version` | Display version number |

### Examples:

```bash
# Benchmark and auto-set the fastest Iranian mirror
sudo ./repo-setter.sh --iran

# Test which Anti-Sanction DNS unblocks get.docker.com and install Docker
sudo ./repo-setter.sh --test-dns

# Fix SSL error 60 for get.docker.com and GitHub
sudo ./repo-setter.sh --fix-dns

# Install Docker with Iran registry mirrors in one step
sudo ./repo-setter.sh --docker
```

---

## 🌐 Included Repository Mirrors

### 🇮🇷 Iranian Mirrors
- **IranServer** (`mirror.iranserver.com`)
- **Isfahan University of Technology - IUT** (`repo.iut.ac.ir`)
- **AminIDC** (`mirror.aminidc.com`)
- **HostIran** (`mirror.hostiran.net`)
- **PardisHost** (`mirrors.pardishost.com`)
- **PetroSystem** (`archive.ubuntu.petrosystem.ir`)
- **Rasanegar** (`mirror.rasanegar.com`)
- **ArvanCloud** (`mirror.arvancloud.ir`)
- **Official Iran Geo Mirror** (`ir.archive.ubuntu.com` / `ftp.ir.debian.org`)

### 🌍 International Mirrors
- **Official Main** (`archive.ubuntu.com` / `deb.debian.org`)
- **Kernel.org** (`mirrors.kernel.org`)
- **Hetzner Germany** (`mirror.hetzner.com`)
- **Leaseweb Netherlands** (`mirror.nl.leaseweb.net`)
- **DigitalOcean Global** (`mirrors.digitalocean.com`)
- **Linode Global** (`mirrors.linode.com`)
- **OVH France** (`ubuntu.mirrors.ovh.net` / `debian.mirrors.ovh.net`)
- **Yandex Russia** (`mirror.yandex.ru`)
- **Aliyun Global** (`mirrors.aliyun.com`)

---

## 🛡️ Supported Anti-Sanction DNS Providers

Option `[7]` (or `--test-dns`) tests each provider live against `https://get.docker.com` to benchmark latency and verify unblocking:

| Provider | Primary IP | Secondary IP | Purpose / Target |
| :--- | :--- | :--- | :--- |
| **Shecan (شکن)** | `178.22.122.100` | `185.51.200.2` | General & Dev Anti-Sanction |
| **403.online (سامانه ۴۰۳)** | `10.202.10.202` | `10.202.10.102` | Developers, Docker, Cloud & AI |
| **Electro (الکترو)** | `78.157.42.100` | `78.157.42.101` | Gaming & Developer Tools |
| **Radar Game (رادار)** | `10.202.10.10` | `10.202.10.11` | Low Latency & Anti-Sanction |
| **Begzar (بگذر)** | `185.55.226.26` | `185.55.225.25` | Open Anti-Sanction Proxy |
| **Shelter (شلتر)** | `185.86.136.241` | `185.86.136.242` | Developer & Server Anti-Sanction |
| **Pishrun (پیشران)** | `5.202.100.100` | `5.202.100.101` | AI & Dev Anti-Sanction |
| **Level 15 (لول ۱۵)** | `185.105.238.167` | `185.105.239.167` | Gaming & Developer Bypass |
| **Hostiran (هاست‌ایران)** | `172.29.0.100` | `172.29.2.100` | Data Center & Dev Tools |
| **Vanilla DNS (وانیلا)** | `10.202.10.100` | `10.202.10.101` | Anti-Sanction Bypass |
| **NobarCloud (نوبر)** | `78.110.120.220` | `78.110.120.200` | Cloud & Infra Anti-Sanction |
| **Beshkan (بشکن)** | `181.41.194.177` | `181.41.194.186` | Developer Anti-Sanction |
| **DynX (داین‌ایکس)** | `193.24.103.1` | `193.24.103.2` | Anti-Sanction Resolver |
| **Cloudflare** | `1.1.1.1` | `1.0.0.1` | Global Baseline |
| **Google** | `8.8.8.8` | `8.8.4.4` | Global Baseline |

---

## 🐧 Supported Linux Distributions

| Distribution | Supported Versions / Codenames |
|---|---|
| **Ubuntu** | 24.10 (Oracular), 24.04 (Noble), 22.04 (Jammy), 20.04 (Focal), 18.04 (Bionic) |
| **Debian** | 13 (Trixie), 12 (Bookworm), 11 (Bullseye), 10 (Buster) |
| **Derivatives** | Linux Mint, Pop!_OS, Raspberry Pi OS, and other Debian/Ubuntu based OS |

---

## 🧪 Testing

Run the included test suite to verify functionality:

```bash
bash tests/test_suite.sh
```

---

## 📄 License

Released under the [MIT License](LICENSE).
