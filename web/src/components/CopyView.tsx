import { useEffect, useState } from "react";
import type { Session } from "../lib/types";
import { dayLabel, formatDuration, formatTime, formatTokens, isInProgress, linesPerHour } from "../lib/types";
import { OverlayTiles } from "./OverlayTiles";

type CopyTab = "activity" | "totals";

export function CopyView({ session: initialSession, sessions }: { session: Session | null; sessions: Session[] }) {
  const [toast, setToast] = useState<string | null>(null);
  const [tab, setTab] = useState<CopyTab>("activity");
  const [selectedStatId, setSelectedStatId] = useState("duration");
  const [showStatPicker, setShowStatPicker] = useState(false);
  const [localSessionId, setLocalSessionId] = useState<string | null>(
    initialSession?.id ?? sessions[0]?.id ?? null
  );
  const [showSheet, setShowSheet] = useState(false);

  const initialSessionId = initialSession?.id;
  useEffect(() => {
    if (initialSessionId) {
      setLocalSessionId(initialSessionId);
    }
  }, [initialSessionId]);

  const session = sessions.find((s) => s.id === localSessionId) ?? sessions[0] ?? null;

  function showToast(msg: string) {
    setToast(msg);
    setTimeout(() => setToast(null), 1400);
  }

  if (!session) {
    return (
      <div className="flex flex-col items-center justify-center min-h-[70vh] gap-[16px] text-center px-5">
        <p className="text-[12px] font-bold font-mono text-text-dim tracking-[0.15em]">NO SESSIONS YET</p>
        <p className="text-[12px] font-mono text-text-muted">Install the CLI and your sessions will sync here.</p>
      </div>
    );
  }

  const repo = session.repo_alias
    ? session.repo_alias.toUpperCase()
    : session.sources.map((s) => s.toUpperCase()).join(" + ");

  return (
    <div className="relative">
      {/* ── MOBILE ── */}
      <div className="desk:hidden">
        <div className="px-[16px]">
          {/* Hints */}
          <div className="flex flex-col gap-[6px] items-center py-[14px]">
            <div className="flex items-center gap-[6px] text-white">
              <svg className="w-3 h-3" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" d="M8 7v8a2 2 0 002 2h6M8 7V5a2 2 0 012-2h4.586a1 1 0 01.707.293l4.414 4.414a1 1 0 01.293.707V15a2 2 0 01-2 2h-2M8 7H6a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2v-2" />
              </svg>
              <span className="text-[11px] font-bold font-mono tracking-[0.15em]">TAP TO COPY</span>
            </div>
            <div className="flex items-center gap-[6px] text-text-dim">
              <svg className="w-2.5 h-2.5" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" d="M19 14l-7 7m0 0l-7-7m7 7V3" />
              </svg>
              <span className="text-[10px] font-bold font-mono tracking-[0.15em]">PRESS + HOLD TO SAVE</span>
            </div>
          </div>

          {/* Session selector */}
          <button
            onClick={() => setShowSheet(true)}
            className="w-full mt-2 flex items-center justify-between gap-2 border border-border rounded-[12px] bg-white/[0.02] px-[14px] py-[12px] text-left cursor-pointer"
          >
            <div className="flex flex-col gap-[4px] min-w-0">
              <span className="text-[11px] font-bold font-mono tracking-[0.08em] text-text-dim truncate">&gt; {repo}</span>
              <span className="text-[12px] font-mono text-white">
                {formatDuration(session.active_duration)} · {formatTime(session.ended_at)}
              </span>
            </div>
            <span className="flex items-center gap-2 shrink-0">
              <span className="text-[9px] font-bold font-mono tracking-[0.15em] text-text-muted">CHANGE</span>
              <svg className="w-[14px] h-[14px] text-text-dim" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7" />
              </svg>
            </span>
          </button>

          {/* Tabs */}
          <div className="flex mt-[8px]">
            <TabButton label="Activity" active={tab === "activity"} onClick={() => setTab("activity")} />
            <TabButton label="Totals" active={tab === "totals"} onClick={() => setTab("totals")} />
          </div>
        </div>

        {tab === "activity" ? (
          <div className="px-[16px] pt-[12px] pb-[100px]">
            <OverlayTiles
              session={session}
              selectedStatId={selectedStatId}
              onStatPickerOpen={() => setShowStatPicker(true)}
              onCopied={() => showToast("Copied!")}
              onSaved={() => showToast("Saved!")}
            />
          </div>
        ) : (
          <div className="px-[16px] pt-[12px] pb-[100px]">
            <WeeklyTotals sessions={sessions} onCopied={() => showToast("Copied!")} />
          </div>
        )}
      </div>

      {/* ── DESKTOP ── */}
      <div className="hidden desk:block">
        <div
          className="grid justify-center gap-8 pt-7 pb-[60px] px-8"
          style={{ gridTemplateColumns: "300px minmax(0, 540px)" }}
        >
          {/* Sidebar rail */}
          <aside className="sticky top-8 self-start border border-border rounded-[16px] bg-white/[0.012] p-[18px] overflow-hidden">
            {/* Hints */}
            <div className="flex flex-col gap-[6px] items-center py-[6px] pb-[4px]">
              <div className="flex items-center gap-[6px] text-white">
                <svg className="w-3 h-3" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M8 7v8a2 2 0 002 2h6M8 7V5a2 2 0 012-2h4.586a1 1 0 01.707.293l4.414 4.414a1 1 0 01.293.707V15a2 2 0 01-2 2h-2M8 7H6a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2v-2" />
                </svg>
                <span className="text-[11px] font-bold font-mono tracking-[0.15em]">TAP TO COPY</span>
              </div>
              <div className="flex items-center gap-[6px] text-text-dim">
                <svg className="w-2.5 h-2.5" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M19 14l-7 7m0 0l-7-7m7 7V3" />
                </svg>
                <span className="text-[10px] font-bold font-mono tracking-[0.15em]">PRESS + HOLD TO SAVE</span>
              </div>
            </div>

            <div className="text-[10px] font-bold font-mono tracking-[0.18em] text-text-muted mt-4 mb-[10px]">
              SESSION · {sessions.length} RECENT
            </div>
            <div className="flex flex-col gap-2 max-h-[320px] overflow-y-auto">
              {sessions.map((s) => (
                <PickerItem
                  key={s.id}
                  session={s}
                  selected={s.id === session.id}
                  onClick={() => setLocalSessionId(s.id)}
                />
              ))}
            </div>

            {/* Tabs */}
            <div className="flex mt-4">
              <TabButton label="Activity" active={tab === "activity"} onClick={() => setTab("activity")} />
              <TabButton label="Totals" active={tab === "totals"} onClick={() => setTab("totals")} />
            </div>
          </aside>

          {/* Main content */}
          <main>
            {tab === "activity" ? (
              <OverlayTiles
                session={session}
                selectedStatId={selectedStatId}
                onStatPickerOpen={() => setShowStatPicker(true)}
                onCopied={() => showToast("Copied!")}
                onSaved={() => showToast("Saved!")}
              />
            ) : (
              <WeeklyTotals sessions={sessions} onCopied={() => showToast("Copied!")} />
            )}
          </main>
        </div>
      </div>

      {/* Toast */}
      {toast && (
        <div className="fixed inset-0 flex items-center justify-center pointer-events-none z-50">
          <span className="text-white font-semibold text-[17px] px-8 py-[18px] bg-white/10 backdrop-blur-xl rounded-2xl">
            {toast}
          </span>
        </div>
      )}

      {/* Mobile session sheet */}
      {showSheet && (
        <div className="fixed inset-0 z-50 flex items-end justify-center" onClick={() => setShowSheet(false)}>
          <div className="absolute inset-0 bg-black/60" />
          <div
            className="relative w-full max-w-lg bg-surface-raised rounded-t-[18px] px-4 pt-2 pb-7 max-h-[70%] overflow-y-auto"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="w-9 h-1 bg-white/30 rounded-full mx-auto mt-[6px] mb-[14px]" />
            <div className="text-[11px] font-bold font-mono tracking-[0.18em] text-text-muted mb-3">PICK A SESSION</div>
            <div className="flex flex-col gap-2">
              {sessions.map((s) => (
                <PickerItem
                  key={s.id}
                  session={s}
                  selected={s.id === session.id}
                  onClick={() => { setLocalSessionId(s.id); setShowSheet(false); }}
                />
              ))}
            </div>
          </div>
        </div>
      )}

      {/* Stat picker modal */}
      {showStatPicker && (
        <StatPickerSheet
          session={session}
          selectedStatId={selectedStatId}
          onSelect={(id) => { setSelectedStatId(id); setShowStatPicker(false); }}
          onClose={() => setShowStatPicker(false)}
        />
      )}
    </div>
  );
}

function PickerItem({ session, selected, onClick }: { session: Session; selected: boolean; onClick: () => void }) {
  const repo = session.repo_alias ? session.repo_alias : session.sources.join(" + ");
  const live = isInProgress(session);
  return (
    <button
      onClick={onClick}
      className={`w-full text-left cursor-pointer border rounded-[12px] bg-white/[0.015] px-[12px] py-[11px] flex flex-col gap-[6px] transition-colors ${
        selected
          ? "border-logo-green/[0.55] bg-logo-green/[0.05]"
          : "border-border hover:border-white/25"
      }`}
    >
      <div className="flex items-center justify-between gap-2">
        <span className="text-[11px] font-bold font-mono tracking-[0.08em] text-text-dim truncate">
          &gt; {repo.toUpperCase()}
        </span>
        <span className="text-[10px] font-mono text-text-muted shrink-0">
          {dayLabel(session.started_at).slice(0, 3)} · {formatTime(session.ended_at)}
        </span>
      </div>
      <div className="text-[11px] font-mono text-text">
        {live && (
          <span className="text-logo-green font-bold tracking-[0.1em]">● IN PROGRESS · </span>
        )}
        <b className="text-white font-bold">{formatDuration(session.active_duration)}</b>
        <span className="text-text-muted"> · {session.lines_added + session.lines_removed} lines · {formatTokens(session.tokens)} tokens</span>
      </div>
    </button>
  );
}

function TabButton({ label, active, onClick }: { label: string; active: boolean; onClick: () => void }) {
  return (
    <button onClick={onClick} className="flex-1 cursor-pointer">
      <div className="space-y-2">
        <p className={`text-[14px] text-center ${active ? "font-semibold text-white" : "text-white/40"}`}>
          {label}
        </p>
        <div className={`h-px ${active ? "bg-white" : "bg-transparent"}`} />
      </div>
    </button>
  );
}

function StatPickerSheet({
  session,
  selectedStatId,
  onSelect,
  onClose,
}: {
  session: Session;
  selectedStatId: string;
  onSelect: (id: string) => void;
  onClose: () => void;
}) {
  const stats = getStatSlots(session);

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center desk:items-center" onClick={onClose}>
      <div className="absolute inset-0 bg-black/50" />
      <div
        className="relative w-full max-w-lg bg-surface-raised rounded-t-2xl px-5 pt-4 pb-8 desk:rounded-2xl desk:pb-5"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="w-9 h-1 bg-white/30 rounded-full mx-auto mb-4 desk:hidden" />
        <div className="grid grid-cols-3 gap-3">
          {stats.map((stat) => (
            <button
              key={stat.id}
              onClick={() => onSelect(stat.id)}
              className={`flex flex-col items-center py-[22px] bg-surface rounded-[14px] border cursor-pointer ${
                stat.id === selectedStatId ? "border-white" : "border-white/[0.12]"
              }`}
            >
              <span className="text-[12px] text-white/50 font-serif">
                {stat.label}
              </span>
              <span className="text-[17px] text-white mt-1 font-serif">
                {stat.display}
              </span>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

function WeeklyTotals({ sessions }: { sessions: Session[]; onCopied: () => void }) {
  const weekSessions = filterToCurrentWeek(sessions);
  const totalDuration = weekSessions.reduce((sum, s) => sum + s.active_duration, 0);
  const totalLines = weekSessions.reduce((sum, s) => sum + s.lines_added + s.lines_removed, 0);
  const totalTokens = weekSessions.reduce((sum, s) => sum + s.tokens, 0);
  const hours = Math.max(totalDuration / 3600, 0.0001);
  const pace = Math.round(totalLines / hours);

  const dur = formatDuration(totalDuration);
  const burn = totalTokens > 0 ? `${formatTokens(totalTokens)} tokens` : "—";

  return (
    <div className="grid grid-cols-2 gap-3">
      <div className="aspect-[1.6] bg-surface rounded-[14px] border border-white/[0.12] flex items-center justify-center px-[14px] py-[12px]">
        <div className="flex flex-col items-start gap-[4px]">
          <p className="text-[9px] font-bold text-white font-serif leading-none">
            This Week
          </p>
          {[dur, `${pace} lines/hr`, burn].map((v, i) => (
            <span
              key={i}
              className="text-[12px] text-white italic font-serif leading-tight whitespace-nowrap"
            >
              {v}
            </span>
          ))}
        </div>
      </div>
    </div>
  );
}

function filterToCurrentWeek(sessions: Session[]): Session[] {
  const now = new Date();
  const startOfWeek = new Date(now.getFullYear(), now.getMonth(), now.getDate() - now.getDay());
  const cutoff = startOfWeek.getTime();
  return sessions.filter((s) => new Date(s.started_at).getTime() >= cutoff);
}

interface StatSlotWeb {
  id: string;
  label: string;
  display: string;
}

function getStatSlots(session: Session): StatSlotWeb[] {
  const volume = session.lines_added + session.lines_removed;
  return [
    { id: "duration", label: "Duration", display: formatDuration(session.active_duration) },
    { id: "pace", label: "Pace", display: `${linesPerHour(session)} lines/hr` },
    { id: "scope", label: "Scope", display: `${session.files_touched} files` },
    { id: "volume", label: "Volume", display: `${volume} lines` },
    { id: "burn", label: "Burn", display: session.tokens > 0 ? `${formatTokens(session.tokens)} tokens` : "—" },
  ];
}
