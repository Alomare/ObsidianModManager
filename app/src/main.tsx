import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "@fontsource-variable/saira/wght.css";
import "@fontsource/barlow/400.css";
import "@fontsource/barlow/500.css";
import "@fontsource/barlow/600.css";
import "./styles.css";
import App from "./App";
import { Crash } from "./Crash";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <Crash>
      <App />
    </Crash>
  </StrictMode>,
);
