import { useState, type CSSProperties } from "react";
import { Link } from "react-router-dom";
import ElectricLogo from "./ElectricLogo";
import { platformLogos } from "./PlatformIcon";
import { BrandMark } from "./Brand";

const nodes = [
  {name:"ChatGPT",x:23,y:22}, {name:"Claude",x:79,y:26},
  {name:"Gemini",x:85,y:65}, {name:"Grok",x:47,y:87}, {name:"Cursor",x:13,y:64},
];
export function SubscriptionNetwork() {
  const [ready, setReady] = useState(false);
  return <div className="subscription-network">
    <div className="network-haze" />
    <svg className="network-lines" viewBox="0 0 600 500" fill="none" aria-hidden="true">
      <defs><radialGradient id="orbit-ink"><stop stopColor="#879cff" stopOpacity=".6"/><stop offset="1" stopColor="#99afd9" stopOpacity=".18"/></radialGradient></defs>
      <g stroke="url(#orbit-ink)"><ellipse cx="300" cy="250" rx="245" ry="145" transform="rotate(-22 300 250)"/><ellipse cx="300" cy="250" rx="215" ry="172" transform="rotate(34 300 250)"/><circle cx="300" cy="250" r="190" strokeDasharray="2 8"/>
      {nodes.map(n=><path key={n.name} d={`M300 250 Q${n.x*6} 250 ${n.x*6} ${n.y*5}`}/>)}</g>
      <g className="network-stars" fill="#9faee4"><circle cx="330" cy="62" r="3"/><circle cx="535" cy="215" r="3"/><circle cx="155" cy="395" r="3"/><circle cx="56" cy="181" r="2"/></g>
    </svg>
    <div className="network-core">
      <div className={`network-fallback ${ready ? "is-rendered" : ""}`}><BrandMark /></div>
      <ElectricLogo src="/brand-mark.svg" theme="light" color="#8a91ed" glowColor="#b2a3eb" scale={0.48} strands={4} bend={0.6} crackle={1.2} arcs={0.6} speed={1.3} thickness={1.3} flicker={0.25} intensity={1} glow={1} fill={0} interactive onRender={() => { if (!ready) setReady(true); }} />
    </div>
    {nodes.map(n=><Link key={n.name} to={`/subscriptions?platform=${n.name}`} className="network-node" style={{"--node-x":`${n.x}%`,"--node-y":`${n.y}%`} as CSSProperties} aria-label={`比较 ${n.name} 订阅`}>
      <span><img src={platformLogos[n.name]} alt="" /></span><strong>{n.name}</strong>
    </Link>)}
  </div>;
}
