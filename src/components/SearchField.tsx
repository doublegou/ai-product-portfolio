import { Search, X } from "lucide-react";

export function SearchField({ value, onChange, label, placeholder }: {
  value: string;
  onChange: (value: string) => void;
  label: string;
  placeholder: string;
}) {
  return <label className="search-field">
    <Search size={18} />
    <input aria-label={label} placeholder={placeholder} value={value} onChange={event => onChange(event.target.value)} />
    {value && <button className="icon-button" aria-label="清空搜索" onClick={() => onChange("")}><X size={15} /></button>}
  </label>;
}
