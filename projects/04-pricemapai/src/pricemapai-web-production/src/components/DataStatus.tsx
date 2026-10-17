import { useOffers } from "../data";

export function DataStatus() {
  const { loading, loaded, error, preview, retry } = useOffers();
  if (loading) return <p role="status" className="data-status">正在加载报价…</p>;
  if (error) return <div role="status" className="data-status">{loaded ? "更新暂时失败，当前显示上次成功获取的报价。" : error} <button type="button" onClick={retry}>重新加载</button></div>;
  if (preview) return <p role="status" className="data-status">本地设计预览 · 使用店铺采集历史快照</p>;
  return null;
}
