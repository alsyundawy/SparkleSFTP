<!-- markdownlint-disable-file MD013 MD022 MD026 MD032 MD033 MD041 MD060 -->

<p align="center">
  <a href="https://github.com/alsyundawy/SparkleSFTP">
    <img src="assets/sparklesftp-desktop-banner.jpg" width="100%" alt="SparkleSFTP Desktop Suite — Commander Transfer Berkas Dual-Pane Asli macOS untuk SFTP, FTP/FTPS, SCP &amp; SSH" />
  </a>
</p>

<p align="center">
  <a href="https://github.com/alsyundawy/SparkleSFTP">
    <img src="src/App/Resources/AppIcon.png" width="128" height="128" alt="Ikon Aplikasi macOS Asli SparkleSFTP" />
  </a>
</p>

<h1 align="center">SparkleSFTP</h1>

<p align="center">
  <b>SparkleSFTP — Commander Transfer Berkas Dual-Pane Native macOS yang Ringan dan Secepat Kilat.</b><br>
  <i>Dirancang dengan Swift 6 dan arsitektur native SwiftUI + AppKit untuk performa transfer maksimal, keamanan zero-cloud, dan efisiensi memori tingkat tinggi</i>
</p>

<p align="center">
  <a href="README.md"><b>English</b></a> &nbsp;|&nbsp; <b>Bahasa Indonesia</b>
</p>

<p align="center">
  <a href="https://github.com/alsyundawy/SparkleSFTP/releases/latest"><img src="https://img.shields.io/badge/Rilis-v0.6.0-2ea44f?style=for-the-badge&logo=github&logoColor=white" alt="Rilis v0.6.0"></a>
  <a href="https://apple.com/macos"><img src="https://img.shields.io/badge/Platform-macOS_13%2B_(Ventura_%7C_Sonoma_%7C_Sequoia)-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Platform: macOS 13+"></a>
  <a href="https://github.com/alsyundawy/SparkleSFTP"><img src="https://img.shields.io/badge/Arsitektur-Universal_2_(arm64_%2B_x86__64)-purple?style=for-the-badge&logo=apple&logoColor=white" alt="Universal 2"></a>
  <a href="https://developer.apple.com/swift/"><img src="https://img.shields.io/badge/Bahasa-Swift_6-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Bahasa: Swift 6"></a>
  <a href="https://developer.apple.com/xcode/swiftui/"><img src="https://img.shields.io/badge/UI-SwiftUI_%2B_AppKit-007AFF?style=for-the-badge&logo=apple&logoColor=white" alt="UI: SwiftUI dan AppKit"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/Lisensi-MIT-2ea44f?style=for-the-badge" alt="Lisensi: MIT"></a>
  <a href="https://github.com/alsyundawy/SparkleSFTP/actions"><img src="https://img.shields.io/badge/CI%2FCD-100%25_Lulus-success?style=for-the-badge&logo=githubactions&logoColor=white" alt="Status CI/CD"></a>
</p>

<p align="center">
  <b>SparkleSFTP</b> adalah aplikasi transfer dan pengelola berkas native dual-pane yang elegan dan super cepat untuk macOS. Dibuat murni sebagai alternatif modern pengganti perkakas transfer berkas tradisional, SparkleSFTP mengutamakan efisiensi daya baterai, hemat RAM, keamanan kriptografi Apple Keychain, dan kenyamanan pengguna tanpa beban browser webview atau Electron.
</p>

<p align="center">
  <a href="#-panduan-unduh--instalasi-cepat">
    <img src="https://img.shields.io/badge/🚀_Unduh_DMG-v0.6.0-238636?style=for-the-badge&logo=cloudsmith&logoColor=white" alt="Unduh DMG">
  </a>
  <a href="https://github.com/alsyundawy/SparkleSFTP/releases/latest">
    <img src="https://img.shields.io/badge/🪞_Rilis_&_Catatan_Perubahan-GitHub-0284c7?style=for-the-badge&logo=github&logoColor=white" alt="Rilis & Catatan Perubahan">
  </a>
  <a href="docs/ARCHITECTURE.md">
    <img src="https://img.shields.io/badge/📖_Dokumentasi_Arsitektur-Docs-6f42c1?style=for-the-badge&logo=gitbook&logoColor=white" alt="Dokumentasi Arsitektur">
  </a>
  <a href="https://github.com/alsyundawy/SparkleSFTP/issues">
    <img src="https://img.shields.io/badge/🐛_Laporkan_Masalah-GitHub_Issues-red?style=for-the-badge&logo=github&logoColor=white" alt="Laporkan Masalah">
  </a>
</p>

---

> Pengembang Utama & Pemelihara:<br>
> **[`HARRY DERTIN SUTISNA ALSYUNDAWY (@alsyundawy)`](https://github.com/alsyundawy)** — [`ALSYUNDAWY IT SOLUTION`](https://alsyundawy.com)<br>
>
> 📋 **[`Rencana Implementasi`](docs/IMPLEMENTATION_PLAN.md)** &nbsp;|&nbsp;
> 🔍 **[`Tinjauan Kode 14 Pilar`](docs/CODE_REVIEW_14_PILLARS.md)** &nbsp;|&nbsp;
> 📐 **[`Arsitektur Sistem`](docs/ARCHITECTURE.md)** &nbsp;|&nbsp;
> 🗺️ **[`Peta Jalan & Syarat Rilis`](docs/ROADMAP.md)** &nbsp;|&nbsp;
> 🔐 **[`Kebijakan Keamanan`](SECURITY.md)** &nbsp;|&nbsp;
> 📜 **[`Catatan Perubahan`](CHANGELOG.md)** &nbsp;|&nbsp;
> 🤝 **[`Panduan Kontribusi`](CONTRIBUTING.md)** &nbsp;|&nbsp;
> 💖 **[`Dukungan via PayPal`](https://www.paypal.me/alsyundawy)**

---

## 🌟 Sorotan Utama & Keunggulan bagi Pengguna di v0.6.0

- 🔒 **Bundel Konfigurasi & Vault Kriptografis Native (`.sparkleconfig` / `.sparklevault`)**: Cadangkan dan pulihkan profil dengan enkripsi autentikasi AES-256-GCM, PBKDF2-HMAC-SHA256 (600.000 iterasi), pengikatan header AAD, dan pembersihan memori kunci zero-knowledge. Impor berkas FileZilla XML, WinSCP INI, dan OpenSSH config dengan 4 kebijakan konflik.
- ⚙️ **Registri Pengaturan 10 Tab & Pencarian Universal (`⌘,`)**: Registri preferensi terpusat dengan pencarian dinamis, atur ulang bawaan per tab, dan ekspor/impor kamus pengaturan JSON di seluruh 10 tab.
- 🔍 **Perbandingan Direktori Berkecepatan Tinggi**: Perbandingan instan $O(N+M)$ mendeteksi berkas identik, perbedaan ukuran, selisih waktu modifikasi, dan berkas hilang di antara 10.000+ berkas dalam hitungan milidetik.
- 📝 **Pengawas & Pengunggah Editor Eksternal**: Sunting berkas remote langsung di editor favorit Anda (VS Code, Sublime, BBEdit) dengan deteksi perubahan otomatis dan sinkronisasi kembali yang aman.
- ⚡ **Pembatas Kecepatan Bandwidth & Pipelining Adaptif**: Pengatur batas kecepatan transfer token-bucket serta pengontrol kedalaman transfer cerdas (1–16 jendela) dengan coba-ulang eksponensial.
- 🏷️ **Ganti Nama Massal & Verifikasi Hash Multi-Algoritma**: Perencana aturan ganti nama berkas massal dengan penghitung digit `[C]` serta verifikasi checksum streaming SHA-256, SHA-512, SHA-1, dan MD5.
- 📦 **Perlengkapan Arsip Aman**: Kompresi dan ekstraksi multi-format (ZIP, TAR, GZ) yang kebal terhadap serangan Zip-Slip path traversal.
- ⌘ **Palet Perintah (*Command Palette*, `⌘⇧P`)**: Peluncur aksi cepat bergaya Spotlight untuk mencari perintah, markah, koneksi, dan navigasi pengaturan.
- 📌 **Manajer Markah & Riwayat Jalur**: Menyimpan markah direktori lokal dan remote dengan ikon kustom, isolasi sesi host, serta Penelusuran Tersinkronisasi.
- 🌲 **Bilah Sisi Pohon Direktori**: Penjelajah pohon folder berhierarki untuk panel lokal dan remote dengan pencegahan siklus rekursif symlink.
- ⚡ **Super Adem & Hemat Daya (Zero Runaway CPU)**: Dirancang dengan notifikasi jendela AppKit presisi, menghentikan perulangan render sehingga konsumsi daya 0.0% saat santai (idle).
- 🎨 **Seluruh 76 Tema Dipulihkan & Dimuat Lengkap**: Koleksi lengkap 76 tema bawaan dalam 26 rumpun yang memenuhi standar kontras WCAG 2.1 AA/AAA.
- 📂 **Arsitektur Dual-Pane Commander**: Menjelajah berkas lokal dan server secara berdampingan dengan daur ulang baris AppKit native.
- 💻 **Terminal Mandiri Bergaya iTerm2 (`⌘⌥T`)**: Ruang kerja terminal multi-tab dengan pembagian jendela vertikal dan horizontal, koneksi SSH, serta sinkronisasi direktori OSC 7.
- 🔐 **Keamanan Apple Keychain & Touch ID**: Tanpa server pihak ketiga (*Zero-cloud*), seluruh kredensial dan kunci privat SSH tersimpan aman di dalam Apple Keychain fisik Mac Anda.

---

## 📥 Panduan Unduh & Instalasi Cepat

### Langkah 1: Unduh Berkas DMG

Unduh berkas instalasi resmi **`SparkleSFTP-0.6.0-universal.dmg`** dari GitHub Releases.

### Langkah 2: Pasang ke Folder Applications

1. Klik dua kali berkas `SparkleSFTP-0.6.0-universal.dmg` untuk membukanya.
2. Seret ikon **SparkleSFTP** ke dalam folder **Applications**.
3. Buka SparkleSFTP melalui Launchpad, Finder, atau Spotlight (`⌘Spasi`).

### Langkah 3: Tips Keamanan Gatekeeper Pertama Kali

Karena rilis komunitas ini menggunakan sertifikat mandiri, Anda dapat membukanya dengan mudah:

- **Cara Termudah**: Klik kanan (atau `Control` + Klik) **SparkleSFTP** di `/Applications`, pilih **Open (Buka)**, lalu klik **Open** pada jendela konfirmasi.
- **Alternatif Terminal**:

  ```bash
  xattr -dr com.apple.quarantine /Applications/SparkleSFTP.app
  ```

### Langkah 4: Menjalankan Mode Galeri Showcase

Untuk mengeksplorasi seluruh 8 layar pratinjau antarmuka Sparkle Commander:

```bash
/Applications/SparkleSFTP.app/Contents/MacOS/SparkleSFTP --showcase-gallery
```

---

## ⌨️ Daftar Tombol Pintas Penting

| Tombol Pintas | Tindakan | Keterangan |
| :--- | :--- | :--- |
| `⌘⇧P` | Palet Perintah | Peluncur cepat tindakan, koneksi, markah, dan navigasi |
| `⌘A` | Pilih Semua | Memilih semua berkas dan folder di panel aktif |
| `Esc` / `⇧⌘A` / `⌘D` | Batalkan Semua Pilihan | Membatalkan / melepas sorotan pilihan semua berkas dan folder |
| `F5` | Transfer Cepat Antar-Panel | Mengirimkan berkas terpilih langsung ke panel di seberangnya |
| `⇧F5` | Salin Ke... | Meminta lokasi folder tujuan kustom untuk menyalin berkas |
| `⌘C` / `⌘V` | Salin / Tempel Clipboard | Operasi salin-tempel standar clipboard macOS |
| `⌥⌘L` | Tampilkan/Sembunyikan Log | Membuka atau menutup konsol riwayat perintah aktivitas server |
| `⌘⌥T` | Terminal Mandiri | Membuka jendela kerja terminal multi-tab bergaya iTerm2 |
| `⌘\` | Bilah Sambungan Cepat | Menampilkan atau menyembunyikan bilah Quick Connect |
| `⌘1` / `⌘2` | Fokus Panel Berkas | Berpindah fokus keyboard antara panel Lokal dan Remote |
| `⌘,` | Pengaturan / Preferensi | Membuka jendela 10 tab setelan dengan fitur cari & atur ulang |
| `⌘W` | Tutup Tab | Menutup tab koneksi server yang sedang aktif |

---

## 🛡️ Jaminan Keamanan & Privasi

- **100% Lokal & Tanpa Telemetri**: SparkleSFTP tidak pernah memantau, mengumpulkan, atau mengirimkan analitik, alamat server, maupun data berkas Anda.
- **Penyimpanan Lokal Terenkripsi**: Frasa sandi SSH dan kunci privat tersimpan langsung di Apple Keychain yang dilindungi Touch ID.
- **Verifikasi Integritas SHA-256**:

```bash
shasum -a 256 SparkleSFTP-0.6.0-universal.dmg
# SHA-256 Valid: baef0c187c94e190b976c31cddc97d38743325571e6d451fac3104e173cba2a6
```

---

## 🛠️ Kompilasi Mandiri Secara Lokal

Kompilasi dan bangun paket menggunakan Swift 6 di macOS 13+:

```bash
swift build -j 2
Tools/Release/build-universal.sh
Tools/Release/create-dmg.sh dist/SparkleSFTP.app 0.6.0
```

---

<p align="center">
  Didistribusikan di bawah <b>Lisensi MIT</b>. Dibuat dengan ❤️ untuk pengguna setia Mac oleh <a href="https://github.com/alsyundawy"><b>@alsyundawy</b></a>
</p>
