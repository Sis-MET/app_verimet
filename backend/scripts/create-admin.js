'use strict';

const crypto = require('node:crypto');
const readline = require('node:readline/promises');
const bcrypt = require('bcrypt');
const dotenv = require('dotenv');
const sql = require('mssql');

dotenv.config();

function required(name) {
  const value = process.env[name];
  if (!value) throw new Error(`Falta la variable ${name}`);
  return value;
}

function validatePassword(value) {
  return value.length >= 12 && /[a-z]/.test(value) && /[A-Z]/.test(value) && /\d/.test(value);
}

async function readSecret(prompt) {
  if (!process.stdin.isTTY || typeof process.stdin.setRawMode !== 'function') {
    const fallback = readline.createInterface({ input: process.stdin, output: process.stdout });
    try {
      return await fallback.question(prompt);
    } finally {
      fallback.close();
    }
  }
  process.stdout.write(prompt);
  process.stdin.setRawMode(true);
  process.stdin.resume();
  process.stdin.setEncoding('utf8');
  return new Promise((resolve, reject) => {
    let value = '';
    const cleanup = () => {
      process.stdin.setRawMode(false);
      process.stdin.pause();
      process.stdin.removeListener('data', onData);
      process.stdout.write('\n');
    };
    const onData = (key) => {
      if (key === '\u0003') {
        cleanup();
        reject(new Error('Operacion cancelada'));
      } else if (key === '\r' || key === '\n') {
        cleanup();
        resolve(value);
      } else if (key === '\u007f' || key === '\b') {
        value = value.slice(0, -1);
      } else {
        value += key;
      }
    };
    process.stdin.on('data', onData);
  });
}

async function main() {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const username = (await rl.question('Usuario del administrador: ')).normalize('NFKC').trim();
  const name = (await rl.question('Nombre completo: ')).trim();
  const emailValue = (await rl.question('Correo (opcional): ')).trim();
  rl.close();
  if (!username || !name) throw new Error('Usuario y nombre son obligatorios');

  const password = await readSecret('Contrasena temporal (min. 12, mayuscula, minuscula y numero): ');
  const confirmation = await readSecret('Repita la contrasena: ');
  if (password !== confirmation) throw new Error('Las contrasenas no coinciden');
  if (!validatePassword(password)) throw new Error('La contrasena no cumple la politica minima');

  const pool = await sql.connect({
    server: required('DB_HOST'),
    port: Number(process.env.DB_PORT || 1433),
    database: required('DB_NAME'),
    user: required('DB_USER'),
    password: required('DB_PASSWORD'),
    options: {
      encrypt: !['false', '0'].includes(String(process.env.DB_ENCRYPT).toLowerCase()),
      trustServerCertificate: ['true', '1'].includes(String(process.env.DB_TRUST_SERVER_CERTIFICATE).toLowerCase()),
      enableArithAbort: true,
    },
  });
  try {
    const hash = await bcrypt.hash(password, Number(process.env.BCRYPT_SALT_ROUNDS || 12));
    const id = crypto.randomUUID();
    const transaction = new sql.Transaction(pool);
    await transaction.begin();
    try {
      await transaction.request()
        .input('id', sql.UniqueIdentifier, id)
        .input('username', sql.NVarChar(100), username)
        .input('normalized', sql.NVarChar(100), username.toUpperCase())
        .input('name', sql.NVarChar(200), name)
        .input('email', sql.NVarChar(254), emailValue || null)
        .input('hash', sql.NVarChar(255), hash)
        .query(`
          INSERT INTO ivmet.usuarios
            (usuario_id, usuario, usuario_normalizado, nombre, email, password_hash,
             rol, cliente_id, estado, debe_cambiar_password)
          VALUES
            (@id, @username, @normalized, @name, @email, @hash,
             N'metrica_admin', NULL, N'ACTIVO', 1)
        `);
      await transaction.request()
        .input('id', sql.UniqueIdentifier, id)
        .input('after', sql.NVarChar(sql.MAX), JSON.stringify({ username, name, email: emailValue || null, role: 'metrica_admin' }))
        .query(`
          INSERT INTO ivmet.auditoria (actor_id,entidad,entidad_id,accion,despues_json)
          VALUES (@id,N'usuario',CONVERT(nvarchar(150),@id),N'bootstrap_admin_create',@after)
        `);
      await transaction.commit();
    } catch (error) {
      await transaction.rollback();
      throw error;
    }
    process.stdout.write(`Administrador creado: ${username} (${id}). Debe cambiar su contrasena al ingresar.\n`);
  } finally {
    await pool.close();
  }
}

main().catch((error) => {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
});
