import { useNavigate } from "react-router-dom";
import { useDarkMode } from "../lib/colorScheme";
import CircularCarousel from "./CircularCarousel";

// Local photography placeholders; replace these entries with API imagery later.
const items = [
  { src: "/images/api-landscape.jpg", alt: "群山与云雾" },
  { src: "/images/api-ocean.jpg", alt: "海浪与海岸" },
  { src: "/images/api-architecture.jpg", alt: "建筑几何" },
  { src: "/images/api-dunes.jpg", alt: "沙丘光影" },
  { src: "/images/api-space.jpg", alt: "星云" },
  { src: "/images/api-forest.jpg", alt: "林间光线" },
];

export function HeroCarousel() {
  const navigate = useNavigate();
  const dark = useDarkMode();

  return <div className="api-carousel">
    <CircularCarousel
      items={items}
      preset="cylinder"
      intro="rise"
      cardWidth={320}
      aspectRatio={4 / 3}
      speed={10}
      captions={false}
      gap={28}
      tilt={-5}
      curve={1}
      perspective={2500}
      autoplay="drift"
      direction="left"
      momentum={0.6}
      snap
      pauseOnHover
      focusOnClick
      draggable
      parallax={0.3}
      stretch={0.5}
      fadeColor={dark ? "#14161c" : "#f4f5fa"}
      depthFade={0.35}
      innerShade={0.6}
      cornerRadius={14}
      onItemClick={() => navigate("/api-pricing")}
    />
  </div>;
}
