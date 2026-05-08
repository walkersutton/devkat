import { useState } from "react";
import type { Session, LeaderboardEntry } from "../lib/types";
import { dayLabel, leaderboardDisplayName, leaderboardFormattedTokens } from "../lib/types";
import { SessionCard } from "./SessionCard";

export function HomeView({
  sessions,
  leaderboard,
  loading,
  onRefresh,
  onSessionTap,
  onCopyTap,
  onSettingsTap,
}: {
  sessions: Session[];
  leaderboard: LeaderboardEntry[];
  loading: boolean;
  onRefresh: () => void;
  onSessionTap: (s: Session) => void;
  onCopyTap: () => void;
  onSettingsTap: () => void;
}) {
  const [copiedCommand, setCopiedCommand] = useState(false);

  const grouped = groupByDay(sessions);

  return (
    <div className="max-w-lg mx-auto h-full flex flex-col">
      {/* Title bar — pinned to top */}
      <div className="sticky top-0 z-10 bg-background">
        <div className="flex items-center px-[16px] py-[14px]">
          <button onClick={onSettingsTap} className="w-[32px] h-[32px] flex items-center justify-center">
            {/* SF Symbol: gearshape.fill */}
            <svg className="w-[18px] h-[18px]" fill="white" viewBox="0 0 24 24">
              <path d="M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58a.49.49 0 00.12-.61l-1.92-3.32a.488.488 0 00-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54a.484.484 0 00-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22L2.74 8.87c-.12.21-.08.47.12.61l2.03 1.58c-.05.3-.09.63-.09.94s.02.64.07.94l-2.03 1.58a.49.49 0 00-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58zM12 15.6c-1.98 0-3.6-1.62-3.6-3.6s1.62-3.6 3.6-3.6 3.6 1.62 3.6 3.6-1.62 3.6-3.6 3.6z"/>
            </svg>
          </button>
          <div className="flex-1 text-center">
            <span className="text-2xl font-semibold tracking-[0.1em] text-white font-led">DEVKAT</span>
          </div>
          <button onClick={onCopyTap} className="w-[32px] h-[32px] flex items-center justify-center">
            {/* SF Symbol: plus.square.on.square */}
            <svg className="w-[18px] h-[18px]" fill="none" stroke="white" strokeWidth={1.3} viewBox="0 0 22 22">
              <rect x="6" y="6" width="14" height="14" rx="3"/>
              <path d="M4 14.5V4a2.5 2.5 0 012.5-2.5H13"/>
              <path d="M13 9.5v5M10.5 12h5" strokeLinecap="round"/>
            </svg>
          </button>
        </div>
        <div className="h-px bg-border" />
      </div>

      {/* Scrollable content */}
      <div className="flex-1 overflow-y-auto">
        {loading && sessions.length === 0 ? (
        <div className="flex items-center justify-center py-20">
          <p className="text-text-muted text-xs font-mono tracking-widest">LOADING...</p>
        </div>
      ) : sessions.length === 0 ? (
        <SetupState
          copiedCommand={copiedCommand}
          onCopy={() => {
            navigator.clipboard.writeText("curl -fsSL https://raw.githubusercontent.com/runnon/devkat-releases/main/install.sh | sh");
            setCopiedCommand(true);
            setTimeout(() => setCopiedCommand(false), 2000);
          }}
          onRefresh={onRefresh}
          loading={loading}
        />
      ) : (
        <>
          {leaderboard.length > 0 && (
            <LeaderboardStrip entries={leaderboard} />
          )}
          <div className="px-[16px] pt-[18px] pb-[100px]">
          <div className="flex flex-col gap-[24px]">
            {grouped.map(({ label, items }) => (
              <section key={label} className="flex flex-col gap-[12px]">
                <div className="flex items-center gap-[8px]">
                  <span className="text-[12px] font-bold font-mono text-text-dim tracking-[0.15em]">
                    {label}
                  </span>
                  <div className="flex-1 h-px bg-border" />
                </div>
                <div className="flex flex-col gap-[12px]">
                  {items.map((s) => (
                    <SessionCard key={s.id} session={s} onClick={() => onSessionTap(s)} />
                  ))}
                </div>
              </section>
            ))}
          </div>
        </div>
        </>
      )}
      </div>
    </div>
  );
}

function SetupState({
  copiedCommand,
  onCopy,
  onRefresh,
  loading,
}: {
  copiedCommand: boolean;
  onCopy: () => void;
  onRefresh: () => void;
  loading: boolean;
}) {
  return (
    <div className="flex flex-col items-center justify-center min-h-[70vh] px-5 text-center space-y-5">
      {/* Terminal icon */}
      <svg className="w-11 h-11 text-text-dim" fill="none" stroke="currentColor" strokeWidth={1} viewBox="0 0 24 24">
        <path strokeLinecap="round" strokeLinejoin="round" d="M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/>
      </svg>

      <p className="text-[11px] font-bold font-mono text-text-dim tracking-[0.15em]">SETUP</p>

      <div className="space-y-2.5 w-full max-w-sm">
        <p className="text-[11px] font-mono text-text-muted">Paste this in your terminal:</p>
        <div
          onClick={onCopy}
          className="cursor-pointer"
        >
          <div className="bg-surface rounded-[10px] px-3 py-2 text-left">
            <code className="text-[11px] font-mono text-text-muted leading-relaxed break-all">
              curl -fsSL https://raw.githubusercontent.com/runnon/devkat-releases/main/install.sh | sh
            </code>
          </div>
          <p className="text-[10px] font-bold font-mono text-logo-green tracking-[0.1em] mt-2">
            {copiedCommand ? "COPIED" : "TAP HERE TO COPY"}
          </p>
        </div>
      </div>

      <p className="text-[10px] font-mono text-text-muted leading-relaxed">
        Sessions from Claude, Codex, and Cursor<br/>will sync automatically.
      </p>

      <button
        onClick={onRefresh}
        disabled={loading}
        className="flex items-center gap-2 text-logo-green border border-logo-green/50 rounded-lg px-3.5 py-2 mt-2 disabled:opacity-50"
      >
        <svg className="w-[11px] h-[11px]" fill="none" stroke="currentColor" strokeWidth={2.5} viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
        </svg>
        <span className="text-[10px] font-bold font-mono tracking-[0.1em]">
          {loading ? "CHECKING..." : "CHECK CONNECTION"}
        </span>
      </button>
    </div>
  );
}

const LEADERBOARD_ICONS = ["🦁", "🐆", "🐈"];

function LeaderboardStrip({ entries }: { entries: LeaderboardEntry[] }) {
  return (
    <div className="py-[14px]">
      <div className="px-[16px] flex items-center gap-[8px] mb-[10px]">
        <span className="text-[10px] font-bold font-mono text-text-muted tracking-[0.15em]">
          TOP TOKEN BURNERS
        </span>
        <div className="flex-1 h-px bg-border" />
      </div>
      <div className="px-[16px] grid grid-cols-3 gap-[12px]">
        {entries.slice(0, 3).map((entry, i) => (
          <div key={entry.email} className="flex flex-col gap-[4px] min-w-0">
            <div className="flex items-center gap-[6px]">
              <span
                className="text-[11px] font-bold font-mono"
                style={{ color: i === 0 ? "var(--logo-green)" : "var(--text-dim)" }}
              >
                {i + 1}
              </span>
              <span className="text-[11px] font-semibold font-mono text-text truncate">
                {leaderboardDisplayName(entry.email)}
              </span>
              <span className="text-[12px]">{LEADERBOARD_ICONS[i]}</span>
            </div>
            <span className="text-[10px] font-mono text-text-muted">
              {leaderboardFormattedTokens(entry.total_tokens)}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

function groupByDay(sessions: Session[]): { label: string; items: Session[] }[] {
  const map = new Map<string, Session[]>();

  for (const s of sessions) {
    const d = new Date(s.started_at);
    const key = `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
    if (!map.has(key)) map.set(key, []);
    map.get(key)!.push(s);
  }

  return Array.from(map.entries()).map(([_, items]) => ({
    label: dayLabel(items[0].started_at),
    items,
  }));
}
