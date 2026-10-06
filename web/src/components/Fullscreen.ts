// Full screen for one element, with a fallback where the browser has none.
//
// The Fullscreen API is used where it works. iPhone Safari only lets video go
// full screen, and a page inside a frame may not be allowed to, so there the
// element is pinned over the whole window instead; Esc leaves either way.

import { useCallback, useEffect, useRef, useState } from "react";

type Mode = "off" | "native" | "window";

export function useFullscreen<T extends HTMLElement>() {
  const ref = useRef<T>(null);
  const [mode, setMode] = useState<Mode>("off");

  useEffect(() => {
    const onChange = () =>
      setMode((current) =>
        document.fullscreenElement != null && document.fullscreenElement === ref.current
          ? "native"
          : current === "native"
            ? "off"
            : current,
      );
    document.addEventListener("fullscreenchange", onChange);
    return () => document.removeEventListener("fullscreenchange", onChange);
  }, []);

  useEffect(() => {
    if (mode !== "window") return;
    // Caught on the way down, so Esc leaves full screen and nothing else on
    // the page (such as an expanded map) also reacts to it.
    const onKey = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      event.stopPropagation();
      setMode("off");
    };
    document.addEventListener("keydown", onKey, true);
    const overflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", onKey, true);
      document.body.style.overflow = overflow;
    };
  }, [mode]);

  // Leaving the page in full screen would leave the browser there.
  useEffect(
    () => () => {
      if (document.fullscreenElement != null && document.fullscreenElement === ref.current) {
        void document.exitFullscreen().catch(() => {});
      }
    },
    [],
  );

  const toggle = useCallback(() => {
    const element = ref.current;
    if (!element) return;
    if (mode === "native") {
      void document.exitFullscreen().catch(() => setMode("off"));
    } else if (mode === "window") {
      setMode("off");
    } else if (document.fullscreenEnabled && element.requestFullscreen) {
      element.requestFullscreen().catch(() => setMode("window"));
      // Some embedded browsers neither grant the request nor refuse it.
      window.setTimeout(() => {
        if (ref.current === element && document.fullscreenElement !== element) {
          setMode((current) => (current === "off" ? "window" : current));
        }
      }, 1000);
    } else {
      setMode("window");
    }
  }, [mode]);

  return {
    ref,
    full: mode !== "off",
    /** Pinned over the window rather than given the screen by the browser. */
    pinned: mode === "window",
    toggle,
  };
}
