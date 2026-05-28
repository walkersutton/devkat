import { useCallback, useRef, useState } from "react";
import type { Session, LeaderboardEntry } from "../lib/types";
import { dayLabel, leaderboardDisplayName, leaderboardFormattedTokens } from "../lib/types";
import { SessionCard } from "./SessionCard";

export function HomeView({
  sessions,
  leaderboard,
  weeklyLeaderboard,
  loading,
  showInfo,
  onInfoTap,
  onInfoClose,
  onRefresh,
  onSessionTap,
  onCopyTap,
  onSettingsTap,
}: {
  sessions: Session[];
  leaderboard: LeaderboardEntry[];
  weeklyLeaderboard: LeaderboardEntry[];
  loading: boolean;
  showInfo: boolean;
  onInfoTap: () => void;
  onInfoClose: () => void;
  onRefresh: () => void;
  onSessionTap: (s: Session) => void;
  onCopyTap: () => void;
  onSettingsTap: () => void;
}) {
  const [copiedCommand, setCopiedCommand] = useState(false);

  const grouped = groupByDay(sessions);

  return (
    <div className="max-w-lg desk:max-w-6xl mx-auto h-full flex flex-col">
      {/* Title bar — pinned to top */}
      <div className="sticky top-0 z-10 bg-background desk:hidden">
        <div className="flex items-center px-[16px] py-[14px]">
          <button onClick={onSettingsTap} className="w-[32px] h-[32px] flex items-center justify-center desk:hidden">
            <svg className="w-[18px] h-[18px]" fill="white" viewBox="0 0 24 24">
              <path d="M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58a.49.49 0 00.12-.61l-1.92-3.32a.488.488 0 00-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54a.484.484 0 00-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22L2.74 8.87c-.12.21-.08.47.12.61l2.03 1.58c-.05.3-.09.63-.09.94s.02.64.07.94l-2.03 1.58a.49.49 0 00-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58zM12 15.6c-1.98 0-3.6-1.62-3.6-3.6s1.62-3.6 3.6-3.6 3.6 1.62 3.6 3.6-1.62 3.6-3.6 3.6z"/>
            </svg>
          </button>
          <button onClick={onInfoTap} className="w-[32px] h-[32px] flex items-center justify-center desk:hidden">
            <svg className="w-[18px] h-[18px]" fill="none" stroke="white" strokeWidth={1.5} viewBox="0 0 24 24">
              <circle cx="12" cy="12" r="10" />
              <path d="M12 16v-4M12 8h.01" strokeLinecap="round" />
            </svg>
          </button>
          <div className="flex-1 text-center desk:hidden">
            <span className="text-2xl font-normal tracking-[0.1em] text-white font-led">DEVKAT</span>
          </div>
          <button onClick={onCopyTap} className="w-[32px] h-[32px] flex items-center justify-center desk:hidden">
            <svg className="w-[18px] h-[18px]" fill="none" stroke="white" strokeWidth={1.3} viewBox="0 0 22 22">
              <rect x="6" y="6" width="14" height="14" rx="3"/>
              <path d="M4 14.5V4a2.5 2.5 0 012.5-2.5H13"/>
              <path d="M13 9.5v5M10.5 12h5" strokeLinecap="round"/>
            </svg>
          </button>
        </div>
        <div className="h-px bg-border" />
      </div>

      {/* Info sheet overlay */}
      {showInfo && <SetupInfoSheet onClose={onInfoClose} />}

      {/* Scrollable content */}
      <div className="flex-1 overflow-y-auto">
        {leaderboard.length > 0 && (
          <LeaderboardStrip entries={leaderboard} />
        )}
        {weeklyLeaderboard.length > 0 && (
          <WeeklyLeaderboardStrip entries={weeklyLeaderboard} />
        )}
        {loading && sessions.length === 0 ? (
          <div className="flex items-center justify-center py-20">
            <p className="text-text-muted text-xs font-mono tracking-widest">LOADING...</p>
          </div>
        ) : sessions.length === 0 ? (
          <SetupState
            copiedCommand={copiedCommand}
            onCopy={() => {
              navigator.clipboard.writeText("curl -fsSL https://raw.githubusercontent.com/runnon/devkat/main/scripts/install.sh | sh");
              setCopiedCommand(true);
              setTimeout(() => setCopiedCommand(false), 2000);
            }}
            onRefresh={onRefresh}
            onInfoTap={onInfoTap}
            loading={loading}
          />
        ) : (
          <div className="px-[16px] pt-[18px] pb-[100px] desk:px-8 desk:pb-10">
            <div className="flex flex-col gap-[24px] desk:gap-[32px]">
              {grouped.map(({ label, items }) => (
                <section key={label} className="flex flex-col gap-[12px]">
                  <div className="flex items-center gap-[8px]">
                    <span className="text-[12px] font-bold font-mono text-text-dim tracking-[0.15em]">
                      {label}
                    </span>
                    <div className="flex-1 h-px bg-border" />
                  </div>
                  <div className="flex flex-col gap-[12px] desk:grid desk:grid-cols-2 xl:grid-cols-3">
                    {items.map((s) => (
                      <SessionCard key={s.id} session={s} onClick={() => onSessionTap(s)} />
                    ))}
                  </div>
                </section>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function SetupState({
  copiedCommand,
  onCopy,
  onRefresh,
  onInfoTap,
  loading,
}: {
  copiedCommand: boolean;
  onCopy: () => void;
  onRefresh: () => void;
  onInfoTap: () => void;
  loading: boolean;
}) {
  return (
    <div className="flex flex-col items-center justify-center min-h-[70vh] px-5 text-center space-y-5">
      {/* Terminal icon */}
      <svg className="w-11 h-11 text-text-dim" fill="none" stroke="currentColor" strokeWidth={1} viewBox="0 0 24 24">
        <path strokeLinecap="round" strokeLinejoin="round" d="M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/>
      </svg>

      <div className="flex items-center gap-[8px]">
        <p className="text-[11px] font-bold font-mono text-text-dim tracking-[0.15em]">SETUP</p>
        <button onClick={onInfoTap}>
          <svg className="w-[14px] h-[14px] text-logo-green" fill="none" stroke="currentColor" strokeWidth={1.8} viewBox="0 0 24 24">
            <circle cx="12" cy="12" r="10" />
            <path d="M12 16v-4M12 8h.01" strokeLinecap="round" />
          </svg>
        </button>
      </div>

      <div className="space-y-2.5 w-full max-w-sm">
        <p className="text-[11px] font-mono text-text-muted">Paste this in your terminal:</p>
        <div
          onClick={onCopy}
          className="cursor-pointer"
        >
          <div className="bg-surface rounded-[10px] px-3 py-2 text-left">
            <code className="text-[11px] font-mono text-text-muted leading-relaxed break-all">
              curl -fsSL https://raw.githubusercontent.com/runnon/devkat/main/scripts/install.sh | sh
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

function SetupInfoSheet({ onClose }: { onClose: () => void }) {
  const items = [
    { icon: "terminal", title: "Local CLI daemon", body: "The curl command installs devkat-push, a lightweight background daemon that runs on your Mac." },
    { icon: "chart", title: "Tracks AI usage stats", body: "It watches your Claude, Codex, and Cursor sessions and computes aggregate stats — duration, lines changed, tokens burned, and files touched." },
    { icon: "shield", title: "No code leaves your machine", body: "Only numbers are synced. No source code, file paths, prompts, or responses are ever transmitted." },
    { icon: "sync", title: "Syncs to this app", body: "Stats push to your Devkat account so you can view session history and create shareable overlay cards." },
  ];

  const iconSvg = (type: string) => {
    switch (type) {
      case "terminal": return <path strokeLinecap="round" strokeLinejoin="round" d="M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/>;
      case "chart": return <path strokeLinecap="round" strokeLinejoin="round" d="M3 3v18h18M7 16V8m4 8V6m4 10v-4m4 4V4"/>;
      case "shield": return <path strokeLinecap="round" strokeLinejoin="round" d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>;
      case "sync": return <path strokeLinecap="round" strokeLinejoin="round" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>;
      default: return null;
    }
  };

  const [dragY, setDragY] = useState(0);
  const [dragging, setDragging] = useState(false);
  const startY = useRef(0);

  const onPointerDown = useCallback((e: React.PointerEvent) => {
    startY.current = e.clientY;
    setDragging(true);
    (e.target as HTMLElement).setPointerCapture(e.pointerId);
  }, []);

  const onPointerMove = useCallback((e: React.PointerEvent) => {
    if (!dragging) return;
    const dy = Math.max(0, e.clientY - startY.current);
    setDragY(dy);
  }, [dragging]);

  const onPointerUp = useCallback(() => {
    setDragging(false);
    if (dragY > 80) {
      onClose();
    } else {
      setDragY(0);
    }
  }, [dragY, onClose]);

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center desk:items-center" onClick={onClose}>
      <div className="absolute inset-0 bg-black/60" />
      <div
        className="relative w-full max-w-lg bg-[#1A1A1A] rounded-t-2xl p-5 pb-10 desk:max-w-[480px] desk:rounded-2xl desk:pb-5"
        style={{
          transform: `translateY(${dragY}px)`,
          transition: dragging ? "none" : "transform 0.25s ease-out",
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <div
          className="w-full pt-1 pb-4 cursor-grab active:cursor-grabbing touch-none desk:hidden"
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={onPointerUp}
        >
          <div className="w-9 h-1 bg-white/30 rounded-full mx-auto" />
        </div>
        <p className="text-[16px] font-semibold text-white mb-4">How it works</p>
        <div className="flex flex-col gap-3">
          {items.map((item) => (
            <div key={item.title} className="flex items-start gap-3">
              <svg className="w-[14px] h-[14px] mt-0.5 shrink-0 text-logo-green" fill="none" stroke="currentColor" strokeWidth={1.8} viewBox="0 0 24 24">
                {iconSvg(item.icon)}
              </svg>
              <div className="flex flex-col gap-[3px]">
                <span className="text-[13px] font-semibold font-mono text-white">{item.title}</span>
                <span className="text-[12px] font-mono text-text-dim leading-relaxed">{item.body}</span>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

const LEADERBOARD_ICONS: Record<number, string> = { 0: "🦁", 1: "🐆", 2: "🐈" };

function LeaderboardStrip({ entries }: { entries: LeaderboardEntry[] }) {
  return (
    <div className="py-[14px]">
      <div className="px-[16px] flex items-center gap-[8px] mb-[10px] desk:px-8">
        <span className="text-[10px] font-bold font-mono text-text-muted tracking-[0.15em] whitespace-nowrap">
          ALL TIME TOKEN BURNERS
        </span>
        <div className="flex-1 h-px bg-border" />
      </div>
      <div className="overflow-x-auto overflow-y-hidden" style={{ scrollbarWidth: "none" }}>
        <div className="flex items-start gap-[24px] px-[16px] desk:px-8" style={{ width: "max-content" }}>
          {entries.slice(0, 5).map((entry, i) => (
            <div key={entry.email} className="flex flex-col gap-[4px]">
              <div className="flex items-center gap-[6px]">
                <span
                  className="text-[11px] font-bold font-mono"
                  style={{ color: i === 0 ? "var(--color-logo-green)" : "var(--color-text-dim)" }}
                >
                  {i + 1}
                </span>
                <span className="text-[11px] font-semibold font-mono text-text whitespace-nowrap">
                  {leaderboardDisplayName(entry.email)}
                </span>
                {LEADERBOARD_ICONS[i] && (
                  <span className="text-[12px]">{LEADERBOARD_ICONS[i]}</span>
                )}
              </div>
              <span className="text-[10px] font-mono text-text-muted">
                {leaderboardFormattedTokens(entry.total_tokens)}
              </span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function WeeklyLeaderboardStrip({ entries }: { entries: LeaderboardEntry[] }) {
  const left = entries.slice(0, 5);
  const right = entries.slice(5, 10);
  return (
    <div className="py-[14px]">
      <div className="px-[16px] flex items-center gap-[8px] mb-[10px] desk:px-8">
        <span className="text-[10px] font-bold font-mono text-text-muted tracking-[0.15em] whitespace-nowrap">
          WEEKLY TOKEN BURNERS
        </span>
        <div className="flex-1 h-px bg-border" />
      </div>
      <div className="px-[16px] flex gap-[24px] desk:px-8">
        <div className="flex flex-col gap-[8px]">
          {left.map((entry, i) => (
            <WeeklyRow key={entry.email} entry={entry} rank={i + 1} />
          ))}
        </div>
        {right.length > 0 && (
          <div className="flex flex-col gap-[8px]">
            {right.map((entry, i) => (
              <WeeklyRow key={entry.email} entry={entry} rank={i + 6} />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function WeeklyRow({ entry, rank }: { entry: LeaderboardEntry; rank: number }) {
  return (
    <div className="flex items-baseline gap-[6px]">
      <span
        className="text-[10px] font-bold font-mono w-[14px] shrink-0"
        style={{ color: rank === 1 ? "var(--color-logo-green)" : "var(--color-text-dim)" }}
      >
        {rank}
      </span>
      <span className="text-[10px] font-semibold font-mono text-text whitespace-nowrap">
        {leaderboardDisplayName(entry.email)}
      </span>
      <span className="text-[9px] font-mono text-text-muted shrink-0">
        {leaderboardFormattedTokens(entry.total_tokens)}
      </span>
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

  return Array.from(map.entries()).map(([, items]) => ({
    label: dayLabel(items[0].started_at),
    items,
  }));
}
