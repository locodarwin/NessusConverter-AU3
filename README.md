# NessusConverter-AU3

An AutoIt port of [levyjm/NessusConverter](https://github.com/levyjm/NessusConverter).
It gathers every `.nessus` file in a folder and writes their findings to a single
CSV file you can open in Excel, with one row per finding:

| ip Address | vulnerability | severity |
|------------|---------------|----------|
| `host-ip` tag of the `<ReportHost>`, or its `name` attribute | compliance check name for compliance scans, otherwise the `pluginName` of each `<ReportItem>` | `severity` of that item |

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
- `/debug` – also write the raw XML of the first finding in each file to
  `nessus_debug.txt` beside the CSV, useful when a column comes out wrong

Compiled with Aut2Exe the script becomes a console program, so progress and the
summary also print to the command prompt.

## Requirements

- AutoIt 3.3.14 or newer
- Windows with MSXML 6 (present on every supported version). No extra UDFs.

## Notes on the port

- The original Python wrote to `/tmp/nessus_file.csv`; this writes to the
  current user's Desktop by default and accepts an output path argument.
- The original paired host names with findings by list index, so a host with
  several findings came out with only one row and the rest were attributed to
  the wrong hosts. This port walks each `ReportHost` and emits every
  `ReportItem` beneath it with the correct host name.
- The first column prefers the `host-ip` host property over the `ReportHost`
  name attribute, which is often a hostname rather than an address.
- In a compliance scan every result is filed under a single plugin such as
  "Unix Compliance Checks", so the plugin name tells you nothing. For those
  items the vulnerability column holds the individual check name, taken from
  the `cm:compliance-check-name` element or, failing that, the quoted title
  that opens the item's `description`.
- Fields containing commas, quotes or line breaks are quoted per RFC 4180.
- Files that fail to parse are skipped with a note on the console; the rest of
  the folder is still converted.
