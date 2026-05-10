import { useRef } from "react";
import { toPng } from "html-to-image";
import type { Session } from "../lib/types";
import {
  formatDuration,
  formatTokens,
  linesPerHour,
  formatTimeHHMM,
} from "../lib/types";

async function copyTile(el: HTMLElement | null): Promise<boolean> {
  if (!el) return false;
  try {
    const dataUrl = await toPng(el, { pixelRatio: 6, backgroundColor: undefined });
    const res = await fetch(dataUrl);
    const blob = await res.blob();
    await navigator.clipboard.write([new ClipboardItem({ "image/png": blob })]);
    return true;
  } catch {
    return false;
  }
}

async function saveTile(el: HTMLElement | null) {
  if (!el) return;
  try {
    const dataUrl = await toPng(el, { pixelRatio: 6, backgroundColor: undefined });
    const a = document.createElement("a");
    a.href = dataUrl;
    a.download = "devkat-tile.png";
    a.click();
  } catch {
    // noop
  }
}

export function OverlayTiles({
  session,
  selectedStatId,
  onStatPickerOpen,
  onCopied,
  onSaved,
}: {
  session: Session;
  selectedStatId: string;
  onStatPickerOpen: () => void;
  onCopied: () => void;
  onSaved: () => void;
}) {
  return (
    <div className="grid grid-cols-2 gap-3">
      <SingleStatTile session={session} statId={selectedStatId} onChevronTap={onStatPickerOpen} onCopied={onCopied} onSaved={onSaved} />
      <DoubleStatTile session={session} onCopied={onCopied} onSaved={onSaved} />
      <TripleStatTile session={session} onCopied={onCopied} onSaved={onSaved} />
      <ClaudeMessageTile session={session} onCopied={onCopied} onSaved={onSaved} />
      <CodexMessageTile session={session} onCopied={onCopied} onSaved={onSaved} />
      <AcidTile session={session} onCopied={onCopied} onSaved={onSaved} />
    </div>
  );
}

/*
 * iOS renders these tiles at 175×110pt (aspect 1.6) and 175×88pt (aspect 2.0).
 * All font sizes below are in CSS px matching iOS pt values exactly.
 * Font: Baskerville-Bold / Baskerville-BoldItalic (mapped via font-serif in tailwind).
 * Message tiles use system monospace (font-mono) at 11px bold.
 */

// ── Tile 1: AuraOverlay (single stat) ──
// VStack(spacing: 4) centered, label 12px Baskerville-Bold, value 17px Baskerville-BoldItalic
function SingleStatTile({
  session,
  statId,
  onChevronTap,
  onCopied,
  onSaved,
}: {
  session: Session;
  statId: string;
  onChevronTap: () => void;
  onCopied: () => void;
  onSaved: () => void;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const stats = getStats(session);
  const stat = stats.find((s) => s.id === statId) ?? stats[0];

  return (
    <div
      ref={ref}
      onClick={async () => { if (await copyTile(ref.current)) onCopied(); }}
      onContextMenu={(e) => { e.preventDefault(); saveTile(ref.current); onSaved(); }}
      className="aspect-[1.6] bg-surface rounded-[14px] border border-white/[0.12] cursor-pointer hover:border-white/[0.2] transition-colors relative select-none flex items-center justify-center"
    >
      {/* Content: centered VStack, spacing 4px, padding-x 8px */}
      <div className="flex flex-col items-center gap-[4px] px-[8px]">
        <span className="text-[12px] font-bold text-white leading-none whitespace-nowrap font-serif">
          {stat.label}
        </span>
        <span className="text-[17px] font-bold italic text-white leading-none whitespace-nowrap font-serif">
          {stat.display}
        </span>
      </div>

      {/* Chevron: 28×28 circle, bg white/12%, positioned 14px from top-right */}
      <button
        onClick={(e) => { e.stopPropagation(); onChevronTap(); }}
        className="absolute top-[14px] right-[14px] w-[28px] h-[28px] rounded-full bg-white/[0.12] flex items-center justify-center"
      >
        <svg className="w-[12px] h-[12px] text-white" fill="none" stroke="currentColor" strokeWidth={2.5} viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7" />
        </svg>
      </button>
    </div>
  );
}

// ── Tile 2: AuraDoubleOverlay (volume + pace) ──
// HStack(spacing: 0), each column: VStack(spacing: 3), label 10px Bold, value 14px BoldItalic, padding-x 6px
function DoubleStatTile({ session, onCopied, onSaved }: { session: Session; onCopied: () => void; onSaved: () => void }) {
  const ref = useRef<HTMLDivElement>(null);
  const volume = session.lines_added + session.lines_removed;
  const pace = linesPerHour(session);

  return (
    <div
      ref={ref}
      onClick={async () => { if (await copyTile(ref.current)) onCopied(); }}
      onContextMenu={(e) => { e.preventDefault(); saveTile(ref.current); onSaved(); }}
      className="aspect-[1.6] bg-surface rounded-[14px] border border-white/[0.12] cursor-pointer hover:border-white/[0.2] transition-colors flex select-none"
    >
      {/* Left column */}
      <div className="flex-1 flex flex-col items-center justify-center gap-[3px] px-[6px]">
        <span className="text-[10px] font-bold text-white leading-none whitespace-nowrap font-serif">
          Volume
        </span>
        <span className="text-[14px] font-bold italic text-white leading-none whitespace-nowrap font-serif">
          {volume} lines
        </span>
      </div>
      {/* Right column */}
      <div className="flex-1 flex flex-col items-center justify-center gap-[3px] px-[6px]">
        <span className="text-[10px] font-bold text-white leading-none whitespace-nowrap font-serif">
          Pace
        </span>
        <span className="text-[14px] font-bold italic text-white leading-none whitespace-nowrap font-serif">
          {pace} lines/hr
        </span>
      </div>
    </div>
  );
}

// ── Tile 3: AuraTripleOverlay (duration + pace + burn) ──
// HStack(spacing: 0), each: VStack(spacing: 2), label 6px Bold, value 8px BoldItalic
function TripleStatTile({ session, onCopied, onSaved }: { session: Session; onCopied: () => void; onSaved: () => void }) {
  const ref = useRef<HTMLDivElement>(null);
  const dur = formatDuration(session.active_duration);
  const pace = linesPerHour(session);
  const tokens = session.tokens;
  const burn = tokens > 0 ? `${formatTokens(tokens)} tokens` : "—";

  const slots = [
    { label: "Duration", value: dur },
    { label: "Pace", value: `${pace} lines/hr` },
    { label: "Burn", value: burn },
  ];

  return (
    <div
      ref={ref}
      onClick={async () => { if (await copyTile(ref.current)) onCopied(); }}
      onContextMenu={(e) => { e.preventDefault(); saveTile(ref.current); onSaved(); }}
      className="aspect-[1.6] bg-surface rounded-[14px] border border-white/[0.12] cursor-pointer hover:border-white/[0.2] transition-colors flex select-none"
    >
      {slots.map((s) => (
        <div key={s.label} className="flex-1 flex flex-col items-center justify-center gap-[2px]">
          <span className="text-[6px] font-bold text-white leading-none whitespace-nowrap font-serif">
            {s.label}
          </span>
          <span className="text-[8px] font-bold italic text-white leading-none whitespace-nowrap font-serif">
            {s.value}
          </span>
        </div>
      ))}
    </div>
  );
}

// ── Tile 4: AuraMessageOverlay (Claude Monkey, blue) ──
// VStack(alignment: .trailing, spacing: 4), padding-h 12
// Bubble: system 11px bold mono, padding-h 12, padding-v 7, bg #007AFF, cornerRadius 14
// Label: system 9px bold mono, white/80%, padding-bottom 3
function ClaudeMessageTile({ session, onCopied, onSaved }: { session: Session; onCopied: () => void; onSaved: () => void }) {
  const ref = useRef<HTMLDivElement>(null);
  const time = formatTimeHHMM(session.started_at);
  const burn = session.tokens > 0 ? `${formatTokens(session.tokens)} tokens` : "—";
  const text = `${formatDuration(session.active_duration)}, ${burn}`;

  return (
    <div
      ref={ref}
      onClick={async () => { if (await copyTile(ref.current)) onCopied(); }}
      onContextMenu={(e) => { e.preventDefault(); saveTile(ref.current); onSaved(); }}
      className="aspect-[2] bg-surface rounded-[14px] border border-white/[0.12] cursor-pointer hover:border-white/[0.2] transition-colors select-none flex flex-col items-end justify-center px-[12px] gap-[4px]"
    >
      <span className="text-[11px] font-bold text-white whitespace-nowrap font-mono px-[12px] py-[7px] bg-imessage-blue rounded-[14px]">
        {text}
      </span>
      <span className="text-[9px] font-bold text-white/80 whitespace-nowrap font-mono pb-[3px]">
        Claude Monkey {time}
      </span>
    </div>
  );
}

// ── Tile 5: CodexMessageOverlay (Codex Monkey, green) ──
// Same layout as Claude but bg #34C759
function CodexMessageTile({ session, onCopied, onSaved }: { session: Session; onCopied: () => void; onSaved: () => void }) {
  const ref = useRef<HTMLDivElement>(null);
  const time = formatTimeHHMM(session.started_at);
  const burn = session.tokens > 0 ? `${formatTokens(session.tokens)} tokens` : "—";
  const text = `${formatDuration(session.active_duration)}, ${burn}`;

  return (
    <div
      ref={ref}
      onClick={async () => { if (await copyTile(ref.current)) onCopied(); }}
      onContextMenu={(e) => { e.preventDefault(); saveTile(ref.current); onSaved(); }}
      className="aspect-[2] bg-surface rounded-[14px] border border-white/[0.12] cursor-pointer hover:border-white/[0.2] transition-colors select-none flex flex-col items-end justify-center px-[12px] gap-[4px]"
    >
      <span className="text-[11px] font-bold text-white whitespace-nowrap font-mono px-[12px] py-[7px] bg-android-green rounded-[14px]">
        {text}
      </span>
      <span className="text-[9px] font-bold text-white/80 whitespace-nowrap font-mono pb-[3px]">
        Codex Monkey {time}
      </span>
    </div>
  );
}

// ── Tile 6: AcidOverlay (all stats, square, custom font) ──
function AcidTile({ session, onCopied, onSaved }: { session: Session; onCopied: () => void; onSaved: () => void }) {
  const ref = useRef<HTMLDivElement>(null);

  const date = new Date(session.started_at).toLocaleDateString("en-US", {
    month: "short", day: "numeric", year: "numeric",
  }).toUpperCase();

  const lines: string[] = [
    date,
    formatDuration(session.active_duration),
    `${session.lines_added + session.lines_removed} LINES`,
    `${linesPerHour(session)} LINES/HR`,
    `${session.files_touched} FILES`,
  ];
  if (session.tokens > 0) lines.push(`${formatTokens(session.tokens)} TOKENS`);

  return (
    <div
      ref={ref}
      onClick={async () => { if (await copyTile(ref.current)) onCopied(); }}
      onContextMenu={(e) => { e.preventDefault(); saveTile(ref.current); onSaved(); }}
      className="aspect-square bg-surface rounded-[14px] border border-white/[0.12] cursor-pointer hover:border-white/[0.2] transition-colors select-none flex flex-col justify-center p-[20px]"
    >
      {lines.map((line, i) => (
        <span
          key={i}
          style={{ fontFamily: '"Acid TM", sans-serif', fontSize: "22px" }}
          className="text-white leading-tight whitespace-nowrap"
        >
          {line}
        </span>
      ))}
    </div>
  );
}

function getStats(session: Session) {
  const volume = session.lines_added + session.lines_removed;
  return [
    { id: "duration", label: "Duration", display: formatDuration(session.active_duration) },
    { id: "pace", label: "Pace", display: `${linesPerHour(session)} lines/hr` },
    { id: "scope", label: "Scope", display: `${session.files_touched} files` },
    { id: "volume", label: "Volume", display: `${volume} lines` },
    { id: "burn", label: "Burn", display: session.tokens > 0 ? `${formatTokens(session.tokens)} tokens` : "—" },
  ];
}
