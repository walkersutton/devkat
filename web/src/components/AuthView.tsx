import { useState, useEffect } from "react";
import { supabase } from "../lib/supabase";
import { capture } from "../lib/posthog";
import { PasswordResetView } from "./PasswordResetView";
import type { LeaderboardEntry } from "../lib/types";
import {
  leaderboardDisplayName,
  leaderboardFormattedTokens,
} from "../lib/types";

// ─── Corner tick marks ───────────────────────────────────────────────────────

function CornerTicks({ highlight }: { highlight?: boolean }) {
  const color = highlight
    ? "var(--color-logo-green)"
    : "var(--color-text-muted)";
  const base: React.CSSProperties = {
    position: "absolute",
    width: 10,
    height: 10,
    borderColor: color,
  };
  return (
    <>
      <span style={{ ...base, top: 8, left: 8, borderTop: "1px solid", borderLeft: "1px solid" }} />
      <span style={{ ...base, top: 8, right: 8, borderTop: "1px solid", borderRight: "1px solid" }} />
      <span style={{ ...base, bottom: 8, left: 8, borderBottom: "1px solid", borderLeft: "1px solid" }} />
      <span style={{ ...base, bottom: 8, right: 8, borderBottom: "1px solid", borderRight: "1px solid" }} />
    </>
  );
}

// ─── Podium card ─────────────────────────────────────────────────────────────

function PodiumCard({
  entry,
  place,
  highlight,
}: {
  entry: LeaderboardEntry;
  place: number;
  highlight?: boolean;
}) {
  const green = "var(--color-logo-green)";
  const muted = "var(--color-text-muted)";
  const text = "var(--color-text)";

  return (
    <div
      className={`podium-card${highlight ? " podium-card--highlight" : ""}`}
      data-place={place}
      style={{
        border: `1px solid ${highlight ? "rgba(0,255,65,0.35)" : "var(--color-border)"}`,
        background: highlight
          ? "linear-gradient(180deg, rgba(0,255,65,0.05), rgba(0,255,65,0.01))"
          : "rgba(255,255,255,0.012)",
      }}
    >
      <CornerTicks highlight={highlight} />

      {/* ── NUMBER SECTION: flex:1 + overflow:hidden → only this clips ── */}
      <div style={{ flex: 1, overflow: "hidden", minHeight: 0 }}>
        <div
          style={{
            fontFamily: "var(--font-mono)",
            fontSize: 9,
            letterSpacing: "0.18em",
            color: highlight ? green : muted,
            marginBottom: 6,
          }}
          className={highlight ? "text-glow" : ""}
        >
          RANK · {String(place).padStart(2, "0")}
        </div>
        <div
          className={`podium-rank-num${highlight ? " text-glow" : ""}`}
          style={{ color: highlight ? green : text }}
        >
          {String(place)}
        </div>
      </div>

      {/* ── BOTTOM ROW: pinned bottom-right on mobile, side-by-side on desktop ── */}
      <div className="podium-bottom">
        <div
          className="podium-handle"
          style={{ color: text }}
        >
          @{leaderboardDisplayName(entry.email)}
        </div>
        <div className="podium-tokens-block" style={{ flexShrink: 0 }}>
          <div
            className={`podium-tokens${highlight ? " text-glow" : ""}`}
            style={{ color: highlight ? green : text }}
          >
            {leaderboardFormattedTokens(entry.total_tokens)}
          </div>
          <div
            className="podium-tokens-label"
            style={{
              marginTop: 3,
              fontFamily: "var(--font-mono)",
              fontSize: 9,
              letterSpacing: "0.2em",
              color: muted,
            }}
          >
            TOKENS
          </div>
        </div>
      </div>
    </div>
  );
}

// ─── Auth modal ───────────────────────────────────────────────────────────────

function AuthModal({
  initialMode,
  onClose,
}: {
  initialMode: "signin" | "signup";
  onClose: () => void;
}) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [mode, setMode] = useState<"signin" | "signup">(initialMode);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [showReset, setShowReset] = useState(false);

  useEffect(() => {
    const handler = (e: KeyboardEvent) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [onClose]);

  if (showReset) {
    return (
      <div className="fixed inset-0 z-50 flex items-end md:items-center justify-center bg-black/80 backdrop-blur-sm">
        <div className="w-full max-w-md bg-surface border border-border rounded-t-2xl md:rounded-2xl p-6">
          <PasswordResetView
            initialEmail={email}
            onCancel={() => setShowReset(false)}
          />
        </div>
      </div>
    );
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);

    capture(mode === "signup" ? "sign_up_submitted" : "sign_in_submitted", {
      method: "email",
    });

    const { error: authError } =
      mode === "signin"
        ? await supabase.auth.signInWithPassword({ email, password })
        : await supabase.auth.signUp({ email, password });

    setLoading(false);
    if (authError) {
      capture(mode === "signup" ? "sign_up_failed" : "sign_in_failed", {
        error: authError.message,
      });
      if (authError.message.includes("email_not_confirmed")) {
        setError("Check your inbox — confirm your email before signing in.");
      } else if (authError.message.includes("Invalid login credentials")) {
        setError("Wrong email or password.");
      } else {
        setError(authError.message);
      }
    }
  }

  return (
    /* Backdrop */
    <div
      className="fixed inset-0 z-50 flex items-end md:items-center justify-center"
      style={{ background: "rgba(0,0,0,0.85)" }}
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      {/* Panel */}
      <div
        className="auth-modal-panel w-full md:max-w-sm relative"
        style={{
          background: "var(--color-surface)",
          border: "1px solid var(--color-border)",
          padding: "28px 24px 32px",
        }}
      >
        {/* Drag handle (mobile only) */}
        <div
          className="md:hidden mx-auto mb-5"
          style={{
            width: 36,
            height: 4,
            borderRadius: 2,
            background: "var(--color-border)",
          }}
        />

        {/* DEVKAT wordmark */}
        <div
          className="animate-flicker font-led text-center mb-6"
          style={{
            fontSize: 28,
            letterSpacing: "0.14em",
            lineHeight: 1,
            color: "var(--color-text)",
          }}
        >
          DEVKAT
        </div>

        {/* Mode tabs — sliding pill indicator */}
        <div
          className="relative flex mb-5"
          style={{
            background: "rgba(255,255,255,0.05)",
            borderRadius: 10,
            padding: 3,
            border: "1px solid var(--color-border)",
          }}
        >
          {/* The pill slides under the active tab */}
          <div
            aria-hidden
            style={{
              position: "absolute",
              top: 3,
              bottom: 3,
              left: 3,
              width: "calc(50% - 3px)",
              background: "var(--color-surface-raised)",
              border: "1px solid var(--color-border)",
              borderRadius: 8,
              transform: mode === "signin" ? "translateX(0)" : "translateX(100%)",
              transition: "transform 220ms cubic-bezier(0.23, 1, 0.32, 1)",
              pointerEvents: "none",
            }}
          />
          {(["signin", "signup"] as const).map((m) => (
            <button
              key={m}
              type="button"
              onClick={() => { setMode(m); setError(null); }}
              className="relative z-10 flex-1 py-2 text-[11px] font-bold font-mono tracking-[0.15em] uppercase cursor-pointer rounded-lg"
              style={{
                background: "transparent",
                border: "1px solid transparent",
                color: mode === m ? "var(--color-text)" : "var(--color-text-dim)",
                transition: "color 220ms cubic-bezier(0.23, 1, 0.32, 1)",
              }}
            >
              {m === "signin" ? "Sign In" : "Create Account"}
            </button>
          ))}
        </div>

        <form onSubmit={handleSubmit} className="space-y-3">
          <input
            type="email"
            placeholder="Email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
            autoComplete="email"
            autoCapitalize="none"
            autoFocus
            className="w-full rounded-[10px] px-4 h-12 text-[15px] focus:outline-none transition-colors font-mono"
            style={{
              background: "var(--color-surface-raised)",
              border: "1px solid var(--color-border)",
              color: "var(--color-text)",
            }}
          />
          <input
            type="password"
            placeholder="Password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            autoComplete={mode === "signin" ? "current-password" : "new-password"}
            className="w-full rounded-[10px] px-4 h-12 text-[15px] focus:outline-none transition-colors font-mono"
            style={{
              background: "var(--color-surface-raised)",
              border: "1px solid var(--color-border)",
              color: "var(--color-text)",
            }}
          />

          {/* Fixed-height error slot so layout doesn't shift */}
          <p
            className="text-[11px] font-mono text-center"
            style={{
              color: "rgba(248,113,113,0.85)",
              minHeight: "1.25rem",
              paddingTop: 2,
              visibility: error ? "visible" : "hidden",
            }}
          >
            {error ?? " "}
          </p>

          <button
            type="submit"
            disabled={loading || !email || !password}
            className="btn-submit mt-1"
          >
            {loading ? "…" : mode === "signin" ? "Sign In" : "Create Account"}
          </button>

          {/* Always rendered — visibility toggled so height is always reserved */}
          <button
            type="button"
            onClick={() => { setError(null); setShowReset(true); }}
            className="w-full text-center text-[11px] font-mono transition-colors cursor-pointer"
            style={{
              color: "var(--color-text-muted)",
              paddingTop: 4,
              visibility: mode === "signin" ? "visible" : "hidden",
            }}
          >
            Forgot password?
          </button>
        </form>

        {/* Close */}
        <button
          type="button"
          onClick={onClose}
          className="absolute top-4 right-4 transition-colors cursor-pointer"
          style={{ color: "var(--color-text-muted)" }}
          aria-label="Close"
        >
          <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
            <path d="M4 4l10 10M14 4L4 14" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
          </svg>
        </button>
      </div>
    </div>
  );
}

// ─── Main AuthView ────────────────────────────────────────────────────────────

export function AuthView() {
  const [authPanel, setAuthPanel] = useState<"signin" | "signup" | null>(null);
  const [leaderboard, setLeaderboard] = useState<LeaderboardEntry[]>([]);
  const [allTimeLeaderboard, setAllTimeLeaderboard] = useState<LeaderboardEntry[]>([]);

  useEffect(() => {
    supabase
      .rpc("weekly_token_leaderboard")
      .then(({ data, error }) => {
        if (!error && data) setLeaderboard(data as LeaderboardEntry[]);
      });
    supabase
      .rpc("token_leaderboard")
      .then(({ data, error }) => {
        if (!error && data) setAllTimeLeaderboard(data as LeaderboardEntry[]);
      });
  }, []);

  const top3 = leaderboard.slice(0, 3);
  const rest = leaderboard.slice(3, 12);
  const totalTokens = leaderboard.reduce((s, e) => s + e.total_tokens, 0);
  const devCount = leaderboard.length;
  const lifetimeTokens = allTimeLeaderboard.reduce((s, e) => s + e.total_tokens, 0);
  const lifetimeDevCount = allTimeLeaderboard.length;

  // Podium order: 2nd (left), 1st (center), 3rd (right) — classic arcade podium
  const podiumOrder =
    top3.length >= 3 ? [top3[1], top3[0], top3[2]] : top3;

  const mono = "var(--font-mono)";
  const green = "var(--color-logo-green)";
  const border = "var(--color-border)";
  const muted = "var(--color-text-muted)";
  const dim = "var(--color-text-dim)";

  return (
    <>
      {/* Auth modal */}
      {authPanel && (
        <AuthModal
          initialMode={authPanel}
          onClose={() => setAuthPanel(null)}
        />
      )}

      {/* Full-page scoreboard */}
      <div
        className="scanlines min-h-screen overflow-y-auto"
        style={{ background: "var(--color-background)", color: "var(--color-text)" }}
      >
        {/* ── STATUS BAR ── */}
        <div
          className="auth-px flex items-center justify-between"
          style={{
            paddingTop: 12,
            paddingBottom: 12,
            borderBottom: `1px solid ${border}`,
            fontFamily: mono,
            fontSize: 11,
            letterSpacing: "0.18em",
            color: muted,
          }}
        >
          {/* Left: live indicator */}
          <div className="flex items-center gap-3 md:gap-6 min-w-0">
            <span
              className="animate-blink shrink-0"
              style={{
                display: "inline-block",
                width: 7,
                height: 7,
                borderRadius: "50%",
                background: green,
                boxShadow: "0 0 12px rgba(0,255,65,0.45)",
              }}
            />
            <span className="text-glow shrink-0" style={{ color: green }}>
              LIVE
            </span>
            {devCount > 0 && (
              <span className="hidden sm:inline">{devCount} DEVS ACTIVE</span>
            )}
            {totalTokens > 0 && (
              <>
                <span className="hidden md:inline" style={{ color: muted }}>·</span>
                <span className="hidden md:inline">
                  {leaderboardFormattedTokens(totalTokens)} TOKENS THIS WEEK
                </span>
              </>
            )}
          </div>

          {/* Right: version + github */}
          <div className="hidden sm:flex items-center gap-3" style={{ color: muted }}>
            <span>v0.4.2</span>
            <span>·</span>
            <a
              href="https://github.com/runnon/devkat"
              target="_blank"
              rel="noreferrer"
              className="hover:text-text-dim transition-colors"
              style={{ color: "inherit", textDecoration: "none" }}
            >
              github.com/runnon/devkat
            </a>
          </div>
        </div>

        {/* ── HEADER ── */}
        <div
          className="auth-px flex flex-col md:flex-row md:items-end md:justify-between gap-4 md:gap-0"
          style={{ paddingTop: 28, paddingBottom: 20 }}
        >
          <div>
            <div
              className="animate-flicker font-led"
              style={{
                fontSize: "clamp(40px, 8vw, 64px)",
                letterSpacing: "0.12em",
                lineHeight: 1,
                color: "var(--color-text)",
              }}
            >
              DEVKAT
            </div>
            <div
              style={{
                marginTop: 12,
                fontFamily: mono,
                fontSize: 12,
                color: muted,
                letterSpacing: "0.06em",
              }}
            >
              a public record of what developers ship with AI
            </div>
          </div>

          {/* CTA buttons */}
          <div className="flex gap-2 items-stretch">
            <button onClick={() => setAuthPanel("signin")} className="btn-ghost cursor-pointer" style={{ padding: "0 16px" }}>
              SIGN IN
            </button>
            <button onClick={() => setAuthPanel("signup")} className="btn-primary cursor-pointer" style={{ padding: "10px 18px" }}>
              CREATE ACCOUNT  →
            </button>
          </div>
        </div>

        {/* ── SCOREBOARD ── */}
        <div className="auth-px" style={{ paddingBottom: 28 }}>
          {/* Section header */}
          <div
            className="flex items-center gap-2 overflow-hidden"
            style={{
              fontFamily: mono,
              fontSize: 11,
              letterSpacing: "0.2em",
              color: muted,
            }}
          >
            <span className="section-header-left" style={{ color: "var(--color-text-dim)", fontWeight: 700 }}>
              THIS WEEK / TOP TOKEN BURNERS
            </span>
            <div style={{ flex: 1, height: 1, background: border, minWidth: 12 }} />
            <span style={{ whiteSpace: "nowrap", flexShrink: 0 }}>
              <span className="text-glow" style={{ color: green }}>●</span>
              &nbsp;LIVE
            </span>
          </div>

          {/* ── PODIUM ── */}
          {podiumOrder.length >= 3 && (
            <div className="podium-grid">
              <PodiumCard entry={podiumOrder[0]} place={2} />
              <PodiumCard entry={podiumOrder[1]} place={1} highlight />
              <PodiumCard entry={podiumOrder[2]} place={3} />
            </div>
          )}

          {/* Loading skeleton */}
          {leaderboard.length === 0 && (
            <div className="podium-grid">
              {[0, 1, 2].map((i) => (
                <div
                  key={i}
                  style={{
                    height: 160,
                    border: `1px solid ${border}`,
                    borderRadius: 14,
                    background: "rgba(255,255,255,0.012)",
                    opacity: 0.5,
                  }}
                />
              ))}
            </div>
          )}

          {/* ── RANK GRID ── */}
          {rest.length > 0 && (
            <div style={{ marginTop: 28 }}>
              {/* Header row */}
              <div
                className="rank-grid-cols grid"
                style={{
                  gap: 10,
                  padding: "8px 6px",
                  borderBottom: `1px solid ${border}`,
                  fontFamily: mono,
                  fontSize: 10,
                  letterSpacing: "0.2em",
                  color: muted,
                }}
              >
                <span>#</span>
                <span>DEVELOPER</span>
                <span style={{ textAlign: "right" }}>TOKENS</span>
              </div>

              {/* Rank rows */}
              {rest.map((entry, idx) => {
                const rank = idx + 4;
                return (
                  <div
                    key={entry.email}
                    className="rank-grid-cols grid"
                    style={{
                      gap: 10,
                      padding: "10px 6px",
                      borderBottom: `1px solid rgba(42,42,42,0.5)`,
                      alignItems: "center",
                      fontFamily: mono,
                      fontSize: 13,
                      color: "var(--color-text)",
                    }}
                  >
                    <span style={{ color: muted, letterSpacing: "0.05em" }}>
                      {String(rank).padStart(2, "0")}
                    </span>
                    <span
                      style={{ fontWeight: 600, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}
                    >
                      @{leaderboardDisplayName(entry.email)}
                    </span>
                    <span
                      style={{
                        textAlign: "right",
                        fontFamily: mono,
                        fontWeight: 700,
                        fontSize: 15,
                        letterSpacing: "-0.01em",
                        color: "var(--color-text)",
                        fontVariantNumeric: "tabular-nums",
                      }}
                    >
                      {leaderboardFormattedTokens(entry.total_tokens)}
                    </span>
                  </div>
                );
              })}
            </div>
          )}
        </div>

        {/* ── MANIFESTO STRIP ── */}
        <div
          className="auth-px"
          style={{
            borderTop: `1px solid ${border}`,
            borderBottom: `1px solid ${border}`,
            paddingTop: 24,
            paddingBottom: 24,
            background:
              "linear-gradient(180deg, transparent, rgba(0,255,65,0.015))",
          }}
        >
          <div
            className="flex flex-col md:grid md:items-center gap-4 md:gap-9"
            style={{ gridTemplateColumns: "auto 1fr auto" }}
          >
            <div
              style={{
                fontFamily: mono,
                fontSize: 10,
                letterSpacing: "0.2em",
                color: muted,
                flexShrink: 0,
              }}
            >
              // MANIFESTO
            </div>
            <div
              className="font-serif italic"
              style={{
                fontSize: "clamp(16px, 2.5vw, 22px)",
                lineHeight: 1.35,
                color: "var(--color-text)",
              }}
            >
              Developers ship things worth sharing. Devkat keeps a systematic
              record — the hours, the lines, the token burn — and makes it look
              like the craft.
            </div>
            <div
              className="hidden md:block"
              style={{
                fontFamily: mono,
                fontSize: 10,
                letterSpacing: "0.2em",
                color: muted,
                textAlign: "right",
                flexShrink: 0,
              }}
            >
              EST. 2025 /<br />RUNS LOCAL
            </div>
          </div>
        </div>

        {/* ── FOOTER STATS ── */}
        <div
          className="auth-px grid grid-cols-2 md:grid-cols-4"
          style={{ paddingTop: 20, paddingBottom: 8 }}
        >
          {[
            {
              k: lifetimeTokens > 0 ? leaderboardFormattedTokens(lifetimeTokens) : "—",
              label: "TOKENS · ALL TIME",
            },
            { k: lifetimeDevCount > 0 ? String(lifetimeDevCount) : "—", label: "TOTAL DEVS" },
            { k: "2.1M", label: "LINES TOUCHED" },
            { k: "38,210", label: "SESSIONS · ALL TIME" },
          ].map(({ k, label }) => (
            <div
              key={label}
              style={{
                borderLeft: `1px solid ${border}`,
                padding: "0 22px",
                marginBottom: 16,
              }}
            >
              <div
                style={{
                  fontFamily: mono,
                  fontWeight: 700,
                  fontSize: "clamp(26px, 5vw, 38px)",
                  lineHeight: 1,
                  color: "var(--color-text)",
                  letterSpacing: "-0.03em",
                  fontVariantNumeric: "tabular-nums",
                }}
              >
                {k}
              </div>
              <div
                style={{
                  marginTop: 8,
                  fontFamily: mono,
                  fontSize: 10,
                  letterSpacing: "0.2em",
                  color: muted,
                }}
              >
                {label}
              </div>
            </div>
          ))}
        </div>

        {/* ── FOOTER SIGN-IN STRIP ── */}
        <div
          className="auth-px flex flex-col sm:flex-row items-center justify-center gap-4 sm:gap-6"
          style={{
            paddingTop: 20,
            paddingBottom: 32,
            borderTop: `1px solid ${border}`,
          }}
        >
          <span
            style={{
              fontFamily: mono,
              fontSize: 11,
              color: muted,
              letterSpacing: "0.1em",
            }}
          >
            START TRACKING YOUR SESSIONS
          </span>
          <div className="flex gap-3">
            <button onClick={() => setAuthPanel("signin")} className="btn-ghost cursor-pointer" style={{ padding: "8px 16px" }}>
              SIGN IN
            </button>
            <button onClick={() => setAuthPanel("signup")} className="btn-primary cursor-pointer" style={{ padding: "8px 16px" }}>
              CREATE ACCOUNT  →
            </button>
          </div>
        </div>
      </div>
    </>
  );
}
