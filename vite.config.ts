import { defineConfig } from "vite";
import { resolve } from "node:path";

export default defineConfig({
  base: "/madrid/",
  server: {
    host: "127.0.0.1",
    port: 5173,
  },
  preview: {
    host: "127.0.0.1",
    port: 4173,
  },
  build: {
    target: "es2022",
    sourcemap: true,
    rollupOptions: {
      input: {
        atlas: resolve(import.meta.dirname, "index.html"),
        housingMigration: resolve(import.meta.dirname, "housing-migration/index.html"),
      },
    },
  },
});
