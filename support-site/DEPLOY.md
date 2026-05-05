# Deploying the Devkat support site

Plain static HTML, no build step. Deploys to GitHub Pages at:

- **Support URL:** `https://kahnxa.github.io/devkat/`
- **Privacy URL:** `https://kahnxa.github.io/devkat/privacy.html`

These are the URLs to paste into App Store Connect.

## One-time setup

### 1. Create the GitHub repo

From this directory:

```bash
cd /Users/xavierkahn/devkat/support-site
git init -b main
git add .
git commit -m "Initial Devkat support site"
gh repo create devkat --public --source=. --push
```

The repo name **must be `devkat`** so the Pages URL ends in `/devkat/`. If you already own a repo named `devkat`, pick a different name (e.g. `devkat-support`) and the URL becomes `https://kahnxa.github.io/<repo-name>/` — update the URLs you give Apple to match.

### 2. Enable GitHub Pages

```bash
gh api -X POST repos/kahnxa/devkat/pages \
  -f 'source[branch]=main' \
  -f 'source[path]=/'
```

Or via UI: repo → Settings → Pages → Source: **Deploy from a branch**, branch `main`, folder `/ (root)`.

### 3. Wait ~1 minute and verify

Open `https://kahnxa.github.io/devkat/` in a browser. You should see the support page. Also check `https://kahnxa.github.io/devkat/privacy.html`.

GitHub Pages serves over HTTPS by default — no extra config needed.

## Verify before submitting to App Store

- [ ] `https://kahnxa.github.io/devkat/` loads with no login
- [ ] `https://kahnxa.github.io/devkat/privacy.html` loads
- [ ] The page identifies the app (Devkat) and shows a contact method (xavier@alleykat.app)
- [ ] Both URLs use HTTPS (they will, automatically)

## Updating

Edit the HTML, commit, push. Pages republishes within ~1 minute.

```bash
git add . && git commit -m "Update support page" && git push
```

## Use these URLs in App Store Connect

- **Support URL:** `https://kahnxa.github.io/devkat/`
- **Privacy Policy URL:** `https://kahnxa.github.io/devkat/privacy.html`
- **Marketing URL** (optional): leave blank or reuse the support URL

## If you later buy a custom domain

If you eventually pick up something like `devkat.app`, add a `CNAME` file containing the domain, configure DNS (`A` records to GitHub's Pages IPs + an apex `ALIAS`/`ANAME` if your registrar supports it), and update the canonical URLs in `index.html` and `privacy.html`. Apple lets you change the Support URL on app updates.
