#!/usr/bin/env bash
set -euo pipefail
root=.cache/dbeaver-26.1.0/dbeaver
[[ $# -eq 0 ]] || { echo 'no arguments accepted' >&2; exit 2; }
[[ -d "$root/plugins" ]] || { echo 'prepared DBeaver installation missing' >&2; exit 1; }
case "$(realpath "$root")" in "$(realpath .cache/dbeaver-26.1.0)"/*) ;; *) echo 'installation escaped prepared root' >&2; exit 1;; esac
one() { local pattern=$1; mapfile -t matches < <(find "$root/plugins" -maxdepth 1 -type f -name "$pattern"); [[ ${#matches[@]} -eq 1 ]] || { echo "expected one $pattern, found ${#matches[@]}" >&2; exit 1; }; printf '%s' "${matches[0]}"; }
sql=$(one 'org.jkiss.dbeaver.ui.editors.sql_*.jar'); text_bundle=$(one 'org.eclipse.text_[0-9]*.jar'); swt=$(one 'org.eclipse.swt.gtk.linux.x86_64_*.jar'); launcher=$(one 'org.eclipse.equinox.launcher_*.jar')
sql_entries=$(unzip -Z1 "$sql")
for entry in org/jkiss/dbeaver/ui/editors/sql/SQLEditorPresentation.class schema/org.jkiss.dbeaver.sqlPresentation.exsd; do grep -Fxq "$entry" <<<"$sql_entries" || { echo "missing $entry" >&2; exit 1; }; done
grep -Fxq 'org/eclipse/jface/text/IDocumentExtension4.class' <<<"$(unzip -Z1 "$text_bundle")"
grep -Fxq 'org/eclipse/swt/browser/Browser.class' <<<"$(unzip -Z1 "$swt")"
[[ -x "$root/dbeaver" && -f "$launcher" ]]
mapfile -t apps < <(sed -n 's/^eclipse.application=//p' "$root/configuration/config.ini")
mapfile -t products < <(sed -n 's/^eclipse.product=//p' "$root/configuration/config.ini")
[[ ${#apps[@]} -eq 1 && -n ${apps[0]} ]] || { echo 'ambiguous application ID' >&2; exit 1; }
[[ ${#products[@]} -eq 1 && -n ${products[0]} ]] || { echo 'ambiguous product ID' >&2; exit 1; }
printf 'application.id=%s\nproduct.id=%s\nlauncher=%s\n' "${apps[0]}" "${products[0]}" "$root/dbeaver"
echo 'DBeaver baseline verification passed'
