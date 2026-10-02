#!/bin/bash
set -euo pipefail

RO_LIST="/etc/cursor-ro.list"
RW_LIST="/etc/cursor-rw.list"

echo "== FS verify =="
echo "HOME is set to: ${HOME:-'NOT SET'}"
echo "Current user: $(whoami)"
echo "Current working directory: $(pwd)"

if [[ ! -f "$RO_LIST" || ! -f "$RW_LIST" ]]; then
  echo "ERROR: verify lists not found: $RO_LIST $RW_LIST"
  exit 1
fi

# Always include internal expected RW dirs as well
EXTRA_RW="
${HOME}/writable
${HOME}/.cursor
${HOME}/.config
${HOME}/.cache
${HOME}/.mozilla
"

STAMP="perm_test_$$"
EXEC_TEST="${HOME}/writable/perm_exec_${STAMP}.sh"

echo "-- RO checks --"
while IFS= read -r d; do
  [[ -z "$d" ]] && continue
  echo -n "RO: $d ... "
  ls -ld "$d" >/dev/null 2>&1 || { echo "FAIL (not readable)"; exit 1; }
  if bash -lc "echo RO > '$d/$STAMP' 2>/dev/null"; then
    echo "FAIL (write succeeded)"
    rm -f "$d/$STAMP" || true
    exit 1
  fi
  echo "OK"
done < "$RO_LIST"

echo "-- RW checks --"
check_rw_dir() {
  local d="$1"
  echo -n "RW: $d ... "
  [ -d "$d" ] || { echo "FAIL (missing)"; exit 1; }
  if ! (echo "RW" > "$d/$STAMP" 2>/dev/null); then
    echo "FAIL (permission denied)"
    exit 1
  fi
  [[ "$(cat "$d/$STAMP")" == "RW" ]] || { echo "FAIL (readback mismatch)"; exit 1; }
  rm -f "$d/$STAMP"
  echo "OK"
}

while IFS= read -r d; do
  [[ -z "$d" ]] && continue
  check_rw_dir "$d"
done < "$RW_LIST"

# Extras
while IFS= read -r d; do
  [[ -z "$d" ]] && continue
  check_rw_dir "$d"
done <<< "$EXTRA_RW"

echo "-- EXEC check --"
cat > "$EXEC_TEST" <<'SH'
#!/bin/bash
echo EXEC_OK
SH
chmod +x "$EXEC_TEST"
OUT="$("$EXEC_TEST")" || { echo "FAIL (exec failed)"; exit 1; }
[[ "$OUT" == "EXEC_OK" ]] || { echo "FAIL (unexpected output: $OUT)"; exit 1; }
rm -f "$EXEC_TEST"

echo "== FS verify: PASSED =="
