/* =====================================================================
   DAMAGE ROAD - CEK ISI DATABASE (aman dijalankan kapan saja, tidak mengubah apa pun)
   Hasil yang diharapkan ada di kolom "Seharusnya".
   ===================================================================== */
SET NOCOUNT ON;
SELECT N'Jumlah tabel' AS Cek, COUNT(*) AS Hasil, 28 AS Seharusnya FROM sys.tables WHERE schema_id = SCHEMA_ID(N'dbo')
UNION ALL SELECT N'Jumlah view',            COUNT(*), 3  FROM sys.views WHERE schema_id = SCHEMA_ID(N'dbo')
UNION ALL SELECT N'Peran',                  COUNT(*), 7  FROM dbo.Peran
UNION ALL SELECT N'Hak akses',              COUNT(*), 22 FROM dbo.HakAkses
UNION ALL SELECT N'Peran -> hak akses',     COUNT(*), 60 FROM dbo.PeranHakAkses
UNION ALL SELECT N'Type kerusakan (R/S/B)', COUNT(*), 3  FROM dbo.TypeKerusakan
UNION ALL SELECT N'Root cause',             COUNT(*), 10 FROM dbo.RootCause
UNION ALL SELECT N'Pengaturan',             COUNT(*), 6  FROM dbo.Pengaturan
UNION ALL SELECT N'Pengguna',               COUNT(*), 1  FROM dbo.Pengguna;
