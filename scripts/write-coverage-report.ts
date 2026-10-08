import{readFileSync,writeFileSync}from'node:fs';
const baseline=JSON.parse(readFileSync('artifacts/merchant-comparison.json','utf8'));
const audit=JSON.parse(readFileSync('artifacts/source-verification.json','utf8'));
const registry=JSON.parse(readFileSync('config/verified-sources.json','utf8'));
const pending=audit.results.filter((r:any)=>!['verified','alias_existing'].includes(r.status));
const additions=audit.results.filter((r:any)=>r.status==='verified');
const aliases=audit.results.filter((r:any)=>r.status==='alias_existing');
const covered=baseline.shared+additions.length+aliases.length;
writeFileSync('config/pending-sources.json',JSON.stringify(pending.map((r:any)=>({name:r.reference.name,reference_url:r.reference.url,reference_collector:r.reference.collector,status:r.status,reason:r.detail})),null,2)+'\n');
const full={checked_at:audit.checked_at,reference:baseline.reference,reference_rows:baseline.reference_total,reference_unique_addresses:baseline.unique_merchants,unidentified_rows:baseline.unidentified.length,duplicate_rows:baseline.duplicate_rows,before:{registered:baseline.our_registered,shared:baseline.shared,missing:baseline.missing.length,extra:baseline.extra.length},after:{registered:registry.length,added:additions.length,covered_reference_addresses:covered,unconnected_reference_addresses:pending.length},results:audit.results,initial_extra:baseline.extra};
writeFileSync('docs/merchant-coverage.json',JSON.stringify(full,null,2)+'\n');
const esc=(x:any)=>String(x??'').replace(/\|/g,'\\|').replace(/\n/g,' ');
const table=(rows:any[])=>'| 名称 | 原站地址 | 结果 |\n| --- | --- | --- |\n'+rows.map(r=>`| ${esc(r.reference.name)} | ${esc(r.reference.url)} | ${esc(r.detail||`${r.offer_count} 条原站报价`)} |`).join('\n');
const text=`# 卡网商家覆盖核验 · 2026-10-09

核验时间：${audit.checked_at}。参考：[PriceAI 商家目录](${baseline.reference})。只提取名称、地址、接口类型作为核验线索；所有价格与库存均由原站采集器读取，未导入 PriceAI 报价。

## 数量口径

| 项目 | 数量 |
| --- | ---: |
| PriceAI 目录记录 | ${baseline.reference_total} |
| 能按完整店铺地址识别、去重的参考地址 | ${baseline.unique_merchants} |
| 没有可识别地址的记录 | ${baseline.unidentified.length} |
| 重复地址记录 | ${baseline.duplicate_rows} |
| 本次之前登记来源 | ${baseline.our_registered} |
| 原来与参考地址重合 | ${baseline.shared} |
| 原来缺少的参考地址 | ${baseline.missing.length} |
| 本次新增、通过原站试采集 | ${additions.length} |
| 经原站确认是已有店铺的地址别名 | ${aliases.length} |
| 现在登记来源 | ${registry.length} |
| 已对应上的参考地址（含别名） | ${covered} |
| 仍未接通的参考地址 | ${pending.length} |

这里按店铺地址计数，同一商家可能在不同平台开店；不能直接等同于独立经营者人数。原先的 18 个“本站额外地址”中有 2 个被确认是参考目录中的别名，剩余 16 个仍保留自己的原站采集。

“已登记／通过试采集”不等于此刻每家都采集成功。新接入的 8 家 wzyp 商铺在本地试采成功，云端随后遇到验证页；其余同平台大量地址遇到 520。数据库保留每次失败原因，未生成假报价，也未绕过验证页或 robots 规则。

## 更新与库存

原先 6 家／21 家／209 家是三批导入配置：60／360／720 分钟，并非产品能力要求。本次所有启用来源统一设为 15 分钟；Cloudflare 每分钟调用 Supabase 采集函数，一批最多领取 64 家，4 家并发。同一原站的请求至少错开 500 毫秒；遇到 429、502、503、520，本轮暂停继续请求该域名。

15 分钟是正常来源的目标周期，从上次采集完成后计时；排队和网络耗时会带来偏差。失败按 30／60／120／240 分钟退避，45 分钟未确认的报价显示过期，不再参与最低价。前端每 5 分钟读取数据库，打开或重新聚焦时立即读取；采集确认时间始终使用 last_seen_at。

库存现在分为原站明确公布的件数、原站的定性文字（如“库存很多”“库存充足”）、有货但未公布数量、未公布库存、缺货及待更新。隐藏具体数量的 ShopApi 商品仅展示其官网采用的文字档位。商品级总库存不重复分配给每个 SKU。数据库通过 offers.raw_data 保存 stock_quantity / stock_text，API 映射至前端字段。

## 新增来源

${table(additions)}

## 原站确认的别名

${table(aliases)}

## 尚未接通

${table(pending)}

完整机器可读记录见 [merchant-coverage.json](merchant-coverage.json)，待接入清单见 [pending-sources.json](../config/pending-sources.json)。这是一份带时间戳的核验结果；原站服务恢复或迁移后需要重新核验。
`;
writeFileSync('docs/merchant-coverage.md',text);console.log(full.after);
