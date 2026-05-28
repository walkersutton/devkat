export interface Session {
  id: string;
  started_at: string;
  ended_at: string;
  active_duration: number;
  lines_added: number;
  lines_removed: number;
  files_touched: number;
  tokens: number;
  sources: string[];
  models: string[];
  repo_alias: string | null;
  git_branch: string | null;
}

export interface SessionComponent {
  session_id: string;
  source: string;
  source_session_id: string;
  started_at: string;
  ended_at: string;
  active_duration: number;
  lines_added: number;
  lines_removed: number;
  files_touched: number;
  tokens: number;
  model: string;
}

export interface Installation {
  hostname: string;
  installed_at: string;
  last_seen_at: string;
  cli_version: string | null;
}

export interface LeaderboardEntry {
  email: string;
  total_tokens: number;
  total_lines?: number;
  total_sessions?: number;
  active_seconds?: number;
}

export interface SourceLeaderboardEntry {
  source: string;
  email: string;
  total_tokens: number;
  total_sessions: number;
  active_seconds: number;
}

export function leaderboardDisplayName(email: string): string {
  return email.split("@")[0] ?? email;
}

export function leaderboardFormattedTokens(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
  return `${n}`;
}

export function isInProgress(session: Session): boolean {
  const endedAt = new Date(session.ended_at).getTime();
  return Date.now() - endedAt < 4 * 3600 * 1000;
}

export function formatDuration(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (h === 0) return `${m}m`;
  return `${h}h ${String(m).padStart(2, "0")}m`;
}

export function formatTokens(n: number): string {
  if (n === 0) return "—";
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}k`;
  return `${n}`;
}

export function linesPerHour(session: Session): number {
  const hours = Math.max(session.active_duration / 3600, 0.0001);
  return Math.round((session.lines_added + session.lines_removed) / hours);
}

export function dayLabel(dateStr: string): string {
  const date = new Date(dateStr);
  const now = new Date();
  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const startOfDay = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const diff = startOfToday.getTime() - startOfDay.getTime();
  const days = diff / (1000 * 60 * 60 * 24);

  if (days === 0) return "TODAY";
  if (days === 1) return "YESTERDAY";
  return date.toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric" }).toUpperCase();
}

export function formatTime(dateStr: string): string {
  const date = new Date(dateStr);
  return date.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit", hour12: true }).toLowerCase();
}

export function formatTimeHHMM(dateStr: string): string {
  const date = new Date(dateStr);
  return date.toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit", hour12: false });
}
