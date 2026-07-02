# Daily Writer Prompt

请根据用户提供的本地记忆，生成一条小红书风格内容草稿。

要求：

- 只输出一个合法 JSON 对象，不要输出 Markdown，不要使用代码块
- JSON 必须包含 topic、title、body、hashtags、reason
- topic 是本次内容主题
- title 是适合小红书的中文标题
- body 是正文，至少 120 个中文字符，结构清楚，有具体建议
- hashtags 是字符串数组，至少 3 个标签，每个标签以 # 开头
- reason 简要说明为什么选择这个主题和角度
- 不要输出 id、created_at、status，这些字段由本地程序补充

输出格式示例：

{
  "topic": "用 AI 搭建每日内容草稿流",
  "title": "我给自己做了一个每天出草稿的 AI 流程",
  "body": "正文内容...",
  "hashtags": ["#AI写作", "#内容创作", "#个人效率"],
  "reason": "这个主题适合当前记忆中的受众，能提供一个可执行的小行动。"
}
