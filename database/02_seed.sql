/* =====================================================================
   DAMAGE ROAD - DATA AWAL (jalankan SETELAH 01_schema.sql)
   Berisi: peran, hak akses (sesuai matriks di dokumen workflow),
   type kerusakan R/S/B + tarif MOU, root cause, pengaturan, akun admin.
   ===================================================================== */

SET NOCOUNT ON;
GO

-- Pengaman: kalau data awal sudah pernah dimasukkan, script berhenti di sini (tidak ada data dobel)
IF EXISTS (SELECT 1 FROM dbo.Peran)
BEGIN
    PRINT N'Data awal Damage Road SUDAH ADA. Script tidak dijalankan ulang (tidak ada yang berubah).';
    SET NOEXEC ON;
END
GO

/* 1. PERAN ------------------------------------------------------------ */
INSERT INTO dbo.Peran (Kode, Nama, Keterangan) VALUES
 (N'ADMIN',      N'Admin aplikasi',      N'Kelola pengguna & semua pengaturan'),
 (N'PMO',        N'PMO',                 N'Validasi, paket usulan, SPK, menutup issue'),
 (N'INSPECTOR',  N'Facility Inspector',  N'Melaporkan kerusakan & memeriksa hasil perbaikan'),
 (N'SURVEYOR',   N'Surveyor',            N'Mengukur, upload DWG/PNEZD, edit issue hasil gambar'),
 (N'DEPT_HEAD',  N'Dept Head Township',  N'Menyetujui / menolak paket usulan'),
 (N'DIV_HEAD',   N'Div Head Township',   N'Menyetujui paket di atas batas nilai'),
 (N'MANAGEMENT', N'Management',          N'Hanya melihat dashboard & laporan');
GO

/* 2. HAK AKSES -------------------------------------------------------- */
INSERT INTO dbo.HakAkses (Kode, Nama) VALUES
 (N'dashboard.view',        N'Lihat dashboard, peta, laporan'),
 (N'report.download',       N'Download laporan PDF'),
 (N'issue.create',          N'Buat issue / pin'),
 (N'issue.attach',          N'Upload foto & lampiran'),
 (N'issue.edit',            N'Edit kode, type, title issue'),
 (N'issue.status.own',      N'Ubah status issue yang ditugaskan kepadanya'),
 (N'issue.status.all',      N'Ubah status semua issue'),
 (N'issue.close',           N'Close issue'),
 (N'issue.emergency',       N'Tandai issue Darurat'),
 (N'issue.delete',          N'Hapus issue'),
 (N'zone.manage',           N'Tandai / lepas zona kerusakan berulang'),
 (N'file.upload',           N'Upload DWG / PNEZD / file (versi baru)'),
 (N'file.delete',           N'Hapus file / versi'),
 (N'package.manage',        N'Validasi & susun paket usulan'),
 (N'package.approve.dept',  N'Approve / tolak paket (Dept Head)'),
 (N'package.approve.div',   N'Approve / tolak paket di atas batas (Div Head)'),
 (N'spk.manage',            N'Kelola data SPK'),
 (N'integration.manage',    N'Kelola integrasi API'),
 (N'ruas.manage',           N'Buat, edit, arsip, hapus ruas jalan'),
 (N'settings.manage',       N'Kelola settings type & root cause'),
 (N'backup.manage',         N'Backup & restore data'),
 (N'user.manage',           N'Kelola pengguna & peran');
GO

/* 3. PETA PERAN -> HAK AKSES (matriks hak akses) ---------------------- */
INSERT INTO dbo.PeranHakAkses (PeranId, HakAksesId)
SELECT p.PeranId, h.HakAksesId
FROM (VALUES
  -- semua peran
  (N'ADMIN', N'dashboard.view'), (N'PMO', N'dashboard.view'), (N'INSPECTOR', N'dashboard.view'), (N'SURVEYOR', N'dashboard.view'),
  (N'DEPT_HEAD', N'dashboard.view'), (N'DIV_HEAD', N'dashboard.view'), (N'MANAGEMENT', N'dashboard.view'),
  (N'ADMIN', N'report.download'), (N'PMO', N'report.download'), (N'INSPECTOR', N'report.download'), (N'SURVEYOR', N'report.download'),
  (N'DEPT_HEAD', N'report.download'), (N'DIV_HEAD', N'report.download'), (N'MANAGEMENT', N'report.download'),
  -- lapangan
  (N'INSPECTOR', N'issue.create'), (N'INSPECTOR', N'issue.attach'), (N'INSPECTOR', N'issue.status.own'),
  (N'SURVEYOR', N'issue.create'), (N'SURVEYOR', N'issue.attach'), (N'SURVEYOR', N'issue.status.own'),
  (N'SURVEYOR', N'issue.edit'), (N'SURVEYOR', N'file.upload'), (N'SURVEYOR', N'zone.manage'),
  -- approval
  (N'DEPT_HEAD', N'package.approve.dept'),
  (N'DIV_HEAD', N'package.approve.div')
) AS m(PeranKode, HakKode)
JOIN dbo.Peran p    ON p.Kode = m.PeranKode
JOIN dbo.HakAkses h ON h.Kode = m.HakKode;
GO

-- PMO: semua hak akses kecuali approval & kelola pengguna
INSERT INTO dbo.PeranHakAkses (PeranId, HakAksesId)
SELECT p.PeranId, h.HakAksesId
FROM dbo.Peran p CROSS JOIN dbo.HakAkses h
WHERE p.Kode = N'PMO'
  AND h.Kode NOT IN (N'package.approve.dept', N'package.approve.div', N'user.manage')
  AND NOT EXISTS (SELECT 1 FROM dbo.PeranHakAkses x WHERE x.PeranId = p.PeranId AND x.HakAksesId = h.HakAksesId);
GO

-- ADMIN: semua hak akses kecuali approval (approval tetap oleh Dept/Div Head)
INSERT INTO dbo.PeranHakAkses (PeranId, HakAksesId)
SELECT p.PeranId, h.HakAksesId
FROM dbo.Peran p CROSS JOIN dbo.HakAkses h
WHERE p.Kode = N'ADMIN'
  AND h.Kode NOT IN (N'package.approve.dept', N'package.approve.div')
  AND NOT EXISTS (SELECT 1 FROM dbo.PeranHakAkses x WHERE x.PeranId = p.PeranId AND x.HakAksesId = h.HakAksesId);
GO

/* 4. TYPE KERUSAKAN + TARIF MOU --------------------------------------- */
INSERT INTO dbo.KategoriType (Nama) VALUES (N'Kerusakan Jalan');
GO
INSERT INTO dbo.TypeKerusakan (KategoriTypeId, Nama, Kode, TarifMouPerM2)
SELECT k.KategoriTypeId, v.Nama, v.Kode, v.Tarif
FROM dbo.KategoriType k
CROSS JOIN (VALUES (N'Ringan', N'R', 180000.00), (N'Sedang', N'S', 240000.00), (N'Berat', N'B', 470000.00)) AS v(Nama, Kode, Tarif)
WHERE k.Nama = N'Kerusakan Jalan';
GO

/* 5. ROOT CAUSE -------------------------------------------------------- */
INSERT INTO dbo.KategoriRootCause (Nama) VALUES (N'Kerusakan Jalan'), (N'Lingkungan'), (N'Pekerjaan');
GO
INSERT INTO dbo.RootCause (KategoriRootCauseId, Nama)
SELECT k.KategoriRootCauseId, v.Nama
FROM dbo.KategoriRootCause k
JOIN (VALUES
  (N'Kerusakan Jalan', N'Beban kendaraan berlebih (truk)'),
  (N'Kerusakan Jalan', N'Usia perkerasan'),
  (N'Kerusakan Jalan', N'Penurunan tanah'),
  (N'Kerusakan Jalan', N'Kerusakan Berulang di Titik yang Sama'),
  (N'Lingkungan',      N'Genangan air / drainase buruk'),
  (N'Lingkungan',      N'Akar pohon'),
  (N'Lingkungan',      N'Cuaca / hujan ekstrem'),
  (N'Pekerjaan',       N'Kualitas material'),
  (N'Pekerjaan',       N'Kualitas pekerjaan (workmanship)'),
  (N'Pekerjaan',       N'Galian utilitas tidak dikembalikan')
) AS v(Kategori, Nama) ON v.Kategori = k.Nama;
GO

/* 6. PENGATURAN UMUM ------------------------------------------------- */
INSERT INTO dbo.Pengaturan (Kunci, Nilai, Keterangan) VALUES
 (N'approval.batas_div_head', NULL,   N'Nilai paket (Rp) yang wajib disetujui Div Head. Isi setelah disepakati.'),
 (N'zona.batas_tumpuk',       N'0.3', N'Saran zona berulang: minimal bagian kotak bidang yang bertumpuk (0.3 = 30%)'),
 (N'zona.toleransi_m',        N'0.5', N'Toleransi pergeseran gambar antar survey (meter)'),
 (N'login.maks_gagal',        N'5',   N'Akun dikunci sementara setelah salah password sebanyak ini'),
 (N'login.kunci_menit',       N'15',  N'Lama akun terkunci (menit)'),
 (N'koordinat.zona_utm',      N'48S', N'Zona UTM gambar Civil 3D BSD');
GO

/* 7. AKUN ADMIN PERTAMA ------------------------------------------------
   Sengaja TANPA password. Saat pertama kali login, aplikasi meminta admin
   membuat password sendiri (WajibGantiPassword = 1). Tidak ada password
   bawaan yang tersimpan di script ini.                                   */
INSERT INTO dbo.Pengguna (Username, NamaLengkap, Email, Company, PasswordHash, WajibGantiPassword)
VALUES (N'admin', N'Administrator Damage Road', NULL, N'BSD PMO', NULL, 1);
GO
INSERT INTO dbo.PenggunaPeran (PenggunaId, PeranId)
SELECT pg.PenggunaId, p.PeranId FROM dbo.Pengguna pg JOIN dbo.Peran p ON p.Kode IN (N'ADMIN', N'PMO')
WHERE pg.Username = N'admin';
GO

/* 8. CEK HASIL -------------------------------------------------------- */
SELECT p.Kode AS Peran, COUNT(*) AS JumlahHakAkses
FROM dbo.PeranHakAkses ph JOIN dbo.Peran p ON p.PeranId = ph.PeranId
GROUP BY p.Kode ORDER BY p.Kode;
GO
PRINT N'Data awal Damage Road selesai dimasukkan.';
GO
SET NOEXEC OFF;
GO
