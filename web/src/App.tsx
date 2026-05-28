import { useCallback, useEffect, useState } from "react";
import { Routes, Route, Navigate, useNavigate, useLocation } from "react-router-dom";
import { supabase } from "./lib/supabase";
import { identify, reset } from "./lib/posthog";
import { AuthView } from "./components/AuthView";
import { HomeView } from "./components/HomeView";
import { CopyView } from "./components/CopyView";
import { LeaderboardView } from "./components/LeaderboardView";
import { PersonalStatsView } from "./components/PersonalStatsView";
import { SettingsView } from "./components/SettingsView";
import type { Session as UserSession } from "@supabase/supabase-js";
import type { Session, SessionComponent, LeaderboardEntry, SourceLeaderboardEntry, Installation } from "./lib/types";

type Tab = "home" | "leaderboard" | "stats" | "copy";

function pathToTab(pathname: string): Tab {
  if (pathname.startsWith("/leaderboard")) return "leaderboard";
  if (pathname === "/stats") return "stats";
  if (pathname === "/copy") return "copy";
  return "home";
}

const CLI_INSTALL_COMMAND = "curl -fsSL https://raw.githubusercontent.com/runnon/devkat/main/scripts/install.sh | sh";

function normalizeVersion(version: string) {
  return version.trim().replace(/^v/i, "");
}

function compareVersions(a: string, b: string) {
  const left = normalizeVersion(a).split(/[.-]/).map((part) => Number.parseInt(part, 10) || 0);
  const right = normalizeVersion(b).split(/[.-]/).map((part) => Number.parseInt(part, 10) || 0);
  const length = Math.max(left.length, right.length);

  for (let i = 0; i < length; i += 1) {
    const diff = (left[i] ?? 0) - (right[i] ?? 0);
    if (diff !== 0) return diff;
  }

  return 0;
}

function newestInstalledVersion(installations: Installation[]) {
  return installations
    .map((installation) => installation.cli_version)
    .filter((version): version is string => Boolean(version))
    .sort(compareVersions)
    .at(-1) ?? null;
}

export default function App() {
  const navigate = useNavigate();
  const location = useLocation();
  const [session, setSession] = useState<UserSession | null>(null);
  const [loading, setLoading] = useState(true);
  const activeTab: Tab = pathToTab(location.pathname);
  const [selectedSession, setSelectedSession] = useState<Session | null>(null);
  const [showSettings, setShowSettings] = useState(false);
  const [showInfo, setShowInfo] = useState(false);
  const [sessions, setSessions] = useState<Session[]>([]);
  const [sessionComponents, setSessionComponents] = useState<SessionComponent[]>([]);
  const [sessionsLoading, setSessionsLoading] = useState(false);
  const [availableCLIUpdate, setAvailableCLIUpdate] = useState<string | null>(null);
  const [leaderboard, setLeaderboard] = useState<LeaderboardEntry[]>([]);
  const [weeklyLeaderboard, setWeeklyLeaderboard] = useState<LeaderboardEntry[]>([]);
  const [dailyLeaderboard, setDailyLeaderboard] = useState<LeaderboardEntry[]>([]);
  const [sourceLeaderboard, setSourceLeaderboard] = useState<Record<string, SourceLeaderboardEntry[]>>({
    day: [],
    weekly: [],
    allTime: [],
  });

  const fetchSessions = useCallback(async () => {
    setSessionsLoading(true);
    const [sessionsResult, componentsResult] = await Promise.all([
      supabase
      .from("sessions")
      .select("*")
      .order("started_at", { ascending: false })
      .limit(200),
      supabase
        .from("session_components")
        .select("session_id,source,source_session_id,started_at,ended_at,active_duration,lines_added,lines_removed,files_touched,tokens,model")
        .order("started_at", { ascending: false })
        .limit(1000),
    ]);
    if (!sessionsResult.error && sessionsResult.data) setSessions(sessionsResult.data as Session[]);
    if (!componentsResult.error && componentsResult.data) setSessionComponents(componentsResult.data as SessionComponent[]);
    setSessionsLoading(false);
  }, []);

  const fetchLeaderboard = useCallback(async () => {
    const [
      allTimeResult,
      weeklyResult,
      dailyResult,
      allTimeSourceResult,
      weeklySourceResult,
      dailySourceResult,
    ] = await Promise.all([
      supabase.rpc("token_leaderboard"),
      supabase.rpc("weekly_token_leaderboard"),
      supabase.rpc("last_24h_token_leaderboard"),
      supabase.rpc("source_token_leaderboard", { p_window: "all_time" }),
      supabase.rpc("source_token_leaderboard", { p_window: "weekly" }),
      supabase.rpc("source_token_leaderboard", { p_window: "24h" }),
    ]);
    if (!allTimeResult.error && allTimeResult.data) setLeaderboard(allTimeResult.data as LeaderboardEntry[]);
    if (!weeklyResult.error && weeklyResult.data) setWeeklyLeaderboard(weeklyResult.data as LeaderboardEntry[]);
    if (!dailyResult.error && dailyResult.data) setDailyLeaderboard(dailyResult.data as LeaderboardEntry[]);
    setSourceLeaderboard({
      allTime: !allTimeSourceResult.error && allTimeSourceResult.data ? allTimeSourceResult.data as SourceLeaderboardEntry[] : [],
      weekly: !weeklySourceResult.error && weeklySourceResult.data ? weeklySourceResult.data as SourceLeaderboardEntry[] : [],
      day: !dailySourceResult.error && dailySourceResult.data ? dailySourceResult.data as SourceLeaderboardEntry[] : [],
    });
  }, []);

  const fetchInstallationsAndCheckCLI = useCallback(async () => {
    const { data, error } = await supabase
      .from("installations")
      .select("hostname,installed_at,last_seen_at,cli_version")
      .order("last_seen_at", { ascending: false });
    if (error || !data || data.length === 0) {
      setAvailableCLIUpdate(null);
      return;
    }

    try {
      const response = await fetch("https://api.github.com/repos/runnon/devkat/releases/latest", {
        headers: { Accept: "application/vnd.github+json" },
        cache: "no-store",
      });
      if (!response.ok) return;

      const release = await response.json() as { tag_name?: string };
      const latestTag = release.tag_name;
      if (!latestTag) return;

      const latestVersion = normalizeVersion(latestTag);
      const installedVersion = newestInstalledVersion(data as Installation[]);
      const updateNeeded = installedVersion
        ? compareVersions(installedVersion, latestVersion) < 0
        : true;

      setAvailableCLIUpdate(updateNeeded ? latestTag : null);
    } catch {
      // CLI update checks are non-critical; avoid disrupting the dashboard.
    }
  }, []);

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session);
      if (session?.user?.email) {
        identify(session.user.email, { email: session.user.email });
      }
      setLoading(false);
    });

    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      (event, session) => {
        setSession(session);
        if (event === "SIGNED_IN" && session?.user?.email) {
          identify(session.user.email, { email: session.user.email });
        } else if (event === "SIGNED_OUT") {
          reset();
        }
      }
    );

    return () => subscription.unsubscribe();
  }, []);

  useEffect(() => {
    queueMicrotask(() => {
      if (session) {
        void fetchSessions();
        void fetchLeaderboard();
        void fetchInstallationsAndCheckCLI();
      } else {
        setSessions([]);
        setSessionComponents([]);
        setAvailableCLIUpdate(null);
        setLeaderboard([]);
        setWeeklyLeaderboard([]);
        setDailyLeaderboard([]);
        setSourceLeaderboard({ day: [], weekly: [], allTime: [] });
      }
    });
  }, [session, fetchSessions, fetchLeaderboard, fetchInstallationsAndCheckCLI]);

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <p className="text-text-muted text-xs font-mono tracking-widest">LOADING...</p>
      </div>
    );
  }

  if (!session) {
    return <AuthView />;
  }

  return (
    <div className="min-h-screen bg-background desk:flex">
      {!showSettings && (
        <aside className="hidden desk:flex w-[220px] shrink-0 flex-col border-r border-border bg-black/60 px-4 py-6">
          <div className="mb-8 px-3 flex items-start justify-between">
            <div>
              <div className="font-led text-[28px] tracking-[0.08em] text-logo-green">devkat</div>
              <div className="mt-1 text-[10px] font-mono font-bold tracking-[0.18em] text-text-muted">WEB</div>
            </div>
            <button onClick={() => setShowInfo(true)} className="mt-1 w-[28px] h-[28px] cursor-pointer flex items-center justify-center text-text-muted hover:text-text transition-colors">
              <svg className="w-[16px] h-[16px]" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24">
                <circle cx="12" cy="12" r="10" />
                <path d="M12 16v-4M12 8h.01" strokeLinecap="round" />
              </svg>
            </button>
          </div>
          <div className="flex flex-col gap-2">
            <SidebarButton active={activeTab === "home"} icon="home" label="Home" onClick={() => { navigate("/"); setShowSettings(false); }} />
            <SidebarButton active={activeTab === "leaderboard"} icon="leaderboard" label="Leaderboard" onClick={() => { navigate("/leaderboard"); setShowSettings(false); }} />
            <SidebarButton active={activeTab === "stats"} icon="stats" label="Your Stats" onClick={() => { navigate("/stats"); setShowSettings(false); }} />
            <SidebarButton active={activeTab === "copy"} icon="copy" label="Copy" onClick={() => { navigate("/copy"); setShowSettings(false); }} />
            <SidebarButton active={false} icon="settings" label="Settings" onClick={() => setShowSettings(true)} />
          </div>
        </aside>
      )}

      {/* Content area */}
      <div className="flex-1 min-w-0 overflow-auto pb-[70px] desk:pb-0">
        {showSettings ? (
          <SettingsView
            email={session.user.email ?? ""}
            onClose={() => setShowSettings(false)}
          />
        ) : (
          <Routes>
            <Route path="/" element={
              <HomeView
                sessions={sessions}
                leaderboard={leaderboard}
                weeklyLeaderboard={weeklyLeaderboard}
                loading={sessionsLoading}
                showInfo={showInfo}
                onInfoTap={() => setShowInfo(true)}
                onInfoClose={() => setShowInfo(false)}
                onRefresh={fetchSessions}
                onSessionTap={(s) => {
                  setSelectedSession(s);
                  navigate("/copy");
                }}
                onCopyTap={() => navigate("/copy")}
                onSettingsTap={() => setShowSettings(true)}
              />
            } />
            <Route path="/leaderboard" element={<Navigate to="/leaderboard/weekly" replace />} />
            <Route path="/leaderboard/:period" element={
              <LeaderboardView
                dailyLeaderboard={dailyLeaderboard}
                weeklyLeaderboard={weeklyLeaderboard}
                allTimeLeaderboard={leaderboard}
                sourceLeaderboard={sourceLeaderboard}
              />
            } />
            <Route path="/stats" element={<PersonalStatsView sessions={sessions} components={sessionComponents} />} />
            <Route path="/copy" element={<CopyView session={selectedSession} sessions={sessions} />} />
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        )}
      </div>

      {availableCLIUpdate && (
        <CLIUpdatePrompt
          version={availableCLIUpdate}
          onDismiss={() => setAvailableCLIUpdate(null)}
        />
      )}

      {/* Bottom tab bar */}
      {!showSettings && (
        <nav className="fixed bottom-0 left-0 right-0 z-40 desk:hidden">
          <div className="bg-black/80 backdrop-blur-xl">
            <div className="max-w-lg mx-auto">
              <div className="h-px bg-white/15" />
              <div className="flex items-center justify-center gap-[36px] py-3">
              <TabIcon
                active={activeTab === "home"}
                icon={activeTab === "home" ? "house-fill" : "house"}
                onClick={() => { navigate("/"); setShowSettings(false); }}
              />
              <TabIcon
                active={activeTab === "leaderboard"}
                icon={activeTab === "leaderboard" ? "leaderboard-fill" : "leaderboard"}
                onClick={() => { navigate("/leaderboard"); setShowSettings(false); }}
              />
              <TabIcon
                active={activeTab === "stats"}
                icon={activeTab === "stats" ? "stats-fill" : "stats"}
                onClick={() => { navigate("/stats"); setShowSettings(false); }}
              />
              <TabIcon
                active={activeTab === "copy"}
                icon={activeTab === "copy" ? "copy-fill" : "copy"}
                onClick={() => { navigate("/copy"); setShowSettings(false); }}
              />
              </div>
            </div>
          </div>
        </nav>
      )}
    </div>
  );
}

function CLIUpdatePrompt({
  version,
  onDismiss,
}: {
  version: string;
  onDismiss: () => void;
}) {
  const [copied, setCopied] = useState(false);

  async function copyCommand() {
    await navigator.clipboard.writeText(CLI_INSTALL_COMMAND);
    setCopied(true);
    setTimeout(() => setCopied(false), 1800);
  }

  return (
    <div className="fixed inset-x-3 bottom-[82px] z-50 mx-auto max-w-lg desk:left-auto desk:right-6 desk:bottom-6 desk:mx-0 desk:w-[420px]">
      <div className="border border-logo-green/40 bg-surface-raised/95 px-4 py-4 shadow-2xl shadow-black/50 backdrop-blur-xl">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <div className="font-mono text-[11px] font-bold tracking-[0.16em] text-logo-green">
              CLI UPDATE AVAILABLE
            </div>
            <p className="mt-2 font-mono text-[12px] leading-relaxed text-text-dim">
              Version {version} is ready. Run the installer on your Mac to update `devkat-push`.
            </p>
          </div>
          <button
            onClick={onDismiss}
            className="flex h-7 w-7 shrink-0 cursor-pointer items-center justify-center text-text-muted transition-colors hover:text-text"
          >
            <svg className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24">
              <path strokeLinecap="round" d="M6 6l12 12M18 6L6 18" />
            </svg>
          </button>
        </div>
        <button
          onClick={copyCommand}
          className="mt-3 w-full cursor-pointer bg-white/[0.06] px-3 py-2 text-left transition-colors hover:bg-white/[0.09]"
        >
          <code className="block break-all font-mono text-[11px] leading-relaxed text-text">
            {CLI_INSTALL_COMMAND}
          </code>
          <span className="mt-2 block font-mono text-[10px] font-bold tracking-[0.14em] text-logo-green">
            {copied ? "COPIED" : "COPY COMMAND"}
          </span>
        </button>
      </div>
    </div>
  );
}

function SidebarButton({
  active,
  icon,
  label,
  onClick,
}: {
  active: boolean;
  icon: "home" | "leaderboard" | "stats" | "copy" | "settings";
  label: string;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className={`flex cursor-pointer items-center gap-3 rounded-2xl px-3 py-3 text-left transition-colors ${
        active ? "bg-white/[0.09] text-text" : "text-text-muted hover:bg-white/[0.05] hover:text-text-dim"
      }`}
    >
      {icon === "home" && (
        <svg className="w-[18px] h-[18px]" fill={active ? "currentColor" : "none"} stroke="currentColor" strokeWidth={1.5} viewBox="0 0 22 22">
          <path d="M2.5 10L11 2.5 19.5 10M5 9.5v9.5h4.5v-5.5h3v5.5H17V9.5" />
        </svg>
      )}
      {icon === "copy" && (
        <svg className="w-[18px] h-[18px]" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 22 22">
          <rect x="6" y="6" width="14" height="14" rx="3" />
          <path d="M4 14.5V4a2.5 2.5 0 012.5-2.5H13" />
          <path d="M13 9.5v5M10.5 12h5" strokeLinecap="round" />
        </svg>
      )}
      {icon === "leaderboard" && (
        <svg className="w-[18px] h-[18px]" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 22 22">
          <path d="M4 18.5h14" strokeLinecap="round" />
          <path d="M5 18.5V11h3.5v7.5M9.25 18.5V5h3.5v13.5M13.5 18.5V8h3.5v10.5" />
        </svg>
      )}
      {icon === "stats" && (
        <svg className="w-[18px] h-[18px]" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 22 22">
          <circle cx="11" cy="11" r="7" />
          <path d="M11 4v7l5 5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      )}
      {icon === "settings" && (
        <svg className="w-[18px] h-[18px]" fill="currentColor" viewBox="0 0 24 24">
          <path d="M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58a.49.49 0 00.12-.61l-1.92-3.32a.488.488 0 00-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54a.484.484 0 00-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22L2.74 8.87c-.12.21-.08.47.12.61l2.03 1.58c-.05.3-.09.63-.09.94s.02.64.07.94l-2.03 1.58a.49.49 0 00-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58zM12 15.6c-1.98 0-3.6-1.62-3.6-3.6s1.62-3.6 3.6-3.6 3.6 1.62 3.6 3.6-1.62 3.6-3.6 3.6z" />
        </svg>
      )}
      <span className="text-[12px] font-bold font-mono tracking-[0.12em]">{label.toUpperCase()}</span>
    </button>
  );
}

function TabIcon({ icon, onClick }: { active: boolean; icon: string; onClick: () => void }) {
  return (
    <button onClick={onClick} className="w-14 h-[50px] flex items-center justify-center">
      {/* SF Symbol: house.fill */}
      {icon === "house-fill" && (
        <svg className="w-[22px] h-[22px]" fill="white" viewBox="0 0 22 22">
          <path d="M11 1.5L1 9.5h3v10h5v-6h4v6h5v-10h3L11 1.5z"/>
        </svg>
      )}
      {/* SF Symbol: house */}
      {icon === "house" && (
        <svg className="w-[22px] h-[22px] opacity-45" fill="none" stroke="white" strokeWidth={1.2} viewBox="0 0 22 22">
          <path d="M2.5 10L11 2.5 19.5 10M5 9.5v9.5h4.5v-5.5h3v5.5H17V9.5"/>
        </svg>
      )}
      {/* SF Symbol: plus.square.on.square.fill */}
      {icon === "copy-fill" && (
        <svg className="w-[22px] h-[22px]" fill="white" viewBox="0 0 22 22">
          <rect x="6" y="6" width="14" height="14" rx="3"/>
          <path d="M4 14.5V4a2.5 2.5 0 012.5-2.5H13" stroke="white" strokeWidth={1.5} fill="none"/>
          <path d="M13 9.5v5M10.5 12h5" stroke="black" strokeWidth={1.5} strokeLinecap="round"/>
        </svg>
      )}
      {icon === "leaderboard-fill" && (
        <svg className="w-[22px] h-[22px]" fill="white" viewBox="0 0 22 22">
          <path d="M4 19.2a.7.7 0 010-1.4h14a.7.7 0 110 1.4H4z" />
          <rect x="4.75" y="10.5" width="3.8" height="7.1" rx="0.8" />
          <rect x="9.1" y="4.25" width="3.8" height="13.35" rx="0.8" />
          <rect x="13.45" y="7.5" width="3.8" height="10.1" rx="0.8" />
        </svg>
      )}
      {icon === "leaderboard" && (
        <svg className="w-[22px] h-[22px] opacity-45" fill="none" stroke="white" strokeWidth={1.2} viewBox="0 0 22 22">
          <path d="M4 18.5h14" strokeLinecap="round" />
          <path d="M5 18.5V11h3.5v7.5M9.25 18.5V5h3.5v13.5M13.5 18.5V8h3.5v10.5" />
        </svg>
      )}
      {icon === "stats-fill" && (
        <svg className="w-[22px] h-[22px]" fill="white" viewBox="0 0 22 22">
          <path d="M11 2.5a8.5 8.5 0 108.5 8.5A8.5 8.5 0 0011 2.5zm.8 8.15l4.05 4.05a.8.8 0 11-1.13 1.13l-4.28-4.28A.8.8 0 0110.2 11V5.75a.8.8 0 011.6 0z" />
        </svg>
      )}
      {icon === "stats" && (
        <svg className="w-[22px] h-[22px] opacity-45" fill="none" stroke="white" strokeWidth={1.2} viewBox="0 0 22 22">
          <circle cx="11" cy="11" r="7" />
          <path d="M11 4v7l5 5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      )}
      {/* SF Symbol: plus.square.on.square */}
      {icon === "copy" && (
        <svg className="w-[22px] h-[22px] opacity-45" fill="none" stroke="white" strokeWidth={1.2} viewBox="0 0 22 22">
          <rect x="6" y="6" width="14" height="14" rx="3"/>
          <path d="M4 14.5V4a2.5 2.5 0 012.5-2.5H13"/>
          <path d="M13 9.5v5M10.5 12h5" strokeLinecap="round"/>
        </svg>
      )}
    </button>
  );
}
