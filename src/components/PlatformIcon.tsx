import { CategoryIcon } from "./CategoryIcon";

// Transparent brand assets from LobeHub Icons. Original paths are not redrawn.
export const platformLogos: Record<string, string> = {
  ChatGPT: "/logos/openai.svg",
  Claude: "/logos/claude-color.svg",
  Gemini: "/logos/gemini-color.svg",
  Grok: "/logos/grok.svg",
  Cursor: "/logos/cursor.svg",
};

export function PlatformIcon({
  platform,
  small = false,
}: {
  platform: string;
  small?: boolean;
}) {
  return (
    <span
      className={`platform-icon ${small ? "small" : ""} platform-${platform.toLowerCase()}`}
      aria-hidden="true"
    >
      {platformLogos[platform] ? (
        <img
          src={platformLogos[platform]}
          alt=""
          width={28}
          height={28}
          draggable={false}
        />
      ) : (
        <CategoryIcon category={platform} size={23} />
      )}
    </span>
  );
}
