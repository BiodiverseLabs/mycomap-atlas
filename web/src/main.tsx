import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

// The fonts are served from this site, not Google's, so a visit tells no one
// else the visitor's address (/privacy).
// Libre Franklin for headings and scientific names, as on mycomap.org and
// MycoMap Vision (Steve, 2026-10-08 and 2026-10-13).
import "@fontsource-variable/libre-franklin/wght.css";
import "@fontsource-variable/libre-franklin/wght-italic.css";

import App from "./App";
import "./index.css";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
