# SAP-Table-EXP-IMP-for-SystemCopy

SAP&trade; Table EXP/IMP for SystemCopy &copy; Florian Lamml 2026

A simple script for exporting and importing SAP tables during a system copy.

<img width="711" height="519" alt="SAP-Table-EXP-IMP-for-SystemCopy" src="https://github.com/user-attachments/assets/13697342-5638-4b1c-a334-342589b8a43d" />

## Unix / Linux / AIX

> [!IMPORTANT]
>`copy to your Unix / Linux Server and run sap_tab_exp_imp.sh`
>
>
> `sap_tab_exp_imp.sh must be executable (e.g. chmod u+x sap_tab_exp_imp.sh)`

Needs the `dialog` command (a prebuilt `dialog` for AIX is included in `dialogaix`).

## Windows

> [!IMPORTANT]
>`copy to your Windows Server and run sap_tab_exp_imp.ps1 as <sid>adm`
>
>
> `powershell.exe -ExecutionPolicy Bypass -File .\sap_tab_exp_imp.ps1`

Requirements:

* Windows PowerShell 5.1 or PowerShell 7+
* a real console host (`conhost` / Windows Terminal) - the **PowerShell ISE is not supported**
* `R3trans.exe` must be in the `PATH` (it is when you are logged on as `<sid>adm`)
* `SAPSYSTEMNAME` must be set (it is when you are logged on as `<sid>adm`)

The PowerShell version is a full port of the shell script and uses the same
templates, the same config options, the same file names and the same exit codes.
The linux `dialog` command is replaced by a built-in console UI
(`script\sap_expimp_ui.ps1`), so no additional software has to be installed.

Keys in the console UI:

| Key | Function |
| --- | --- |
| `UP` / `DOWN` / `PGUP` / `PGDN` / `HOME` / `END` | move |
| `SPACE` | select / toggle |
| `A` / `N` | select all / none (checklist) |
| `ENTER` | OK |
| `ESC` | Cancel |

## Files

| File | Description |
| --- | --- |
| `sap_tab_exp_imp.sh` | main script (Unix / Linux / AIX) |
| `script/sap_export_tables.sh` | export script (Unix / Linux / AIX) |
| `script/sap_import_tables.sh` | import script (Unix / Linux / AIX) |
| `sap_tab_exp_imp.ps1` | main script (Windows) |
| `script/sap_export_tables.ps1` | export script (Windows) |
| `script/sap_import_tables.ps1` | import script (Windows) |
| `script/sap_expimp_ui.ps1` | console UI for Windows (replaces `dialog`) |
| `templates/*` | R3trans table templates (used by both versions) |

## Config

Both main scripts have the same three config options at the top:

| Option | Description |
| --- | --- |
| `EXPIMPLOC` | export / import location, default `<script dir>/expimp/<SID>` |
| `EXPCLIENT` | `ALL`, `000` or a client number, default `ALL` |
| `PARALLEL` | R3trans parallel parameter (SAP note 1127194), default `0` |

## Exit codes

| Code | Description |
| --- | --- |
| 99 | started as `root` (Unix) / built-in `Administrator` (Windows) |
| 98 | cannot find SAP SID |
| 97 | cannot start `dialog` (Unix) / the console UI (Windows) |
| 96 | hit ESC |
| 95 | cannot find `R3trans.exe` (Windows only) |
| 10 | export: exit because old run detected |
| 11 | export: fail to select templates for export |
| 12 | export: no template selected for export |
| 13 | export: error while export |
| 14 | export: export info error |
| 20 | import: no exports found for import |
| 21 | import: exit because old run detected |
| 22 | import: no OK exports found for import |
| 23 | import: import select error |
| 24 | import: no exports selected for import |
| 25 | import: error while import |
| 26 | import: import info error |

Website: www.florian-lamml.de
