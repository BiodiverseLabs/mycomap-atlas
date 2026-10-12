import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

// The fonts are served from this site, not Google's, so a visit tells no one
// else the visitor's address (/privacy).
// Headings in Libre Franklin, as on mycomap.org and MycoMap Vision (Steve, 2026-10-08).
import "@fontsource-variable/libre-franklin/wght.css";
import "@fontsource-variable/libre-franklin/wght-italic.css";
import "@fontsource-variable/source-sans-3/wght.css";
import "@fontsource-variable/source-sans-3/wght-italic.css";

import App from "./App";
import "./index.css";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
