import { existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const migrationsDir = join(process.cwd(), 'supabase', 'migrations');

if (!existsSync(migrationsDir)) {
  console.log('No supabase/migrations directory yet; remote baseline is still pending.');
  process.exit(0);
}

const files = readdirSync(migrationsDir)
  .filter((file) => file.endsWith('.sql'))
  .sort((left, right) => left.localeCompare(right));
const filenamePattern = /^(\d{14})_[a-z0-9_]+\.sql$/;
const versions = new Set();

for (const file of files) {
  const match = filenamePattern.exec(file);
  if (!match) throw new Error(`Invalid migration filename: ${file}`);
  if (versions.has(match[1])) throw new Error(`Duplicate migration version: ${match[1]}`);
  versions.add(match[1]);
}

console.log(`Validated ${files.length} migration file(s) in timestamp order.`);
