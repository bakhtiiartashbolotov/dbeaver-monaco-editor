# Task 1 DBeaver 26.1.0 baseline evidence

## Product archive and platform

- Archive: `https://dbeaver.io/files/26.1.0/dbeaver-ce-26.1.0-linux-x86_64.tar.gz`
- Official checksum source: `https://downloads.dbeaver.net/community/26.1.0/checksum/dbeaver-ce-26.1.0-linux-x86_64.tar.gz.sha256`
- SHA-256: `cc090775d879c66f521cc57a39c269976037fa54b818c2436d9ffece0ff93f31`
- Redirect chain: `dbeaver.io` → `github.com/dbeaver/dbeaver/releases/download/26.1.0` → `release-assets.githubusercontent.com`, all HTTPS.
- DBeaver product: 26.1.0 (`org.jkiss.dbeaver.core` 26.1.0.202605311718).
- SQL editor bundle: `org.jkiss.dbeaver.ui.editors.sql` 1.0.180.202605311718; it exports `org.jkiss.dbeaver.ui.editors.sql`.
- Eclipse UI: 3.208.0.v20251219-1043; JFace Text: 3.30.0.v20260203-0841; SWT: 3.133.0.v20260225-1014; Equinox launcher: 1.7.100.v20251111-0406.

## Launch contract

The product's `configuration/config.ini` contains one unambiguous application and product value:

- application ID: `org.jkiss.dbeaver.ui.app.standalone.standalone`
- product ID: `org.jkiss.dbeaver.ui.app.standalone.product`
- launcher: `.cache/dbeaver-26.1.0/dbeaver/dbeaver`
- Task 4 UI-test invocation: `<launcher> -application org.jkiss.dbeaver.ui.app.standalone.standalone -product org.jkiss.dbeaver.ui.app.standalone.product`; no additional product argument was found in the shipped configuration.

## Public compile contract

`javap -public` against the shipped bundles proves:

- public `SQLEditorPresentation`, including `createPresentation`, `dispose`, `getControl`, `getTextViewer`, `getAdapter`, `canShowPresentation(SQLEditor, boolean)`, and `canHidePresentation(SQLEditor)`;
- public `SQLEditor.showExtraPresentation(String)` and `showExtraPresentation(SQLPresentationDescriptor)`;
- `SQLEditorCommands.CMD_EXECUTE_STATEMENT` = `org.jkiss.dbeaver.ui.editors.sql.run.statement` and `CMD_EXECUTE_SCRIPT` = `org.jkiss.dbeaver.ui.editors.sql.run.script`;
- Eclipse `ISelectionProvider`, `IDocumentExtension4`, `IRewriteTarget.beginCompoundChange/endCompoundChange`, and `IUndoManager.undo/redo` are public.

The SQL presentation schema is shipped at `schema/org.jkiss.dbeaver.sqlPresentation.exsd`. Later code must use the extension and public APIs, not `ExtraPresentationManager`.

## Critical native command routes and surfaces

All routes below use Eclipse commands and the public `IHandlerService` (`canExecute`, `executeCommand`) plus command enabled state; none of the inspected toolbar/menu/key contributions directly mutates editor text.

| Route | Command ID | Handler/service evidence | Shipped surfaces |
| --- | --- | --- | --- |
| Save | `org.eclipse.ui.file.save` | Eclipse default `SaveHandler`; active `ISaveablePart` | File menu, workbench save image/toolbar action, global `M1+S` |
| Undo | `org.eclipse.ui.edit.undo` | Eclipse text-editor action/undo manager via command service | Edit menu, workbench action/image, global `M1+Z` |
| Redo | `org.eclipse.ui.edit.redo` | Eclipse text-editor action/undo manager via command service | Edit menu, workbench action/image, global `M1+Y` and `M1+M2+Z` |
| Statement | `org.jkiss.dbeaver.ui.editors.sql.run.statement` | public command; `SQLEditorHandlerExecute`; enabled by `org.jkiss.dbeaver.ui.editors.sql.canExecute=statement` | SQL toolbar, SQL/editor context menus, global focused-context `Ctrl+Enter` (`Command+Enter` on macOS) |
| Script | `org.jkiss.dbeaver.ui.editors.sql.run.script` | public command; `SQLEditorHandlerExecute`; enabled by `org.jkiss.dbeaver.ui.editors.sql.canExecute=script` | SQL toolbar, SQL/editor context menus, global focused-context `Alt+X` |

## Native formatting compatibility finding

Formatting is present and publicly command-backed: `org.jkiss.dbeaver.ui.editors.text.content.format`. Its global keybinding is `Ctrl+Shift+F`; SQL menu enablement/visibility is resolved through the Eclipse command/handler service. The active handler contract is queried through public `IHandlerService.canExecute/executeCommand`; the shipped content-editor handler is `org.jkiss.dbeaver.ui.editors.content.ContentFormatHandler`. Therefore Task 7 can guard the public command route; Monaco must remain read-only if its scoped active handler cannot be proven and guarded at runtime. No direct mutating format toolbar contribution was found.
