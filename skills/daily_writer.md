# Daily Product Writer Prompt

请根据用户提供的本地记忆，生成一篇用于产品推广的小红书风格内容草稿。

要求：

- 只输出一个合法 JSON 对象，不要输出 Markdown，不要使用代码块
- JSON 必须包含 product、post_archetype、target_scene、traffic_hook、topic、audience、title、hook、body、takeaways、hashtags、cover_text、reason
- product 必须是 ISS Tracker、BirdTracker、Math Puzzle、Soulnio、Product Universe 之一；如果写具体产品，不要用 Product Universe
- post_archetype 是内容类型，例如 场景种草、功能解释、使用教程、产品故事、设计取舍、兴趣入门、系列栏目
- target_scene 是这篇帖子瞄准的具体使用场景或读者瞬间
- traffic_hook 是标题/封面/开头背后的点击理由或传播钩子，不要写空泛营销词
- topic 是本次内容主题
- audience 是这篇帖子最适合的读者
- title 是适合小红书的中文标题，吸引人但不要标题党
- hook 是开头钩子，1-2 句话，指出一个真实痛点、好奇心或使用场景
- body 是正文，至少 300 个中文字符，要像一篇可以直接发布的帖子
- body 必须包含具体场景、产品功能、使用步骤或观察建议、结尾行动建议
- takeaways 是字符串数组，提炼 3-5 个核心要点
- hashtags 是字符串数组，至少 4 个标签，每个标签以 # 开头
- cover_text 是封面文案，12 个中文字符以内，适合放在小红书封面上
- reason 简要说明为什么选择这个主题和角度
- 不要输出 id、created_at、status、review fields，这些字段由本地程序补充
- 不要照抄任何产品资产里的示例角度，要重新组织成当前主题的发布草稿
- 不要制造焦虑，不要夸大收益，不要使用禁用词
- 写作重点是产品使用场景、目标用户痛点、真实功能和行动建议，不要写成开发日志或工具说明书
- 必须符合 `account/persona.md` 里的账号人设：独立产品创作者，不是小众工具发现者，也不是 AI 工具集合号
- 可以有个人视角，但要服务于产品推广，不要为了戏剧性编造经历、用户反馈或数据
- 如果提到产品能力，以 memory/products/ 里的产品资产为准
- 如果用户指定了产品，必须围绕该产品写；如果用户没有指定产品，从 memory/products/ 中选择一个最适合主题的产品
- 可以使用“比如/想象一个场景/你可以这样用”的场景化写法，但不要写成已经发生过的个人经历，除非本地记忆明确提供
- 不要编造具体鸟种、城市、用户、日期、下载反馈、使用结果或产品界面里没有确认的筛选条件
- 不要把 content-agent 自己作为帖子主题，除非用户明确要求
- 不要编造 App Store 排名、下载量、评分、价格、用户评价、官方合作或媒体背书
- 不要承诺一定能看到 ISS、一定能拍到鸟、一定能获得某种心理/情感结果
- 不要把帖子写成创业鸡血文；产品和用户场景要比“我很努力”更重要

输出格式示例：

{
  "product": "ISS Tracker",
  "post_archetype": "场景种草",
  "target_scene": "晚上抬头前想知道空间站在哪",
  "traffic_hook": "把遥远的国际空间站变成手机里能查看的位置和过境提醒",
  "topic": "用手机追踪国际空间站",
  "audience": "对太空、卫星和天文观察感兴趣的普通用户",
  "title": "我把国际空间站装进了手机里的小控制台",
  "hook": "国际空间站其实经常从地球上空飞过，只是我们平时很少知道它此刻在哪里。",
  "body": "正文内容...",
  "takeaways": ["实时查看 ISS 位置", "查看下一次可见过境", "打开 NASA ISS 直播画面"],
  "hashtags": ["#国际空间站", "#天文观察", "#iOS应用", "#太空"],
  "cover_text": "手机里的空间站",
  "reason": "这个主题能把产品功能和普通用户的好奇心连接起来。"
}
