/* =====================================================================
   DAMAGE ROAD - SKEMA DATABASE SQL SERVER
   Versi 1 - mengikuti dokumen "Workflow & Peran Aplikasi Damage Road"

   Cara pakai: buka di SQL Server Management Studio (SSMS), pastikan
   database yang aktif = DamageRoad, lalu tekan F5 (Execute).
   Jalankan 01_schema.sql dulu, baru 02_seed.sql.

   Catatan:
   - File DWG, foto, dan lampiran TIDAK disimpan di database. Database hanya
     menyimpan lokasi file-nya (kolom LokasiPenyimpanan). File fisiknya
     disimpan di folder server / SharePoint / Blob storage.
   - Kode kerusakan (R1, S2, B3) unik per ruas.
   - Script ini aman dijalankan di database kosong. Kalau tabel sudah ada,
     hapus database lalu buat ulang (khusus masa pengembangan).
   ===================================================================== */

SET NOCOUNT ON;
GO

-- Pengaman: kalau skema sudah pernah dibuat, script berhenti di sini (tidak ada error merah, tidak ada yang berubah)
IF OBJECT_ID(N'dbo.Peran', N'U') IS NOT NULL
BEGIN
    PRINT N'Skema Damage Road SUDAH ADA di database ini. Script tidak dijalankan ulang (tidak ada yang berubah).';
    SET NOEXEC ON;
END
GO

/* ---------------------------------------------------------------------
   1. PENGGUNA, PERAN, HAK AKSES (untuk fitur login)
   --------------------------------------------------------------------- */

CREATE TABLE dbo.Peran (
    PeranId         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Peran PRIMARY KEY,
    Kode            NVARCHAR(30)  NOT NULL CONSTRAINT UQ_Peran_Kode UNIQUE,   -- ADMIN, PMO, INSPECTOR, ...
    Nama            NVARCHAR(100) NOT NULL,
    Keterangan      NVARCHAR(400) NULL
);
GO

CREATE TABLE dbo.HakAkses (
    HakAksesId      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_HakAkses PRIMARY KEY,
    Kode            NVARCHAR(60)  NOT NULL CONSTRAINT UQ_HakAkses_Kode UNIQUE, -- mis. issue.create
    Nama            NVARCHAR(150) NOT NULL
);
GO

CREATE TABLE dbo.PeranHakAkses (
    PeranId         INT NOT NULL CONSTRAINT FK_PeranHakAkses_Peran REFERENCES dbo.Peran(PeranId),
    HakAksesId      INT NOT NULL CONSTRAINT FK_PeranHakAkses_HakAkses REFERENCES dbo.HakAkses(HakAksesId),
    CONSTRAINT PK_PeranHakAkses PRIMARY KEY (PeranId, HakAksesId)
);
GO

CREATE TABLE dbo.Pengguna (
    PenggunaId          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Pengguna PRIMARY KEY,
    Username            NVARCHAR(50)  NOT NULL CONSTRAINT UQ_Pengguna_Username UNIQUE,
    NamaLengkap         NVARCHAR(150) NOT NULL,
    Email               NVARCHAR(200) NULL,
    Company             NVARCHAR(100) NULL,                    -- mis. BSD TM, BSD PMO
    -- Login username/password: hanya HASH (bcrypt) yang disimpan, BUKAN password asli.
    PasswordHash        NVARCHAR(200) NULL,                    -- NULL = belum pernah set password
    -- Untuk login akun Microsoft kantor (Entra ID) di masa depan
    EntraObjectId       NVARCHAR(64)  NULL,
    Aktif               BIT           NOT NULL CONSTRAINT DF_Pengguna_Aktif DEFAULT (1),
    WajibGantiPassword  BIT           NOT NULL CONSTRAINT DF_Pengguna_WajibGanti DEFAULT (1),
    GagalLogin          INT           NOT NULL CONSTRAINT DF_Pengguna_Gagal DEFAULT (0),
    TerkunciSampai      DATETIME2(0)  NULL,                    -- dikunci sementara setelah salah password berkali-kali
    LoginTerakhir       DATETIME2(0)  NULL,
    DibuatPada          DATETIME2(0)  NOT NULL CONSTRAINT DF_Pengguna_Dibuat DEFAULT (SYSDATETIME()),
    DiubahPada          DATETIME2(0)  NULL
);
GO
CREATE UNIQUE INDEX UX_Pengguna_Email ON dbo.Pengguna(Email) WHERE Email IS NOT NULL;
CREATE UNIQUE INDEX UX_Pengguna_Entra ON dbo.Pengguna(EntraObjectId) WHERE EntraObjectId IS NOT NULL;
GO

CREATE TABLE dbo.PenggunaPeran (
    PenggunaId      INT NOT NULL CONSTRAINT FK_PenggunaPeran_Pengguna REFERENCES dbo.Pengguna(PenggunaId),
    PeranId         INT NOT NULL CONSTRAINT FK_PenggunaPeran_Peran REFERENCES dbo.Peran(PeranId),
    CONSTRAINT PK_PenggunaPeran PRIMARY KEY (PenggunaId, PeranId)
);
GO

-- Sesi login (refresh token). Yang disimpan hanya hash token-nya.
CREATE TABLE dbo.SesiLogin (
    SesiId          UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_SesiLogin PRIMARY KEY CONSTRAINT DF_SesiLogin_Id DEFAULT (NEWID()),
    PenggunaId      INT            NOT NULL CONSTRAINT FK_SesiLogin_Pengguna REFERENCES dbo.Pengguna(PenggunaId),
    TokenHash       NVARCHAR(200)  NOT NULL,
    BerlakuSampai   DATETIME2(0)   NOT NULL,
    DicabutPada     DATETIME2(0)   NULL,
    AlamatIp        NVARCHAR(64)   NULL,
    UserAgent       NVARCHAR(300)  NULL,
    DibuatPada      DATETIME2(0)   NOT NULL CONSTRAINT DF_SesiLogin_Dibuat DEFAULT (SYSDATETIME())
);
GO
CREATE INDEX IX_SesiLogin_Pengguna ON dbo.SesiLogin(PenggunaId);
GO

/* ---------------------------------------------------------------------
   2. PENGATURAN: TYPE KERUSAKAN, ROOT CAUSE, PENGATURAN UMUM
   --------------------------------------------------------------------- */

CREATE TABLE dbo.KategoriType (
    KategoriTypeId  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_KategoriType PRIMARY KEY,
    Nama            NVARCHAR(100) NOT NULL CONSTRAINT UQ_KategoriType_Nama UNIQUE,   -- mis. Kerusakan Jalan
    Aktif           BIT NOT NULL CONSTRAINT DF_KategoriType_Aktif DEFAULT (1)
);
GO

CREATE TABLE dbo.TypeKerusakan (
    TypeId          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TypeKerusakan PRIMARY KEY,
    KategoriTypeId  INT NOT NULL CONSTRAINT FK_TypeKerusakan_Kategori REFERENCES dbo.KategoriType(KategoriTypeId),
    Nama            NVARCHAR(100) NOT NULL,                     -- Ringan / Sedang / Berat
    Kode            NVARCHAR(3)   NOT NULL CONSTRAINT UQ_TypeKerusakan_Kode UNIQUE,   -- R / S / B (huruf depan kode kerusakan)
    TarifMouPerM2   DECIMAL(18,2) NULL,                         -- dipakai untuk estimasi biaya titik yang belum SPK
    Aktif           BIT NOT NULL CONSTRAINT DF_TypeKerusakan_Aktif DEFAULT (1),
    CONSTRAINT UQ_TypeKerusakan_Nama UNIQUE (KategoriTypeId, Nama)
);
GO

CREATE TABLE dbo.KategoriRootCause (
    KategoriRootCauseId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_KategoriRootCause PRIMARY KEY,
    Nama            NVARCHAR(100) NOT NULL CONSTRAINT UQ_KategoriRootCause_Nama UNIQUE,
    Aktif           BIT NOT NULL CONSTRAINT DF_KategoriRootCause_Aktif DEFAULT (1)
);
GO

CREATE TABLE dbo.RootCause (
    RootCauseId         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_RootCause PRIMARY KEY,
    KategoriRootCauseId INT NOT NULL CONSTRAINT FK_RootCause_Kategori REFERENCES dbo.KategoriRootCause(KategoriRootCauseId),
    Nama                NVARCHAR(200) NOT NULL,
    Aktif               BIT NOT NULL CONSTRAINT DF_RootCause_Aktif DEFAULT (1),
    CONSTRAINT UQ_RootCause UNIQUE (KategoriRootCauseId, Nama)
);
GO

-- Pengaturan umum (key-value), mis. batas nilai paket untuk persetujuan Div Head
CREATE TABLE dbo.Pengaturan (
    Kunci           NVARCHAR(100) NOT NULL CONSTRAINT PK_Pengaturan PRIMARY KEY,
    Nilai           NVARCHAR(MAX) NULL,
    Keterangan      NVARCHAR(400) NULL,
    DiubahOleh      INT NULL CONSTRAINT FK_Pengaturan_Pengguna REFERENCES dbo.Pengguna(PenggunaId),
    DiubahPada      DATETIME2(0) NULL
);
GO

/* ---------------------------------------------------------------------
   3. RUAS JALAN (proyek)
   --------------------------------------------------------------------- */

CREATE TABLE dbo.Ruas (
    RuasId          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Ruas PRIMARY KEY,
    KodeRuas        NVARCHAR(20)  NOT NULL CONSTRAINT UQ_Ruas_Kode UNIQUE,       -- BSD0003
    NamaRuas        NVARCHAR(100) NOT NULL CONSTRAINT UQ_Ruas_Nama UNIQUE,       -- Row 40B
    NamaJalan       NVARCHAR(200) NULL,                                          -- Jl. BSD Grand Boulevard
    Area            NVARCHAR(10)  NULL CONSTRAINT CK_Ruas_Area CHECK (Area IN (N'Barat', N'Timur')),
    Hub             NVARCHAR(50)  NULL,
    PanjangM        DECIMAL(12,2) NULL,
    LebarM          DECIMAL(8,2)  NULL,
    Keterangan      NVARCHAR(400) NULL,
    Status          NVARCHAR(10)  NOT NULL CONSTRAINT DF_Ruas_Status DEFAULT (N'aktif')
                    CONSTRAINT CK_Ruas_Status CHECK (Status IN (N'aktif', N'arsip')),
    DiarsipkanPada  DATETIME2(0)  NULL,
    DibuatOleh      INT NULL CONSTRAINT FK_Ruas_DibuatOleh REFERENCES dbo.Pengguna(PenggunaId),
    DibuatPada      DATETIME2(0)  NOT NULL CONSTRAINT DF_Ruas_Dibuat DEFAULT (SYSDATETIME()),
    DiubahPada      DATETIME2(0)  NULL
);
GO

/* ---------------------------------------------------------------------
   4. FILE & VERSI (DWG, PNEZD, dokumen, foto, laporan)
   --------------------------------------------------------------------- */

CREATE TABLE dbo.FileDokumen (
    FileId          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FileDokumen PRIMARY KEY,
    RuasId          INT NOT NULL CONSTRAINT FK_FileDokumen_Ruas REFERENCES dbo.Ruas(RuasId),
    Folder          NVARCHAR(40) NOT NULL CONSTRAINT CK_FileDokumen_Folder
                    CHECK (Folder IN (N'Civil 3D', N'Survey (PNEZD)', N'Dokumen', N'Foto', N'Laporan')),
    NamaFile        NVARCHAR(260) NOT NULL,
    NamaNormal      NVARCHAR(260) NOT NULL,     -- nama tanpa spasi/titik/huruf besar: untuk menyambung versi
    DibuatOleh      INT NULL CONSTRAINT FK_FileDokumen_DibuatOleh REFERENCES dbo.Pengguna(PenggunaId),
    DibuatPada      DATETIME2(0) NOT NULL CONSTRAINT DF_FileDokumen_Dibuat DEFAULT (SYSDATETIME()),
    CONSTRAINT UQ_FileDokumen UNIQUE (RuasId, Folder, NamaNormal)
);
GO

CREATE TABLE dbo.FileVersi (
    FileVersiId         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FileVersi PRIMARY KEY,
    FileId              INT NOT NULL CONSTRAINT FK_FileVersi_File REFERENCES dbo.FileDokumen(FileId),
    NomorVersi          INT NOT NULL,                       -- 1, 2, 3, ...
    NamaFileAsli        NVARCHAR(260) NOT NULL,             -- nama file saat di-upload
    TipeMime            NVARCHAR(100) NULL,
    UkuranByte          BIGINT NULL,
    LokasiPenyimpanan   NVARCHAR(600) NOT NULL,             -- path / URL file fisik
    Catatan             NVARCHAR(400) NULL,
    JumlahBidang        INT NULL,                           -- bidang kerusakan terbaca dari DWG
    JumlahTitikCogo     INT NULL,
    DiuploadOleh        INT NULL CONSTRAINT FK_FileVersi_Uploader REFERENCES dbo.Pengguna(PenggunaId),
    DiuploadPada        DATETIME2(0) NOT NULL CONSTRAINT DF_FileVersi_Upload DEFAULT (SYSDATETIME()),
    CONSTRAINT UQ_FileVersi UNIQUE (FileId, NomorVersi),
    CONSTRAINT CK_FileVersi_Nomor CHECK (NomorVersi >= 1)
);
GO

-- Hasil baca DWG (garis, bidang, teks) disimpan sebagai JSON supaya gambar tidak perlu dibaca ulang
CREATE TABLE dbo.FileVersiGeometri (
    FileVersiId     INT NOT NULL CONSTRAINT PK_FileVersiGeometri PRIMARY KEY
                    CONSTRAINT FK_FileVersiGeometri_Versi REFERENCES dbo.FileVersi(FileVersiId),
    GeometriJson    NVARCHAR(MAX) NOT NULL CONSTRAINT CK_FileVersiGeometri_Json CHECK (ISJSON(GeometriJson) = 1),
    DibuatPada      DATETIME2(0) NOT NULL CONSTRAINT DF_FileVersiGeometri_Dibuat DEFAULT (SYSDATETIME())
);
GO

/* ---------------------------------------------------------------------
   5. SPK (dari Rekap SAP / API) - dibuat sebelum Issue karena direferensikan
   --------------------------------------------------------------------- */

CREATE TABLE dbo.Spk (
    SpkId           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Spk PRIMARY KEY,
    NoSpk           NVARCHAR(20)  NOT NULL CONSTRAINT UQ_Spk_No UNIQUE,         -- mis. 4400007066
    Sumber          NVARCHAR(10)  NOT NULL CONSTRAINT CK_Spk_Sumber CHECK (Sumber IN (N'sap', N'api', N'manual')),
    TanggalSpk      DATE NULL,
    NamaPekerjaan   NVARCHAR(500) NULL,
    Jenis           NVARCHAR(10)  NOT NULL CONSTRAINT DF_Spk_Jenis DEFAULT (N'Jalan')
                    CONSTRAINT CK_Spk_Jenis CHECK (Jenis IN (N'Jalan', N'Saluran', N'Lainnya')),
    NilaiDpp        DECIMAL(18,2) NULL,
    NilaiPpn        DECIMAL(18,2) NULL,
    Vendor          NVARCHAR(150) NULL,
    Wbs             NVARCHAR(60)  NULL,
    WbsTahun        INT NULL,
    Area            NVARCHAR(50)  NULL,
    TanggalMulai    DATE NULL,                  -- tanggal pelaksanaan (dipakai untuk SPK otomatis per tanggal)
    TanggalSelesai  DATE NULL,
    Pelaksanaan     NVARCHAR(200) NULL,         -- teks asli dari SAP
    DiperbaruiPada  DATETIME2(0) NOT NULL CONSTRAINT DF_Spk_Diperbarui DEFAULT (SYSDATETIME())
);
GO

-- Ruas yang dikerjakan oleh satu SPK (bisa lebih dari satu)
CREATE TABLE dbo.SpkRuas (
    SpkId           INT NOT NULL CONSTRAINT FK_SpkRuas_Spk REFERENCES dbo.Spk(SpkId),
    RuasId          INT NOT NULL CONSTRAINT FK_SpkRuas_Ruas REFERENCES dbo.Ruas(RuasId),
    Otomatis        BIT NOT NULL CONSTRAINT DF_SpkRuas_Otomatis DEFAULT (1),   -- 1 = terdeteksi dari nama pekerjaan
    CONSTRAINT PK_SpkRuas PRIMARY KEY (SpkId, RuasId)
);
GO

/* ---------------------------------------------------------------------
   6. ZONA KERUSAKAN BERULANG (ditentukan user)
   --------------------------------------------------------------------- */

CREATE TABLE dbo.Zona (
    ZonaId          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Zona PRIMARY KEY,
    RuasId          INT NOT NULL CONSTRAINT FK_Zona_Ruas REFERENCES dbo.Ruas(RuasId),
    KodeZona        NVARCHAR(10) NOT NULL,                                   -- Z-01, Z-02, ...
    DibuatOleh      INT NULL CONSTRAINT FK_Zona_DibuatOleh REFERENCES dbo.Pengguna(PenggunaId),
    DibuatPada      DATETIME2(0) NOT NULL CONSTRAINT DF_Zona_Dibuat DEFAULT (SYSDATETIME()),
    CONSTRAINT UQ_Zona UNIQUE (RuasId, KodeZona)
);
GO

/* ---------------------------------------------------------------------
   7. ISSUE (titik kerusakan)
   --------------------------------------------------------------------- */

CREATE TABLE dbo.Issue (
    IssueId             INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Issue PRIMARY KEY,
    AppKey              NVARCHAR(60)  NULL,                 -- id dari aplikasi (dipakai saat migrasi dari backup .json)
    RuasId              INT NOT NULL CONSTRAINT FK_Issue_Ruas REFERENCES dbo.Ruas(RuasId),
    NomorIssue          INT NOT NULL,                       -- #1, #2, ... per ruas
    KodeKerusakan       NVARCHAR(20)  NOT NULL,             -- R1, S12, B3 (unik per ruas)
    Title               NVARCHAR(200) NOT NULL,
    Status              NVARCHAR(20)  NOT NULL CONSTRAINT DF_Issue_Status DEFAULT (N'Open')
                        CONSTRAINT CK_Issue_Status CHECK (Status IN (
                            N'Open', N'In progress', N'In review', N'Closed',                 -- status yang dipakai sekarang
                            N'Dilaporkan', N'Terukur', N'Divalidasi', N'Diusulkan',          -- status workflow (tahap berikutnya)
                            N'Disetujui', N'Ditolak', N'Pelaksanaan', N'Pemeriksaan')),
    TypeId              INT NOT NULL CONSTRAINT FK_Issue_Type REFERENCES dbo.TypeKerusakan(TypeId),
    RootCauseId         INT NULL CONSTRAINT FK_Issue_RootCause REFERENCES dbo.RootCause(RootCauseId),
    Deskripsi           NVARCHAR(MAX) NULL,
    DetailLokasi        NVARCHAR(400) NULL,
    AssignedToId        INT NULL CONSTRAINT FK_Issue_Assigned REFERENCES dbo.Pengguna(PenggunaId),
    AssignedToNama      NVARCHAR(150) NULL,                 -- nama bebas (selama belum semua orang punya akun)
    StartDate           DATE NULL,
    DueDate             DATE NULL,
    CloseDate           DATE NULL,                          -- terisi saat status Closed
    Darurat             BIT NOT NULL CONSTRAINT DF_Issue_Darurat DEFAULT (0),
    Sumber              NVARCHAR(10)  NOT NULL CONSTRAINT CK_Issue_Sumber CHECK (Sumber IN (N'dwg', N'pin', N'forma')),
    -- penempatan di gambar
    FileId              INT NULL CONSTRAINT FK_Issue_File REFERENCES dbo.FileDokumen(FileId),
    VersiPertama        INT NULL,                           -- muncul pertama di versi DWG ke-
    VersiTerakhir       INT NULL,                           -- terakhir terlihat di versi ke-
    TidakAdaDiVersi     INT NULL,                           -- bidangnya tidak ada lagi mulai versi ke-
    UtmX                DECIMAL(12,3) NULL,                 -- koordinat UTM 48S (posisi pin terbaru)
    UtmY                DECIMAL(12,3) NULL,
    Lat                 DECIMAL(10,7) NULL,
    Lon                 DECIMAL(10,7) NULL,
    -- data dari API eksternal (luas, company, No SPK)
    LuasApi             DECIMAL(12,3) NULL,
    CompanyApi          NVARCHAR(100) NULL,
    NoSpkApi            NVARCHAR(20)  NULL,
    ApiDiperbaruiPada   DATETIME2(0)  NULL,
    -- zona kerusakan berulang (ditentukan user)
    ZonaId              INT NULL CONSTRAINT FK_Issue_Zona REFERENCES dbo.Zona(ZonaId),
    FormaKey            NVARCHAR(150) NULL,                 -- kalau terhubung ke issue Forma
    DibuatOleh          INT NULL CONSTRAINT FK_Issue_DibuatOleh REFERENCES dbo.Pengguna(PenggunaId),
    DibuatPada          DATETIME2(0) NOT NULL CONSTRAINT DF_Issue_Dibuat DEFAULT (SYSDATETIME()),
    DiubahOleh          INT NULL CONSTRAINT FK_Issue_DiubahOleh REFERENCES dbo.Pengguna(PenggunaId),
    DiubahPada          DATETIME2(0) NULL,
    CONSTRAINT UQ_Issue_Kode UNIQUE (RuasId, KodeKerusakan),
    CONSTRAINT UQ_Issue_Nomor UNIQUE (RuasId, NomorIssue),
    CONSTRAINT CK_Issue_Tanggal CHECK (DueDate IS NULL OR StartDate IS NULL OR DueDate >= StartDate)
);
GO
CREATE UNIQUE INDEX UX_Issue_AppKey ON dbo.Issue(AppKey) WHERE AppKey IS NOT NULL;
CREATE INDEX IX_Issue_Status ON dbo.Issue(Status);
CREATE INDEX IX_Issue_Ruas_Tanggal ON dbo.Issue(RuasId, StartDate, DueDate);   -- untuk aturan SPK otomatis per tanggal
CREATE INDEX IX_Issue_Zona ON dbo.Issue(ZonaId);
GO

-- Posisi & bentuk bidang issue di setiap versi DWG
CREATE TABLE dbo.IssueVersi (
    IssueId         INT NOT NULL CONSTRAINT FK_IssueVersi_Issue REFERENCES dbo.Issue(IssueId),
    NomorVersi      INT NOT NULL,
    UtmX            DECIMAL(12,3) NOT NULL,
    UtmY            DECIMAL(12,3) NOT NULL,
    Kategori        NVARCHAR(20)  NULL,                     -- kategori bidang di gambar versi itu
    LuasBidangM2    DECIMAL(12,3) NULL,                     -- luas bidang di gambar (info; luas resmi dari API)
    PoligonJson     NVARCHAR(MAX) NULL CONSTRAINT CK_IssueVersi_Json CHECK (PoligonJson IS NULL OR ISJSON(PoligonJson) = 1),
    CONSTRAINT PK_IssueVersi PRIMARY KEY (IssueId, NomorVersi)
);
GO

-- Activity log tiap issue
CREATE TABLE dbo.IssueLog (
    IssueLogId      BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_IssueLog PRIMARY KEY,
    IssueId         INT NOT NULL CONSTRAINT FK_IssueLog_Issue REFERENCES dbo.Issue(IssueId),
    Waktu           DATETIME2(0) NOT NULL CONSTRAINT DF_IssueLog_Waktu DEFAULT (SYSDATETIME()),
    PenggunaId      INT NULL CONSTRAINT FK_IssueLog_Pengguna REFERENCES dbo.Pengguna(PenggunaId),
    Teks            NVARCHAR(1000) NOT NULL
);
GO
CREATE INDEX IX_IssueLog_Issue ON dbo.IssueLog(IssueId, Waktu);
GO

-- Foto / lampiran issue (file fisik di penyimpanan file)
CREATE TABLE dbo.Lampiran (
    LampiranId          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Lampiran PRIMARY KEY,
    IssueId             INT NOT NULL CONSTRAINT FK_Lampiran_Issue REFERENCES dbo.Issue(IssueId),
    NamaFile            NVARCHAR(260) NOT NULL,
    TipeMime            NVARCHAR(100) NULL,
    UkuranByte          BIGINT NULL,
    LokasiPenyimpanan   NVARCHAR(600) NOT NULL,
    DiuploadOleh        INT NULL CONSTRAINT FK_Lampiran_Uploader REFERENCES dbo.Pengguna(PenggunaId),
    DiuploadPada        DATETIME2(0) NOT NULL CONSTRAINT DF_Lampiran_Upload DEFAULT (SYSDATETIME())
);
GO

-- Saran zona yang sudah ditolak user ("Bukan"), supaya tidak muncul lagi
CREATE TABLE dbo.SaranZonaDitolak (
    IssueIdA        INT NOT NULL CONSTRAINT FK_SaranTolak_A REFERENCES dbo.Issue(IssueId),
    IssueIdB        INT NOT NULL CONSTRAINT FK_SaranTolak_B REFERENCES dbo.Issue(IssueId),
    DitolakOleh     INT NULL CONSTRAINT FK_SaranTolak_Pengguna REFERENCES dbo.Pengguna(PenggunaId),
    DitolakPada     DATETIME2(0) NOT NULL CONSTRAINT DF_SaranTolak_Waktu DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_SaranZonaDitolak PRIMARY KEY (IssueIdA, IssueIdB),
    CONSTRAINT CK_SaranZonaDitolak_Urut CHECK (IssueIdA < IssueIdB)   -- simpan sekali per pasangan
);
GO

-- Hubungan issue <-> SPK yang ditetapkan (dari Forma, API, atau manual).
-- SPK otomatis per tanggal (start & due date sama) dihitung oleh aplikasi, tidak perlu disimpan di sini.
CREATE TABLE dbo.IssueSpk (
    IssueId         INT NOT NULL CONSTRAINT PK_IssueSpk PRIMARY KEY
                    CONSTRAINT FK_IssueSpk_Issue REFERENCES dbo.Issue(IssueId),
    SpkId           INT NOT NULL CONSTRAINT FK_IssueSpk_Spk REFERENCES dbo.Spk(SpkId),
    Sumber          NVARCHAR(10) NOT NULL CONSTRAINT CK_IssueSpk_Sumber CHECK (Sumber IN (N'forma', N'api', N'manual')),
    DitetapkanOleh  INT NULL CONSTRAINT FK_IssueSpk_Pengguna REFERENCES dbo.Pengguna(PenggunaId),
    DitetapkanPada  DATETIME2(0) NOT NULL CONSTRAINT DF_IssueSpk_Waktu DEFAULT (SYSDATETIME())
);
GO

/* ---------------------------------------------------------------------
   8. PAKET USULAN & APPROVAL (tahap 3-4 workflow)
   --------------------------------------------------------------------- */

CREATE TABLE dbo.PaketUsulan (
    PaketId         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PaketUsulan PRIMARY KEY,
    RuasId          INT NOT NULL CONSTRAINT FK_Paket_Ruas REFERENCES dbo.Ruas(RuasId),
    Judul           NVARCHAR(200) NOT NULL,
    StartDate       DATE NULL,
    DueDate         DATE NULL,
    EstimasiBiaya   DECIMAL(18,2) NULL,             -- luas x tarif MOU
    Darurat         BIT NOT NULL CONSTRAINT DF_Paket_Darurat DEFAULT (0),
    Status          NVARCHAR(12) NOT NULL CONSTRAINT DF_Paket_Status DEFAULT (N'Draft')
                    CONSTRAINT CK_Paket_Status CHECK (Status IN (N'Draft', N'Diajukan', N'Disetujui', N'Ditolak', N'Dibatalkan')),
    SpkId           INT NULL CONSTRAINT FK_Paket_Spk REFERENCES dbo.Spk(SpkId),     -- SPK yang terbit untuk paket ini
    DibuatOleh      INT NULL CONSTRAINT FK_Paket_DibuatOleh REFERENCES dbo.Pengguna(PenggunaId),
    DibuatPada      DATETIME2(0) NOT NULL CONSTRAINT DF_Paket_Dibuat DEFAULT (SYSDATETIME()),
    DiajukanPada    DATETIME2(0) NULL
);
GO

CREATE TABLE dbo.PaketItem (
    PaketId         INT NOT NULL CONSTRAINT FK_PaketItem_Paket REFERENCES dbo.PaketUsulan(PaketId),
    IssueId         INT NOT NULL CONSTRAINT FK_PaketItem_Issue REFERENCES dbo.Issue(IssueId),
    CONSTRAINT PK_PaketItem PRIMARY KEY (PaketId, IssueId)
);
GO

CREATE TABLE dbo.Approval (
    ApprovalId      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Approval PRIMARY KEY,
    PaketId         INT NOT NULL CONSTRAINT FK_Approval_Paket REFERENCES dbo.PaketUsulan(PaketId),
    Tingkat         NVARCHAR(20) NOT NULL CONSTRAINT CK_Approval_Tingkat CHECK (Tingkat IN (N'DEPT_HEAD', N'DIV_HEAD')),
    PenggunaId      INT NOT NULL CONSTRAINT FK_Approval_Pengguna REFERENCES dbo.Pengguna(PenggunaId),
    Keputusan       NVARCHAR(10) NOT NULL CONSTRAINT CK_Approval_Keputusan CHECK (Keputusan IN (N'Disetujui', N'Ditolak')),
    Catatan         NVARCHAR(1000) NULL,             -- wajib diisi kalau ditolak (dicek di API)
    Waktu           DATETIME2(0) NOT NULL CONSTRAINT DF_Approval_Waktu DEFAULT (SYSDATETIME())
);
GO
CREATE INDEX IX_Approval_Paket ON dbo.Approval(PaketId);
GO

/* ---------------------------------------------------------------------
   9. AUDIT LOG (siapa melakukan apa, untuk semua tabel penting)
   --------------------------------------------------------------------- */

CREATE TABLE dbo.AuditLog (
    AuditId         BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AuditLog PRIMARY KEY,
    Waktu           DATETIME2(0) NOT NULL CONSTRAINT DF_AuditLog_Waktu DEFAULT (SYSDATETIME()),
    PenggunaId      INT NULL CONSTRAINT FK_AuditLog_Pengguna REFERENCES dbo.Pengguna(PenggunaId),
    Aksi            NVARCHAR(30)  NOT NULL,          -- login, create, update, delete, approve, ...
    NamaTabel       NVARCHAR(60)  NULL,
    KunciData       NVARCHAR(100) NULL,
    DetailJson      NVARCHAR(MAX) NULL CONSTRAINT CK_AuditLog_Json CHECK (DetailJson IS NULL OR ISJSON(DetailJson) = 1),
    AlamatIp        NVARCHAR(64)  NULL
);
GO
CREATE INDEX IX_AuditLog_Waktu ON dbo.AuditLog(Waktu);
GO

/* ---------------------------------------------------------------------
   10. VIEW untuk laporan / Power BI
   --------------------------------------------------------------------- */

CREATE VIEW dbo.vIssue AS
SELECT  i.IssueId, r.KodeRuas, r.NamaRuas, r.NamaJalan, r.Area,
        i.NomorIssue, i.KodeKerusakan, i.Title, i.Status,
        kt.Nama AS KategoriType, t.Nama AS TypeKerusakan, t.Kode AS KodeType,
        rc.Nama AS RootCause,
        COALESCE(p.NamaLengkap, i.AssignedToNama) AS AssignedTo,
        i.StartDate, i.DueDate, i.CloseDate, i.Darurat,
        i.LuasApi AS Luas, i.CompanyApi AS Company,
        COALESCE(s.NoSpk, i.NoSpkApi) AS NoSpk,
        z.KodeZona,
        i.VersiPertama, i.VersiTerakhir, i.TidakAdaDiVersi,
        i.Lat, i.Lon, i.Sumber,
        CASE WHEN i.Status <> N'Closed' AND i.DueDate < CAST(SYSDATETIME() AS DATE) THEN 1 ELSE 0 END AS Overdue,
        CAST(t.TarifMouPerM2 * i.LuasApi AS DECIMAL(18,2)) AS EstimasiBiaya,
        i.DibuatPada, i.DiubahPada
FROM    dbo.Issue i
JOIN    dbo.Ruas r            ON r.RuasId = i.RuasId
JOIN    dbo.TypeKerusakan t   ON t.TypeId = i.TypeId
JOIN    dbo.KategoriType kt   ON kt.KategoriTypeId = t.KategoriTypeId
LEFT JOIN dbo.RootCause rc    ON rc.RootCauseId = i.RootCauseId
LEFT JOIN dbo.Pengguna p      ON p.PenggunaId = i.AssignedToId
LEFT JOIN dbo.IssueSpk isk    ON isk.IssueId = i.IssueId
LEFT JOIN dbo.Spk s           ON s.SpkId = isk.SpkId
LEFT JOIN dbo.Zona z          ON z.ZonaId = i.ZonaId;
GO

-- Rekap per zona berulang: berapa kali satu lokasi rusak
CREATE VIEW dbo.vZonaBerulang AS
SELECT  z.ZonaId, r.NamaRuas, z.KodeZona,
        COUNT(i.IssueId)            AS JumlahKejadian,
        MIN(i.StartDate)            AS KejadianPertama,
        MAX(i.StartDate)            AS KejadianTerakhir,
        SUM(CASE WHEN i.Status = N'Closed' THEN 1 ELSE 0 END) AS SudahDiperbaiki
FROM    dbo.Zona z
JOIN    dbo.Ruas r   ON r.RuasId = z.RuasId
LEFT JOIN dbo.Issue i ON i.ZonaId = z.ZonaId
GROUP BY z.ZonaId, r.NamaRuas, z.KodeZona;
GO

-- Hak akses efektif per pengguna (dipakai API saat login)
CREATE VIEW dbo.vHakAksesPengguna AS
SELECT DISTINCT pg.PenggunaId, pg.Username, h.Kode AS HakAkses
FROM   dbo.Pengguna pg
JOIN   dbo.PenggunaPeran pp   ON pp.PenggunaId = pg.PenggunaId
JOIN   dbo.PeranHakAkses ph   ON ph.PeranId = pp.PeranId
JOIN   dbo.HakAkses h         ON h.HakAksesId = ph.HakAksesId
WHERE  pg.Aktif = 1;
GO

PRINT N'Skema Damage Road selesai dibuat.';
GO
SET NOEXEC OFF;
GO
