/* =====================================================================
   DAMAGE ROAD - AKUN DATABASE UNTUK API
   API (program penghubung) masuk ke database memakai akun khusus ini,
   bukan akun Windows-mu. Hak aksesnya dibatasi: baca, tulis, jalankan.

   SEBELUM menjalankan:
   1. Ganti  GANTI_PASSWORD_INI  di bawah dengan password yang kuat
      (min. 8 karakter, huruf besar + kecil + angka), lalu catat.
      Password yang sama nanti diisi di file .env (DB_PASSWORD).
   2. Jangan simpan file ini ke GitHub setelah password diisi.
   ===================================================================== */
USE master;
GO
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'damageroad_api')
    CREATE LOGIN damageroad_api WITH PASSWORD = N'GANTI_PASSWORD_INI', CHECK_POLICY = ON, DEFAULT_DATABASE = DamageRoad;
GO
USE DamageRoad;
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'damageroad_api')
    CREATE USER damageroad_api FOR LOGIN damageroad_api;
GO
ALTER ROLE db_datareader ADD MEMBER damageroad_api;
ALTER ROLE db_datawriter ADD MEMBER damageroad_api;
GRANT EXECUTE TO damageroad_api;
GO
PRINT N'Akun database damageroad_api siap dipakai API.';
GO
