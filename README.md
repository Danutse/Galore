# Galore Launcher

Galore Launcher is a Windows desktop control center for starting programs, tracking running applications, organizing quick-access items, managing small desktop tools, and keeping a personalized launcher layout.

## Highlights

- Launch or end the programs you configure.
- Choose whether actions apply to selected programs or every configured program at once.
- Change any managed executable from its right-click menu.
- Create four program categories, each containing up to five programs.
- Search files and installed applications from the built-in search window.
- Monitor CPU, RAM, GPU, and GPU-temperature information.
- Keep quick-access icons for files, folders, shortcuts, and web shortcuts.
- Mirror ordinary Windows application windows in the left-side taskbar.
- Use network retry, volume, keyboard-language, calculator, and post-it tools.
- Automatically save window placement, program choices, categories, post-its, and quick-access layout.

## Installation

1. Download `GaloreLauncherSetup.exe` from the latest GitHub release.
2. Run the installer.
3. Choose the folder where you want Galore installed.
4. Open `GaloreLauncher.exe` from the installation folder.

The installed release creates its `Settings`, `Logs`, and program-data folders as needed. No PowerShell modules folder is required beside the installed executable.

## First-time setup

1. Right-click a program name to choose the executable it should manage.
2. Left-click a program name or checkbox to include or exclude it from selected actions.
3. Use **Launch All**, **Terminate All**, **Launch Selected**, or **Terminate Selected**.
4. Right-click a category button to configure up to five programs.
5. Drag a supported file, folder, `.lnk` shortcut, or `.url` shortcut onto the quick-access bar.

## Support

If something does not work as expected, check the `Logs` folder first. When reporting an issue, include the relevant log entries, your Windows version, and the steps that caused it.

## Shortcuts

See [SHORTCUTS.txt](SHORTCUTS.txt) for the available keyboard shortcuts.

## License

Galore Launcher is released under the [MIT License](LICENSE).
