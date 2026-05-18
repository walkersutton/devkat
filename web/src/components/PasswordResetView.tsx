import { useState } from "react";
import { supabase } from "../lib/supabase";
import { capture, identify } from "../lib/posthog";

type Step = "email" | "code" | "newPassword";

interface Props {
  initialEmail: string;
  onCancel: () => void;
}

export function PasswordResetView({ initialEmail, onCancel }: Props) {
  const [step, setStep] = useState<Step>("email");
  const [email, setEmail] = useState(initialEmail);
  const [code, setCode] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function sendCode(initial: boolean) {
    const trimmed = email.trim().toLowerCase();
    if (!trimmed) return;
    setEmail(trimmed);
    setError(null);
    setInfo(null);
    setLoading(true);
    capture("password_reset_code_requested");

    const { error: authError } = await supabase.auth.resetPasswordForEmail(trimmed);

    setLoading(false);
    if (authError) {
      setError(authError.message);
      return;
    }
    setStep("code");
    if (!initial) setInfo("New code sent.");
  }

  async function verifyCode() {
    setLoading(true);
    setError(null);

    const { error: authError } = await supabase.auth.verifyOtp({
      email,
      token: code,
      type: "recovery",
    });

    setLoading(false);
    if (authError) {
      setError("Invalid or expired code. Try again.");
      return;
    }
    setStep("newPassword");
  }

  async function savePassword() {
    if (newPassword.length < 8) {
      setError("Password must be at least 8 characters.");
      return;
    }
    if (newPassword !== confirmPassword) {
      setError("Passwords don't match.");
      return;
    }

    setLoading(true);
    setError(null);

    const { error: authError } = await supabase.auth.updateUser({ password: newPassword });

    if (authError) {
      setLoading(false);
      setError(authError.message);
      return;
    }
    capture("password_reset_completed");
    identify(email, { email });
    // Leave loading=true — App.tsx will swap us out when session settles.
  }

  function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (step === "email") sendCode(true);
    else if (step === "code") verifyCode();
    else savePassword();
  }

  const canSubmit =
    (step === "email" && email.length > 0) ||
    (step === "code" && code.length === 6) ||
    (step === "newPassword" && newPassword.length >= 8 && newPassword === confirmPassword);

  const title =
    step === "email"
      ? "Reset your password."
      : step === "code"
      ? "Check your email."
      : "Set a new password.";

  const subtitle =
    step === "email"
      ? "Enter the email you use to sign in. We'll send you a 6-digit code."
      : step === "code"
      ? `We sent a 6-digit code to ${email}. Enter it below to continue.`
      : "Pick a new password (at least 8 characters). You'll be signed in once it's saved.";

  const buttonLabel =
    step === "email"
      ? "SEND CODE"
      : step === "code"
      ? "VERIFY CODE"
      : "SAVE PASSWORD";

  return (
    <div className="min-h-screen flex items-center justify-center px-8 md:px-12">
      <div className="w-full max-w-sm md:max-w-4xl md:grid md:grid-cols-[minmax(0,1fr)_380px] md:items-center md:gap-16 space-y-10 md:space-y-0">
        <div className="flex justify-start">
          <button
            type="button"
            onClick={onCancel}
            className="text-[11px] font-mono text-text-dim tracking-[0.15em] uppercase font-semibold"
          >
            CANCEL
          </button>
        </div>

        <div className="space-y-3 text-left md:max-w-xl">
          <p
            className="text-[26px] text-text italic"
            style={{ fontFamily: "'Times New Roman', Times, serif" }}
          >
            {title}
          </p>
          <p className="text-[11px] font-mono text-text-dim leading-relaxed">
            {subtitle}
          </p>
        </div>

        <form onSubmit={onSubmit} className="space-y-3 md:rounded-2xl md:border md:border-border md:bg-surface/50 md:p-5">
          {step === "email" && (
            <input
              type="email"
              placeholder="Email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              autoCapitalize="none"
              autoCorrect="off"
              autoFocus
              className="w-full bg-surface border border-white/[0.12] rounded-[10px] px-4 h-12 text-[15px] text-text placeholder:text-text-muted focus:outline-none focus:border-white/30 transition-colors font-mono"
            />
          )}

          {step === "code" && (
            <input
              type="text"
              inputMode="numeric"
              pattern="[0-9]*"
              autoComplete="one-time-code"
              placeholder="6-digit code"
              value={code}
              onChange={(e) => {
                const digits = e.target.value.replace(/\D/g, "").slice(0, 6);
                setCode(digits);
              }}
              autoFocus
              className="w-full bg-surface border border-white/[0.12] rounded-[10px] px-4 h-12 text-[15px] text-text placeholder:text-text-muted focus:outline-none focus:border-white/30 transition-colors font-mono tracking-[0.3em] text-center"
            />
          )}

          {step === "newPassword" && (
            <>
              <input
                type="password"
                placeholder="New password"
                value={newPassword}
                onChange={(e) => setNewPassword(e.target.value)}
                required
                autoFocus
                className="w-full bg-surface border border-white/[0.12] rounded-[10px] px-4 h-12 text-[15px] text-text placeholder:text-text-muted focus:outline-none focus:border-white/30 transition-colors font-mono"
              />
              <input
                type="password"
                placeholder="Confirm password"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                required
                className="w-full bg-surface border border-white/[0.12] rounded-[10px] px-4 h-12 text-[15px] text-text placeholder:text-text-muted focus:outline-none focus:border-white/30 transition-colors font-mono"
              />
            </>
          )}

          {info && (
            <p className="text-[11px] font-mono text-text-dim text-center pt-1">{info}</p>
          )}
          {error && (
            <p className="text-[11px] font-mono text-red-400/80 text-center pt-1">{error}</p>
          )}

          <button
            type="submit"
            disabled={loading || !canSubmit}
            className="w-full bg-white text-black font-bold text-[11px] font-mono tracking-[0.15em] uppercase rounded-xl h-12 hover:bg-white/90 transition-colors disabled:opacity-50 mt-2"
          >
            {loading ? "..." : buttonLabel}
          </button>

          {step === "code" && (
            <button
              type="button"
              onClick={() => sendCode(false)}
              disabled={loading}
              className="w-full text-center text-[11px] font-mono text-text-dim pt-1"
            >
              Resend code
            </button>
          )}
        </form>
      </div>
    </div>
  );
}
