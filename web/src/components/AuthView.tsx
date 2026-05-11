import { useState } from "react";
import { supabase } from "../lib/supabase";
import { capture } from "../lib/posthog";
import { PasswordResetView } from "./PasswordResetView";

export function AuthView() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [mode, setMode] = useState<"signin" | "signup">("signin");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [showPasswordReset, setShowPasswordReset] = useState(false);

  if (showPasswordReset) {
    return (
      <PasswordResetView
        initialEmail={email}
        onCancel={() => setShowPasswordReset(false)}
      />
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
    <div className="min-h-screen flex items-center justify-center px-8">
      <div className="w-full max-w-sm space-y-10">
        {/* Logo */}
        <div className="text-center space-y-2.5">
          <h1 className="text-[34px] font-normal text-text font-led">
            DEVKAT
          </h1>
          <p className="text-[11px] font-mono text-text-muted">
            hello, sharing
          </p>
        </div>

        {/* Manifesto */}
        <div className="space-y-3 text-left">
          <p className="text-2xl text-text italic" style={{ fontFamily: "'Times New Roman', Times, serif" }}>
            Developers ship things worth sharing.
          </p>
          <p className="text-xl text-text-dim italic leading-relaxed" style={{ fontFamily: "'Times New Roman', Times, serif" }}>
            I wanted a systematic record of my sessions — the hours, the lines, the token burn — and a way to share it that matched the craft.
          </p>
        </div>

        {/* Form */}
        <form onSubmit={handleSubmit} className="space-y-3">
          <input
            type="email"
            placeholder="Email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
            autoCapitalize="none"
            autoCorrect="off"
            className="w-full bg-surface border border-white/[0.12] rounded-[10px] px-4 h-12 text-[15px] text-text placeholder:text-text-muted focus:outline-none focus:border-white/30 transition-colors font-mono"
          />
          <input
            type="password"
            placeholder="Password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            className="w-full bg-surface border border-white/[0.12] rounded-[10px] px-4 h-12 text-[15px] text-text placeholder:text-text-muted focus:outline-none focus:border-white/30 transition-colors font-mono"
          />

          {error && (
            <p className="text-[11px] font-mono text-red-400/80 text-center pt-1">{error}</p>
          )}

          <button
            type="submit"
            disabled={loading || !email || !password}
            className="w-full bg-white text-black font-bold text-[11px] font-mono tracking-[0.15em] uppercase rounded-xl h-12 hover:bg-white/90 transition-colors disabled:opacity-50 mt-2"
          >
            {loading ? "..." : mode === "signin" ? "SIGN IN" : "CREATE ACCOUNT"}
          </button>

          <button
            type="button"
            onClick={() => { setMode(mode === "signin" ? "signup" : "signin"); setError(null); }}
            className="w-full text-center text-[11px] font-mono text-text-dim pt-1"
          >
            {mode === "signin" ? "No account? Create one" : "Already have an account? Sign in"}
          </button>

          {mode === "signin" && (
            <button
              type="button"
              onClick={() => { setError(null); setShowPasswordReset(true); }}
              className="w-full text-center text-[11px] font-mono text-text-dim"
            >
              Forgot password?
            </button>
          )}
        </form>
      </div>
    </div>
  );
}
