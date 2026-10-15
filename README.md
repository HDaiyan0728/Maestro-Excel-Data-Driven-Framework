# HTML Test Report Combiner

A Windows utility that combines multiple compatible HTML test reports into a single interactive summary.

## Features

- Select individual reports, multiple reports, ranges, or all reports.
- Summarize passed and failed flows.
- Display flow details, properties, steps, and durations.
- Filter reports by status and flow type.
- Generate a timestamped HTML summary.

## Requirements

- Windows
- Windows PowerShell
- HTML test reports compatible with the parser
- Internet access to load Bootstrap styling from its CDN

## Usage

1. Place `combine_report_generation.bat` in your working directory.
2. Create a folder named `Reports` beside the script.
3. Put your HTML test reports inside `Reports` or its subfolders.
4. Run `combine_report_generation.bat`.
5. Select reports using `all`, a range such as `1-5`, or individual numbers such as `1,3,5`.
6. Open the generated HTML summary from the `Combined Reports` folder.

## Compatibility

The script expects a particular HTML report structure. Other report formats may require adjustments to the parsing logic.

## License

Use the license already provided by the repository. If the repository has no license, consult the maintainer before adding or selecting one.