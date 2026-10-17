import { GlobeHemisphereWestIcon } from "@phosphor-icons/react/dist/csr/GlobeHemisphereWest";

export function BrandMark({ className = "" }: { className?: string }) {
  return <span className={`brand-globe ${className}`} aria-hidden="true">
    <GlobeHemisphereWestIcon size={32} weight="duotone" />
    <span>AI</span>
  </span>;
}
