# NessusConverter-AU3

An AutoIt port of [levyjm/NessusConverter](https://github.com/levyjm/NessusConverter).
It gathers every `.nessus` file in a folder and writes their findings to a single
CSV file you can open in Excel, one row per finding.

## Output

The first two columns identify the host:

| Column | Source |
|--------|--------|
| `ip Address` | the `host-ip` tag under `HostProperties`, or the `ReportHost` name if that tag is absent |
| `host` | the `ReportHost` name attribute |

After those comes one column for every attribute and every child element that
appears on any `ReportItem` in any of the files, named exactly as in the XML
(`pluginName`, `severity`, `description`, `plugin_output`,
`cm:compliance-check-name`, `cm:compliance-result`, and so on). Columns are
ordered by first appearance. A finding that lacks a field leaves that cell
empty. Elements that repeat on one finding, such as several `cve` entries, are
joined with `; ` in the one cell.

Long fields keep their line breaks inside quoted cells, and the file is UTF-8
with a byte order mark so Excel opens it directly.

## Usage

Drop `nessus_to_csv.au3` into the folder that holds your `.nessus` files and
double-click it. When the summary box appears, the CSV is at
`nessus_file.csv` on your Desktop.

From a command prompt you can point it elsewhere:

```
AutoIt3.exe nessus_to_csv.au3 [input_dir] [output_csv] [/quiet]
```

- `input_dir` – folder containing the `.nessus` files (default: the script's own folder)
- `output_csv` – path of the CSV to write (default: `nessus_file.csv` on the current user's Desktop)
- `/quiet` – do not show the summary message box

Compiled with Aut2Exe the script becomes a console program, so progress and the
summary also print to the command prompt.

## Requirements

- AutoIt 3.3.14 or newer
- Windows with MSXML 6 and the Scripting Runtime (both present on every
  supported version). No extra UDFs.

## Notes on the port

- The original Python wrote three fixed columns (IP, plugin name, severity) to
  `/tmp/nessus_file.csv`. This version writes every field of every finding, so
  compliance scans, where all results share one plugin name, come out with the
  individual check names and results, and defaults to the Desktop.
- Each file is parsed twice: once to learn the column set, once to write rows.
  That keeps memory use low on large exports.
- Files that fail to parse are skipped with a note on the console; the rest of
  the folder is still converted.
