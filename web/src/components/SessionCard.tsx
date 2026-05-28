import type { Session } from "../lib/types";
import {
  isInProgress,
  formatDuration,
  formatTokens,
  linesPerHour,
  formatTime,
} from "../lib/types";

export function SessionCard({
  session,
  onClick,
}: {
  session: Session;
  onClick: () => void;
}) {
  const volume = session.lines_added + session.lines_removed;
  const pace = linesPerHour(session);
  const inProgress = isInProgress(session);

  return (
    <button
      onClick={onClick}
      className="w-full cursor-pointer text-left p-[20px] rounded-2xl relative overflow-hidden aspect-[1.35] md:aspect-[1.15] xl:aspect-[1.25] transition-colors hover:bg-white/[0.08]"
      style={{
        background: "rgba(255,255,255,0.06)",
      }}
    >
      {/* Gradient border */}
      <div className="absolute inset-0 rounded-2xl border-[0.5px] border-white/[0.08] pointer-events-none" />

      <div className="flex flex-col h-full">
        {/* Header: > REPO  time */}
        <div className="flex items-center justify-between">
          <span className="flex items-center gap-[6px] text-[11px] font-mono">
            <span className="text-text-muted">&gt;</span>
            <span className="font-bold text-text-dim tracking-[0.1em]">
              {session.repo_alias?.toUpperCase() || session.sources.map(s => s.toUpperCase()).join(" + ")}
            </span>
          </span>
          <span className="text-[11px] font-mono text-text-muted">
            {formatTime(session.ended_at)}
          </span>
        </div>

        {/* Divider — iOS: .padding(.top, 14) */}
        <div className="h-px bg-border mt-[14px]" />

        {/* Spacer — flex-1 pushes duration to center */}
        <div className="flex-1" />

        {/* Duration section — iOS: VStack(spacing: 6) */}
        <div className="flex flex-col gap-[6px]">
          {inProgress ? (
            <span className="inline-block self-start text-[9px] font-bold font-mono tracking-[0.1em] text-logo-green bg-logo-green/[0.12] border-[0.5px] border-logo-green/30 rounded-full px-[8px] py-[4px]">
              IN PROGRESS
            </span>
          ) : (
            <span className="text-[11px] font-bold font-mono text-text-muted tracking-[0.15em]">
              DURATION
            </span>
          )}
          <p className="text-[44px] font-bold font-mono text-text leading-none">
            {formatDuration(session.active_duration)}
          </p>
        </div>

        {/* Spacer — flex-1 pushes stats to bottom */}
        <div className="flex-1" />

        {/* Stats — iOS: VStack(spacing: 22) > HStack > stat.frame(maxWidth: .infinity, alignment: .leading) */}
        <div className="flex flex-col gap-[22px]">
          <div className="flex">
            <Stat label="VOLUME" value={`${volume}`} unit="lines" />
            <Stat label="PACE" value={`${pace}`} unit="lines/hr" />
          </div>
          <div className="flex">
            <Stat label="SCOPE" value={`${session.files_touched}`} unit="files" />
            <Stat label="BURN" value={formatTokens(session.tokens)} unit={session.tokens > 0 ? "tokens" : ""} />
          </div>
        </div>
      </div>
    </button>
  );
}

// iOS: VStack(alignment: .leading, spacing: 5)
// label: 10px mono bold, text-muted, tracking 1.5
// value: 18px mono semibold, text white
function Stat({ label, value, unit }: { label: string; value: string; unit: string }) {
  const display = unit ? `${value} ${unit}` : value;
  return (
    <div className="flex-1 flex flex-col gap-[5px]">
      <p className="text-[10px] font-bold font-mono text-text-muted tracking-[0.1em]">{label}</p>
      <p className="text-[18px] font-semibold font-mono text-text leading-none truncate">
        {display}
      </p>
    </div>
  );
}
