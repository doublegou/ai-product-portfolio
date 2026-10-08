import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { workerEnv } from './shared';

const env = workerEnv();
const token = process.env.CRAWLER_TOKEN;
if (!token) throw new Error('请先在 .dev.vars 配置与采集函数一致的 CRAWLER_TOKEN');
const sqlValue = (value: string) => "'" + value.replaceAll("'", "''") + "'";
const secrets = {
  pricemapai_collector_url: `${env.SUPABASE_URL.replace(/\/$/, '')}/functions/v1/collect-prices`,
  pricemapai_collector_api_key: env.SUPABASE_SERVICE_ROLE_KEY,
  pricemapai_collector_token: token,
};
const dir = mkdtempSync(join(tmpdir(), 'pricemapai-scheduler-'));
try {
  const file = join(dir, 'configure.sql');
  const sql = Object.entries(secrets).map(([name, value]) => `
do $configure$
declare secret_id uuid;
begin
 select id into secret_id from vault.secrets where name=${sqlValue(name)};
 if secret_id is null then
   perform vault.create_secret(${sqlValue(value)}, ${sqlValue(name)});
 else
   perform vault.update_secret(secret_id, ${sqlValue(value)});
 end if;
end $configure$;`).join('\n');
  writeFileSync(file, `begin;\n${sql}\ncommit;`, { mode: 0o600 });
  const result = spawnSync('npx', ['--yes', 'supabase@2.120.0', 'db', 'query', '--linked', '--file', file], { encoding: 'utf8' });
  // SQL diagnostics may echo the statement, so redact credentials before printing.
  const redact = (text: string) => Object.values(secrets).reduce((out, value) => out.replaceAll(value, '[redacted]'), text);
  if (result.status !== 0) throw new Error(redact(result.stderr || result.stdout || 'Supabase Vault 配置失败'));
  console.log('已在当前关联 Supabase 项目的 Vault 中配置采集调度凭据，未输出任何密钥。');
} finally {
  rmSync(dir, { recursive: true, force: true });
}
