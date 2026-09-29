// Leaflet maps as React components, written here over plain Leaflet.
//
// Atlas used react-leaflet for this, but its licence (Hippocratic-2.1) adds use
// restrictions that GPL-3.0, Atlas's licence, does not allow on the bundle it
// ships. The app needs only a handful of pieces, so they live here: a map that
// hands itself to its children, and layers that add themselves on mount,
// follow their props, and remove themselves on unmount.
//
// The map reads its options and first view once, when it is made, as
// react-leaflet's did; to move it later, use useMap(). Center and zoom win over
// bounds when both are given.

import {
  createContext,
  useContext,
  useEffect,
  useRef,
  useState,
  type MutableRefObject,
  type ReactNode,
} from "react";
import L from "leaflet";
import "leaflet/dist/leaflet.css";

const MapContext = createContext<L.Map | null>(null);

/** The map this component sits in. Only inside a MapContainer. */
export function useMap(): L.Map {
  const map = useContext(MapContext);
  if (!map) throw new Error("useMap needs a MapContainer around it");
  return map;
}

interface MapContainerProps extends L.MapOptions {
  center?: L.LatLngExpression;
  zoom?: number;
  bounds?: L.LatLngBoundsExpression;
  className?: string;
  children?: ReactNode;
}

export function MapContainer({ center, zoom, bounds, className, children, ...options }: MapContainerProps) {
  const element = useRef<HTMLDivElement>(null);
  const [map, setMap] = useState<L.Map | null>(null);
  // Only the first render's view and options are used, so they are read inside
  // an effect that runs once per mount. React's development double mount makes
  // and removes a map in between, which is why remove() is always called.
  useEffect(() => {
    const created = L.map(element.current!, options);
    if (center != null && zoom != null) created.setView(center, zoom);
    else if (bounds != null) created.fitBounds(bounds);
    setMap(created);
    return () => {
      created.remove();
      setMap(null);
    };
  }, []);
  return (
    <div ref={element} className={className}>
      {map && <MapContext.Provider value={map}>{children}</MapContext.Provider>}
    </div>
  );
}

/** Call these handlers on the map's events. The handlers may change on every render. */
export function useMapEvents(handlers: L.LeafletEventHandlerFnMap): L.Map {
  const map = useMap();
  const latest = useRef(handlers);
  latest.current = handlers;
  const names = Object.keys(handlers).sort().join(" ");
  useEffect(() => {
    const bound = names
      .split(" ")
      .filter(Boolean)
      .map((name) => {
        const handler = (event: L.LeafletEvent) =>
          (latest.current as Record<string, ((e: L.LeafletEvent) => void) | undefined>)[name]?.(event);
        map.on(name, handler);
        return [name, handler] as const;
      });
    return () => {
      for (const [name, handler] of bound) map.off(name, handler);
    };
  }, [map, names]);
  return map;
}

/**
 * Add a layer to the map for as long as the component is mounted. make() runs
 * with the props of the render that mounted it; each layer follows later
 * changes with its own setters.
 */
function useLayer<T extends L.Layer>(make: () => T): MutableRefObject<T | null> {
  const map = useMap();
  const layer = useRef<T | null>(null);
  useEffect(() => {
    const created = make().addTo(map);
    layer.current = created;
    return () => {
      created.remove();
      layer.current = null;
    };
  }, [map]);
  return layer;
}

// Call sites pass fresh array and object literals on every render; compare
// them by value so a layer is only touched when something really changed.
const same = (value: unknown) => JSON.stringify(value);

export function TileLayer({ url, attribution }: { url: string; attribution?: string }) {
  const layer = useLayer(() => L.tileLayer(url, { attribution }));
  useEffect(() => {
    layer.current?.setUrl(url);
  }, [layer, url]);
  return null;
}

export function ImageOverlay({
  url,
  bounds,
  opacity = 1,
}: {
  url: string;
  bounds: L.LatLngBoundsExpression;
  opacity?: number;
}) {
  const layer = useLayer(() => L.imageOverlay(url, bounds, { opacity }));
  useEffect(() => {
    layer.current?.setUrl(url);
  }, [layer, url]);
  const boundsKey = same(bounds);
  useEffect(() => {
    layer.current?.setBounds(L.latLngBounds(bounds as L.LatLngBoundsLiteral));
  }, [layer, boundsKey]);
  useEffect(() => {
    layer.current?.setOpacity(opacity);
  }, [layer, opacity]);
  return null;
}

interface CircleProps {
  center: L.LatLngExpression;
  /** Metres for a Circle, pixels for a CircleMarker. */
  radius: number;
  pathOptions?: L.PathOptions;
  /** Plain text shown on hover. */
  tooltip?: string;
}

// Tooltip text goes in as a text node, never as HTML.
function textNode(text: string): HTMLElement {
  const span = document.createElement("span");
  span.textContent = text;
  return span;
}

function useCircle(layer: MutableRefObject<L.CircleMarker | null>, { center, radius, pathOptions, tooltip }: CircleProps) {
  const centerKey = same(center);
  useEffect(() => {
    layer.current?.setLatLng(center);
  }, [layer, centerKey]);
  useEffect(() => {
    layer.current?.setRadius(radius);
  }, [layer, radius]);
  const styleKey = same(pathOptions ?? {});
  useEffect(() => {
    layer.current?.setStyle(pathOptions ?? {});
  }, [layer, styleKey]);
  useEffect(() => {
    const current = layer.current;
    if (!current) return;
    if (tooltip == null) current.unbindTooltip();
    else if (current.getTooltip()) current.setTooltipContent(textNode(tooltip));
    else current.bindTooltip(textNode(tooltip));
  }, [layer, tooltip]);
}

/** A circle a fixed number of pixels across, whatever the zoom. */
export function CircleMarker(props: CircleProps) {
  const layer = useLayer(() => L.circleMarker(props.center, { ...props.pathOptions, radius: props.radius }));
  useCircle(layer, props);
  return null;
}

/** A circle a fixed number of metres across on the ground. */
export function Circle(props: CircleProps) {
  const layer = useLayer(() => L.circle(props.center, { ...props.pathOptions, radius: props.radius }));
  useCircle(layer, props);
  return null;
}
