# OpenNGC Messier data

`messier-openngc.json` is a subset of [OpenNGC by Mattia Verga and contributors](https://github.com/mattiaverga/OpenNGC), revision [36cb178](https://github.com/mattiaverga/OpenNGC/tree/36cb178a0f69dba8bfc03a99c10512831edf1c6b). The data subset is distributed under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).

The subset selects Messier-tagged rows from NGC.csv and addendum.csv, skips duplicates and existing OMANOVA entries, converts coordinates to decimal hours/degrees and angular major-axis sizes to degrees, and adapts display names and object classes. OpenNGC's duplicate M102 entry is omitted. Existing OMANOVA entries retain their own attribution.
