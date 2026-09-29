import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// The development API is the plumber server started by `./atlas api`.
// @contract is inst/api, where the OpenAPI description and the list of sources
// live: the API serves those files and this site is drawn from the same ones.
const contract = fileURLToPath(new URL("../inst/api", import.meta.url));

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url)),
      "@contract": contract,
    },
  },
  server: {
    port: 5101,
    fs: { allow: [fileURLToPath(new URL(".", import.meta.url)), contract] },
    proxy: {
      "/api": {
        // ATLAS_API points a second copy of the site at a second API.
        target: process.env.ATLAS_API ?? "http://127.0.0.1:5100",
        changeOrigin: true,
      },
    },
  },
});
