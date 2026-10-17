import { readSources, workerEnv, clientFor } from "./shared";

try {
  const rows = readSources();
  if (!process.argv.includes("--write")) {
    console.log(`已检查 ${rows.length} 家原站来源。未连接数据库；添加 --write 才会导入。`);
  } else {
    const client = clientFor(workerEnv());
    const { error } = await client.from("sources").upsert(rows, { onConflict: "base_url" });
    if (error) throw new Error(error.message);
    console.log(`已导入 ${rows.length} 家原站来源；保留已有来源 ID，不写入价格或库存。`);
  }
} catch (error) {
  console.error(error instanceof Error ? error.message : "来源导入失败");
  process.exitCode = 1;
}
