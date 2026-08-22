/* Application.vala
 *
 * Copyright 2022 Paulo Queiroz <pvaqueiroz@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

public class Terminal.Application : Adw.Application {
  private ActionEntry[] ACTIONS = {
    { "focus-next-tab", on_focus_next_tab },
    { "focus-previous-tab", on_focus_previous_tab },
    { "new-window", on_new_window },
    { "about", on_about },
    //  { "quit", on_app_quit },
  };

  public Application () {
    Object (
      application_id: "com.raggesilver.BlackBox",
      flags: ApplicationFlags.HANDLES_COMMAND_LINE
    );

    Intl.setlocale (LocaleCategory.ALL, "");
    Intl.textdomain (GETTEXT_PACKAGE);
    Intl.bindtextdomain (GETTEXT_PACKAGE, LOCALEDIR);
    Intl.bind_textdomain_codeset (GETTEXT_PACKAGE, "UTF-8");

    this.add_action_entries (ACTIONS, this);

    var border_action = new SimpleAction (
      "set-terminal-border",
      new VariantType ("(isbs)")
    );
    border_action.activate.connect (this.on_set_terminal_border);
    this.add_action (border_action);

    var focus_action = new SimpleAction (
      "focus-terminal",
      new VariantType ("i")
    );
    focus_action.activate.connect (this.on_focus_terminal);
    this.add_action (focus_action);

    var notify_action = new SimpleAction (
      "notify-turn-finished",
      new VariantType ("i")
    );
    notify_action.activate.connect (this.on_notify_turn_finished);
    this.add_action (notify_action);

    var attention_action = new SimpleAction (
      "notify-codex-attention",
      new VariantType ("(is)")
    );
    attention_action.activate.connect (this.on_notify_codex_attention);
    this.add_action (attention_action);

    ProfileManager.get_default ().initialize (this);
  }

  public override void activate () {
    new Window (this).show ();
  }

  public override int command_line (GLib.ApplicationCommandLine cmd) {
    CommandLineOptions options;

    this.hold ();

    if (!CommandLine.parse_command_line (cmd, out options)) {
      this.release ();
      return -1;
    }
    else if (options.help) {
      // For logistical reasons help is handled in `parse_command_line`.
    }
    else if (options.version) {
      cmd.print (
        "%s version %s%s\n",
        APP_NAME,
        VERSION,
        is_flatpak () ? " (flatpak)" : ""
      );
    }
    else {
      new Window (
        this,
        options.command,
        options.current_working_dir,
        false
      ).show ();
    }
    this.release ();
    return 0;
  }

  //  private void on_app_quit () {
  //    // This involves confirming before closing tabs/windows
  //    warning ("App quit is not implemented yet.");
  //  }

  private void on_about () {
    var win = create_about_dialog () as Gtk.Window;
    win.set_transient_for (this.get_active_window ());
    win.show ();
  }

  private void on_new_window () {
    string? target_cwd=null;
    if(this.get_active_window()!=null){
      var window=(this.get_active_window() as Window);
      var tab=window.active_terminal;
      var cwd=GLib.FileUtils.read_link("/proc/"+tab.pid.to_string()+"/cwd");
      message(cwd.to_string());
      target_cwd=cwd;
    }
    
    new Window (this, null, target_cwd, false).show ();
  }

  private void on_focus_next_tab () {
    (this.get_active_window () as Window)?.focus_next_tab ();
  }

  private void on_focus_previous_tab () {
    (this.get_active_window () as Window)?.focus_previous_tab ();
  }

  private Window? find_terminal_window (int terminal_pid) {
    if (terminal_pid == 0) {
      return this.get_active_window () as Window;
    }

    foreach (var gtk_window in this.get_windows ()) {
      var window = gtk_window as Window;
      if (window != null && window.owns_terminal_pid (terminal_pid)) {
        return window;
      }
    }
    return null;
  }

  private void on_set_terminal_border (Variant? parameter) {
    if (parameter == null) {
      return;
    }

    int terminal_pid;
    string color;
    bool animate;
    string border_type;
    parameter.get (
      "(isbs)",
      out terminal_pid,
      out color,
      out animate,
      out border_type
    );

    this.find_terminal_window (terminal_pid)?.set_external_border (
      color,
      animate,
      border_type
    );
  }

  private void on_focus_terminal (Variant? parameter) {
    if (parameter != null) {
      var terminal_pid = parameter.get_int32 ();
      this.find_terminal_window (terminal_pid)?.focus_terminal_pid (
        terminal_pid
      );
    }
  }

  private void on_notify_turn_finished (Variant? parameter) {
    if (parameter == null) {
      return;
    }

    this.send_codex_notification (
      parameter.get_int32 (),
      _("Codex turn finished."),
      _("Codex turn finished")
    );
  }

  private void on_notify_codex_attention (Variant? parameter) {
    if (parameter == null) {
      return;
    }

    int terminal_pid;
    string body;
    parameter.get ("(is)", out terminal_pid, out body);
    this.send_codex_notification (
      terminal_pid,
      body,
      _("Codex needs attention")
    );
  }

  private void send_codex_notification (
    int terminal_pid,
    string body,
    string fallback_title
  ) {
    var window = this.find_terminal_window (terminal_pid);
    if (window == null) {
      return;
    }

    var notification = new GLib.Notification (
      window.terminal_title_for_pid (terminal_pid)
        ?? fallback_title
    );
    notification.set_body (body);
    notification.set_priority (GLib.NotificationPriority.URGENT);
    notification.set_default_action_and_target_value (
      "app.focus-terminal",
      new Variant.int32 (terminal_pid)
    );
    this.send_notification (
      "codex-turn-%d".printf (terminal_pid),
      notification
    );
  }
}
