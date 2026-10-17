import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { fileURLToPath } from "node:url";

export default defineConfig(({ command, mode }) => ({
  plugins: [react()],
  resolve: { alias: { "@preview-snapshot": fileURLToPath(new URL(
    command === "serve" && mode === "design" ? "./fixtures/subscriptions.json" : "./src/data/empty-preview.ts", import.meta.url,
  )) } },
  build: { rollupOptions: { input: { public: "index.html", admin: "admin.html" } } },
  server: { proxy: { "/api": "http://127.0.0.1:8787" } },
}));
