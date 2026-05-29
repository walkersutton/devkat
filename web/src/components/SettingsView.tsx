import { useState } from "react";
import { supabase } from "../lib/supabase";
import { capture } from "../lib/posthog";

type LegalSheet = "dataPrivacy" | "terms" | "privacy" | null;

export function SettingsView({ email, onClose }: { email: string; onClose: () => void }) {
  const [legalSheet, setLegalSheet] = useState<LegalSheet>(null);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);

  async function handleLogout() {
    capture("signed_out");
    await supabase.auth.signOut();
  }

  async function handleDelete() {
    setIsDeleting(true);
    setDeleteError(null);
    try {
      const { error } = await supabase.rpc("delete_user_account");
      if (error) throw error;
      capture("account_deleted");
      await supabase.auth.signOut();
    } catch (e: unknown) {
      setDeleteError(e instanceof Error ? e.message : "Failed to delete account");
      setIsDeleting(false);
    }
  }

  if (legalSheet) {
    return (
      <LegalView
        title={legalSheet === "dataPrivacy" ? "DATA & PRIVACY" : legalSheet === "terms" ? "TERMS OF SERVICE" : "PRIVACY POLICY"}
        sections={legalSheet === "terms" ? termsOfService : privacyPolicy}
        onBack={() => setLegalSheet(null)}
      />
    );
  }

  return (
    <div className="scanlines mx-auto flex h-full max-w-lg flex-col desk:max-w-6xl">
      {/* Mobile sticky header */}
      <div className="sticky top-0 z-10 border-b border-border bg-background desk:hidden">
        <div className="flex items-center px-4 py-[14px]">
          <button
            onClick={onClose}
            className="flex items-center gap-2 text-text-muted hover:text-text transition-colors"
          >
            <svg className="w-[14px] h-[14px]" fill="none" stroke="currentColor" strokeWidth={2.5} viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
            </svg>
            <span className="font-mono text-[10px] font-bold tracking-[0.16em]">BACK</span>
          </button>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto px-4 pb-[100px] pt-5 desk:px-8 desk:pb-10 desk:pt-8">
        {/* Page header */}
        <div>
          <div className="font-mono text-[11px] font-bold tracking-[0.2em] text-logo-green text-glow">
            ACCOUNT
          </div>
          <h1 className="mt-3 font-led text-[40px] leading-none tracking-[0.1em] text-text desk:text-[58px]">
            SETTINGS
          </h1>
        </div>

        <div className="mt-8 flex flex-col gap-5">
          {/* Data */}
          <SettingsSection label="DATA">
            <SettingsActionRow label="REFRESH SESSIONS" onClick={() => window.location.reload()} />
          </SettingsSection>

          {/* About */}
          <SettingsSection label="ABOUT">
            <SettingsInfoRow label="APP" value="DEVKAT" />
            <SettingsInfoRow label="PLATFORM" value="WEB" />
            <SettingsInfoRow label="VERSION" value="1.0" />
            <SettingsMailRow label="CONTACT" address="xavier@alleykat.app" />
          </SettingsSection>

          {/* Legal */}
          <SettingsSection label="LEGAL">
            <SettingsNavRow label="DATA & PRIVACY" onClick={() => setLegalSheet("dataPrivacy")} />
            <SettingsNavRow label="TERMS OF SERVICE" onClick={() => setLegalSheet("terms")} />
            <SettingsNavRow label="PRIVACY POLICY" onClick={() => setLegalSheet("privacy")} />
          </SettingsSection>

          {/* Account */}
          <SettingsSection label="ACCOUNT">
            <SettingsInfoRow label="EMAIL" value={email} />
            <SettingsActionRow label="LOG OUT" destructive onClick={handleLogout} />
          </SettingsSection>

          {/* Danger zone */}
          <SettingsSection label="DANGER ZONE">
            <SettingsActionRow
              label={isDeleting ? "DELETING..." : "DELETE ACCOUNT"}
              destructive
              onClick={() => { setDeleteError(null); setShowDeleteConfirm(true); }}
              disabled={isDeleting}
            />
            {deleteError && (
              <div className="px-3 py-2.5 font-mono text-[11px] text-red-400/80 border-t border-border/60">
                {deleteError}
              </div>
            )}
          </SettingsSection>
        </div>
      </div>

      {/* Delete confirmation dialog */}
      {showDeleteConfirm && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div className="absolute inset-0 bg-black/70" onClick={() => setShowDeleteConfirm(false)} />
          <div className="relative border border-border bg-surface-raised mx-8 max-w-sm w-full">
            <div className="border-b border-border bg-white/[0.025] px-3 py-3">
              <span className="font-mono text-[10px] font-bold tracking-[0.18em] text-text-muted">
                CONFIRM DELETION
              </span>
            </div>
            <div className="px-3 py-4">
              <p className="font-mono text-[13px] text-text-dim leading-[1.7]">
                This permanently deletes your account and all synced session data. This cannot be undone.
              </p>
            </div>
            <div className="flex border-t border-border">
              <button
                onClick={() => setShowDeleteConfirm(false)}
                className="flex-1 py-3 font-mono text-[11px] font-bold tracking-[0.14em] text-text-muted border-r border-border hover:bg-white/[0.03] transition-colors"
              >
                CANCEL
              </button>
              <button
                onClick={() => { setShowDeleteConfirm(false); handleDelete(); }}
                className="flex-1 py-3 font-mono text-[11px] font-bold tracking-[0.14em] text-red-400 hover:bg-red-400/5 transition-colors"
              >
                DELETE
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function SettingsSection({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="border border-border bg-white/[0.012]">
      <div className="border-b border-border bg-white/[0.025] px-3 py-3">
        <span className="font-mono text-[10px] font-bold tracking-[0.18em] text-text-muted">{label}</span>
      </div>
      <div className="divide-y divide-border/60">
        {children}
      </div>
    </div>
  );
}

function SettingsInfoRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between gap-4 px-3 py-3.5">
      <span className="font-mono text-[12px] font-bold tracking-[0.08em] text-text-dim shrink-0">{label}</span>
      <span className="font-mono text-[13px] text-text truncate text-right">{value}</span>
    </div>
  );
}

function SettingsActionRow({
  label,
  destructive,
  onClick,
  disabled,
}: {
  label: string;
  destructive?: boolean;
  onClick?: () => void;
  disabled?: boolean;
}) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className={`w-full flex items-center px-3 py-3.5 hover:bg-white/[0.03] transition-colors disabled:opacity-40 ${
        destructive ? "text-red-400" : "text-text"
      }`}
    >
      <span className="font-mono text-[13px] font-bold tracking-[0.06em]">{label}</span>
    </button>
  );
}

function SettingsNavRow({ label, onClick }: { label: string; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className="w-full flex items-center justify-between gap-3 px-3 py-3.5 hover:bg-white/[0.03] transition-colors"
    >
      <span className="font-mono text-[13px] font-bold tracking-[0.06em] text-text">{label}</span>
      <svg className="w-[11px] h-[11px] text-text-dim shrink-0" fill="none" stroke="currentColor" strokeWidth={2.5} viewBox="0 0 24 24">
        <path strokeLinecap="round" strokeLinejoin="round" d="M9 5l7 7-7 7" />
      </svg>
    </button>
  );
}

function SettingsMailRow({ label, address }: { label: string; address: string }) {
  return (
    <a
      href={`mailto:${address}`}
      className="flex items-center justify-between gap-4 px-3 py-3.5 hover:bg-white/[0.03] transition-colors"
    >
      <span className="font-mono text-[12px] font-bold tracking-[0.08em] text-text-dim shrink-0">{label}</span>
      <span className="font-mono text-[13px] text-text-dim truncate text-right">{address}</span>
    </a>
  );
}

// --- Legal View ---

interface LegalSectionData {
  heading: string | null;
  body: string;
}

function LegalView({ title, sections, onBack }: { title: string; sections: LegalSectionData[]; onBack: () => void }) {
  return (
    <div className="scanlines mx-auto flex h-full max-w-lg flex-col desk:max-w-6xl">
      {/* Mobile sticky header */}
      <div className="sticky top-0 z-10 border-b border-border bg-background desk:hidden">
        <div className="flex items-center px-4 py-[14px]">
          <button
            onClick={onBack}
            className="flex items-center gap-2 text-text-muted hover:text-text transition-colors"
          >
            <svg className="w-[14px] h-[14px]" fill="none" stroke="currentColor" strokeWidth={2.5} viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
            </svg>
            <span className="font-mono text-[10px] font-bold tracking-[0.16em]">SETTINGS</span>
          </button>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto px-4 pb-[100px] pt-5 desk:px-8 desk:pb-10 desk:pt-8">
        {/* Desktop back link */}
        <button
          onClick={onBack}
          className="hidden desk:flex items-center gap-2 mb-6 text-text-muted hover:text-text transition-colors"
        >
          <svg className="w-[12px] h-[12px]" fill="none" stroke="currentColor" strokeWidth={2.5} viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
          </svg>
          <span className="font-mono text-[10px] font-bold tracking-[0.14em]">BACK TO SETTINGS</span>
        </button>

        {/* Page header */}
        <div>
          <div className="font-mono text-[11px] font-bold tracking-[0.2em] text-logo-green text-glow">
            LEGAL
          </div>
          <h1 className="mt-3 font-led text-[40px] leading-none tracking-[0.1em] text-text desk:text-[58px]">
            {title}
          </h1>
        </div>

        <div className="mt-8 flex flex-col gap-3">
          {sections.map((section, i) => (
            <div key={i} className="border border-border bg-white/[0.012]">
              {section.heading && (
                <div className="border-b border-border bg-white/[0.025] px-3 py-3">
                  <span className="font-mono text-[10px] font-bold tracking-[0.18em] text-text-muted">
                    {section.heading.toUpperCase()}
                  </span>
                </div>
              )}
              <div className="px-3 py-4">
                <p className="font-mono text-[13px] text-text-dim leading-[1.7] whitespace-pre-line">{section.body}</p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

// --- Legal Content ---

const effectiveDate = "May 4, 2026";

const privacyPolicy: LegalSectionData[] = [
  {
    heading: null,
    body: `Effective date: ${effectiveDate}\n\nDevkat ("we", "our", "the app") turns your AI coding sessions into shareable visual cards. This policy explains what data we collect, how we use it, and the controls you have.`,
  },
  {
    heading: "1. Data We Collect",
    body: `Account credentials. When you sign up we store your email address and a securely hashed password via Supabase Auth. We never see or store your plaintext password.\n\nSession statistics. When you push a session from your machine, we receive aggregate stats only: duration, lines added/removed, file count, token usage, model name, and timestamps. We do not receive source code, file contents, file paths, environment variables, or prompt/response text.\n\nDevice information. We may collect basic device identifiers (iOS version, device model) for crash reporting and analytics. This data is anonymised and cannot be linked to your source code.`,
  },
  {
    heading: "2. Data We Never Collect",
    body: `Source code or diffs. Devkat's CLI parser computes statistics locally on your machine. Raw code never leaves your device.\n\nFile paths. Paths are counted but not transmitted. The "Scope" stat is a number, not a list of filenames.\n\nSecrets or credentials. The CLI does not read .env files, API keys, or tokens from your codebase. A pre-flight scan strips any secrets that might appear in session metadata before upload.\n\nPrompt or response text. The content of your conversations with AI assistants is never sent to our servers.`,
  },
  {
    heading: "3. How We Use Your Data",
    body: `Display your sessions. Statistics are stored so you can view your session history and generate overlay cards within the app.\n\nImprove the product. We may use anonymised, aggregate usage patterns (e.g. average session length across all users) to improve Devkat. We will never sell individual data or share it with third parties for advertising.`,
  },
  {
    heading: "4. Image Composition & Sharing",
    body: `Overlay cards are rendered entirely on your device. When you copy or save an image, it goes to your local clipboard or camera roll. Devkat does not upload, store, or have access to the images you create. What you share and where you share it is entirely your choice.`,
  },
  {
    heading: "5. Data Storage & Security",
    body: `Your session data is stored in Supabase (hosted on AWS) with row-level security — each user can only access their own records. Auth tokens are stored in your device's Keychain. All network communication uses TLS 1.2+.`,
  },
  {
    heading: "6. Data Retention & Deletion",
    body: `You can delete your account at any time from Settings. When you delete your account, all associated session data is permanently removed from our servers. There is no recovery period — deletion is immediate and irreversible.`,
  },
  {
    heading: "7. Third-Party Services",
    body: `Supabase — authentication and database hosting.\nApple — app distribution, crash reporting via Xcode Organizer.\n\nWe do not use any third-party analytics SDKs, advertising networks, or tracking pixels.`,
  },
  {
    heading: "8. Children's Privacy",
    body: `Devkat is not directed at children under 13. We do not knowingly collect information from children under 13. If you believe a child has provided us with personal data, please contact us and we will delete it.`,
  },
  {
    heading: "9. Changes to This Policy",
    body: `We may update this policy from time to time. If we make material changes, we will notify you through the app or via email. Your continued use of Devkat after changes take effect constitutes acceptance of the updated policy.`,
  },
  {
    heading: "10. Contact",
    body: `Questions or concerns? Reach us at support@devkat.app.`,
  },
];

const termsOfService: LegalSectionData[] = [
  {
    heading: null,
    body: `Effective date: ${effectiveDate}\n\nBy using Devkat you agree to these terms. If you don't agree, please don't use the app.`,
  },
  {
    heading: "1. What Devkat Does",
    body: `Devkat parses aggregate statistics from your AI coding sessions and displays them as visual overlay cards. The app does not access, read, store, or transmit your source code.`,
  },
  {
    heading: "2. Your Account",
    body: `You must provide a valid email to create an account. You're responsible for keeping your credentials secure. One account per person — don't share your login. We reserve the right to suspend accounts that violate these terms.`,
  },
  {
    heading: "3. Your Data, Your Responsibility",
    body: `Session statistics you push to Devkat belong to you. You grant us a limited license to store and display this data back to you within the app. We don't claim ownership of your data.\n\nThe images you create with Devkat are yours. You're responsible for ensuring anything you share publicly doesn't contain sensitive information. While Devkat includes redaction features, you should always review a card before posting it.`,
  },
  {
    heading: "4. Acceptable Use",
    body: `Don't use Devkat to:\n• Reverse-engineer, decompile, or disassemble the app.\n• Attempt to access other users' data.\n• Automate access in a way that degrades the service for others.\n• Distribute malicious content through any sharing feature.`,
  },
  {
    heading: "5. Intellectual Property",
    body: `The Devkat name, logo, pixel cat mascot, overlay templates, and app design are our intellectual property. Your session data and generated images are yours.`,
  },
  {
    heading: "6. Service Availability",
    body: `We aim to keep Devkat available and reliable, but we don't guarantee 100% uptime. We may pause the service for maintenance, updates, or circumstances beyond our control. We'll try to give advance notice when possible.`,
  },
  {
    heading: "7. Limitation of Liability",
    body: `Devkat is provided "as is" without warranties of any kind. We're not liable for any indirect, incidental, or consequential damages arising from your use of the app. Our total liability is limited to the amount you've paid us in the 12 months preceding the claim (which, for a free app, is zero).`,
  },
  {
    heading: "8. Termination",
    body: `You can stop using Devkat and delete your account at any time. We may also terminate or suspend your access if you violate these terms. On termination, your data is deleted per our Privacy Policy.`,
  },
  {
    heading: "9. Changes to These Terms",
    body: `We may update these terms. Material changes will be communicated through the app. Continued use after changes means you accept the new terms.`,
  },
  {
    heading: "10. Governing Law",
    body: `These terms are governed by the laws of the United States. Any disputes will be resolved in the courts of New York, NY.`,
  },
  {
    heading: "11. Contact",
    body: `Questions? Reach us at support@devkat.app.`,
  },
];
