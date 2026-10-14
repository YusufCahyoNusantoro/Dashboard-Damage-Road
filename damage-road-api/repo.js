// =====================================================================
// Akses database SQL Server untuk login & pengguna.
// Semua query memakai parameter (@nama) -> aman dari SQL injection.
// =====================================================================
const sql = require('mssql');

let poolPromise = null;
function pool() {
  if (!poolPromise) {
    const cfg = {
      server: process.env.DB_SERVER || 'localhost',
      port: parseInt(process.env.DB_PORT || '1433', 10),
      database: process.env.DB_NAME || 'DamageRoad',
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
      options: { encrypt: true, trustServerCertificate: true },
      pool: { max: 10, min: 0, idleTimeoutMillis: 30000 }
    };
    if (process.env.DB_INSTANCE) { cfg.options.instanceName = process.env.DB_INSTANCE; delete cfg.port; }
    poolPromise = new sql.ConnectionPool(cfg).connect().catch(err => { poolPromise = null; throw err; });
  }
  return poolPromise;
}
async function q(text, params = {}) {
  const p = await pool();
  const r = p.request();
  for (const [k, v] of Object.entries(params)) r.input(k, v);
  return r.query(text);
}

module.exports = {
  async ping() { const r = await q('SELECT DB_NAME() AS db, @@VERSION AS versi'); return r.recordset[0]; },

  async setting(key, def) {
    const r = await q('SELECT Nilai FROM dbo.Pengaturan WHERE Kunci = @k', { k: key });
    const v = r.recordset[0] && r.recordset[0].Nilai;
    return v == null || v === '' ? def : v;
  },

  async userByUsername(username) {
    const r = await q(`SELECT PenggunaId, Username, NamaLengkap, Email, Company, PasswordHash, Aktif, WajibGantiPassword,
                              GagalLogin, TerkunciSampai, LoginTerakhir
                       FROM dbo.Pengguna WHERE Username = @u`, { u: username });
    return r.recordset[0] || null;
  },
  async userById(id) {
    const r = await q(`SELECT PenggunaId, Username, NamaLengkap, Email, Company, PasswordHash, Aktif, WajibGantiPassword,
                              GagalLogin, TerkunciSampai, LoginTerakhir
                       FROM dbo.Pengguna WHERE PenggunaId = @id`, { id });
    return r.recordset[0] || null;
  },
  async rolesOf(id) {
    const r = await q(`SELECT p.Kode, p.Nama FROM dbo.PenggunaPeran pp JOIN dbo.Peran p ON p.PeranId = pp.PeranId
                       WHERE pp.PenggunaId = @id ORDER BY p.PeranId`, { id });
    return r.recordset;
  },
  async permsOf(id) {
    const r = await q('SELECT HakAkses FROM dbo.vHakAksesPengguna WHERE PenggunaId = @id', { id });
    return r.recordset.map(x => x.HakAkses);
  },
  async loginOk(id) {
    await q('UPDATE dbo.Pengguna SET GagalLogin = 0, TerkunciSampai = NULL, LoginTerakhir = SYSDATETIME() WHERE PenggunaId = @id', { id });
  },
  // tambah hitungan gagal; kunci akun kalau melewati batas
  async loginFail(id, maxFail, lockMin) {
    await q(`UPDATE dbo.Pengguna
             SET GagalLogin = GagalLogin + 1,
                 TerkunciSampai = CASE WHEN GagalLogin + 1 >= @mx THEN DATEADD(MINUTE, @lm, SYSDATETIME()) ELSE TerkunciSampai END
             WHERE PenggunaId = @id`, { id, mx: maxFail, lm: lockMin });
  },
  async setPassword(id, hash, mustChange) {
    await q(`UPDATE dbo.Pengguna SET PasswordHash = @h, WajibGantiPassword = @w, GagalLogin = 0, TerkunciSampai = NULL, DiubahPada = SYSDATETIME()
             WHERE PenggunaId = @id`, { id, h: hash, w: mustChange ? 1 : 0 });
  },

  async listUsers() {
    const r = await q(`SELECT pg.PenggunaId, pg.Username, pg.NamaLengkap, pg.Email, pg.Company, pg.Aktif, pg.WajibGantiPassword,
                              CASE WHEN pg.PasswordHash IS NULL THEN 0 ELSE 1 END AS PunyaPassword,
                              pg.TerkunciSampai, pg.LoginTerakhir,
                              STRING_AGG(p.Kode, ',') WITHIN GROUP (ORDER BY p.PeranId) AS Peran
                       FROM dbo.Pengguna pg
                       LEFT JOIN dbo.PenggunaPeran pp ON pp.PenggunaId = pg.PenggunaId
                       LEFT JOIN dbo.Peran p ON p.PeranId = pp.PeranId
                       GROUP BY pg.PenggunaId, pg.Username, pg.NamaLengkap, pg.Email, pg.Company, pg.Aktif, pg.WajibGantiPassword,
                                pg.PasswordHash, pg.TerkunciSampai, pg.LoginTerakhir
                       ORDER BY pg.NamaLengkap`);
    return r.recordset.map(u => ({ ...u, Peran: u.Peran ? u.Peran.split(',') : [] }));
  },
  async listRoles() {
    const r = await q('SELECT Kode, Nama, Keterangan FROM dbo.Peran ORDER BY PeranId');
    return r.recordset;
  },
  async createUser(u) {
    const r = await q(`INSERT INTO dbo.Pengguna (Username, NamaLengkap, Email, Company, PasswordHash, WajibGantiPassword)
                       OUTPUT INSERTED.PenggunaId VALUES (@u, @n, @e, @c, NULL, 1)`,
      { u: u.username, n: u.nama, e: u.email || null, c: u.company || null });
    return r.recordset[0].PenggunaId;
  },
  async updateUser(id, u) {
    await q(`UPDATE dbo.Pengguna SET NamaLengkap = @n, Email = @e, Company = @c, Aktif = @a, DiubahPada = SYSDATETIME()
             WHERE PenggunaId = @id`, { id, n: u.nama, e: u.email || null, c: u.company || null, a: u.aktif ? 1 : 0 });
  },
  async setRoles(id, kodeList) {
    const p = await pool();
    const tx = new sql.Transaction(p);
    await tx.begin();
    try {
      await new sql.Request(tx).input('id', id).query('DELETE FROM dbo.PenggunaPeran WHERE PenggunaId = @id');
      for (const k of kodeList) {
        await new sql.Request(tx).input('id', id).input('k', k)
          .query('INSERT INTO dbo.PenggunaPeran (PenggunaId, PeranId) SELECT @id, PeranId FROM dbo.Peran WHERE Kode = @k');
      }
      await tx.commit();
    } catch (e) { await tx.rollback(); throw e; }
  },
  async resetPassword(id) {
    await q('UPDATE dbo.Pengguna SET PasswordHash = NULL, WajibGantiPassword = 1, GagalLogin = 0, TerkunciSampai = NULL WHERE PenggunaId = @id', { id });
  },
  async countActiveAdmins(exceptId) {
    const r = await q(`SELECT COUNT(DISTINCT pg.PenggunaId) AS n FROM dbo.Pengguna pg
                       JOIN dbo.PenggunaPeran pp ON pp.PenggunaId = pg.PenggunaId JOIN dbo.Peran p ON p.PeranId = pp.PeranId
                       WHERE p.Kode = N'ADMIN' AND pg.Aktif = 1 AND pg.PenggunaId <> @x`, { x: exceptId || 0 });
    return r.recordset[0].n;
  },

  async audit(userId, aksi, tabel, kunci, detail, ip) {
    await q(`INSERT INTO dbo.AuditLog (PenggunaId, Aksi, NamaTabel, KunciData, DetailJson, AlamatIp)
             VALUES (@u, @a, @t, @k, @d, @ip)`,
      { u: userId || null, a: aksi, t: tabel || null, k: kunci != null ? String(kunci) : null, d: detail ? JSON.stringify(detail) : null, ip: ip || null });
  }
};
