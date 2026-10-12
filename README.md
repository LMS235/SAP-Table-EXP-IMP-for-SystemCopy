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

Needs the `dialog` command (a prebuilt `dialog` for AIX is included in `dialogaix`)
and a tool for SHA-256 checksums (`sha256sum`, `shasum`, `csum` or `openssl`).

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
* the script must be run as `<sid>adm` (not as the built-in Administrator or a system account)

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
| `script/sap_expimp_lib.sh` | helper functions (Unix / Linux / AIX) |
| `sap_tab_exp_imp.ps1` | main script (Windows) |
| `script/sap_export_tables.ps1` | export script (Windows) |
| `script/sap_import_tables.ps1` | import script (Windows) |
| `script/sap_expimp_ui.ps1` | console UI for Windows (replaces `dialog`) |
| `templates/*` | R3trans table templates (used by both versions) |

## Config

Both main scripts have the same config options at the top:

| Option | Description |
| --- | --- |
| `EXPIMPLOC` | export / import location (absolute path), default `<script dir>/expimp/<SID>` |
| `EXPCLIENT` | `ALL`, `DEFAULT` or a 3-digit client number, default `ALL` |
| `PARALLEL` | R3trans parallel parameter (SAP note 1127194), `0` or a positive number, default `0` |
| `BACKUPKEEP` | number of backups of previous runs to keep in `EXPIMPLOC/backup`, `0` = unlimited, default `0` |
| `EXPIMPPERM` | Unix only: `OPEN` (files `666`, directories `777`, no checks) or `STRICT` (files `660`, directories `770`, checks), default `OPEN` |
| `EXPIMPGROUP` | Windows only: group with access to `EXPIMPLOC` (e.g. other `<sid>adm` users), default `SAP_LocalAdmin` |

Invalid values stop the script with exit code 91.

## Security

> [!WARNING]
> The exports contain **sensitive data**, e.g. PSEs with private keys (`STRUST`),
> the secure storage (`SECSTORE`), RFC destinations (`SM59`), OAuth, LDAP and SAML2 configuration.

* The script must be run as `<sid>adm` (not as `root` / built-in Administrator / system account).
* Unix: the permissions are set by `EXPIMPPERM` (see Config):
  * `OPEN` (default): files `666`, directories `777`, no permission checks - works always,
    e.g. on NFS v3 shares with different UIDs / GIDs.
  * `STRICT`: files `660`, directories `770` (`umask 007`), so the export and the import can be run
    by different `<sid>adm` users of the same group (`sapsys`), but nobody else has access.
    The script stops if `EXPIMPLOC` contains files of another group or files writable by others.
  * An existing directory `EXPIMPLOC` may belong to another user / group, it only has to be
    writable for `<sid>adm`.
* Windows: `EXPIMPLOC` gets its own permissions without inheritance: full control for the current user,
  Administrators and SYSTEM, modify for `EXPIMPGROUP`. If the permissions cannot be set (e.g. the
  directory belongs to another user), only a warning is shown - `EXPIMPLOC` only has to be writable.
* Every export writes the SHA-256 checksum of each data file and the source system
  (SID, host, client, user, date) into `exported_tables.conf`.
* Before the import the checksums are verified (exit code 27 if a data file is missing or was changed)
  and the import has to be confirmed (default is "Exit"). The confirmation shows the source system
  of the export and a warning if its SID differs from the current SID. If the export was created by
  an older version without checksums, the SID of the current system has to be typed in to confirm.
* Before a new export, the files of the previous run are copied to `EXPIMPLOC/backup/<timestamp>`
  and only then deleted. With `BACKUPKEEP` > 0 only the newest backups are kept, older backups are
  deleted after a new backup was created (default `0` = backups are never deleted).
* If there are several exports (the current export and backups of previous runs), the export to
  import can be selected (default is the newest). The import reads the data from the selected
  directory and writes its own files (`*.imp.log`, `imported_tables.conf`, ...) into it.
* The data files are never deleted after an import (they can be imported several times or into
  several systems) - delete `EXPIMPLOC` manually when it is no longer needed.

## Exit codes

| Code | Description |
| --- | --- |
| 99 | started as `root` (Unix) / built-in `Administrator` or a system account (Windows) |
| 98 | cannot find SAP SID |
| 97 | cannot start `dialog` (Unix) / the console UI (Windows) |
| 96 | hit ESC |
| 95 | cannot find `R3trans.exe` (Windows only) |
| 94 | cannot create the export location / not writable (Unix `STRICT`: files of another group / writable by others) |
| 93 | no SHA-256 tool found (Unix only) |
| 92 | user is not `<sid>adm` |
| 90 | export / import script started directly (must be started by the main script) |
| 91 | invalid config value (`EXPIMPLOC`, `EXPCLIENT`, `PARALLEL`, `BACKUPKEEP`, `EXPIMPPERM`) |
| 10 | export: exit because old run detected |
| 11 | export: fail to select templates for export |
| 12 | export: no template selected for export |
| 13 | export: error while export (R3trans RC >= 8 or template missing) |
| 14 | export: export info error |
| 15 | export: backup of the previous run failed |
| 20 | import: no exports found for import |
| 21 | import: exit because old run detected |
| 22 | import: no OK exports found for import |
| 23 | import: import select error |
| 24 | import: no exports selected for import |
| 25 | import: error while import (R3trans RC >= 8) |
| 26 | import: import info error |
| 27 | import: checksum verification failed |
| 28 | import: import not confirmed |
| 29 | import: no export selected for import (current export / backup) |

Website: www.florian-lamml.de
