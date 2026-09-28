import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { Route, Switch } from "wouter";

import Layout from "@/components/Layout";
import Overview from "@/pages/Overview";
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
      <Layout>
        <Switch>
          <Route path="/" component={Overview} />
          <Route path="/taxa" component={Taxa} />
          <Route path="/taxa/:name" component={Taxon} />
          <Route>
            <p className="text-muted-foreground">Page not found.</p>
          </Route>
        </Switch>
      </Layout>
    </QueryClientProvider>
  );
}
