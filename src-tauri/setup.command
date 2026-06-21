#!/usr/bin/env bash
set -euo pipefail

APP="/Applications/Eye in the Sky.app"
REL="$APP/Contents/Resources/rel"
ENV_FILE="$HOME/.config/eits/.env"

log()  { echo "  $*"; }
ok()   { echo "✓ $*"; }
fail() { echo "✗ $*"; exit 1; }

echo ""
echo "Eye in the Sky — first-run setup"
echo "================================="
echo ""

# ── 1. Homebrew ───────────────────────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
  log "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
else
  ok "Homebrew already installed"
fi

# ── 2. PostgreSQL ─────────────────────────────────────────────────────────────
if ! brew list postgresql@17 &>/dev/null; then
  log "Installing PostgreSQL 17..."
  brew install postgresql@17
else
  ok "PostgreSQL 17 already installed"
fi

# Ensure pg binaries are on PATH
PG_BIN="$(brew --prefix postgresql@17)/bin"
export PATH="$PG_BIN:$PATH"

# Start the service
if ! pg_isready -q 2>/dev/null; then
  log "Starting PostgreSQL service..."
  brew services start postgresql@17
  sleep 3
fi

if pg_isready -q; then
  ok "PostgreSQL is running"
else
  fail "PostgreSQL failed to start. Try: brew services restart postgresql@17"
fi

# ── 3. Database ───────────────────────────────────────────────────────────────
if psql -lqt 2>/dev/null | cut -d'|' -f1 | grep -qw eits_dev; then
  ok "Database eits_dev already exists"
else
  log "Creating database eits_dev..."
  createdb eits_dev
  ok "Created eits_dev"
fi

# ── 4. .env file ──────────────────────────────────────────────────────────────
mkdir -p "$(dirname "$ENV_FILE")"

if [[ -f "$ENV_FILE" ]]; then
  ok ".env already exists at $ENV_FILE"
else
  log "Writing default .env..."
  DB_USER="$(whoami)"
  cat > "$ENV_FILE" <<EOF
DATABASE_URL=ecto://${DB_USER}@localhost/eits_dev
DATABASE_SSL_VERIFY=false
PHX_SERVER=true
PHX_DISABLE_FORCE_SSL=1
DISABLE_AUTH=1
EOF
  ok "Created $ENV_FILE"
fi

# Symlink .env into the release directory so the app finds it at startup
if [[ ! -L "$REL/.env" ]]; then
  ln -sf "$ENV_FILE" "$REL/.env" 2>/dev/null || true
fi

# ── 5. Migrations ─────────────────────────────────────────────────────────────
if [[ -x "$REL/bin/eye_in_the_sky" ]]; then
  log "Running database migrations..."
  env \
    DATABASE_URL="ecto://$(whoami)@localhost/eits_dev" \
    DATABASE_SSL_VERIFY=false \
    PHX_SERVER=false \
    "$REL/bin/eye_in_the_sky" eval "EyeInTheSky.Release.migrate()" 2>&1 | tail -5
  ok "Migrations complete"
else
  log "Skipping migrations — app not found at $REL/bin/eye_in_the_sky"
fi

echo ""
echo "Setup complete. Open Eye in the Sky from your Applications folder."
echo ""
