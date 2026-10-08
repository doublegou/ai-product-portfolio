import { Children, isValidElement, useEffect, useId, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { Check, ChevronDown } from "lucide-react";

type OptionProps = { value: string; children: ReactNode };
export function GlassSelect({ value, onChange, children, "aria-label": label = "选择条件" }: {
  value: string; onChange: (value: string) => void; children: ReactNode; "aria-label"?: string;
}) {
  const options = Children.toArray(children).filter(isValidElement<OptionProps>).map(option => option.props);
  const id = useId();
  const trigger = useRef<HTMLButtonElement>(null);
  const menu = useRef<HTMLDivElement>(null);
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(0);
  const [position, setPosition] = useState({ top: 0, left: 0, width: 200, maxHeight: 300 });
  const selected = Math.max(0, options.findIndex(option => option.value === value));
  const show = () => {
    const rect = trigger.current!.getBoundingClientRect();
    const width = Math.min(rect.width, window.innerWidth - 24);
    const height = Math.min(options.length * 40 + 12, 300);
    const below = window.innerHeight - rect.bottom - 16;
    const above = rect.top - 16;
    const upwards = below < height && above > below;
    const maxHeight = Math.max(80, Math.min(height, upwards ? above : below));
    setPosition({ top: upwards ? rect.top - maxHeight - 6 : rect.bottom + 6, left: Math.max(12, Math.min(rect.right - width, window.innerWidth - width - 12)), width, maxHeight });
    setActive(selected);
    setOpen(true);
  };
  const choose = (index: number) => { onChange(options[index].value); setOpen(false); trigger.current?.focus(); };
  useEffect(() => {
    if (!open) return;
    const outside = (event: PointerEvent) => {
      if (!menu.current?.contains(event.target as Node) && !trigger.current?.contains(event.target as Node)) setOpen(false);
    };
    const reposition = (event: Event) => { if (!menu.current?.contains(event.target as Node)) setOpen(false); };
    document.addEventListener("pointerdown", outside);
    window.addEventListener("resize", reposition);
    window.addEventListener("scroll", reposition, true);
    return () => { document.removeEventListener("pointerdown", outside); window.removeEventListener("resize", reposition); window.removeEventListener("scroll", reposition, true); };
  }, [open]);
  useEffect(() => { if (open) menu.current?.children[active]?.scrollIntoView({ block: "nearest" }); }, [active, open]);
  return <div className="glass-select">
    <button ref={trigger} type="button" className="glass-select-trigger" role="combobox" aria-label={label} aria-expanded={open} aria-controls={`${id}-list`} aria-haspopup="listbox" aria-activedescendant={open ? `${id}-${active}` : undefined}
      onClick={() => open ? setOpen(false) : show()}
      onKeyDown={event => {
        if (["ArrowDown", "ArrowUp", "Home", "End", "Enter", " ", "Escape"].includes(event.key)) event.preventDefault();
        if (event.key === "Escape" || event.key === "Tab") { setOpen(false); return; }
        if (event.key === "ArrowDown" || event.key === "ArrowUp") {
          if (!open) show(); else setActive(index => (index + (event.key === "ArrowDown" ? 1 : -1) + options.length) % options.length);
        } else if (event.key === "Home" && open) setActive(0);
        else if (event.key === "End" && open) setActive(options.length - 1);
        else if (event.key === "Enter" || event.key === " ") { if (open) choose(active); else show(); }
      }}><span>{options[selected]?.children}</span><ChevronDown size={14} className={open ? "rotated" : ""} /></button>
    {open && createPortal(<div ref={menu} id={`${id}-list`} className="glass-select-menu" role="listbox" aria-label={label} style={position}>
      {options.map((option, index) => <div key={option.value} id={`${id}-${index}`} role="option" aria-selected={value === option.value} className={`glass-select-option ${index === active ? "highlighted" : ""}`} onPointerMove={() => setActive(index)} onMouseDown={event => event.preventDefault()} onClick={() => choose(index)}>
        <span>{option.children}</span>{value === option.value && <Check size={14} />}
      </div>)}
    </div>, document.body)}
  </div>;
}
