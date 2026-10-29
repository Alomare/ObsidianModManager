/// <reference types="vitest/config" />
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// The Tauri shell loads the dev server on a fixed port; the catalogs in ../locales are shared with the loader.
export default defineConfig({
  plugins: [react()],
  clearScreen: false,
  server: { port: 1420, strictPort: true, fs: { allow: [".."] } },
  test: { environment: "jsdom" },
});
