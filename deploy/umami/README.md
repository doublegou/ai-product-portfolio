# Umami on Tencent Lighthouse

部署日期：2026-10-09。实例为腾讯云北京轻量服务器 `lhins-f9n1rbfu`，Ubuntu 22.04，约 2 GB 内存、50 GB 磁盘，使用腾讯云 OrcaTerm 免密网页终端维护。

## 服务与入口

- 地址：<https://stats.pricemapai.com>。
- 部署目录：服务器 `/opt/umami`。
- Umami 3.4.0 + PostgreSQL 15，Docker Compose 管理，随 Docker 开机重启。
- Umami 仅监听 `127.0.0.1:3000`；数据库不发布宿主机端口。
- Cloudflare Tunnel：`umami-tencent`，ID `df46fafd-d92f-41af-bf44-b5a78099d7f5`。
- Cloudflare DNS 自动创建代理 CNAME：`stats` → `df46fafd-d92f-41af-bf44-b5a78099d7f5.cfargotunnel.com`。
- Tunnel 服务 `/etc/systemd/system/umami-tunnel.service` 使用 HTTP/2 出站连接，开机启动，无需新开入站端口。
- 管理入口由 Cloudflare Access 应用“Umami 管理后台”保护，只允许 Cloudflare 账号所有者邮箱通过验证码验证。策略 ID `23ad3f57-0780-45ce-8889-2f6807f6c996`，应用 ID `d77bd6fd-497d-4a8d-a343-b1d350e466b1`。
- 管理员用户名保留 `admin`，首次密码已由所有者自行修改，并验证新密码可以登录。
- PriceMapAI 网站 ID：`89ee5fce-9013-4146-a0bd-32e85e49cf15`。前端 `index.html` 接入官方统计脚本，仅在 `pricemapai.com` 自动采集页面访问；不采集 URL 查询参数和 hash，不启用录屏或热力图。
- 公开采集接口 Access 应用“Umami 公开采集接口”（ID `0bebae3b-29da-4771-8b5c-e07c7f89e1cb`）仅匹配 `/script.js` 与 `/api/send`，使用公开 Bypass 策略 `17bb05dc-a333-46da-8dff-9d9c54c6fa3b`。其他后台路径仍要求本人邮箱验证。访客无需邮箱验证或 Umami 登录。

Docker Hub 从此实例连接超时，因此 PostgreSQL 使用 Docker 官方镜像在 AWS ECR 的公开仓库；Umami 使用官方 GitHub Container Registry 镜像。

## 凭据保存位置

服务器 `/opt/umami/.env` 保存随机数据库密码、APP_SECRET 和 TWO_FACTOR_ENCRYPTION_KEY，权限 600。`/opt/umami/cloudflared.token` 保存此隧道的连接令牌，权限 600。仓库提供 `.env.example` 和部署说明，不含实际凭据。管理员密码通过 Umami 个人资料页面管理。

本部署不使用 GitHub Actions 或 CI/CD，不需要在 GitHub Secrets 中保存管理员密码。管理员密码不写入源码，也不放入前端环境变量。

## 上线验证

生产站点已部署统计脚本和对应 CSP。实际浏览器访问首页并切换到 `/subscriptions` 后，Umami 实时统计收到同一访客的两次页面访问，包含 SPA 页面切换。匿名访问统计脚本返回 200，管理后台仍要求 Cloudflare Access 邮箱验证。

## 维护

```sh
cd /opt/umami
docker compose ps
docker compose logs --tail 50 umami
curl -fsS http://127.0.0.1:3000/api/heartbeat
systemctl status umami-tunnel --no-pager
journalctl -u umami-tunnel -n 30 --no-pager
```

服务器现有 `.env` 不应重新生成，否则可能导致数据库密码不匹配或会话、2FA 密钥失效。升级前执行备份、读取对应 Umami 版本迁移说明，并手动修改固定镜像版本。

## 备份

`/opt/umami/backup.sh` 导出 gzip SQL 到服务器 `/opt/umami/backups`。`/etc/cron.d/umami-backup` 每天按服务器时区 03:15 执行：

```cron
15 3 * * * root /opt/umami/backup.sh >> /opt/umami/backups/backup.log 2>&1
```

成功备份后自动清理 `-mtime +7` 的旧备份，实际保留约 7～8 天。首份备份已生成。备份和数据库同机，目前没有异地副本，不覆盖整台服务器磁盘故障。

```sh
/opt/umami/backup.sh
ls -lh /opt/umami/backups/*.sql.gz
df -h /
docker compose exec -T db psql -U umami -d umami -c 'SELECT pg_size_pretty(pg_database_size(current_database()));'
```

本部署使用腾讯云本地数据库，不调用价格站点的 Supabase 数据库。
