// Who is signed in, for the header and the download buttons. Signing in is
// through a mycomap.org account (R/auth.R); pages work the same without it.

import { useQuery, useQueryClient } from "@tanstack/react-query";

import { getMe, signInUrl, signOut, type Me } from "@/lib/api";

const SIGNED_OUT: Me = { signedIn: false, signInAvailable: false };

export function useMe(): Me {
  const me = useQuery({ queryKey: ["me"], queryFn: getMe, staleTime: 5 * 60 * 1000, retry: 0 });
  return me.data ?? SIGNED_OUT;
}

/** The sign-in link for the page the person is on now. */
export function signInHere(): string {
  return signInUrl(`${window.location.pathname}${window.location.search}`);
}

export function useSignOut(): () => Promise<void> {
  const client = useQueryClient();
  return async () => {
    await signOut();
    await client.invalidateQueries({ queryKey: ["me"] });
  };
}
