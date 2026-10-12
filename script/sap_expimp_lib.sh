#!/bin/bash
# SAP(R) Table EXP/IMP for SystemCopy (c) Florian Lamml 2026
# www.florian-lamml.de
# helper functions (shared by main / export / import script)
# Version 1.10 - Security Hardening

# find a tool for SHA-256 checksums (sha256sum on Linux, csum or openssl on AIX)
# prints the tool name, returns 1 if no usable tool was found
expimp_find_sha256_tool() {
 for tool in sha256sum shasum csum openssl
 do
  command -v "$tool" > /dev/null 2>&1 || continue
  SHA256TOOL=$tool
  if expimp_sha256 "$0" | grep -q '^[0-9a-f]\{64\}$'
  then
   echo "$tool"
   return 0
  fi
 done
 return 1
}

# SHA-256 checksum of a file (lower case hex)
expimp_sha256() {
 case "$SHA256TOOL" in
  sha256sum) sha256sum "$1" 2>/dev/null | awk '{ print $1 }' ;;
  shasum)    shasum -a 256 "$1" 2>/dev/null | awk '{ print $1 }' ;;
  csum)      csum -h SHA256 "$1" 2>/dev/null | awk '{ print $1 }' ;;
  openssl)   openssl dgst -sha256 "$1" 2>/dev/null | awk '{ print $NF }' ;;
 esac | tr '[:upper:]' '[:lower:]'
}

# value of a metadata line "# KEY=value" in an info file
expimp_meta() {
 sed -n "s/^# $2=//p" "$1" | head -1
}

# files of a previous export / import run in EXPIMPLOC (one per line)
expimp_run_files() {
 for f in "$EXPIMPLOC"/selected_tables_for_export.conf "$EXPIMPLOC"/exported_tables.conf \
          "$EXPIMPLOC"/exported_tables_ok.conf "$EXPIMPLOC"/selected_tables_import.conf \
          "$EXPIMPLOC"/imported_tables.conf "$EXPIMPLOC"/*.tpl "$EXPIMPLOC"/*.dat \
          "$EXPIMPLOC"/*.exp.log "$EXPIMPLOC"/*.imp.log
 do
  [ -f "$f" ] && echo "$f"
 done
}
