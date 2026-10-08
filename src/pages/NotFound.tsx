import { Link } from "react-router-dom";
import { ArrowLeft } from "lucide-react";
export function NotFound() {
  return (
    <div className="not-found container">
      <span className="eyebrow">404 / OFF THE MAP</span>
      <h1>这个位置，还没有标记。</h1>
      <p>页面或套餐不存在，回到目录继续探索。</p>
      <Link className="button dark" to="/subscriptions">
        <ArrowLeft size={16} />
        返回套餐目录
      </Link>
    </div>
  );
}
