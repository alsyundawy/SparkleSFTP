<!-- markdownlint-disable-file MD013 MD022 MD026 MD032 MD033 MD041 MD060 -->

<p align="center">
  <a href="https://github.com/alsyundawy/SparkleSFTP">
    <img src="assets/sparklesftp-desktop-banner.jpg" width="100%" alt="SparkleSFTP Desktop Suite — Native macOS Dual-Pane SFTP, FTP/FTPS, SCP &amp; SSH Commander" />
  </a>
</p>

<p align="center">
  <a href="https://github.com/alsyundawy/SparkleSFTP">
    <img src="src/App/Resources/AppIcon.png" width="128" height="128" alt="SparkleSFTP Native macOS Application Icon" />
  </a>
</p>

<h1 align="center">SparkleSFTP</h1>

<p align="center">
  <b>SparkleSFTP — Lightweight, blazing-fast native macOS Dual-Pane SFTP, FTP/FTPS, SCP &amp; SSH Commander.</b><br>
  <i>Engineered with Swift 6 and native SwiftUI + AppKit architecture for maximum transfer performance, zero-cloud security, and minimal memory footprint</i>
</p>

<p align="center">
  <b>English</b> &nbsp;|&nbsp; <a href="README-id.md"><b>Bahasa Indonesia</b></a>
</p>

<p align="center">
  <a href="https://github.com/alsyundawy/SparkleSFTP/releases/latest"><img src="https://img.shields.io/badge/Release-v0.6.0-2ea44f?style=for-the-badge&logo=github&logoColor=white" alt="Latest Release v0.6.0"></a>
  <a href="https://apple.com/macos"><img src="https://img.shields.io/badge/Platform-macOS_13%2B_(Ventura_%7C_Sonoma_%7C_Sequoia)-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Platform: macOS 13+"></a>
  <a href="https://github.com/alsyundawy/SparkleSFTP"><img src="https://img.shields.io/badge/Architecture-Universal_2_(arm64_%2B_x86__64)-purple?style=for-the-badge&logo=apple&logoColor=white" alt="Universal 2"></a>
  <a href="https://developer.apple.com/swift/"><img src="https://img.shields.io/badge/Language-Swift_6-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Language: Swift 6"></a>
  <a href="https://developer.apple.com/xcode/swiftui/"><img src="https://img.shields.io/badge/UI-SwiftUI_%2B_AppKit-007AFF?style=for-the-badge&logo=apple&logoColor=white" alt="UI: SwiftUI and AppKit"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-2ea44f?style=for-the-badge" alt="License: MIT"></a>
  <a href="https://github.com/alsyundawy/SparkleSFTP/actions"><img src="https://img.shields.io/badge/CI%2FCD-100%25_Passing-success?style=for-the-badge&logo=githubactions&logoColor=white" alt="CI/CD Status"></a>
</p>

<p align="center">
  <b>SparkleSFTP</b> is a premier native file transfer suite and dual-pane commander crafted exclusively for macOS. Built from the ground up to replace outdated transfer utilities, SparkleSFTP prioritizes energy efficiency, memory minimalism, cryptographic security, and power-user ergonomics without any Electron or webview bloat.
</p>

<p align="center">
  <a href="#-quick-download--installation-guide">
    <img src="https://img.shields.io/badge/🚀_Download_DMG-v0.6.0-238636?style=for-the-badge&logo=cloudsmith&logoColor=white" alt="Download DMG">
  </a>
  <a href="https://github.com/alsyundawy/SparkleSFTP/releases/latest">
    <img src="https://img.shields.io/badge/🪞_Releases_&_Changelog-GitHub-0284c7?style=for-the-badge&logo=github&logoColor=white" alt="Releases & Changelog">
  </a>
  <a href="docs/ARCHITECTURE.md">
    <img src="https://img.shields.io/badge/📖_Architecture-Docs-6f42c1?style=for-the-badge&logo=gitbook&logoColor=white" alt="Architecture Docs">
  </a>
  <a href="https://github.com/alsyundawy/SparkleSFTP/issues">
    <img src="https://img.shields.io/badge/🐛_Report_Issue-GitHub_Issues-red?style=for-the-badge&logo=github&logoColor=white" alt="Report Issue">
  </a>
</p>

---

> Lead Developer & Maintainer:<br>
> **[`HARRY DERTIN SUTISNA ALSYUNDAWY (@alsyundawy)`](https://github.com/alsyundawy)** — [`ALSYUNDAWY IT SOLUTION`](https://alsyundawy.com)<br>
>
> 📋 **[`Implementation Plan`](docs/IMPLEMENTATION_PLAN.md)** &nbsp;|&nbsp;
> 🔍 **[`14-Pillar Code Review`](docs/CODE_REVIEW_14_PILLARS.md)** &nbsp;|&nbsp;
> 📐 **[`Architecture`](docs/ARCHITECTURE.md)** &nbsp;|&nbsp;
> 🗺️ **[`Roadmap & Release Gate`](docs/ROADMAP.md)** &nbsp;|&nbsp;
> 🔐 **[`Security Policy`](SECURITY.md)** &nbsp;|&nbsp;
> 📜 **[`Changelog`](CHANGELOG.md)** &nbsp;|&nbsp;
> 🤝 **[`Contributing`](CONTRIBUTING.md)** &nbsp;|&nbsp;
> 💖 **[`Support via PayPal`](https://www.paypal.me/alsyundawy)**

---

## 🌟 Key Highlights & What Makes SparkleSFTP Special

- 🔒 **Native Configuration Bundles & Vault (`.sparkleconfig` / `.sparklevault`)**: Securely backup and restore profiles with AES-256-GCM encryption, PBKDF2-HMAC-SHA256 (600,000 iterations), AAD header binding, and zero-knowledge memory zeroization. Import FileZilla XML, WinSCP INI, and OpenSSH configs with 4 conflict policies.
- ⚙️ **Comprehensive 10-Tab Settings Registry & Universal Search (`⌘,`)**: Centralized preferences registry featuring dynamic search, per-tab reset, and settings dictionary import/export across all 10 tabs.
- 🔍 **High-Performance Directory Comparison**: Instant $O(N+M)$ comparison detecting identical files, size mismatches, modification time differences, and missing items across 10,000+ files in milliseconds.
- 📝 **External Editor Watcher & Sync-Back**: Edit remote files seamlessly in your favorite editor (VS Code, Sublime, BBEdit) with automatic change detection and sandboxed sync-back.
- ⚡ **Bandwidth Limiter & Adaptive Pipeline Depth**: Token-bucket transfer speed limiter and dynamic latency-sensing pipeline controller (1–16 window) with exponential backoff retries.
- 🏷️ **Batch Rename & Multi-Hash Checksums**: Pure rule planner for batch file renaming with `[C]` counters and streaming SHA-256, SHA-512, SHA-1, and MD5 hash verification.
- 📦 **Safe Archive Toolkit**: Multi-format archive compression and extraction (ZIP, TAR, GZ) with Zip-Slip path traversal immunity.
- ⌘ **Command Palette (`⌘⇧P`)**: Spotlight-style quick launcher for commands, bookmarks, connections, and settings navigation.
- 📌 **Bookmarks & Path History Manager**: Save local and remote directory bookmarks with custom icons and host scoping, plus Synchronized Browsing.
- 🌲 **Directory Tree Navigation Sidebar**: Collapsible tree navigation for both local and remote panes with cycle-safe symlink detection.
- ⚡ **Zero Runaway CPU & Battery Coolness**: Engineered with precision AppKit window notifications, eliminating redraw loops so your Mac stays cool and battery usage drops to 0.0% at idle.
- 🎨 **All 76 Themes Restored & Instant Eager Access**: Complete catalog of 76 curated themes meeting WCAG 2.1 AA/AAA contrast guidelines.
- 📂 **Dual-Pane Commander Architecture**: High-speed side-by-side local and remote directory browsers with native AppKit cell reuse.
- 💻 **Standalone iTerm2-Style Terminal (`⌘⌥T`)**: Dedicated terminal workspace featuring split vertical and horizontal panes, remote SSH sessions, and OSC 7 directory sync.
- 🔐 **Apple Keychain & Touch ID Security**: Zero-cloud local security storing credentials, passwords, and private SSH keys strictly inside macOS Keychain.

---

## 📥 Quick Download & Installation Guide

### Step 1: Download the Universal 2 DMG

Grab the latest official release image **`SparkleSFTP-0.6.0-universal.dmg`** from GitHub Releases.

### Step 2: Drag to Applications

1. Double-click `SparkleSFTP-0.6.0-universal.dmg` to mount the disk image.
2. Drag the **SparkleSFTP** icon into your **Applications** folder.
3. Launch SparkleSFTP from Launchpad, Finder, or Spotlight (`⌘Space`).

### Step 3: Gatekeeper First-Launch Tip

Because community builds are ad-hoc signed, macOS may ask for initial confirmation on first launch:

- **Easiest Method**: Right-click (or `Control` + Click) **SparkleSFTP** in `/Applications`, choose **Open**, and click **Open** in the dialog.
- **Terminal Alternative**:

  ```bash
  xattr -dr com.apple.quarantine /Applications/SparkleSFTP.app
  ```

### Step 4: Previewing the Showcase Gallery

To explore all 8 showcase screens of the Sparkle Commander visual refresh:

```bash
/Applications/SparkleSFTP.app/Contents/MacOS/SparkleSFTP --showcase-gallery
```

---

## ⌨️ Essential Keyboard Shortcuts

| Shortcut | Action | Description |
| :--- | :--- | :--- |
| `⌘⇧P` | Command Palette | Spotlight-style instant action and navigation launcher |
| `⌘A` | Select All | Select all files and folders in the active file pane |
| `Esc` / `⇧⌘A` / `⌘D` | Deselect All | Deselect / cancel selection of all files and folders |
| `F5` | Cross-Pane Transfer | Transfer selected items directly to the opposing file pane |
| `⇧F5` | Copy To... | Prompt for a custom destination directory to copy files |
| `⌘C` / `⌘V` | Clipboard Copy / Paste | Standard macOS clipboard file operations |
| `⌥⌘L` | Toggle Activity Log | Show or hide the real-time command log in sidebar |
| `⌘⌥T` | Standalone Terminal | Open the multi-tab iTerm2 terminal workspace |
| `⌘\` | Toggle Quick Connect | Show or hide the quick connect connection bar |
| `⌘1` / `⌘2` | Pane Focus | Switch keyboard focus between Local and Remote file tables |
| `⌘,` | Preferences | Open the 10-tab Settings window with Search & Reset |
| `⌘W` | Close Tab | Close the active workspace connection tab |

---

## 🛡️ Security & Privacy Assurance

- **100% Local & Zero Telemetry**: SparkleSFTP does not track, collect, or transmit any analytics, server addresses, or transfer data.
- **Encrypted Local Storage**: SSH passphrases, passwords, and private keys reside directly in macOS Keychain with hardware Touch ID gating.
- **SHA-256 Checksum Verification**:

```bash
shasum -a 256 SparkleSFTP-0.6.0-universal.dmg
# Expected SHA-256: baef0c187c94e190b976c31cddc97d38743325571e6d451fac3104e173cba2a6
```

---

## 🛠️ Building & Contributing Locally

Build and test using Swift 6 on macOS 13+:

```bash
swift build -j 2
Tools/Release/build-universal.sh
Tools/Release/create-dmg.sh dist/SparkleSFTP.app 0.6.0
```

---

<p align="center">
  Distributed under the <b>MIT License</b>. Crafted with ❤️ for macOS power users by <a href="https://github.com/alsyundawy"><b>@alsyundawy</b></a>
</p>
