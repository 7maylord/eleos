"use client";

import { useVaultStats } from "@/lib/eleos";
import { formatToken } from "@/lib/eleos/utils";

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex flex-col items-center gap-1">
      <span className="text-2xl font-bold text-zinc-100 tabular-nums">
        {value}
      </span>
      <span className="text-xs text-zinc-500 uppercase tracking-wider">
        {label}
      </span>
    </div>
  );
}

export function VaultStatsBar() {
  const { poolBalance, totalSeeded, totalPaid, isLoading } = useVaultStats();

  if (isLoading) {
    return (
      <div className="flex justify-center gap-16 py-8">
        {[1, 2, 3].map((i) => (
          <div key={i} className="flex flex-col items-center gap-2">
            <div className="h-8 w-24 animate-pulse rounded bg-zinc-800" />
            <div className="h-3 w-16 animate-pulse rounded bg-zinc-800" />
          </div>
        ))}
      </div>
    );
  }

  return (
    <div className="grid grid-cols-3 divide-x divide-zinc-800 border border-zinc-800 rounded-2xl bg-zinc-900/50 py-8">
      <Stat
        label="Vault Balance"
        value={
          poolBalance !== undefined
            ? `${formatToken(poolBalance, 2)} ELOA`
            : "—"
        }
      />
      <Stat
        label="Total Seeded"
        value={
          totalSeeded !== undefined
            ? `${formatToken(totalSeeded, 2)} ELOA`
            : "—"
        }
      />
      <Stat
        label="Total Paid Out"
        value={
          totalPaid !== undefined ? `${formatToken(totalPaid, 2)} ELOA` : "—"
        }
      />
    </div>
  );
}
