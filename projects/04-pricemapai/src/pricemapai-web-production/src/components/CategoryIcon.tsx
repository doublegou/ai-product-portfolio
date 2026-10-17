// Original Microsoft Fluent Color assets; kept in their native colors and shapes.
export function CategoryIcon({ category, size = 22 }: { category: string; size?: number }) {
  const name = category === "email" || category === "邮箱" ? "email"
    : category === "verification" || category === "接码" ? "verification"
    : category === "other" || category === "其他" ? "other"
    : category === "image" ? "image" : category === "video" ? "video" : "all";
  return <img src={`/icons/categories/${name}.svg`} width={size} height={size}
    className={`category-icon category-icon-${name}`} alt="" aria-hidden="true" draggable={false}/>;
}
