import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { Redirect, Route, Switch } from "wouter";

import Layout from "@/components/Layout";
import Data from "@/pages/Data";
import Developers from "@/pages/Developers";
import Embed from "@/pages/Embed";
import Guide from "@/pages/Guide";
import Here from "@/pages/Here";
import Home from "@/pages/Home";
import Maps from "@/pages/Maps";
import Methods from "@/pages/Methods";
import Models from "@/pages/Models";
import NotFound from "@/pages/NotFound";
import Privacy from "@/pages/Privacy";
import Sources from "@/pages/Sources";
import Taxa from "@/pages/Taxa";
import Taxon from "@/pages/Taxon";

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { refetchOnWindowFocus: false, retry: 1 },
  },
});

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <Switch>
        {/* A map for another site's iframe: no header, no footer. */}
        <Route path="/embed/taxa/:name" component={Embed} />
        <Route>
          <Layout>
            <Switch>
              <Route path="/" component={Home} />
              <Route path="/maps" component={Maps} />
              <Route path="/here" component={Here} />
              <Route path="/models" component={Models} />
              <Route path="/taxa" component={Taxa} />
              <Route path="/taxa/:name" component={Taxon} />
              <Route path="/data" component={Data} />
              <Route path="/guide" component={Guide} />
              <Route path="/methods" component={Methods} />
              <Route path="/sources" component={Sources} />
              <Route path="/developers" component={Developers} />
              <Route path="/privacy" component={Privacy} />
              {/* How it works grew into the full methods page. */}
              <Route path="/about">
                <Redirect to="/methods" />
              </Route>
              {/* The layers page became part of Data. */}
              <Route path="/layers">
                <Redirect to="/data" />
              </Route>
              <Route component={NotFound} />
            </Switch>
          </Layout>
        </Route>
      </Switch>
    </QueryClientProvider>
  );
}
