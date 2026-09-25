#!/bin/zsh
# Download the SEC 10-K used by bench/sec_retrieval.py and render it to PDF locally with headless Chrome.
# SEC fair-access policy requires a contact email in the User-Agent: SEC_CONTACT=you@example.com scripts/fetch-sec.sh
set -e
root=${0:A:h:h}; out=$root/bench/fixtures/sec
: ${SEC_CONTACT:?set SEC_CONTACT to a contact email for the SEC User-Agent}
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
mkdir -p $out
curl -fsS -A "foundation-model-skills bench $SEC_CONTACT" \
  https://www.sec.gov/Archives/edgar/data/320193/000032019325000079/aapl-20250927.htm -o $out/aapl-10k-2025.htm
"$chrome" --headless=new --disable-gpu --no-pdf-header-footer --print-to-pdf=$out/aapl-10k-2025.pdf "file://$out/aapl-10k-2025.htm" 2>/dev/null
echo "wrote $out/aapl-10k-2025.pdf" >&2
