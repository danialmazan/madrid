import { defineConfig } from "vite";
import { resolve } from "node:path";
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";

const dataVersion = createHash("sha256")
  .update(readFileSync(resolve(import.meta.dirname, "config/source-lock.json")))
  .digest("hex").slice(0, 12);

export default defineConfig({
  base: "/madrid/",
  define: { "import.meta.env.VITE_ATLAS_DATA_VERSION": JSON.stringify(dataVersion) },
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
