import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

// The fonts are served from this site, not Google's, so a visit tells no one
// else the visitor's address (/privacy).
import "@fontsource-variable/fraunces/opsz.css";
import "@fontsource-variable/source-sans-3/wght.css";
import "@fontsource-variable/source-sans-3/wght-italic.css";

import App from "./App";
import "./index.css";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
