# Notepad Help

## Getting Started

- **New Tab** `⌘N`, **New Window** `⇧⌘N`, **Open** `⌘O`, **Save** `⌘S`, **Save As** `⇧⌘S`.
- Opening a file automatically detects its **encoding** and **line ending**, shown on the right of the status bar; click to change them.
- **Close Tab** `⌘W`; **Close Window** `⇧⌘W`.
- **Auto Save** is on by default: after quitting or a crash, relaunching restores all tabs and cursor positions.

## Common Actions

- **Find / Replace**: `⌘F` / `⌥⌘F`; `⌘G` next, `⇧⌘G` previous.
- **Go to Line**: `⌃G`.
- **Insert Date/Time**: `F5`.
- **Zoom**: `⌘+` / `⌘-` / `⌘0` (10%–500%).
- **Word Wrap**: `⌥⌘W` (checkable in the Format menu).
- **Font**: Format → Font… (system font panel).
- **Status Bar**: `⌘/` to show or hide.
- **Theme**: View → Theme (Light / Dark / System).
- **Switch Tabs**: `⇧⌘]` / `⇧⌘[`.
- **Print / Page Setup**: `⌘P` / File → Page Setup….

## Encodings & Line Endings

- Supports UTF-8, UTF-16 LE/BE, UTF-32 LE/BE (with / without BOM), GB18030 (GBK / GB2312), Big5, Windows-1252.
- Encoding is detected on open; click the encoding name in the status bar to **reopen** with a different encoding. Saving keeps the current encoding and original line endings.
- Line endings LF / CRLF / CR are recognized automatically and can be converted from the status bar.

## Large Files

Files larger than 10MB open in **read-only mode**; editing and saving are disabled to keep the app responsive.

## Printing

File → Print…: the header shows the centered file name, the footer shows "Page X of Y"; Page Setup adjusts paper, orientation and margins.

## FAQ

**Some Chinese files show garbled text?**

Click the encoding in the status bar, choose the correct one (e.g. GB18030) and reopen; saving keeps that encoding.

**How do I report a problem?**

Help → Send Feedback… (email). Please include your macOS version and steps to reproduce.
