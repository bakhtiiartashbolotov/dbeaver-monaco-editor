#!/usr/bin/env bash
set -euo pipefail
root=.cache/dbeaver-26.1.0/dbeaver
[[ $# -eq 0 ]] || { echo 'no arguments accepted' >&2; exit 2; }
command -v javap >/dev/null || { echo 'required Java API inspector unavailable: javap' >&2; exit 1; }
command -v javac >/dev/null || { echo 'required Java compiler unavailable: javac' >&2; exit 1; }
[[ -d "$root/plugins" ]] || { echo 'prepared DBeaver installation missing' >&2; exit 1; }
case "$(realpath "$root")" in "$(realpath .cache/dbeaver-26.1.0)"/*) ;; *) echo 'installation escaped prepared root' >&2; exit 1;; esac
one() { local pattern=$1; mapfile -t matches < <(find "$root/plugins" -maxdepth 1 -type f -name "$pattern"); [[ ${#matches[@]} -eq 1 ]] || { echo "expected one $pattern, found ${#matches[@]}" >&2; exit 1; }; printf '%s' "${matches[0]}"; }
sql=$(one 'org.jkiss.dbeaver.ui.editors.sql_*.jar'); text_bundle=$(one 'org.eclipse.text_[0-9]*.jar'); swt=$(one 'org.eclipse.swt.gtk.linux.x86_64_*.jar'); launcher=$(one 'org.eclipse.equinox.launcher_*.jar')
sql_entries=$(unzip -Z1 "$sql")
for entry in org/jkiss/dbeaver/ui/editors/sql/SQLEditorPresentation.class schema/org.jkiss.dbeaver.sqlPresentation.exsd; do grep -Fxq "$entry" <<<"$sql_entries" || { echo "missing $entry" >&2; exit 1; }; done
grep -Fxq 'org/eclipse/jface/text/IDocumentExtension4.class' <<<"$(unzip -Z1 "$text_bundle")"
grep -Fxq 'org/eclipse/swt/browser/Browser.class' <<<"$(unzip -Z1 "$swt")"
[[ -x "$root/dbeaver" ]] || { echo 'DBeaver launcher is not executable' >&2; exit 1; }
[[ -x "$root/jre/bin/java" ]] || { echo 'bundled DBeaver JRE is not executable' >&2; exit 1; }
[[ -f "$launcher" ]] || { echo 'Equinox launcher bundle is missing' >&2; exit 1; }
mapfile -t apps < <(sed -n 's/^eclipse.application=//p' "$root/configuration/config.ini")
mapfile -t products < <(sed -n 's/^eclipse.product=//p' "$root/configuration/config.ini")
[[ ${#apps[@]} -eq 1 && -n ${apps[0]} ]] || { echo 'ambiguous application ID' >&2; exit 1; }
[[ ${#products[@]} -eq 1 && -n ${products[0]} ]] || { echo 'ambiguous product ID' >&2; exit 1; }
printf 'application.id=%s\nproduct.id=%s\nlauncher=%s\n' "${apps[0]}" "${products[0]}" "$root/dbeaver"
temporary=$(mktemp -d)
contributor_javap=$temporary/contributor.javap
base_javap=$temporary/base.javap
trap 'rm -rf "$temporary"' EXIT
javap -public -classpath "$sql" org.jkiss.dbeaver.ui.editors.sql.SQLEditorPresentation > "$temporary/presentation.javap"
cat > "$temporary/presentation.expected" <<'EOF'
Compiled from "SQLEditorPresentation.java"
public interface org.jkiss.dbeaver.ui.editors.sql.SQLEditorPresentation {
  public abstract void createPresentation(org.eclipse.swt.widgets.Composite, org.jkiss.dbeaver.ui.editors.sql.SQLEditor);
  public default void showPresentation(org.jkiss.dbeaver.ui.editors.sql.SQLEditor, boolean);
  public default void hidePresentation(org.jkiss.dbeaver.ui.editors.sql.SQLEditor);
  public default boolean canShowPresentation(org.jkiss.dbeaver.ui.editors.sql.SQLEditor, boolean);
  public default boolean canHidePresentation(org.jkiss.dbeaver.ui.editors.sql.SQLEditor);
  public abstract void dispose();
  public abstract org.eclipse.jface.viewers.ISelectionProvider getSelectionProvider();
}
EOF
diff -u "$temporary/presentation.expected" "$temporary/presentation.javap" || {
  echo 'SQLEditorPresentation public API contract drifted' >&2
  exit 1
}
javap -public -constants -classpath "$sql" org.jkiss.dbeaver.ui.editors.sql.SQLEditor \
  org.jkiss.dbeaver.ui.editors.sql.SQLEditorCommands > "$temporary/sql-public.javap"
for pattern in \
  'public void showExtraPresentation(java.lang.String);' \
  'public void showExtraPresentation(org.jkiss.dbeaver.ui.editors.sql.registry.SQLPresentationDescriptor);' \
  'CMD_EXECUTE_STATEMENT = "org.jkiss.dbeaver.ui.editors.sql.run.statement";' \
  'CMD_EXECUTE_SCRIPT = "org.jkiss.dbeaver.ui.editors.sql.run.script";'; do
  grep -Fq "$pattern" "$temporary/sql-public.javap" || { echo "DBeaver SQL public API drift: $pattern" >&2; exit 1; }
done
workbench=$(one 'org.eclipse.ui.workbench_[0-9]*.jar')
javap -public -constants -classpath "$workbench" org.eclipse.ui.IWorkbenchCommandConstants > "$temporary/workbench-commands.javap"
for pattern in \
  'FILE_SAVE = "org.eclipse.ui.file.save";' \
  'EDIT_UNDO = "org.eclipse.ui.edit.undo";' \
  'EDIT_REDO = "org.eclipse.ui.edit.redo";'; do
  grep -Fq "$pattern" "$temporary/workbench-commands.javap" || { echo "workbench command ID drift: $pattern" >&2; exit 1; }
done
cat > "$temporary/ApiContract.java" <<'EOF'
import org.eclipse.jface.text.IDocumentExtension4;
import org.eclipse.jface.text.IRewriteTarget;
import org.eclipse.jface.text.IUndoManager;
import org.eclipse.jface.viewers.ISelectionProvider;
import org.eclipse.ui.commands.ICommandService;
import org.eclipse.ui.handlers.IHandlerService;
final class ApiContract {
  void verify(IRewriteTarget rewrite, IUndoManager undo, ISelectionProvider selection,
      IDocumentExtension4 document, IHandlerService handlers, ICommandService commands) throws Exception {
    rewrite.beginCompoundChange();
    rewrite.endCompoundChange();
    undo.undo();
    undo.redo();
    selection.getSelection();
    document.getModificationStamp();
    handlers.executeCommand("org.eclipse.ui.file.save", null);
    commands.getCommand("org.eclipse.ui.edit.undo");
  }
}
EOF
javac -proc:none -classpath "$root/plugins/*" -d "$temporary/classes" "$temporary/ApiContract.java" || {
  echo 'public Eclipse compile contract drifted' >&2
  exit 1
}
javap -p -c -classpath "$sql" org.jkiss.dbeaver.ui.editors.sql.SQLEditorContributor > "$contributor_javap"
javap -p -c -classpath "$sql" org.jkiss.dbeaver.ui.editors.sql.SQLEditorBase > "$base_javap"
for pattern in 'private void createActions();' 'public void contributeToMenu' 'org.jkiss.dbeaver.ui.editors.text.content.format' 'Field contentFormatProposal' 'String edit'; do
  grep -Fq "$pattern" "$contributor_javap" || { echo "missing format contributor evidence: $pattern" >&2; exit 1; }
done
for pattern in 'protected void createActions();' 'public void editorContextMenuAboutToShow' 'class org/eclipse/ui/texteditor/TextOperationAction' 'bipush        15' 'org.jkiss.dbeaver.ui.editors.text.content.format' 'String format'; do
  grep -Fq "$pattern" "$base_javap" || { echo "missing format editor evidence: $pattern" >&2; exit 1; }
done
echo 'native Format bytecode surface evidence passed'
echo 'DBeaver baseline verification passed'
