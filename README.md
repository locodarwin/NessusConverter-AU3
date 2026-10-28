# NessusConverter-AU3

An AutoIt port of [levyjm/NessusConverter](https://github.com/levyjm/NessusConverter).
It gathers every `.nessus` file in a folder and writes their findings to a single
CSV file you can open in Excel, with one row per finding:

| ip Address | vulnerability | severity |
|------------|---------------|----------|
| host name from `<ReportHost name="...">` | `pluginName` of each `<ReportItem>` | `severity` of that item |

## Usage

Drop `nessus_to_csv.au3` into the folder that holds your `.nessus` files and
double-click it. When the summary box appears, the CSV is at
`%TEMP%\nessus_file.csv`.

From a command prompt you can point it elsewhere:

```
AutoIt3.exe nessus_to_csv.au3 [input_dir] [output_csv] [/quiet]
```

- `input_dir` – folder containing the `.nessus` files (default: the script's own folder)
- `output_csv` – path of the CSV to write (default: `%TEMP%\nessus_file.csv`)
- `/quiet` – do not show the summary message box

Compiled with Aut2Exe the script becomes a console program, so progress and the
summary also print to the command prompt.

## Requirements

- AutoIt 3.3.14 or newer
- Windows with MSXML 6 (present on every supported version). No extra UDFs.

## Notes on the port

- The original Python wrote to `/tmp/nessus_file.csv`; this writes to the
  Windows temp folder by default and accepts an output path argument.
- The original paired host names with findings by list index, so a host with
  several findings came out with only one row and the rest were attributed to
  the wrong hosts. This port walks each `ReportHost` and emits every
  `ReportItem` beneath it with the correct host name.
- Fields containing commas, quotes or line breaks are quoted per RFC 4180.
- Files that fail to parse are skipped with a note on the console; the rest of
  the folder is still converted.
