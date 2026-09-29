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
    // The sign-in routes live on the API too, outside /api: they redirect and
    // set cookies, so the browser must reach them on this same origin.
    proxy: Object.fromEntries(
      ["/api", "/auth"].map((path) => [
        path,
        {
          // ATLAS_API points a second copy of the site at a second API.
          target: process.env.ATLAS_API ?? "http://127.0.0.1:5100",
          changeOrigin: true,
        },
      ]),
    ),
  },
});
