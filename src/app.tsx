import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import type { InventoryView } from '@/lib/ipc-contract';

// Placeholder that proves the IPC round trip. The real shell replaces it (plan phase 3).
export function App() {
  const [inv, setInv] = useState<InventoryView | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = () => {
    window.reins.invoke('inventory:read').then((reply) => {
      if (reply.ok) { setInv(reply.data); setError(null); } else setError(reply.error);
    });
  };
  useEffect(load, []);

  const counts = (cli: 'claude' | 'codex') => ({
    skills: inv?.items.filter((i) => i.cli === cli && i.kind === 'skill').length ?? 0,
    agents: inv?.items.filter((i) => i.cli === cli && i.kind === 'agent').length ?? 0,
    hooks: inv?.hooks.filter((h) => h.cli === cli).length ?? 0,
  });

  return (
    <main className="p-8 font-sans">
      <h1 className="text-xl font-semibold">Reins</h1>
      {error && <p role="alert" className="mt-4 text-destructive">{error}</p>}
      {inv && (
        <dl className="mt-4 grid max-w-sm grid-cols-[auto_1fr_1fr_1fr] gap-x-6 gap-y-1 text-sm">
          <dt />
          <dd className="text-muted-foreground">Skills</dd>
          <dd className="text-muted-foreground">Agents</dd>
          <dd className="text-muted-foreground">Hooks</dd>
          {(['claude', 'codex'] as const).map((cli) => (
            <div key={cli} className="contents">
              <dt>{cli === 'claude' ? 'Claude Code' : 'Codex'}</dt>
              <dd>{counts(cli).skills}</dd>
              <dd>{counts(cli).agents}</dd>
              <dd>{counts(cli).hooks}</dd>
            </div>
          ))}
        </dl>
      )}
      <p className="mt-4 text-sm text-muted-foreground">Usage scan: {inv?.usageStatus.state ?? 'loading'}</p>
      <Button className="mt-4" variant="outline" onClick={load}>Refresh</Button>
    </main>
  );
}
