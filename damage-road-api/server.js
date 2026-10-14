// =====================================================================
// DAMAGE ROAD API - login & pengguna
// Jalankan: npm start  (pengaturan di file .env, contoh di .env.example)
// =====================================================================
require('dotenv').config();
const path = require('path');
const crypto = require('crypto');
const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const repo = require(process.env.REPO_MODULE || './repo');

const PORT = parseInt(process.env.PORT || '3000', 10);
let JWT_SECRET = process.env.JWT_SECRET;
if (!JWT_SECRET || JWT_SECRET.length < 32) {
  JWT_SECRET = crypto.randomBytes(48).toString('hex');
  console.warn('[PERINGATAN] JWT_SECRET di .env kosong/terlalu pendek. Dipakai kunci acak sementara: semua orang harus login ulang setiap API di-restart.');
}
const TOKEN_JAM = parseInt(process.env.TOKEN_JAM || '8', 10);
const LOGIN_PER_MENIT = parseInt(process.env.LOGIN_PER_MENIT || '10', 10);
const ORIGINS = (process.env.CORS_ORIGINS || 'https://yusufcahyonusantoro.github.io').split(',').map(s => s.trim()).filter(Boolean);

const app = express();
app.disable('x-powered-by');
app.use(express.json({ limit: '1mb' }));

// ---- CORS: hanya alamat aplikasi yang diizinkan (+ localhost untuk pengembangan) ----
app.use((req, res, next) => {
  // Chrome: halaman di internet (GitHub Pages) yang memanggil localhost perlu izin "jaringan lokal"
  if (req.headers['access-control-request-private-network']) res.setHeader('Access-Control-Allow-Private-Network', 'true');
  next();
});
app.use(cors({
  origin(origin, cb) {
    if (!origin) return cb(null, true);                                  // akses langsung / same-origin
    if (ORIGINS.includes(origin) || /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)) return cb(null, true);
    return cb(null, false);
  },
  methods: ['GET', 'POST', 'PUT', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));

// ---- pembatas percobaan login per alamat IP (LOGIN_PER_MENIT kali / menit, bawaan 10) ----
const hits = new Map();
function limitLogin(req, res, next) {
  const k = req.ip, now = Date.now();
  const arr = (hits.get(k) || []).filter(t => now - t < 60000);
  arr.push(now); hits.set(k, arr);
  if (arr.length > LOGIN_PER_MENIT) return res.status(429).json({ error: 'Terlalu banyak percobaan login. Tunggu 1 menit.' });
  next();
}

const isLocal = req => ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(req.socket.remoteAddress);
const wrap = fn => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

function passwordProblem(pw) {
  if (typeof pw !== 'string' || pw.length < 8) return 'Password minimal 8 karakter.';
  if (!/[A-Za-z]/.test(pw) || !/\d/.test(pw)) return 'Password harus berisi huruf dan angka.';
  return null;
}
function tempPassword() {
  // password sementara yang mudah dibacakan: 4 huruf + 4 angka (tanpa huruf/angka yang mirip)
  const L = 'ABCDEFGHJKMNPQRSTUVWXYZ', D = '23456789';
  let s = ''; for (let i = 0; i < 4; i++) s += L[crypto.randomInt(L.length)];
  for (let i = 0; i < 4; i++) s += D[crypto.randomInt(D.length)];
  return s;
}
async function userPayload(u) {
  const roles = await repo.rolesOf(u.PenggunaId);
  const perms = await repo.permsOf(u.PenggunaId);
  return {
    id: u.PenggunaId, username: u.Username, nama: u.NamaLengkap, email: u.Email, company: u.Company,
    roles: roles.map(r => r.Kode), roleNames: roles.map(r => r.Nama), perms, wajibGantiPassword: !!u.WajibGantiPassword
  };
}
function issueToken(u) { return jwt.sign({ sub: u.PenggunaId, typ: 'access' }, JWT_SECRET, { expiresIn: TOKEN_JAM + 'h' }); }

// ---- middleware: wajib login (+ hak akses tertentu) ----
function requireAuth(opts = {}) {
  return wrap(async (req, res, next) => {
    const h = req.headers.authorization || '';
    const tok = h.startsWith('Bearer ') ? h.slice(7) : null;
    if (!tok) return res.status(401).json({ error: 'Silakan login dulu.' });
    let p; try { p = jwt.verify(tok, JWT_SECRET); } catch (e) { return res.status(401).json({ error: 'Sesi login habis. Silakan login lagi.' }); }
    if (p.typ !== 'access') return res.status(401).json({ error: 'Token tidak valid.' });
    const u = await repo.userById(p.sub);
    if (!u || !u.Aktif) return res.status(401).json({ error: 'Akun tidak aktif.' });
    if (u.WajibGantiPassword && !opts.allowMustChange) return res.status(403).json({ error: 'Wajib ganti password dulu.', code: 'MUST_CHANGE_PASSWORD' });
    req.user = u;
    if (opts.perm) {
      const perms = await repo.permsOf(u.PenggunaId);
      if (!perms.includes(opts.perm)) return res.status(403).json({ error: 'Kamu tidak punya hak akses untuk ini.' });
    }
    next();
  });
}

// ============================ ROUTES ============================
app.get('/api/health', wrap(async (req, res) => {
  try { const d = await repo.ping(); res.json({ ok: true, app: 'damage-road-api', database: d.db }); }
  catch (e) { res.status(500).json({ ok: false, error: 'Database tidak bisa dihubungi: ' + e.message }); }
}));

app.post('/api/auth/login', limitLogin, wrap(async (req, res) => {
  const username = String((req.body || {}).username || '').trim();
  const password = String((req.body || {}).password || '');
  if (!username) return res.status(400).json({ error: 'Username wajib diisi.' });
  const u = await repo.userByUsername(username);
  const salah = () => res.status(401).json({ error: 'Username atau password salah.' });
  if (!u) { await repo.audit(null, 'login_gagal', 'Pengguna', username, { alasan: 'tidak ada' }, req.ip); return salah(); }
  if (!u.Aktif) return res.status(403).json({ error: 'Akun ini dinonaktifkan. Hubungi admin.' });
  if (u.TerkunciSampai && new Date(u.TerkunciSampai) > new Date()) {
    const menit = Math.ceil((new Date(u.TerkunciSampai) - new Date()) / 60000);
    return res.status(423).json({ error: 'Akun terkunci karena salah password berkali-kali. Coba lagi dalam ' + menit + ' menit.' });
  }
  if (!u.PasswordHash) {
    // password pertama hanya boleh dibuat dari komputer server (localhost) -> aman walau API bisa diakses jaringan
    if (!isLocal(req)) return res.status(403).json({ error: 'Akun ini belum punya password. Minta admin membuatkan password sementara.' });
    const setupToken = jwt.sign({ sub: u.PenggunaId, typ: 'setup' }, JWT_SECRET, { expiresIn: '15m' });
    return res.json({ needSetup: true, setupToken, nama: u.NamaLengkap });
  }
  const ok = await bcrypt.compare(password, u.PasswordHash);
  if (!ok) {
    const mx = parseInt(await repo.setting('login.maks_gagal', '5'), 10), lm = parseInt(await repo.setting('login.kunci_menit', '15'), 10);
    await repo.loginFail(u.PenggunaId, mx, lm);
    await repo.audit(u.PenggunaId, 'login_gagal', 'Pengguna', u.PenggunaId, null, req.ip);
    return salah();
  }
  await repo.loginOk(u.PenggunaId);
  await repo.audit(u.PenggunaId, 'login', 'Pengguna', u.PenggunaId, null, req.ip);
  res.json({ token: issueToken(u), user: await userPayload(u) });
}));

app.post('/api/auth/setup-password', limitLogin, wrap(async (req, res) => {
  const { setupToken, newPassword } = req.body || {};
  let p; try { p = jwt.verify(setupToken, JWT_SECRET); } catch (e) { return res.status(401).json({ error: 'Waktu pembuatan password habis. Login ulang.' }); }
  if (p.typ !== 'setup') return res.status(401).json({ error: 'Token tidak valid.' });
  const prob = passwordProblem(newPassword); if (prob) return res.status(400).json({ error: prob });
  const u = await repo.userById(p.sub);
  if (!u || u.PasswordHash) return res.status(409).json({ error: 'Password akun ini sudah pernah dibuat.' });
  await repo.setPassword(u.PenggunaId, await bcrypt.hash(newPassword, 10), false);
  await repo.audit(u.PenggunaId, 'buat_password', 'Pengguna', u.PenggunaId, null, req.ip);
  const fresh = await repo.userById(u.PenggunaId);
  await repo.loginOk(u.PenggunaId);
  res.json({ token: issueToken(fresh), user: await userPayload(fresh) });
}));

app.get('/api/auth/me', requireAuth({ allowMustChange: true }), wrap(async (req, res) => {
  res.json({ user: await userPayload(req.user) });
}));

app.post('/api/auth/change-password', requireAuth({ allowMustChange: true }), wrap(async (req, res) => {
  const { oldPassword, newPassword } = req.body || {};
  if (!req.user.PasswordHash || !(await bcrypt.compare(String(oldPassword || ''), req.user.PasswordHash))) return res.status(400).json({ error: 'Password lama salah.' });
  const prob = passwordProblem(newPassword); if (prob) return res.status(400).json({ error: prob });
  if (oldPassword === newPassword) return res.status(400).json({ error: 'Password baru harus berbeda dari password lama.' });
  await repo.setPassword(req.user.PenggunaId, await bcrypt.hash(newPassword, 10), false);
  await repo.audit(req.user.PenggunaId, 'ganti_password', 'Pengguna', req.user.PenggunaId, null, req.ip);
  const fresh = await repo.userById(req.user.PenggunaId);
  res.json({ ok: true, token: issueToken(fresh), user: await userPayload(fresh) });
}));

// ---- kelola pengguna (hak akses user.manage) ----
app.get('/api/roles', requireAuth({ perm: 'user.manage' }), wrap(async (req, res) => res.json({ roles: await repo.listRoles() })));
app.get('/api/users', requireAuth({ perm: 'user.manage' }), wrap(async (req, res) => res.json({ users: await repo.listUsers() })));

app.post('/api/users', requireAuth({ perm: 'user.manage' }), wrap(async (req, res) => {
  const b = req.body || {};
  const username = String(b.username || '').trim().toLowerCase();
  if (!/^[a-z0-9._-]{3,50}$/.test(username)) return res.status(400).json({ error: 'Username 3-50 karakter: huruf kecil, angka, titik, minus, garis bawah.' });
  if (!String(b.nama || '').trim()) return res.status(400).json({ error: 'Nama lengkap wajib diisi.' });
  const roles = Array.isArray(b.roles) ? b.roles : [];
  if (!roles.length) return res.status(400).json({ error: 'Pilih minimal satu peran.' });
  if (await repo.userByUsername(username)) return res.status(409).json({ error: 'Username sudah dipakai.' });
  const id = await repo.createUser({ username, nama: String(b.nama).trim(), email: b.email, company: b.company });
  await repo.setRoles(id, roles);
  const temp = tempPassword();
  await repo.setPassword(id, await bcrypt.hash(temp, 10), true);
  await repo.audit(req.user.PenggunaId, 'buat_pengguna', 'Pengguna', id, { username, roles }, req.ip);
  res.status(201).json({ id, tempPassword: temp });
}));

app.put('/api/users/:id', requireAuth({ perm: 'user.manage' }), wrap(async (req, res) => {
  const id = parseInt(req.params.id, 10), b = req.body || {};
  const u = await repo.userById(id); if (!u) return res.status(404).json({ error: 'Pengguna tidak ditemukan.' });
  const roles = Array.isArray(b.roles) ? b.roles : null;
  const aktif = b.aktif !== false;
  const willBeAdmin = roles ? roles.includes('ADMIN') : (await repo.rolesOf(id)).some(r => r.Kode === 'ADMIN');
  if ((!aktif || !willBeAdmin) && (await repo.countActiveAdmins(id)) === 0) return res.status(400).json({ error: 'Harus tetap ada minimal satu admin aktif.' });
  if (id === req.user.PenggunaId && !aktif) return res.status(400).json({ error: 'Tidak bisa menonaktifkan akun sendiri.' });
  await repo.updateUser(id, { nama: String(b.nama || u.NamaLengkap).trim(), email: b.email, company: b.company, aktif });
  if (roles) { if (!roles.length) return res.status(400).json({ error: 'Pilih minimal satu peran.' }); await repo.setRoles(id, roles); }
  await repo.audit(req.user.PenggunaId, 'ubah_pengguna', 'Pengguna', id, { roles, aktif }, req.ip);
  res.json({ ok: true });
}));

app.post('/api/users/:id/reset-password', requireAuth({ perm: 'user.manage' }), wrap(async (req, res) => {
  const id = parseInt(req.params.id, 10);
  const u = await repo.userById(id); if (!u) return res.status(404).json({ error: 'Pengguna tidak ditemukan.' });
  const temp = tempPassword();
  await repo.setPassword(id, await bcrypt.hash(temp, 10), true);
  await repo.audit(req.user.PenggunaId, 'reset_password', 'Pengguna', id, null, req.ip);
  res.json({ ok: true, tempPassword: temp });
}));

// ---- aplikasi Damage Road (index.html) disajikan dari folder public ----
app.use(express.static(path.join(__dirname, 'public'), { extensions: ['html'] }));

// ---- penanganan error ----
app.use('/api', (req, res) => res.status(404).json({ error: 'Alamat API tidak ditemukan.' }));
app.use((err, req, res, next) => {
  console.error('[ERROR]', err);
  res.status(500).json({ error: /ConnectionError|ESOCKET|ELOGIN|ETIMEOUT/.test(String(err && (err.code || err.name))) ? 'Database tidak bisa dihubungi. Cek SQL Server & pengaturan .env.' : 'Terjadi kesalahan di server.' });
});

if (require.main === module) {
  app.listen(PORT, () => {
    console.log('Damage Road API berjalan di http://localhost:' + PORT);
    console.log('Buka aplikasi: http://localhost:' + PORT + '/');
    repo.ping().then(d => console.log('Database tersambung:', d.db)).catch(e => console.error('[!] Database belum tersambung:', e.message));
  });
}
module.exports = app;
