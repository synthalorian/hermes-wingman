import 'dart:io';

/// Terminal detection for cross-platform terminal launching.
///
/// Detects the user's primary terminal emulator on Linux, macOS, and Windows.
/// Used by "New Chat" and other terminal-launching features.

class TerminalDetector {
  /// Detect the best available terminal command for this system.
  /// Returns a list of [command, ...args] to run a program, or null if none found.
  static Future<List<String>?> detect() async {
    if (Platform.isLinux) return _detectLinux();
    if (Platform.isMacOS) return _detectMacOS();
    if (Platform.isWindows) return _detectWindows();
    return null;
  }

  /// Detect terminal on Linux. Checks common terminals in order of preference.
  static Future<List<String>?> _detectLinux() async {
    // First check TERMINAL env var (user preference)
    final termEnv = Platform.environment['TERMINAL'];
    if (termEnv != null && termEnv.isNotEmpty) {
      final which = await _which(termEnv);
      if (which != null) return [which, '-e'];
    }

    // Ordered by popularity/preference
    final terminals = ['alacritty', 'kitty', 'foot', 'gnome-terminal', 'konsole',
                        'xfce4-terminal', 'lxterminal', 'xterm'];

    for (final term in terminals) {
      final path = await _which(term);
      if (path != null) {
        switch (term) {
          case 'kitty':
            return [path];
          case 'foot':
            return [path];
          case 'gnome-terminal':
            return [path, '--'];
          case 'konsole':
            return [path, '-e'];
          case 'xfce4-terminal':
            return [path, '-e'];
          case 'lxterminal':
            return [path, '-e'];
          case 'alacritty':
            return [path, '-e'];
          case 'xterm':
            return [path, '-e'];
          default:
            return [path, '-e'];
        }
      }
    }

    // Last resort: x-terminal-emulator (Debian/Ubuntu symlink)
    final xterm = await _which('x-terminal-emulator');
    if (xterm != null) return [xterm, '-e'];

    return null;
  }

  /// Detect terminal on macOS.
  static Future<List<String>?> _detectMacOS() async {
    // Check iTerm2 first (user preference usually)
    final iTerm = await _which('iterm2');
    if (iTerm != null) return [iTerm, 'open', '-a', 'iTerm'];

    // Check Warp
    final warp = await _which('warp');
    if (warp != null) return [warp];

    // Fallback: Terminal.app via open command
    return ['open', '-a', 'Terminal'];
  }

  /// Detect terminal on Windows.
  static Future<List<String>?> _detectWindows() async {
    // Windows Terminal (modern)
    final wt = await _which('wt');
    if (wt != null) return [wt];

    // PowerShell
    final pwsh = await _which('pwsh');
    if (pwsh != null) return [pwsh, '-NoExit', '-Command'];

    // Fallback: cmd.exe
    final cmd = await _which('cmd');
    if (cmd != null) return [cmd, '/K'];

    return null;
  }

  /// Launch a command in the detected terminal.
  /// Returns true if launch succeeded.
  static Future<bool> launchInTerminal(List<String> command) async {
    final terminal = await detect();
    if (terminal == null) return false;

    try {
      await Process.run(
        terminal[0],
        [...terminal.sublist(1), ...command],
        runInShell: true,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Run `which` to find an executable in PATH.
  static Future<String?> _which(String name) async {
    try {
      final result = await Process.run(
        Platform.isWindows ? 'where' : 'which',
        [name],
        runInShell: true,
      );
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim().split('\n').first.trim();
        if (path.isNotEmpty) return path;
      }
    } catch (_) {}
    return null;
  }

  /// Get a human-readable name for the current terminal.
  static Future<String> getTerminalName() async {
    final term = await detect();
    if (term == null) return 'System Default';
    
    final name = term[0].split('/').last;
    switch (name) {
      case 'alacritty': return 'Alacritty';
      case 'kitty': return 'Kitty';
      case 'foot': return 'Foot';
      case 'gnome-terminal': return 'GNOME Terminal';
      case 'konsole': return 'Konsole';
      case 'xterm': return 'XTerm';
      case 'x-terminal-emulator': return 'X Terminal Emulator';
      case 'wt': return 'Windows Terminal';
      case 'pwsh': return 'PowerShell';
      case 'cmd': return 'Command Prompt';
      case 'open': return 'Terminal.app';
      default: return name;
    }
  }
}
