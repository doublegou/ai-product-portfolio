import { useSyncExternalStore } from "react";

const preference = window.matchMedia("(prefers-color-scheme: dark)");
const subscribe = (notify: () => void) => {
  preference.addEventListener("change", notify);
  return () => preference.removeEventListener("change", notify);
};
export function useDarkMode() {
  return useSyncExternalStore(subscribe, () => preference.matches, () => false);
}
