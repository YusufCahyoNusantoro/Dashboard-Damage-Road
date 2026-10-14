# Damage Road API (login & pengguna)

API ini menghubungkan aplikasi Damage Road dengan database **DamageRoad** di SQL Server,
dan menangani **login, password, serta hak akses** setiap pengguna.

Setelah API berjalan, aplikasi dibuka di **http://localhost:3000** dan wajib login.

> Tahap ini: login & pengguna sudah memakai database.
> Data issue, ruas, dan file **masih disimpan di browser** (dipindah ke database di tahap berikutnya).

---

## Langkah 1 – Izinkan login "SQL Server Authentication"

API masuk ke database memakai akun khusus (bukan akun Windows-mu), jadi SQL Server perlu mengizinkan login dengan username & password.

1. Buka **SSMS** → di **Object Explorer**, klik kanan nama server `localhost\SQLEXPRESS` → **Properties**.
2. Pilih halaman **Security** → di *Server authentication* pilih **SQL Server and Windows Authentication mode** → **OK**.
3. Klik kanan nama server lagi → **Restart** → **Yes**.

## Langkah 2 – Nyalakan koneksi TCP/IP (port 1433)

SQL Server Express mematikan koneksi jaringan secara bawaan. API membutuhkannya.

1. Tekan tombol **Windows**, ketik **SQL Server 2025 Configuration Manager**, buka (izinkan kalau diminta).
   *Kalau tidak muncul di pencarian:* tekan **Windows + R**, ketik `SQLServerManager17.msc`, Enter.
2. Buka **SQL Server Network Configuration → Protocols for SQLEXPRESS**.
3. Klik kanan **TCP/IP** → **Enable**.
4. Klik dua kali **TCP/IP** → tab **IP Addresses** → gulir ke paling bawah ke bagian **IPAll**:
   - **TCP Dynamic Ports**: kosongkan
   - **TCP Port**: isi `1433`
   → **OK**.
5. Buka **SQL Server Services** → klik kanan **SQL Server (SQLEXPRESS)** → **Restart**.

## Langkah 3 – Buat akun database untuk API

1. Buka `database/04_login_api.sql` di SSMS.
2. Ganti tulisan `GANTI_PASSWORD_INI` dengan password yang kuat (min. 8 karakter, huruf besar + kecil + angka). **Catat** password ini.
3. Tekan **F5**. Harus muncul: `Akun database damageroad_api siap dipakai API.`

## Langkah 4 – Pasang Node.js

1. Buka **nodejs.org** → unduh versi **LTS** → pasang (semua pilihan bawaan).
2. Cek: buka **Command Prompt**, ketik `node -v` → harus muncul nomor versi (mis. `v22.x`).

## Langkah 5 – Siapkan folder API

1. Salin folder `api` ini ke laptop, misalnya `C:\DamageRoad\api`.
2. Di dalam folder itu, salin file **`.env.example`** lalu ganti namanya menjadi **`.env`**.
3. Buka `.env` dengan Notepad, isi:
   - `DB_PASSWORD=` → password dari Langkah 3
   - `JWT_SECRET=` → teks acak panjang. Cara membuatnya: buka Command Prompt di folder `api`, jalankan
     `node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"` lalu salin hasilnya.
4. Simpan.

> File `.env` berisi password. **Jangan di-upload ke GitHub** (sudah dikecualikan di `.gitignore`).

## Langkah 6 – Jalankan API

Buka Command Prompt di folder `api`, lalu:

```
npm install
npm start
```

`npm install` hanya perlu sekali (mengunduh komponen). Kalau berhasil, muncul:

```
Damage Road API berjalan di http://localhost:3000
Database tersambung: DamageRoad
```

Biarkan jendela Command Prompt ini tetap terbuka selama aplikasi dipakai.

## Langkah 7 – Login pertama sebagai admin

1. Buka browser → **http://localhost:3000**
2. Username: `admin` → klik **Masuk** (password dikosongkan).
3. Aplikasi meminta **membuat password admin** (min. 8 karakter, huruf + angka).
4. Selesai. Di sidebar kiri bawah muncul akunmu dengan menu **Kelola pengguna**.

> Password pertama admin hanya bisa dibuat dari laptop yang menjalankan API (localhost), jadi aman walaupun API bisa diakses dari jaringan.

## Menambah pengguna

**Kelola pengguna** → **+ Tambah pengguna** → isi username, nama, company, centang peran → **Buat pengguna**.
Aplikasi menampilkan **password sementara** (mis. `YVDS9374`). Berikan ke orangnya; saat login pertama ia wajib menggantinya.

Kalau ada yang lupa password atau akunnya terkunci (5x salah password → terkunci 15 menit): **Kelola pengguna → Reset password**.

## Peran & hak akses

| Peran | Bisa |
|---|---|
| Admin aplikasi | Semua, termasuk kelola pengguna |
| PMO | Semua kecuali kelola pengguna & approval |
| Facility Inspector | Buat issue, upload foto, ubah status issue yang ditugaskan kepadanya |
| Surveyor | Seperti inspector + upload DWG/PNEZD, edit issue, tandai zona berulang |
| Dept Head / Div Head | Lihat semua + approval paket (tahap berikutnya) |
| Management | Hanya melihat dashboard & laporan |

Tombol yang tidak boleh dipakai otomatis disembunyikan atau ditolak dengan pesan.

## Kalau ada masalah

| Pesan | Penyebab | Solusi |
|---|---|---|
| `Database belum tersambung: Failed to connect to localhost:1433` | TCP/IP belum aktif / port salah | Ulangi Langkah 2, restart SQL Server |
| `Login failed for user 'damageroad_api'` | Password di `.env` beda, atau Langkah 1 belum dilakukan | Cek `.env`, ulangi Langkah 1 & 3 |
| `'npm' is not recognized` | Node.js belum terpasang / Command Prompt dibuka sebelum instal | Pasang Node.js, buka Command Prompt baru |
| Layar login: "Tidak bisa menghubungi server API" | API belum dijalankan | Jalankan `npm start` |

## Tentang aplikasi di GitHub Pages

Versi di GitHub Pages tetap berjalan tanpa login seperti sekarang.
Kalau ingin versi GitHub Pages juga memakai login, buka **Kelola Data → Server & login**, isi alamat API, dan centang **Wajib login**.
Chrome akan meminta izin "akses jaringan lokal" saat pertama kali – pilih **Izinkan**.
