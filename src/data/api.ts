export type ApiProvider = {
  id: string; name: string; kind: 'official' | 'relay'; logo?: string;
  models: string[]; families: string[]; billing: string; note: string; url: string; pricingUrl: string;
};
// Official public model and pricing destinations, reviewed 2026-10-08.
export const apiProviders: ApiProvider[] = [
  {id:'openai',name:'OpenAI',kind:'official',logo:'/logos/openai.svg',families:['gpt','image','video'],models:['GPT','图像','视频'],billing:'按模型与用量计费',note:'输入、输出、缓存及工具调用分别计费。',url:'https://platform.openai.com',pricingUrl:'https://developers.openai.com/api/docs/pricing'},
  {id:'anthropic',name:'Anthropic',kind:'official',logo:'/logos/claude-color.svg',families:['claude'],models:['Claude'],billing:'输入 / 输出 / 缓存',note:'模型、缓存与批处理采用不同费率。',url:'https://platform.claude.com',pricingUrl:'https://platform.claude.com/docs/en/about-claude/pricing'},
  {id:'google',name:'Google AI',kind:'official',logo:'/logos/gemini-color.svg',families:['gemini','image','video'],models:['Gemini','Imagen','Veo'],billing:'免费层 / 按量付费',note:'按模型区分输入、输出与缓存费用。',url:'https://aistudio.google.com',pricingUrl:'https://ai.google.dev/gemini-api/docs/pricing'},
  {id:'xai',name:'xAI',kind:'official',logo:'/logos/grok.svg',families:['grok','image','video'],models:['Grok','Imagine'],billing:'Token / 图像 / 视频',note:'文本与生成图像、视频按各自单位计费。',url:'https://console.x.ai',pricingUrl:'https://docs.x.ai/developers/models'},
  {id:'deepseek',name:'DeepSeek',kind:'official',logo:'/logos/deepseek-color.svg',families:['deepseek'],models:['DeepSeek'],billing:'输入 / 输出 / 缓存',note:'缓存命中与未命中采用不同输入价格。',url:'https://platform.deepseek.com',pricingUrl:'https://api-docs.deepseek.com/quick_start/pricing/'},
  {id:'kimi',name:'Kimi 开放平台',kind:'official',logo:'/logos/moonshot.svg',families:['kimi'],models:['Kimi'],billing:'输入 / 输出 / 缓存',note:'模型 API 按量计费；缓存读取与写入单独核算。',url:'https://platform.kimi.com',pricingUrl:'https://platform.kimi.com/docs/pricing/chat'},
  {id:'bailian',name:'阿里云百炼',kind:'official',logo:'/logos/qwen-color.svg',families:['qwen','deepseek','image','video'],models:['千问','DeepSeek','万相'],billing:'按量 / 上下文阶梯',note:'支持多种模型；上下文长度、地域和批处理影响费用。',url:'https://bailian.console.aliyun.com',pricingUrl:'https://help.aliyun.com/zh/model-studio/model-pricing'},
  {id:'ark',name:'火山方舟',kind:'official',logo:'/logos/bytedance-color.svg',families:['doubao','deepseek','image','video'],models:['豆包','DeepSeek','Seedream','Seedance'],billing:'Token / 图片 / 视频',note:'按模型与任务计费，可选择按量或吞吐保障方案。',url:'https://console.volcengine.com/ark',pricingUrl:'https://docs.volcengine.com/docs/ark/model-service-pricing?lang=zh'},
  {id:'glm',name:'智谱 BigModel',kind:'official',logo:'/logos/zhipu-color.svg',families:['glm','image','video'],models:['GLM','图像','视频'],billing:'按模型与用量计费',note:'模型服务与 Coding 套餐分别查看。',url:'https://open.bigmodel.cn',pricingUrl:'https://open.bigmodel.cn/pricing'},
  {id:'mimo',name:'小米 MiMo',kind:'official',logo:'/logos/xiaomimimo.svg',families:['mimo'],models:['MiMo'],billing:'按量 / Token Plan',note:'按量 API 与 Token Plan 分别使用对应额度。',url:'https://platform.xiaomimimo.com',pricingUrl:'https://platform.xiaomimimo.com/docs/en-US/news/v2.5-price-update'},
  {id:'minimax',name:'MiniMax 开放平台',kind:'official',logo:'/logos/minimax-color.svg',families:['minimax','video'],models:['MiniMax','语音','视频'],billing:'Token / 字符 / 秒',note:'语言、语音与视频采用不同计费单位。',url:'https://platform.minimax.cn',pricingUrl:'https://platform.minimax.cn/docs/guides/pricing-paygo'},
  {id:'hunyuan',name:'腾讯混元 / TokenHub',kind:'official',logo:'/logos/hunyuan-color.svg',families:['hunyuan'],models:['混元'],billing:'按量 / 预付费',note:'新模型服务入口迁移至 TokenHub。',url:'https://console.cloud.tencent.com/tokenhub',pricingUrl:'https://cloud.tencent.com/document/product/1729/97731'},
];
