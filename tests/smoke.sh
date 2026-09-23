#!/bin/zsh
# End-to-end check of every bundled binary against the fixtures. Run on a macOS 27+ Apple silicon Mac.
set -u
root=${0:A:h:h}; fx=$root/tests/fixtures; fail=0
check() {  # check <label> <expected-substring> <command...>
  local label=$1 want=$2; shift 2
  local out; out=$("$@" 2>&1)
  if [[ $out == *$want* ]]; then print "ok   $label"; else print "FAIL $label\n$out"; fail=1; fi
}
sums=$(shasum $root/plugins/*/bin/fm-darwin-arm64 | awk '{print $1}' | sort -u | wc -l)
(( sums == 1 )) && print "ok   bundled binaries identical" || { print "FAIL bundled binaries differ; run scripts/build.sh"; fail=1; }

check "ocr image"            '$1,284.50'    $root/plugins/ocr/bin/fm ocr $fx/invoice.png
check "ocr scanned pdf"      'INVOICE #4471' $root/plugins/ocr/bin/fm ocr $fx/invoice-scanned.pdf
check "pdf-to-text layer"    '14 Oct 2026'  $root/plugins/pdf-to-text/bin/fm pdf-to-text $fx/invoice-text.pdf
check "pdf-to-text scanned"  '$1,284.50'    $root/plugins/pdf-to-text/bin/fm pdf-to-text $fx/invoice-scanned.pdf
check "describe-image"       'nvoice'       $root/plugins/describe-image/bin/fm describe-image $fx/invoice.png
check "ask-image"            '1,284.50'     $root/plugins/ask-image/bin/fm ask-image $fx/invoice.png "What is the total due?"
check "rejects wrong type"   'expects a .pdf' $root/plugins/pdf-to-text/bin/fm pdf-to-text $fx/invoice.png

exit $fail
