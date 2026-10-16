# `analysis.md` format

Create exactly one final file named `analysis.md` in the task directory. Use Chinese throughout except for proper nouns or source-language terms that are clearer when retained.

Use these three top-level sections in this order. Keep their internal structure flexible and adapt it to the actual video.

```markdown
# 中文主题

## 一、概述

视频标题：原始标题  
视频链接：https://www.youtube.com/...

用中文写完整内容摘要、核心观点和理解这段内容所需的重要背景。根据视频实际情况组织段落，不要为了套模板制造空洞小节。清楚区分视频中的观点、事实陈述和分析者的判断。

## 二、内容

[00:00:00] 中文转译内容……

[00:01:18] 中文转译内容……

## 三、二创

从全部内容出发，先判断它可以直接做成什么方向，或者天然适合轻微改造成什么方向。给出一个主要方向并标明“直接改编”或“轻微改编”，再说明标题方向、目标受众、核心承诺、完整叙事结构与可视化方式。不要为了制造差异而强行换题或只截取局部。描述成品时采用独立创作者的视角和口吻，不出现“原视频”“原作者”“素材里提到”“根据字幕”等来源依附表达。
```

## Translation rules

- Preserve the full spoken content, original order, examples, qualifications, causal relationships, and important repetition. Do not turn this section into a summary.
- Translate by semantic paragraphs rather than one subtitle fragment per line. Start each paragraph with the first source segment's `[HH:MM:SS]` timestamp.
- For long videos, process the transcript in ordered chunks and assemble all chunks before finishing. Check the first and last timestamp against the source transcript.
- Remove caption artifacts and meaningless filler only when meaning is unaffected. Preserve uncertainty, disagreement, humor, and changes of position.
- If the source is already Chinese, lightly normalize it for readability instead of retranslating it.
- Do not invent visual information that cannot be established from the transcript.

## Adaptation rules

- Start from the complete argument by default. Preserve the central topic, overall framework, major claims, supporting reasoning, and actionable conclusions instead of selecting one narrow fragment.
- Build a full-content map before choosing a direction: central question, conclusion, major framework, supporting arguments, examples, qualifications, and actionable takeaways.
- Apply this decision order:
  1. **Direct adaptation** — if the complete topic is already clear, valuable, and suitable for the target platform, keep it and adapt only the language and presentation.
  2. **Light adaptation** — if platform fit can improve, adjust only the title, audience framing, opening hook, information order, tone, or visualization while retaining the central thesis and complete major content.
  3. **Partial adaptation** — use only when the user explicitly requests a narrower angle or the full content objectively cannot fit the chosen format. State what is omitted and why.
- Do not force differentiation for its own sake. The adapted title, topic, and structure may overlap substantially with the analyzed content when that is the clearest and most valuable direction. For example, content titled `How to vibe code securely` can become `How to 正确打开 Vibe Coding` while retaining the complete security workflow.
- Treat originality as independent voice, target-platform organization, and final expression—not as an obligation to invent a different thesis. Do not fabricate novelty, experience, or unsupported claims.
- Propose one primary, comprehensive direction first and label it as direct or light adaptation. Add variants only when they express the same full content for a meaningfully different audience or tone.
- Derive the framing from the topic and audience value, not from the source creator's identity. Keep the finished expression standalone and avoid source-dependent wording.
- Evaluate whether the material has enough information density, visual structure, demonstrations, narrative tension, and depth for a carousel note, short video, or long video.
- Keep the detailed reasoning in this section, but give one primary format recommendation in the Codex chat after saving the file.

## Codex chat delivery

After saving and verifying `analysis.md`, reply in Chinese with these items:

1. The clickable path to `analysis.md`.
2. `完整摘要`: a self-contained Chinese summary that lets the user understand the video's full argument without opening the file.
3. `建议二创形式`: choose exactly one primary format from `图文笔记`, `短视频`, or `长视频`, and explain the reason briefly. Mention a secondary format only when the choice is genuinely close.

Do not repeat the separate core-viewpoints or necessary-background sections in the chat, and do not paste the full timestamped translation. Keep those materials in `analysis.md` and make the chat summary concise enough to scan.
