import { Search, X } from "lucide-react";
import { useEffect, useRef, useState } from "react";

export function SearchField({ value, onChange, label, placeholder }: {
  value: string;
  onChange: (value: string) => void;
  label: string;
  placeholder: string;
}) {
  const [draft, setDraft] = useState(value);
  const composing = useRef(false);
  const published = useRef(value);
  useEffect(() => {
    if (!composing.current) {
      setDraft(value);
      published.current = value;
    }
  }, [value]);
  const publish = (next: string) => {
    if (next !== published.current) {
      published.current = next;
      onChange(next);
    }
  };
  return <label className="search-field">
    <Search size={18} />
    <input aria-label={label} placeholder={placeholder} value={draft}
      onCompositionStart={() => { composing.current = true; }}
      onCompositionEnd={event => {
        composing.current = false;
        setDraft(event.currentTarget.value);
        publish(event.currentTarget.value);
      }}
      onChange={event => {
        setDraft(event.target.value);
        // URL navigation during IME composition can interrupt the candidate word.
        if (!composing.current && !(event.nativeEvent as InputEvent).isComposing) publish(event.target.value);
      }} />
    {draft && <button type="button" className="icon-button" aria-label="清空搜索" onClick={() => {
      composing.current = false;
      setDraft("");
      publish("");
    }}><X size={15} /></button>}
  </label>;
}
