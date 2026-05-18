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
        title={legalSheet === "dataPrivacy" ? "Data & Privacy" : legalSheet === "terms" ? "Terms of Service" : "Privacy Policy"}
        sections={legalSheet === "terms" ? termsOfService : privacyPolicy}
        onClose={() => setLegalSheet(null)}
      />
    );
  }

  return (
    <div className="max-w-lg md:max-w-2xl mx-auto md:px-8">
      <div className="px-[16px] pt-[16px] md:px-0 md:pt-8 md:pb-10">
        <div className="flex flex-col gap-[28px]">
          {/* Header */}
          <div className="relative flex items-center justify-center pt-[8px] pb-[4px]">
            <button
              onClick={onClose}
              className="absolute left-0 w-[32px] h-[32px] bg-surface rounded-full flex items-center justify-center"
            >
              <svg className="w-[14px] h-[14px] text-text-dim" fill="none" stroke="currentColor" strokeWidth={2.5} viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
            <span className="text-[17px] font-semibold text-text">Settings</span>
          </div>

          {/* Data */}
          <SettingsSection title="Data">
            <ActionRow icon="refresh" label="Refresh Sessions" onClick={() => { window.location.reload(); }} />
          </SettingsSection>

          {/* About */}
          <SettingsSection title="About">
            <ActionRow icon="terminal" label="Devkat" />
            <SettingsDivider />
            <InfoRow label="Version" value="1.0 (web)" />
            <SettingsDivider />
            <MailRow label="Contact" address="xavier@alleykat.app" />
          </SettingsSection>

          {/* Legal */}
          <SettingsSection title="Legal">
            <NavRow label="Data & Privacy" onClick={() => setLegalSheet("dataPrivacy")} />
            <SettingsDivider />
            <NavRow label="Terms of Service" onClick={() => setLegalSheet("terms")} />
            <SettingsDivider />
            <NavRow label="Privacy Policy" onClick={() => setLegalSheet("privacy")} />
          </SettingsSection>

          {/* Account */}
          <SettingsSection title="Account">
            <InfoRow label="Email" value={email} />
            <SettingsDivider />
            <ActionRow label="Log Out" color="red" onClick={handleLogout} />
          </SettingsSection>

          {/* Delete Account */}
          <SettingsSection title="Delete Account">
            <ActionRow
              label="Delete Account"
              color="red"
              onClick={() => { setDeleteError(null); setShowDeleteConfirm(true); }}
              disabled={isDeleting}
            />
            {isDeleting && (
              <>
                <SettingsDivider />
                <div className="flex items-center gap-[10px] px-[16px] py-[14px]">
                  <div className="w-3 h-3 border-2 border-text-dim border-t-transparent rounded-full animate-spin" />
                  <span className="text-[12px] font-mono text-text-dim">Deleting account...</span>
                </div>
              </>
            )}
            {deleteError && (
              <>
                <SettingsDivider />
                <div className="px-[16px] py-[14px]">
                  <span className="text-[12px] font-mono text-red-400/85">{deleteError}</span>
                </div>
              </>
            )}
          </SettingsSection>
        </div>
      </div>

      {/* Delete confirmation dialog */}
      {showDeleteConfirm && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div className="absolute inset-0 bg-black/60" onClick={() => setShowDeleteConfirm(false)} />
          <div className="relative bg-surface-raised rounded-2xl p-6 mx-8 max-w-sm w-full space-y-4">
            <h3 className="text-[17px] font-semibold text-text text-center">Delete Account?</h3>
            <p className="text-[13px] text-text-dim text-center leading-relaxed">
              This permanently deletes your account and all synced session data. This cannot be undone.
            </p>
            <div className="flex gap-3 pt-2">
              <button
                onClick={() => setShowDeleteConfirm(false)}
                className="flex-1 py-[11px] rounded-xl bg-surface text-[15px] font-semibold text-text"
              >
                Cancel
              </button>
              <button
                onClick={() => { setShowDeleteConfirm(false); handleDelete(); }}
                className="flex-1 py-[11px] rounded-xl bg-red-500/20 text-[15px] font-semibold text-red-400"
              >
                Delete
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function SettingsSection({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-[8px]">
      <p className="text-[15px] font-semibold text-text-muted pl-[4px]">{title}</p>
      <div className="bg-surface-raised rounded-[12px] overflow-hidden">
        {children}
      </div>
    </div>
  );
}

function ActionRow({
  icon,
  label,
  color = "white",
  onClick,
  disabled,
}: {
  icon?: string;
  label: string;
  color?: string;
  onClick?: () => void;
  disabled?: boolean;
}) {
  const textColor = color === "red" ? "text-red-400" : "text-text";

  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className="w-full flex items-center gap-[10px] px-[16px] py-[14px] hover:bg-white/[0.03] transition-colors disabled:opacity-50"
    >
      {icon === "refresh" && (
        <svg className={`w-[15px] h-[15px] ${textColor}`} fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
        </svg>
      )}
      {icon === "terminal" && (
        <svg className={`w-[15px] h-[15px] ${textColor}`} fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" d="M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/>
        </svg>
      )}
      <span className={`text-[17px] ${textColor}`}>{label}</span>
    </button>
  );
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between px-[16px] py-[14px]">
      <span className="text-[17px] text-text">{label}</span>
      <span className="text-[17px] text-text-dim">{value}</span>
    </div>
  );
}

function NavRow({ label, onClick }: { label: string; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className="w-full flex items-center justify-between px-[16px] py-[14px] hover:bg-white/[0.03] transition-colors"
    >
      <span className="text-[17px] text-text">{label}</span>
      <svg className="w-[13px] h-[13px] text-text-muted" fill="none" stroke="currentColor" strokeWidth={2.5} viewBox="0 0 24 24">
        <path strokeLinecap="round" strokeLinejoin="round" d="M9 5l7 7-7 7" />
      </svg>
    </button>
  );
}

function MailRow({ label, address }: { label: string; address: string }) {
  return (
    <a
      href={`mailto:${address}`}
      className="flex items-center justify-between px-[16px] py-[14px] hover:bg-white/[0.03] transition-colors"
    >
      <span className="text-[17px] text-text">{label}</span>
      <span className="text-[17px] text-text-dim">{address}</span>
    </a>
  );
}

function SettingsDivider() {
  return <div className="h-[0.5px] bg-border ml-[16px]" />;
}

// --- Legal View ---

interface LegalSectionData {
  heading: string | null;
  body: string;
}

function LegalView({ title, sections, onClose }: { title: string; sections: LegalSectionData[]; onClose: () => void }) {
  return (
    <div className="max-w-lg md:max-w-3xl mx-auto md:px-8">
      <div className="px-[20px] pt-[16px] pb-[60px] md:px-0 md:pt-8 md:pb-10">
        <div className="flex flex-col gap-[24px]">
          {/* Header */}
          <div className="relative flex items-center justify-center pt-[8px] pb-[8px]">
            <button
              onClick={onClose}
              className="absolute left-0 w-[32px] h-[32px] bg-surface rounded-full flex items-center justify-center"
            >
              <svg className="w-[14px] h-[14px] text-text-dim" fill="none" stroke="currentColor" strokeWidth={2.5} viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
            <span className="text-[17px] font-semibold text-text">{title}</span>
          </div>

          {/* Sections */}
          {sections.map((section, i) => (
            <div key={i} className="flex flex-col gap-[8px]">
              {section.heading && (
                <p className="text-[15px] font-semibold text-text">{section.heading}</p>
              )}
              <p className="text-[15px] text-text-dim leading-[1.6] whitespace-pre-line">{section.body}</p>
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
