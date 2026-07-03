# content-agent

本地运行的内容制作 Agent。第一版目标是跑通一个最小技术闭环：

1. 读取本地 Markdown 记忆文件
2. 调用 LLM 生成小红书风格内容草稿
3. 校验草稿结构和内容
4. 保存为本地 JSON 文件

## 环境

项目目录：

```bash
/Users/doublegou/Documents/workspace/MediaOps/content-agent
```

推荐使用已经创建好的 conda 环境：

```bash
cd /Users/doublegou/Documents/workspace/MediaOps/content-agent
conda activate content-agent
python --version
pip install -r requirements.txt
cp .env.example .env
```

在 `.env` 中填写：

```bash
OPENAI_API_KEY=your_api_key_here
OPENAI_BASE_URL=https://api.sensenova.cn/v1
MODEL=deepseek-v4-flash
```

不要把真实 API Key 写进代码或提交到 git。

## 运行

```bash
python run_daily.py
```

成功后会在 `data/drafts/` 下生成一个 JSON 草稿文件。

如果没有配置 `OPENAI_API_KEY`，程序会提示：

```text
Missing OPENAI_API_KEY. Please set it in .env.
```

## 输出字段

```json
{
  "id": "...",
  "created_at": "...",
  "topic": "...",
  "title": "...",
  "body": "...",
  "hashtags": ["...", "..."],
  "reason": "...",
  "status": "draft"
}
```
