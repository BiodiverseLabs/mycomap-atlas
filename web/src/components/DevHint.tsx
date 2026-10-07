/**
 * The command that fixes something, for someone running Atlas from the
 * repository. Shown only in a development build: the public site tells a
 * visitor what is missing, never which command to run.
 */
export function DevHint({ command }: { command: string }) {
  if (!import.meta.env.DEV) return null;
  return (
    <span className="mt-1 block text-xs text-muted-foreground">
      Development: run <code className="rounded bg-muted px-1">{command}</code>.
    </span>
  );
}
