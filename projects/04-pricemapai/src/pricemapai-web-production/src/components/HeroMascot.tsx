import { useEffect, useRef, type CSSProperties, type PointerEvent as ReactPointerEvent } from "react";
import { Link } from "react-router-dom";
import GrokBall, { type GrokBallEngine } from "../vendor/grok-ball/grok-ball.ts";
import { platformLogos } from "./PlatformIcon";
import "./HeroMascot.css";

// Keep the original renderer and eye morphs, with a quieter home-page idle pose.
const restingEmotion = "pricemap-rest";
GrokBall.config.register({
  id: restingEmotion, name: "PriceMap resting", group: "custom",
  transition: 650, pool: [0], poolMs: [9000, 16000],
  blinkMs: [4500, 8000], body: { breathe: 0 }, antics: false,
});

const curiousEmotion = "03";
const idleExpressions = ["03", "10", "14", "19", "16", "04"];
// Every original emotion remains reachable by clicking; lead with everyday reactions.
const clickExpressions = [...new Set(["10", "13", "14", "19", ...GrokBall.EMOTIONS.filter(e => e.group !== "custom").map(e => e.id)])];

const platforms = [
  { name: "ChatGPT", x: 13, y: 50, size: 72, color: "92, 164, 144", delay: -1 },
  { name: "Claude", x: 24, y: 24, size: 78, color: "214, 150, 119", delay: -4 },
  { name: "Gemini", x: 43, y: 13, size: 70, color: "113, 147, 237", delay: -2 },
  { name: "Grok", x: 66, y: 16, size: 74, color: "148, 135, 184", delay: -5 },
  { name: "Cursor", x: 83, y: 34, size: 66, color: "108, 147, 173", delay: -3 },
  { name: "其他", x: 87, y: 60, size: 70, color: "124, 145, 205", delay: -6 },
];

export function HeroMascot() {
  const scene = useRef<HTMLDivElement>(null);
  const mount = useRef<HTMLSpanElement>(null);
  const engine = useRef<GrokBallEngine | null>(null);
  const focused = useRef<HTMLElement | null>(null);
  const reducedMotion = useRef(false);
  const hovered = useRef(false);
  const reactionUntil = useRef(0);
  const expressionIndex = useRef(0);
  const reactionTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  useEffect(() => {
    if (!mount.current || !scene.current) return;
    const reduced = matchMedia("(prefers-reduced-motion: reduce)");
    const dark = matchMedia("(prefers-color-scheme: dark)");
    const fine = matchMedia("(hover: hover) and (pointer: fine)");
    reducedMotion.current = reduced.matches;
    const ball = GrokBall.create(mount.current, {
      emotion: restingEmotion, fallbackId: restingEmotion, color: dark.matches ? "#e7e5e0" : "#292b31", eyeColor: dark.matches ? "#2d2d32" : "#f9f9fc", eyeScale: .9,
      upright: true, stableBody: true, gazeResponse: 25, gazeRange: [43, 32],
      autostart: !reduced.matches, idle: false,
    });
    engine.current = ball;
    const syncTheme = () => ball.setTheme(dark.matches ? "#e7e5e0" : "#292b31", dark.matches ? "#2d2d32" : "#f9f9fc");
    dark.addEventListener("change", syncTheme);
    let visible = true;
    let frame = 0;
    let point: { x: number; y: number } | null = null;
    const gaze = () => {
      frame = 0;
      if (reduced.matches || !visible) return;
      const rect = mount.current?.getBoundingClientRect();
      const target = focused.current?.getBoundingClientRect();
      const at = target ? { x: target.left + target.width / 2, y: target.top + target.height / 2 } : point;
      if (rect && at) {
        ball.setGaze((at.x - rect.left - rect.width / 2) / (rect.width * .7), (at.y - rect.top - rect.height / 2) / (rect.height * .65));
      } else ball.clearGaze();
    };
    const schedule = () => { if (!frame) frame = requestAnimationFrame(gaze); };
    const move = (event: PointerEvent) => {
      if (!fine.matches || event.pointerType === "touch" || reduced.matches || !visible) return;
      focused.current = null;
      point = { x: event.clientX, y: event.clientY };
      if (frame) cancelAnimationFrame(frame);
      gaze();
    };
    const reset = () => { point = null; schedule(); };
    const syncMotion = () => {
      reducedMotion.current = reduced.matches;
      ball.setActive(visible && !document.hidden && !reduced.matches);
      if (reduced.matches) { ball.clearGaze(); ball.setEmotion(restingEmotion); }
    };
    let idleIndex = 0;
    const idleTimer = setInterval(() => {
      if (!visible || document.hidden || reduced.matches || hovered.current || Date.now() < reactionUntil.current) return;
      ball.setEmotion(idleExpressions[idleIndex++ % idleExpressions.length]);
      reactionUntil.current = Date.now() + 4200;
      clearTimeout(reactionTimer.current);
      reactionTimer.current = setTimeout(() => ball.setEmotion(restingEmotion), 4200);
    }, 12000);
    const observer = new IntersectionObserver(([entry]) => { visible = entry.isIntersecting; syncMotion(); });
    observer.observe(scene.current);
    window.addEventListener("pointermove", move, { passive: true });
    window.addEventListener("focusin", schedule);
    window.addEventListener("focusout", schedule);
    window.addEventListener("scroll", schedule, { passive: true });
    window.addEventListener("blur", reset);
    document.documentElement.addEventListener("pointerleave", reset);
    document.addEventListener("visibilitychange", syncMotion);
    reduced.addEventListener("change", syncMotion);
    return () => {
      cancelAnimationFrame(frame);
      clearTimeout(reactionTimer.current);
      clearInterval(idleTimer);
      observer.disconnect();
      window.removeEventListener("pointermove", move);
      window.removeEventListener("focusin", schedule);
      window.removeEventListener("focusout", schedule);
      window.removeEventListener("scroll", schedule);
      window.removeEventListener("blur", reset);
      document.documentElement.removeEventListener("pointerleave", reset);
      document.removeEventListener("visibilitychange", syncMotion);
      reduced.removeEventListener("change", syncMotion);
      dark.removeEventListener("change", syncTheme);
      ball.destroy();
      engine.current = null;
    };
  }, []);

  const watch = (node: HTMLElement | null, keyboard = false) => {
    focused.current = keyboard ? node : null;
    hovered.current = !!node;
    reactionUntil.current = Date.now() + 1200;
    clearTimeout(reactionTimer.current);
    if (reducedMotion.current) return;
    engine.current?.setEmotion(node ? curiousEmotion : restingEmotion);
    if (node && mount.current) {
      const target = node.getBoundingClientRect(), rect = mount.current.getBoundingClientRect();
      engine.current?.setGaze((target.left + target.width / 2 - rect.left - rect.width / 2) / (rect.width * .7),
        (target.top + target.height / 2 - rect.top - rect.height / 2) / (rect.height * .65));
    }
  };
  const highlight = (event: ReactPointerEvent<HTMLAnchorElement>) => {
    if (reducedMotion.current) return;
    const rect = event.currentTarget.getBoundingClientRect();
    const x = (event.clientX - rect.left) / rect.width, y = (event.clientY - rect.top) / rect.height;
    event.currentTarget.style.setProperty("--light-x", `${x * 100}%`);
    event.currentTarget.style.setProperty("--light-y", `${y * 100}%`);
    event.currentTarget.style.setProperty("--tilt-x", `${(y - .5) * -14}deg`);
    event.currentTarget.style.setProperty("--tilt-y", `${(x - .5) * 14}deg`);
  };
  const greet = () => {
    clearTimeout(reactionTimer.current);
    reactionUntil.current = Date.now() + 8000;
    engine.current?.setEmotion(clickExpressions[expressionIndex.current++ % clickExpressions.length]);
    reactionTimer.current = setTimeout(() => engine.current?.setEmotion(restingEmotion), 8000);
  };

  return <div className="companion-scene" ref={scene}>
    <div className="companion-atmosphere" aria-hidden="true" />
    <nav className="bubble-platforms" aria-label="按平台浏览卡网订阅">
      {platforms.map(({ name, x, y, size, color, delay }) => <Link key={name}
        to={name === "其他" ? "/subscriptions?category=other" : `/subscriptions?platform=${encodeURIComponent(name)}`}
        className="platform-bubble" aria-label={`查看 ${name} 订阅报价`}
        style={{ "--x": `${x}%`, "--y": `${y}%`, "--size": `${size}px`, "--tint": color, "--delay": `${delay}s` } as CSSProperties}
        onPointerEnter={event => watch(event.currentTarget)} onPointerMove={highlight}
        onPointerLeave={() => watch(null)} onFocus={event => watch(event.currentTarget, true)} onBlur={() => watch(null)}>
        <span className="bubble-float">
          <span className="bubble-surface">
            <span className="bubble-reflection" aria-hidden="true" />
            <img src={platformLogos[name] ?? "/icons/categories/other.svg"} alt="" draggable={false} />
          </span>
          <span className="bubble-label">{name}</span>
        </span>
      </Link>)}
    </nav>
    <div className="companion-anchor">
      <span className="companion-shadow" aria-hidden="true" />
      <button className="companion-character" type="button" onClick={greet}
        aria-label="切换表情">
        <span className="companion-render" ref={mount} aria-hidden="true" />
      </button>
    </div>
  </div>;
}
