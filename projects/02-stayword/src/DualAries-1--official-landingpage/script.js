document.documentElement.classList.add("js-enabled");

const languageStorageKey = "dualaires-site-language";
const supportedLanguages = ["zh", "en"];

const commonTranslations = {
  zh: {
    skip: "跳到主要内容",
    headerLabel: "主导航",
    brandLabel: "北京种梦智能科技有限公司首页",
    brandCompany: "北京种梦智能科技有限公司",
    navLabel: "页面导航",
    nav: ["首页", "产品", "关于我们", "联系我们"],
    primaryActions: "主要操作",
    productGallery: "产品图片展示",
    downloadAccess: "下载入口",
    moreProducts: "更多产品",
    placeholder: "占位",
    footerCompany: "© 2026 北京种梦智能科技有限公司",
    languageLabel: "语言切换",
    languageButton: "EN",
  },
  en: {
    skip: "Skip to main content",
    headerLabel: "Primary navigation",
    brandLabel: "DualariesAI home",
    brandCompany: "Beijing Zhongmeng Intelligence Technology Co., Ltd.",
    navLabel: "Page navigation",
    nav: ["Home", "Products", "About", "Contact"],
    primaryActions: "Primary actions",
    productGallery: "Product screenshots",
    downloadAccess: "Download links",
    moreProducts: "More products",
    placeholder: "Soon",
    footerCompany: "© 2026 Beijing Zhongmeng Intelligence Technology Co., Ltd.",
    languageLabel: "Language",
    languageButton: "中",
  },
};

const pageTranslations = {
  home: {
    zh: {
      title: "北京种梦智能科技有限公司 | AI 原生技术公司",
      description:
        "北京种梦智能科技有限公司是一家 AI 原生科技公司，致力于构建由混合模型架构与 AI Runtime 驱动的人工智能基础设施。",
      items: [
        [".hero .eyebrow", "AI-Native Technology Company"],
        ["#hero-title", "从技术出发，走向更大的智能世界。"],
        [
          ".hero-text",
          "我们是一家 AI 原生科技公司，致力于构建由混合模型架构与 AI Runtime 驱动的人工智能基础设施，并以此构筑 Agents OS 与 AI 应用族群，让智能成为产品的原生能力。",
        ],
        [".hero-actions .button-primary", "产品族群"],
        [".hero-actions .button-secondary", "认识种梦"],
        [".product-suite .eyebrow", "Product Family"],
        ["#products-title", "AI 产品，是人工智能的最后一公里。"],
        [
          ".section-heading p:not(.eyebrow)",
          "我们基于 AI 原生基础设施构建产品族群，将底层智能能力推进到用户可触达、可操作、可感知的应用场景，并在持续使用中完成从技术能力到产品价值的跃迁。",
        ],
        [".technology-heading .eyebrow", "About us"],
        ["#technology-title", "为智能时代，构建原生技术。"],
        [
          ".technology-heading p:not(.eyebrow)",
          "我们围绕模型训练、高性能推理、AI Runtime 与 Intelligence Infer 构建原生技术资产，让一切源于智能。",
        ],
        [".contact .eyebrow", "Contact"],
        ["#contact-title", "与我们一起，开启 AI 纪元大航海。"],
      ],
      products: [
        ["自然探索", "万种鸟类百科、叫声、观鸟点与迁徙轨迹，构成一套随身自然观察系统。"],
        ["宇宙探索", "实时追踪卫星与空间轨迹，把宇宙运行转化为可感知的探索界面。"],
        ["离线 AI 整理", "在 iPhone 上实现最高 60 倍速端侧转写与智能摘要，核心内容不上传，一次买断。"],
        ["数字游戏", "用数字、逻辑与观察构建轻量谜题，让推理成为可持续游玩的互动体验。"],
        ["智能工具", "以手势启动自动化动作，把日常操作压缩成更自然的瞬间响应。"],
      ],
      technology: [
        ["垂类模型与训练体系", "围绕真实场景训练语音合成、语音转录、视觉识别、声音识别与分类模型等垂类能力；结合数据构建、大模型微调与持续训练，让通用模型能力进入可稳定交付的应用场景。", "Domain Models · Fine-tuning"],
        ["自研高性能推理框架", "统一模型服务、请求编排、上下文管理、缓存、批处理与异构优化，让模型能力以低时延、高吞吐稳定进入真实产品。", "Inference Engine · Acceleration"],
        ["高性能智能资源基础设施与智能系统", "我们将模型能力、推理服务、智能体集群与应用组件抽象为可组合、可调度、可复用的智能资源，并由 AI Runtime 完成智能编排与动态调度，让底层智能能力自动转化为可交付、可扩展、可持续演进的产品能力，支撑真实生产场景。", "Serverless Intelligence · AI Runtime"],
      ],
      metrics: ["2.3× 吞吐提升", "−45% P95 推理时延", "+30% 资源利用率"],
      teamx: [
        "Coming Soon",
        "TeamX · Agentic System",
        "从任务导向转向结果导向，定义 HAI 协同系统。",
        "AI 原生 Agent OS，调度 Serverless 智能资源集群。",
        "让目标成为新的生产指令，让结果成为智能时代的标准输出。",
      ],
    },
    en: {
      title: "Beijing Zhongmeng Intelligence Technology Co., Ltd. | AI-Native Technology Company",
      description:
        "Beijing Zhongmeng Intelligence Technology Co., Ltd. is an AI-native technology company building AI infrastructure powered by hybrid model architecture and AI Runtime.",
      items: [
        [".hero .eyebrow", "AI-Native Technology Company"],
        ["#hero-title", "Technology for a larger intelligent world."],
        [
          ".hero-text",
          "We build AI-native infrastructure powered by hybrid model architecture and AI Runtime, then turn it into Agents OS and practical AI products.",
        ],
        [".hero-actions .button-primary", "Products"],
        [".hero-actions .button-secondary", "About us"],
        [".product-suite .eyebrow", "Product Family"],
        ["#products-title", "AI products are the last mile of intelligence."],
        [
          ".section-heading p:not(.eyebrow)",
          "Our product family carries AI-native infrastructure into reachable, usable, and observable scenarios where technical capability becomes product value.",
        ],
        [".technology-heading .eyebrow", "About us"],
        ["#technology-title", "Native technology for the intelligent era."],
        [
          ".technology-heading p:not(.eyebrow)",
          "We build core assets across model training, high-performance inference, AI Runtime, and Intelligence Infer so every product can start from intelligence.",
        ],
        [".contact .eyebrow", "Contact"],
        ["#contact-title", "Build the AI era with us."],
      ],
      products: [
        ["Nature", "Bird encyclopedia, calls, hotspots, and migration clues in one field observation system."],
        ["Space", "Real-time satellite and orbital tracking that turns space movement into an observable interface."],
        ["Offline AI Notes", "Up to 60× on-device transcription and AI summary on iPhone. Core data stays local. One-time purchase."],
        ["Number Game", "Lightweight puzzles built from numbers, logic, and observation for repeatable play."],
        ["Smart Tool", "Gesture-triggered automation that compresses everyday operations into natural responses."],
      ],
      technology: [
        ["Domain models and training systems", "We train speech synthesis, transcription, vision recognition, sound recognition, and classification models for real scenarios, then combine data building, fine-tuning, and continual training for stable delivery.", "Domain Models · Fine-tuning"],
        ["Self-developed inference framework", "A unified layer for model serving, request orchestration, context management, caching, batching, and heterogeneous optimization, built for low-latency and high-throughput products.", "Inference Engine · Acceleration"],
        ["High-performance intelligent resource infrastructure", "We abstract models, inference services, agent clusters, and app components into composable intelligent resources, then use AI Runtime for orchestration and dynamic scheduling.", "Serverless Intelligence · AI Runtime"],
      ],
      metrics: ["2.3× throughput", "−45% P95 latency", "+30% resource utilization"],
      teamx: [
        "Coming Soon",
        "TeamX · Agentic System",
        "From task-oriented work to outcome-oriented collaboration, defining the HAI system.",
        "An AI-native Agent OS that schedules Serverless intelligent resource clusters.",
        "Goals become production instructions. Results become the standard output of the intelligent era.",
      ],
    },
  },
};

const productTranslations = {
  birdtracker: {
    zh: {
      title: "Bird Tracker | 产品详情 | 北京种梦智能科技有限公司",
      description: "Bird Tracker 是面向自然观察的鸟类图鉴、识别、观鸟点与观察记录应用。",
      heading: "把一次偶遇，整理成自然观察。",
      lead: "Bird Tracker 将鸟类图鉴、声音样本、拍照记录、附近观鸟点与迁徙线索放进一套清爽的移动体验，让每一次看见都能被保存、理解和再次出发。",
      overview: "随身的自然观察系统。",
      overviewText: "Bird Tracker 不是简单的鸟类列表，而是一套围绕观察行为组织的工具。用户可以查找鸟种、播放鸟鸣、查看分布区域，在地图中发现附近观鸟点，也可以用相机记录一次真实的野外遇见。",
      features: [
        ["图鉴与搜索", "按地区和关键词浏览鸟类信息，用清晰的卡片与图片快速建立识别线索。"],
        ["鸟鸣与分布", "在鸟种详情中查看分布地图与声音样本，把外形、声音和地点联系起来。"],
        ["拍照记录", "通过 iPhone 相机保存观察照片，补充地点、天气和笔记，形成自己的观鸟档案。"],
        ["观鸟点追踪", "围绕当前位置、范围和时间筛选观鸟点与可观察鸟种，辅助下一次外出探索。"],
      ],
      download: "下载 Bird Tracker。",
    },
    en: {
      title: "Bird Tracker | Product Details | DualariesAI",
      description: "Bird Tracker is a bird guide, identification, hotspot, and observation log app for nature watching.",
      heading: "Turn a chance sighting into nature observation.",
      lead: "Bird Tracker brings bird guides, sound samples, photo records, nearby hotspots, and migration clues into a clean mobile experience.",
      overview: "A field observation system in your pocket.",
      overviewText: "Bird Tracker is more than a bird list. It organizes species search, calls, distribution, nearby hotspots, and camera records around the act of observation.",
      features: [
        ["Guide and search", "Browse birds by region and keyword, using clear cards and images to build quick identification clues."],
        ["Calls and distribution", "Connect appearance, sound, and place through distribution maps and audio samples in each species profile."],
        ["Photo records", "Save sightings with the iPhone camera, then add location, weather, and notes to build your own birding archive."],
        ["Hotspot tracking", "Filter birding spots and observable species by location, range, and time to plan the next outing."],
      ],
      download: "Download Bird Tracker.",
    },
  },
  isstracker: {
    zh: {
      title: "ISS Tracker | 产品详情 | 北京种梦智能科技有限公司",
      description: "ISS Tracker 是用于追踪国际空间站、卫星轨道与过境时间的空间探索应用。",
      heading: "让空间站经过天空时，被你看见。",
      lead: "ISS Tracker 把国际空间站和卫星轨道转化为直观的观测体验。用户可以查看实时位置、过境时间和轨迹信息，把遥远的太空运行变成可感知的日常探索。",
      overview: "把轨道数据变成可理解的探索界面。",
      overviewText: "对普通用户来说，空间站并不只是屏幕上的一个点。ISS Tracker 通过实时位置、可视化轨迹和观测信息，让用户知道它在哪里、何时经过、如何抬头寻找。",
      features: [
        ["实时位置", "查看国际空间站与相关轨道目标的实时运行状态，理解它们与地球表面的关系。"],
        ["过境时间", "关注可见过境窗口，让用户知道什么时候有机会在夜空中看到空间站。"],
        ["轨迹展示", "用直观的轨道视图呈现运动路径，降低专业航天数据的理解门槛。"],
        ["轻量探索", "适合天文爱好者、亲子科普和日常观察，把一次抬头变成可计划的发现。"],
      ],
      download: "下载 ISS Tracker。",
    },
    en: {
      title: "ISS Tracker | Product Details | DualariesAI",
      description: "ISS Tracker is a space exploration app for tracking the International Space Station, satellite orbits, and visible passes.",
      heading: "See the space station as it crosses your sky.",
      lead: "ISS Tracker turns the International Space Station and satellite orbits into an intuitive observation experience with real-time position, pass times, and trajectory details.",
      overview: "Orbital data in a clear exploration interface.",
      overviewText: "For everyday users, the space station is more than a dot on a screen. ISS Tracker shows where it is, when it passes, and how to look up and find it.",
      features: [
        ["Real-time position", "View live movement of the International Space Station and related orbital targets in relation to Earth."],
        ["Visible passes", "Track viewing windows so users know when they may see the station in the night sky."],
        ["Trajectory views", "Present movement paths through intuitive orbital views that make space data easier to understand."],
        ["Light exploration", "Built for astronomy fans, family learning, and everyday observation, turning a glance upward into a planned discovery."],
      ],
      download: "Download ISS Tracker.",
    },
  },
  stayword: {
    zh: {
      title: "StayWord | 产品详情 | 北京种梦智能科技有限公司",
      description: "StayWord 是专为长录音打造的本地 AI 整理工具，支持 60 倍速端侧转写与智能摘要。",
      heading: "录完即整理，核心不上传。",
      lead: "StayWord 专为长录音打造，在 iPhone 上实现最高 60 倍速端侧转写与智能摘要。音频与文字完全保留在本地，无持续订阅，一次买断。",
      overview: "离线 AI，随身录音笔。",
      overviewText: "StayWord 不依赖云端，而是将语音转录与大语言模型摘要能力完全运行在 iPhone 端侧。录音结束即可整理成文字、提取重点，核心数据始终留在设备上。",
      features: [
        ["60× 极速转写", "高端设备约 1 分钟完成 1 小时音频的端侧语音转文字。"],
        ["端侧 AI 摘要", "内置大语言模型自动生成标题、摘要与关键要点。"],
        ["核心不上传", "本地推理与 SwiftData 保存，断网可用，隐私优先。"],
        ["买断无限制", "一次购买永久使用，无订阅费、无额度限制。"],
      ],
      download: "下载 StayWord。",
    },
    en: {
      title: "StayWord | Product Details | DualariesAI",
      description: "StayWord is a local AI note-taking tool for long recordings with up to 60× on-device transcription and smart summaries.",
      heading: "Transcribe on finish. Core data stays local.",
      lead: "StayWord is built for long recordings. It delivers up to 60× on-device transcription and AI summaries on iPhone. Audio and text stay entirely local, with no subscription.",
      overview: "Offline AI, your pocket recorder.",
      overviewText: "StayWord runs speech-to-text and LLM summarization fully on-device. Once recording ends, it produces text and highlights instantly while keeping all core data on the device.",
      features: [
        ["60× fast transcription", "On high-end devices, transcribe one hour of audio in about one minute, all on-device."],
        ["On-device AI summary", "A built-in large language model automatically generates titles, summaries, and key points."],
        ["Core data stays local", "Local inference and SwiftData storage. Works offline. Privacy first."],
        ["One-time purchase", "Buy once and use forever. No subscription fees, no usage limits."],
      ],
      download: "Download StayWord.",
    },
  },
  mathpuzzle: {
    zh: {
      title: "Math Puzzle | 产品详情 | 北京种梦智能科技有限公司",
      description: "Math Puzzle 是一款数字、逻辑与观察驱动的轻量益智游戏。",
      heading: "把数字推理，做成轻量游戏。",
      lead: "Math Puzzle 用数字、逻辑和观察构建可持续游玩的谜题体验。它适合碎片时间训练专注力，也适合喜欢推理和脑力挑战的用户逐关推进。",
      overview: "在简单规则里持续思考。",
      overviewText: "Math Puzzle 的目标是把数字关系、观察判断和步骤推理组合成轻巧的游戏体验。它不依赖复杂操作，而是让玩家在每一关里找到规律、验证思路，获得清晰的解题反馈。",
      features: [
        ["数字关系", "围绕数字组合和规则变化组织谜题，让玩家在观察中找到突破口。"],
        ["逻辑训练", "通过逐步推理完成关卡，适合日常脑力练习和短时间专注训练。"],
        ["轻量节奏", "玩法清晰、上手快速，每次打开都能进入一段完整而克制的解题过程。"],
        ["持续挑战", "用层层递进的题目组织难度，让玩家在熟悉规则后继续获得挑战感。"],
      ],
      download: "下载 Math Puzzle。",
    },
    en: {
      title: "Math Puzzle | Product Details | DualariesAI",
      description: "Math Puzzle is a lightweight puzzle game driven by numbers, logic, and observation.",
      heading: "Turn number reasoning into a light puzzle game.",
      lead: "Math Puzzle builds repeatable puzzle play from numbers, logic, and observation. It fits quick focus sessions and steady progression for people who enjoy reasoning challenges.",
      overview: "Keep thinking within simple rules.",
      overviewText: "Math Puzzle combines number relationships, observation, and step-by-step reasoning into a light game experience with clear feedback after each solution.",
      features: [
        ["Number relationships", "Organize puzzles around number combinations and changing rules so players can find the first clue through observation."],
        ["Logic practice", "Complete levels through step-by-step reasoning, useful for daily mental exercise and short focus sessions."],
        ["Light rhythm", "Clear rules and quick starts make each session feel complete and restrained."],
        ["Ongoing challenge", "Progressive puzzles keep the challenge alive after players understand the rules."],
      ],
      download: "Download Math Puzzle.",
    },
  },
  flickwand: {
    zh: {
      title: "Flick Wand | 产品详情 | 北京种梦智能科技有限公司",
      description: "Flick Wand 是一款通过手势启动自动化动作的智能工具应用。",
      heading: "用一个手势，启动一串动作。",
      lead: "Flick Wand 面向高频日常操作，把手势识别与自动化动作连接起来。用户可以用更自然的触发方式完成重复任务，让工具响应更接近直觉。",
      overview: "把重复操作压缩成自然响应。",
      overviewText: "Flick Wand 的核心不是堆叠按钮，而是把用户已经熟悉的手势变成自动化入口。它适合启动工具、整理日常任务和快速完成重复动作，让操作路径更短。",
      features: [
        ["手势入口", "以滑动、轻触等自然动作作为触发方式，减少在菜单中寻找功能的时间。"],
        ["动作编排", "将多个步骤组合为一次响应，让常用任务更接近一键执行。"],
        ["日常工具", "围绕真实使用场景设计，让自动化服务于高频动作而不是复杂配置。"],
        ["轻快反馈", "用清晰的反馈确认动作已执行，降低自动化工具使用时的不确定感。"],
      ],
      download: "下载 Flick Wand。",
    },
    en: {
      title: "Flick Wand | Product Details | DualariesAI",
      description: "Flick Wand is a smart tool app that starts automated actions through gestures.",
      heading: "Start a chain of actions with one gesture.",
      lead: "Flick Wand connects gesture recognition with automation for frequent everyday operations, letting repeated tasks respond in a more natural way.",
      overview: "Compress repeated operations into natural responses.",
      overviewText: "Flick Wand turns familiar gestures into automation entry points. It works well for launching tools, organizing daily tasks, and shortening repeated action paths.",
      features: [
        ["Gesture entry", "Use swipes, taps, and other natural actions as triggers, reducing the time spent searching through menus."],
        ["Action orchestration", "Combine multiple steps into one response so common tasks feel closer to one-tap execution."],
        ["Everyday tools", "Designed around real usage, making automation serve frequent actions instead of complex configuration."],
        ["Fast feedback", "Clear responses confirm that an action has run and reduce uncertainty when using automation."],
      ],
      download: "Download Flick Wand.",
    },
  },
};

Object.entries(productTranslations).forEach(([key, value]) => {
  pageTranslations[key] = value;
});

function getPageKey() {
  const pathname = window.location.pathname.replace(/\/index\.html$/, "/");

  if (pathname === "/") return "home";
  if (pathname === "/products/birdtracker/") return "birdtracker";
  if (pathname === "/products/isstracker/") return "isstracker";
  if (pathname === "/products/stayword/") return "stayword";
  if (pathname === "/products/mathpuzzle/") return "mathpuzzle";
  if (pathname === "/products/flickwand/") return "flickwand";

  return null;
}

function getInitialLanguage() {
  const params = new URLSearchParams(window.location.search);
  const urlLanguage = params.get("lang");

  if (supportedLanguages.includes(urlLanguage)) return urlLanguage;

  const storedLanguage = window.localStorage.getItem(languageStorageKey);
  return supportedLanguages.includes(storedLanguage) ? storedLanguage : "zh";
}

function setText(selector, value) {
  const element = document.querySelector(selector);
  if (element && value !== undefined) element.textContent = value;
}

function setTexts(selector, values) {
  document.querySelectorAll(selector).forEach((element, index) => {
    if (values[index] !== undefined) element.textContent = values[index];
  });
}

function setAttr(selector, attribute, value) {
  const element = document.querySelector(selector);
  if (element && value !== undefined) element.setAttribute(attribute, value);
}

function createLanguageSwitcher() {
  const nav = document.querySelector(".nav");
  if (!nav || nav.querySelector(".nav-actions")) return;

  const actions = document.createElement("div");
  actions.className = "nav-actions";

  const switcher = document.createElement("div");
  switcher.className = "language-switcher";
  const button = document.createElement("button");
  button.type = "button";
  button.addEventListener("click", () => {
    applyLanguage(currentLanguage === "zh" ? "en" : "zh");
  });
  switcher.append(button);

  actions.append(switcher);
  nav.append(actions);
}

function applyCommonLanguage(language) {
  const t = commonTranslations[language];

  setText(".skip-link", t.skip);
  setAttr(".site-header", "aria-label", t.headerLabel);
  setAttr(".brand", "aria-label", t.brandLabel);
  setText(".brand-company", t.brandCompany);
  setAttr(".nav-links", "aria-label", t.navLabel);
  setTexts(".nav-links a", t.nav);
  setAttr(".product-detail-actions", "aria-label", t.primaryActions);
  setAttr(".product-story-grid", "aria-label", t.productGallery);
  setAttr(".download-access", "aria-label", t.downloadAccess);
  setAttr(".product-more-list", "aria-label", t.moreProducts);
  setTexts(".download-qr-placeholder > span", [...document.querySelectorAll(".download-qr-placeholder > span")].map(() => t.placeholder));
  setText(".site-footer p span:first-child", t.footerCompany);

  const switcher = document.querySelector(".language-switcher");
  if (switcher) switcher.setAttribute("aria-label", t.languageLabel);

  const button = document.querySelector(".language-switcher button");
  if (button) {
    button.textContent = t.languageButton;
    button.setAttribute("aria-label", language === "zh" ? "Switch to English" : "切换到中文");
  }
}

function applyHomeLanguage(page) {
  page.items.forEach(([selector, value]) => setText(selector, value));

  document.querySelectorAll(".product-index-item").forEach((item, index) => {
    const product = page.products[index];
    if (!product) return;
    const [kicker, body] = product;
    const kickerElement = item.querySelector(".product-kicker");
    const bodyElement = item.querySelector(":scope > p");
    if (kickerElement) kickerElement.textContent = kicker;
    if (bodyElement) bodyElement.textContent = body;
  });

  document.querySelectorAll(".technology-list li").forEach((item, index) => {
    const technology = page.technology[index];
    if (!technology) return;
    const [heading, body, tag] = technology;
    const headingElement = item.querySelector("h3");
    const bodyElement = item.querySelector("div > p:not(.technology-metrics)");
    const tagElement = item.querySelector(".technology-tag");
    if (headingElement) headingElement.textContent = heading;
    if (bodyElement) bodyElement.textContent = body;
    if (tagElement) tagElement.textContent = tag;
  });

  setTexts(".technology-metrics span", page.metrics);
  setText(".teamx-status", page.teamx[0]);
  setText("#teamx-title", page.teamx[1]);
  setTexts(".teamx-core-lines p", page.teamx.slice(2));
}

function applyProductLanguage(page) {
  setText("#product-title", page.heading);
  setText(".product-detail-lead", page.lead);
  setText("#overview-title", page.overview);
  setText(".product-detail-section > p", page.overviewText);
  setText("#download-title", page.download);
  setText("#more-products-title", commonTranslations[currentLanguage].moreProducts === "更多产品" ? "继续查看产品。" : "Continue exploring products.");
  setTexts(".product-detail-actions .button", currentLanguage === "zh" ? ["立即体验", "全部产品"] : ["Try now", "All products"]);

  if (page.accessLabel) {
    setAttr(".download-access", "aria-label", page.accessLabel);
  }

  if (page.open) {
    setText(".download-option .button-primary", page.open);
  }

  document.querySelectorAll(".product-story-list li").forEach((item, index) => {
    const feature = page.features[index];
    if (!feature) return;
    const [heading, body] = feature;
    const headingElement = item.querySelector("strong");
    const bodyElement = item.querySelector("span");
    if (headingElement) headingElement.textContent = heading;
    if (bodyElement) bodyElement.textContent = body;
  });
}

let currentLanguage = getInitialLanguage();

function applyLanguage(language) {
  currentLanguage = language;
  window.localStorage.setItem(languageStorageKey, language);
  const pageKey = getPageKey();
  const page = pageTranslations[pageKey]?.[language];

  if (!page) return;

  document.documentElement.lang = language === "zh" ? "zh-CN" : "en";
  document.title = page.title;
  setAttr("meta[name='description']", "content", page.description);
  applyCommonLanguage(language);

  if (pageKey === "home") {
    applyHomeLanguage(page);
  } else {
    applyProductLanguage(page);
  }
}

if (getPageKey()) {
  createLanguageSwitcher();
  applyLanguage(currentLanguage);
}

const revealItems = document.querySelectorAll(".reveal");

if ("IntersectionObserver" in window) {
  requestAnimationFrame(() => {
    revealItems.forEach((item) => {
      const rect = item.getBoundingClientRect();

      if (rect.top < window.innerHeight * 0.92) {
        item.classList.add("is-visible");
      }
    });
  });

  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.18 }
  );

  revealItems.forEach((item) => observer.observe(item));
} else {
  revealItems.forEach((item) => item.classList.add("is-visible"));
}

const sections = [...document.querySelectorAll("main section[id]")];
const navLinks = [...document.querySelectorAll(".nav-links a")];

if ("IntersectionObserver" in window && sections.length > 0) {
  const navObserver = new IntersectionObserver(
    (entries) => {
      const visible = entries
        .filter((entry) => entry.isIntersecting)
        .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];

      if (!visible) return;

      const activeLink = navLinks.find(
        (link) => link.getAttribute("href") === `#${visible.target.id}`
      );

      if (!activeLink) return;

      navLinks.forEach((link) => {
        link.classList.toggle("is-active", link === activeLink);
      });
    },
    {
      rootMargin: "-25% 0px -55% 0px",
      threshold: [0.12, 0.4, 0.7],
    }
  );

  sections.forEach((section) => navObserver.observe(section));
}
