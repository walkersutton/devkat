import { useMemo, useState } from "react";
import type { ReactNode } from "react";
import type { Session, SessionComponent } from "../lib/types";
import { leaderboardFormattedTokens } from "../lib/types";

type StatsPeriod = "day" | "weekly" | "allTime";

type Breakdown = {
  key: string;
  label: string;
  sessions: number;
  tokens: number;
  lines: number;
  seconds: number;
};

const PERIODS: Array<{ id: StatsPeriod; label: string; title: string }> = [
  { id: "day", label: "Last 24h", title: "LAST 24 HOURS" },
  { id: "weekly", label: "Week", title: "THIS WEEK" },
  { id: "allTime", label: "All Time", title: "ALL TIME" },
];

const CHART_COLORS = ["#00FF41", "#FFFFFF", "#9A9A9A", "#5A5A5A", "#34C759", "#007AFF"];

function formatDuration(seconds: number) {
  const totalMinutes = Math.round(seconds / 60);
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  if (hours === 0) return `${minutes}m`;
  return `${hours}h ${String(minutes).padStart(2, "0")}m`;
}

function formatNumber(n: number) {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
  return `${Math.round(n)}`;
}

function sourceLabel(source: string) {
  if (!source) return "Unknown";
  return source.charAt(0).toUpperCase() + source.slice(1);
}

function projectLabel(session: Session) {
  return session.repo_alias || "Unknown Project";
}

function filterSessionsByPeriod(sessions: Session[], period: StatsPeriod) {
  if (period === "allTime") return sessions;

  if (period === "day") {
    const cutoff = Date.now() - 24 * 3600 * 1000;
    return sessions.filter((session) => new Date(session.started_at).getTime() >= cutoff);
  }

  const now = new Date();
  const startOfWeek = new Date(now.getFullYear(), now.getMonth(), now.getDate() - now.getDay());
  return sessions.filter((session) => new Date(session.started_at).getTime() >= startOfWeek.getTime());
}

function filterComponentsByPeriod(components: SessionComponent[], period: StatsPeriod) {
  if (period === "allTime") return components;

  if (period === "day") {
    const cutoff = Date.now() - 24 * 3600 * 1000;
    return components.filter((component) => new Date(component.started_at).getTime() >= cutoff);
  }

  const now = new Date();
  const startOfWeek = new Date(now.getFullYear(), now.getMonth(), now.getDate() - now.getDay());
  return components.filter((component) => new Date(component.started_at).getTime() >= startOfWeek.getTime());
}

function addToBreakdown(map: Map<string, Breakdown>, key: string, label: string, values: Omit<Breakdown, "key" | "label">) {
  const current = map.get(key) ?? { key, label, sessions: 0, tokens: 0, lines: 0, seconds: 0 };
  current.sessions += values.sessions;
  current.tokens += values.tokens;
  current.lines += values.lines;
  current.seconds += values.seconds;
  map.set(key, current);
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

function PieChart({ rows, metric }: { rows: Breakdown[]; metric: "seconds" | "tokens" | "lines" }) {
  const total = rows.reduce((sum, row) => sum + row[metric], 0);
  let cursor = 0;
  const gradient = total > 0
    ? rows.slice(0, 6).map((row, index) => {
        const start = cursor;
        const degrees = Math.max((row[metric] / total) * 360, 2);
        cursor += degrees;
        return `${CHART_COLORS[index % CHART_COLORS.length]} ${start}deg ${cursor}deg`;
      }).join(", ")
    : "var(--color-border) 0deg 360deg";

  return (
    <div className="flex items-center gap-5">
      <div
        className="h-[132px] w-[132px] shrink-0 rounded-full border border-border"
        style={{ background: `conic-gradient(${gradient})` }}
      />
      <div className="min-w-0 flex-1 space-y-2">
        {rows.slice(0, 6).map((row, index) => {
          const pct = total > 0 ? Math.round((row[metric] / total) * 100) : 0;
          return (
            <div key={row.key} className="flex items-center gap-2 font-mono">
              <span
                className="h-2 w-2 shrink-0"
                style={{ background: CHART_COLORS[index % CHART_COLORS.length] }}
              />
              <span className="min-w-0 flex-1 truncate text-[11px] font-bold text-text">
                {row.label}
              </span>
              <span className="text-[10px] text-text-muted">{pct}%</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function BreakdownTable({
  title,
  rows,
  primary,
  columns = 1,
  zeroLinesLabel,
}: {
  title: string;
  rows: Breakdown[];
  primary: "seconds" | "tokens" | "lines";
  columns?: 1 | 2;
  zeroLinesLabel?: string;
}) {
  const total = rows.reduce((sum, row) => sum + row[primary], 0);

  return (
    <div className="border border-border bg-white/[0.012]">
      <div className="flex items-center justify-between gap-3 border-b border-border bg-white/[0.025] px-3 py-3 font-mono">
        <span className="text-[10px] font-bold tracking-[0.18em] text-text-muted">
          {title}
        </span>
        <span className="text-[9px] font-bold tracking-[0.14em] text-text-muted">
          {rows.length} TOTAL
        </span>
      </div>
      <div className={`max-h-[360px] overflow-y-auto ${columns === 2 ? "xl:grid xl:grid-cols-2 xl:gap-x-3 xl:px-3 xl:py-3" : "divide-y divide-border/60"}`}>
        {rows.length > 0 ? rows.map((row) => {
          const percent = total > 0 ? (row[primary] / total) * 100 : 0;
          return (
            <div
              key={row.key}
              className={`${columns === 2 ? "border border-border/60 bg-white/[0.012] px-3 py-2.5" : "px-3 py-3"} font-mono`}
            >
              <div className="flex items-center justify-between gap-3">
                <div className="min-w-0">
                  <div className="truncate text-[13px] font-bold text-text">{row.label}</div>
                  <div className="mt-1 text-[10px] text-text-muted">
                    {formatDuration(row.seconds)} · {row.lines > 0 ? `${formatNumber(row.lines)} LOC` : zeroLinesLabel ?? "0 LOC"} · {row.sessions} sessions
                  </div>
                </div>
                <div className="shrink-0 text-right text-[13px] font-bold tabular-nums text-text">
                  {leaderboardFormattedTokens(row.tokens)}
                </div>
              </div>
              <div className="mt-2 h-1.5 bg-white/[0.05]">
                <div className="h-full bg-logo-green" style={{ width: `${Math.max(percent, 2)}%` }} />
              </div>
            </div>
          );
        }) : (
          <div className="px-3 py-10 text-center font-mono text-[12px] text-text-muted xl:col-span-2">
            NO SESSIONS IN THIS WINDOW
          </div>
        )}
      </div>
    </div>
  );
}

export function PersonalStatsView({
  sessions,
  components,
}: {
  sessions: Session[];
  components: SessionComponent[];
}) {
  const [period, setPeriod] = useState<StatsPeriod>("weekly");
  const periodMeta = PERIODS.find((item) => item.id === period) ?? PERIODS[1];
  const periodSessions = useMemo(() => filterSessionsByPeriod(sessions, period), [sessions, period]);
  const periodComponents = useMemo(() => filterComponentsByPeriod(components, period), [components, period]);

  const stats = useMemo(() => {
    const projects = new Map<string, Breakdown>();
    const harnesses = new Map<string, Breakdown>();
    let tokens = 0;
    let lines = 0;
    let seconds = 0;

    for (const session of periodSessions) {
      const sessionLines = session.lines_added + session.lines_removed;
      tokens += session.tokens;
      lines += sessionLines;
      seconds += session.active_duration;

      const project = projectLabel(session);
      addToBreakdown(projects, project, project, {
        sessions: 1,
        tokens: session.tokens,
        lines: sessionLines,
        seconds: session.active_duration,
      });

    }

    for (const component of periodComponents) {
      const componentLines = component.lines_added + component.lines_removed;
      addToBreakdown(harnesses, component.source, sourceLabel(component.source), {
        sessions: 1,
        tokens: component.tokens,
        lines: componentLines,
        seconds: component.active_duration,
      });
    }

    return {
      tokens,
      lines,
      seconds,
      sessions: periodSessions.length,
      projects: Array.from(projects.values()).sort((a, b) => b.seconds - a.seconds),
      harnesses: Array.from(harnesses.values()).sort((a, b) => b.tokens - a.tokens),
    };
  }, [periodSessions, periodComponents]);

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
              PRIVATE DEV STATS
            </div>
            <h1 className="mt-3 font-led text-[40px] leading-none tracking-[0.1em] text-text desk:text-[58px]">
              YOUR STATS
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
          <MetricTile label="WINDOW" value={periodMeta.title} />
          <MetricTile label="SESSIONS" value={String(stats.sessions)} />
          <MetricTile label="TIME" value={formatDuration(stats.seconds)} />
          <MetricTile label="TOKENS" value={leaderboardFormattedTokens(stats.tokens)} />
        </div>

        <div className="mt-6 grid gap-4 xl:grid-cols-2">
          <div className="border border-border bg-white/[0.012] px-4 py-4">
            <div className="mb-4 font-mono text-[10px] font-bold tracking-[0.18em] text-text-muted">
              TIME BY PROJECT
            </div>
            <PieChart rows={stats.projects} metric="seconds" />
          </div>
          <div className="border border-border bg-white/[0.012] px-4 py-4">
            <div className="mb-4 font-mono text-[10px] font-bold tracking-[0.18em] text-text-muted">
              TOKENS BY HARNESS
            </div>
            <PieChart rows={stats.harnesses} metric="tokens" />
          </div>
        </div>

        <div className="mt-6 grid gap-4">
          <BreakdownTable title="PROJECT BREAKDOWN" rows={stats.projects} primary="seconds" columns={2} />
          <BreakdownTable title="HARNESS BREAKDOWN" rows={stats.harnesses} primary="tokens" zeroLinesLabel="LOC unavailable" />
        </div>

        <div className="mt-3 font-mono text-[10px] leading-relaxed text-text-muted">
          Harness totals use per-source session components. LOC is unavailable for harnesses whose parser does not emit line stats for a session.
        </div>
      </div>
    </div>
  );
}
