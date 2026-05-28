import { useMemo } from "react";
import type { ReactNode } from "react";
import { useParams, useNavigate } from "react-router-dom";
import type { LeaderboardEntry, SourceLeaderboardEntry } from "../lib/types";
import {
  leaderboardDisplayName,
  leaderboardFormattedTokens,
} from "../lib/types";

type LeaderboardPeriod = "day" | "weekly" | "allTime";

const PERIODS: Array<{ id: LeaderboardPeriod; label: string; title: string }> = [
  { id: "day", label: "Last 24h", title: "LAST 24 HOURS" },
  { id: "weekly", label: "Week", title: "THIS WEEK" },
  { id: "allTime", label: "All Time", title: "ALL TIME" },
];

function getValue(entry: LeaderboardEntry, key: "total_lines" | "total_sessions" | "active_seconds") {
  const value = entry[key];
  if (value === null || value === undefined) return null;
  return Number(value);
}

function hasExpandedStats(entry: LeaderboardEntry) {
  return (
    entry.total_lines !== null &&
    entry.total_lines !== undefined &&
    entry.total_sessions !== null &&
    entry.total_sessions !== undefined &&
    entry.active_seconds !== null &&
    entry.active_seconds !== undefined
  );
}

function formatDuration(seconds: number) {
  const totalMinutes = Math.round(seconds / 60);
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  if (hours === 0) return `${minutes}m`;
  return `${hours}h ${String(minutes).padStart(2, "0")}m`;
}

function formatNumber(n: number) {
  if (n >= 1_000_000_000_000) return `${(n / 1_000_000_000_000).toFixed(1)}T`;
  if (n >= 1_000_000_000) return `${(n / 1_000_000_000).toFixed(1)}B`;
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
  return `${n}`;
}

function sourceLabel(source: string) {
  if (!source) return "Unknown";
  return source.charAt(0).toUpperCase() + source.slice(1);
}

function rankTone(rank: number) {
  if (rank === 1) return "text-logo-green text-glow";
  if (rank <= 3) return "text-text";
  return "text-text-muted";
}

function MetricTile({ label, value }: { label: string; value: string }) {
  return (
    <div className="border border-border bg-white/[0.015] px-4 py-3">
      <div className="font-mono text-[10px] font-bold tracking-[0.16em] text-text-muted">
        {label}
      </div>
      <div className="mt-2 truncate font-mono text-[22px] font-bold tabular-nums text-text">
        {value}
      </div>
    </div>
  );
}

function PeriodButton({
  active,
  children,
  onClick,
}: {
  active: boolean;
  children: ReactNode;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className={`rounded-[7px] px-3 py-2 text-center font-mono text-[10px] font-bold tracking-[0.12em] transition-colors ${
        active ? "bg-logo-green text-black" : "text-text-muted hover:bg-white/[0.05] hover:text-text"
      }`}
    >
      {children}
    </button>
  );
}

function LeaderboardRow({ entry, rank }: { entry: LeaderboardEntry; rank: number }) {
  const tokens = Number(entry.total_tokens ?? 0);
  const lines = getValue(entry, "total_lines");
  const sessions = getValue(entry, "total_sessions");
  const activeSeconds = getValue(entry, "active_seconds");
  const tokensPerHour = activeSeconds && activeSeconds > 0 ? Math.round(tokens / (activeSeconds / 3600)) : null;

  return (
    <div className={`${hasExpandedStats(entry) ? "combat-leaderboard-cols-expanded" : "combat-leaderboard-cols"} grid items-center gap-3 border-b border-border/60 px-3 py-3 font-mono text-[12px] transition-colors hover:bg-white/[0.035]`}>
      <div className={`text-[13px] font-bold tabular-nums ${rankTone(rank)}`}>
        {String(rank).padStart(2, "0")}
      </div>
      <div className="min-w-0">
        <div className="truncate text-[13px] font-bold text-text">
          @{leaderboardDisplayName(entry.email)}
        </div>
        {sessions !== null && activeSeconds !== null && (
          <div className="mt-1 flex items-center gap-2 text-[9px] font-bold tracking-[0.12em] text-text-muted">
            <span>{sessions} SESSIONS</span>
            <span className="text-border">/</span>
            <span>{formatDuration(activeSeconds)}</span>
          </div>
        )}
      </div>
      <div className="text-right text-[14px] font-bold tabular-nums text-text">
        {leaderboardFormattedTokens(tokens)}
      </div>
      <div className="hidden text-right tabular-nums text-text-dim sm:block">
        {lines !== null ? formatNumber(lines) : ""}
      </div>
      <div className="hidden text-right tabular-nums text-text-dim md:block">
        {tokensPerHour !== null ? formatNumber(tokensPerHour) : ""}
      </div>
    </div>
  );
}

function SourceWinners({ entries }: { entries: SourceLeaderboardEntry[] }) {
  return (
    <div className="grid gap-2 md:grid-cols-2 xl:grid-cols-4">
      {entries.map((entry) => (
        <div key={entry.source} className="border border-border bg-white/[0.015] px-4 py-3">
          <div className="flex items-center justify-between gap-3">
            <div className="font-mono text-[10px] font-bold tracking-[0.16em] text-logo-green">
              TOP {sourceLabel(entry.source).toUpperCase()}
            </div>
            <div className="font-mono text-[10px] text-text-muted">
              {entry.total_sessions} RUNS
            </div>
          </div>
          <div className="mt-3 truncate font-mono text-[14px] font-bold text-text">
            @{leaderboardDisplayName(entry.email)}
          </div>
          <div className="mt-1 font-mono text-[12px] text-text-dim">
            {leaderboardFormattedTokens(entry.total_tokens)} tokens · {formatDuration(entry.active_seconds)}
          </div>
        </div>
      ))}
    </div>
  );
}

const URL_TO_PERIOD: Record<string, LeaderboardPeriod> = {
  day: "day",
  weekly: "weekly",
  "all-time": "allTime",
};
const PERIOD_TO_URL: Record<LeaderboardPeriod, string> = {
  day: "day",
  weekly: "weekly",
  allTime: "all-time",
};

export function LeaderboardView({
  dailyLeaderboard,
  weeklyLeaderboard,
  allTimeLeaderboard,
  sourceLeaderboard,
}: {
  dailyLeaderboard: LeaderboardEntry[];
  weeklyLeaderboard: LeaderboardEntry[];
  allTimeLeaderboard: LeaderboardEntry[];
  sourceLeaderboard: Record<string, SourceLeaderboardEntry[]>;
}) {
  const { period: periodParam } = useParams<{ period: string }>();
  const navigate = useNavigate();
  const period: LeaderboardPeriod = (periodParam && URL_TO_PERIOD[periodParam]) ?? "weekly";
  function setPeriod(p: LeaderboardPeriod) {
    navigate(`/leaderboard/${PERIOD_TO_URL[p]}`, { replace: true });
  }
  const activeEntries =
    period === "day"
      ? dailyLeaderboard
      : period === "weekly"
        ? weeklyLeaderboard
        : allTimeLeaderboard;
  const periodMeta = PERIODS.find((item) => item.id === period) ?? PERIODS[1];
  const totalTokens = useMemo(
    () => activeEntries.reduce((sum, entry) => sum + Number(entry.total_tokens ?? 0), 0),
    [activeEntries]
  );
  const totalLines = useMemo(
    () => activeEntries.reduce((sum, entry) => sum + (getValue(entry, "total_lines") ?? 0), 0),
    [activeEntries]
  );
  const totalSessions = useMemo(
    () => activeEntries.reduce((sum, entry) => sum + (getValue(entry, "total_sessions") ?? 0), 0),
    [activeEntries]
  );
  const leader = activeEntries[0];
  const activeSourceEntries = sourceLeaderboard[period] ?? [];
  const showExpandedStats = activeEntries.some(hasExpandedStats);

  return (
    <div className="scanlines mx-auto flex h-full max-w-lg flex-col desk:max-w-6xl">
      <div className="sticky top-0 z-10 border-b border-border bg-background desk:hidden">
        <div className="px-4 py-[18px] text-center">
          <span className="font-led text-2xl font-normal tracking-[0.1em] text-white">
            DEVKAT
          </span>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto px-4 pb-[100px] pt-5 desk:px-8 desk:pb-10 desk:pt-8">
        <div className="flex flex-col gap-5 desk:flex-row desk:items-end desk:justify-between">
          <div>
            <div className="font-mono text-[11px] font-bold tracking-[0.2em] text-logo-green text-glow">
              LIVE DEV STATS
            </div>
            <h1 className="mt-3 font-led text-[40px] leading-none tracking-[0.1em] text-text desk:text-[58px]">
              LEADERBOARD
            </h1>
          </div>

          <div className="grid grid-cols-3 gap-1 rounded-[10px] border border-border bg-white/[0.03] p-1 desk:w-[360px]">
            {PERIODS.map((item) => (
              <PeriodButton
                key={item.id}
                active={period === item.id}
                onClick={() => setPeriod(item.id)}
              >
                {item.label}
              </PeriodButton>
            ))}
          </div>
        </div>

        <div className="mt-6 grid grid-cols-2 gap-2 desk:grid-cols-4">
          <MetricTile label="BOARD" value={periodMeta.title} />
          <MetricTile label="DEVS" value={String(activeEntries.length)} />
          <MetricTile label="TOKENS" value={leaderboardFormattedTokens(totalTokens)} />
          {showExpandedStats && <MetricTile label="LINES" value={formatNumber(totalLines)} />}
        </div>

        {activeSourceEntries.length > 0 && (
          <div className="mt-6">
            <div className="mb-2 font-mono text-[10px] font-bold tracking-[0.18em] text-text-muted">
              TOP DEVS BY HARNESS
            </div>
            <SourceWinners entries={activeSourceEntries} />
          </div>
        )}

        <div className="mt-6 border border-border bg-white/[0.012]">
          <div className="border-b border-border bg-white/[0.025] px-3 py-3">
            <div className="flex items-center justify-between gap-3">
              <div className="min-w-0">
                <div className="font-mono text-[10px] font-bold tracking-[0.18em] text-text-muted">
                  {periodMeta.title} / TOKEN BURN
                </div>
                <div className="mt-1 truncate font-mono text-[11px] text-text-dim">
                  {leader
                    ? `Leader: @${leaderboardDisplayName(leader.email)} · ${leaderboardFormattedTokens(leader.total_tokens)} tokens`
                    : "No ranked sessions yet"}
                </div>
              </div>
              <div className="hidden shrink-0 font-mono text-[10px] font-bold tracking-[0.18em] text-logo-green text-glow sm:block">
                ● LIVE
              </div>
            </div>
          </div>

          <div className={`${showExpandedStats ? "combat-leaderboard-cols-expanded" : "combat-leaderboard-cols"} grid gap-3 border-b border-border px-3 py-2 font-mono text-[9px] font-bold tracking-[0.16em] text-text-muted`}>
            <span>RANK</span>
            <span>DEV</span>
            <span className="text-right">TOKENS</span>
            {showExpandedStats && <span className="hidden text-right sm:block">LINES</span>}
            {showExpandedStats && <span className="hidden text-right md:block">TOKENS/HR</span>}
          </div>

          {activeEntries.length > 0 ? (
            activeEntries.map((entry, idx) => (
              <LeaderboardRow key={entry.email} entry={entry} rank={idx + 1} />
            ))
          ) : (
            <div className="px-3 py-14 text-center font-mono text-[12px] text-text-muted">
              NO DEVS RANKED FOR THIS WINDOW
            </div>
          )}
        </div>

        <div className="mt-3 flex justify-between font-mono text-[10px] font-bold tracking-[0.14em] text-text-muted">
          <span>{showExpandedStats ? `${totalSessions} SESSION${totalSessions === 1 ? "" : "S"}` : ""}</span>
          <span>SORTED BY TOKENS</span>
        </div>

      </div>
    </div>
  );
}
