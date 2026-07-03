# Xiaohongshu Research Workflow

目标：让 content-agent 从“能写产品帖”进化到“能基于平台样本写产品帖”。

## 研究闭环

1. 采集对标账号和笔记样本
2. 把样本整理成 `samples/research_input.example.json` 的结构
3. 运行 `python run_research.py <input.json>`
4. 检查 `data/research/reports/` 里的报告
5. 把稳定结论沉淀到 `memory/research/` 或 `memory/platform/xiaohongshu.md`
6. 再运行 `python run_once.py "..."`

## 样本类型

账号级样本：

- 账号名
- 主页简介
- 粉丝数、获赞数等可见信息
- 主页内容气质
- 置顶笔记或高互动笔记列表
- 人设判断：独立开发者、产品设计师、创业者、兴趣达人、工具号等

笔记级样本：

- 标题
- 封面文字
- 正文摘要，不要复制整篇长文
- 标签
- 可见互动数据
- 高价值评论
- 观察信号：标题机制、开头钩子、正文结构、视觉风格、转化方式

## 采集路径

优先级 1：浏览器直接采集。

当 Codex 内置浏览器能稳定打开小红书并已登录时，可以由 Codex 浏览账号页、搜索页和笔记页，抽取可见信息并生成研究输入。

当前更推荐的本机通道：

```bash
python run_collect.py xhs-current "关键词" --limit 10
```

它使用你已经登录的普通 Chrome。首次需要打开 Chrome 菜单：

```text
View > Developer > Allow JavaScript from Apple Events
```

之后采集器可以自动导航、滚动和抽取可见笔记卡片。

备用自动化 profile：

```bash
python run_collect.py xhs "关键词" --limit 10
```

这个通道使用 `data/browser/xhs-chrome` 下的独立 Chrome profile。首次可能需要在打开的窗口里登录小红书一次。

优先级 2：用户提供链接或截图。

如果网页环境不稳定，用户可以提供对标账号链接、笔记链接或截图。Codex 根据可见内容整理成研究输入。

优先级 3：手动摘录。

把少量高价值样本先填进 JSON。数量不需要一开始很大，第一轮 5 个账号、30 篇笔记就足够暴露模式。

## 边界

- 不绕过登录、验证码、风控或平台限制
- 不做刷量、诱导互动、批量骚扰或批量发布
- 不复制他人长文，只分析结构和机制
- 不把对标账号原话直接改写成自己的内容
- 不把样本里的未经证实数据当作事实

## 备用平台

如果小红书短期内仍然被登录态或页面风控卡住，可以先接入更稳定的官方 API 平台来验证“采集 -> 分析 -> 写作”的自动闭环：

- YouTube Data API 的 `search.list` 可以按关键词返回视频、频道和播放列表搜索结果
- X API v2 的 recent search 可以检索最近 7 天匹配查询的帖子
- TikTok Research API 可以查询公开视频和账号数据，但需要符合资格并申请

这些平台可以验证自动研究能力，但不能替代小红书语境。小红书仍然是目标平台研究的主路径。
