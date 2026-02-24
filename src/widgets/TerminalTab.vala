/* TerminalTab.vala
 *
 * Copyright 2021-2022 Paulo Queiroz
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
 */

public class Terminal.TerminalTab : Gtk.Box {

  public signal void close_request ();

  public string             title     { get; protected set; }
  public Terminal           terminal  { get; protected set; }
  public Gtk.ScrolledWindow scrolled  { get; protected set; }
  public string             profile_name { get; private set; }

  private SearchToolbar     search_toolbar;
  private bool              profile_overrides_enabled = false;
  private bool              profile_show_scrollbars = true;
  private bool              profile_use_overlay_scrolling = true;
  public  Window            window;

  public TerminalTab (
    Window window,
    string? command,
    string? cwd,
    string? profile_name = null
  ) {
    Object (
      orientation: Gtk.Orientation.VERTICAL,
      spacing: 0,
      hexpand: true,
      vexpand: true,
      halign: Gtk.Align.FILL,
      valign: Gtk.Align.FILL
    );

    this.window = window;
    var profile_manager = ProfileManager.get_default ();
    if (
      profile_name != null &&
      profile_manager.has_profile (profile_name)
    ) {
      this.profile_name = profile_name;
    }
    else {
      this.profile_name = profile_manager.session_profile_name;
    }

    var startup_profile = profile_manager.get_profile_snapshot (this.profile_name);

    this.terminal = new Terminal (
      this.window,
      command,
      cwd,
      startup_profile
    );
    this.add_css_class ("transparent-bg");

    // Hack to stop vala-language-server from complaining
    var twig = this.terminal as Gtk.Widget;
    //  this.set_child(twig);
    this.scrolled = new Gtk.ScrolledWindow () {
      hexpand = true,
      vexpand = true,
      halign = Gtk.Align.FILL,
      valign = Gtk.Align.FILL,
      hscrollbar_policy = Gtk.PolicyType.NEVER,
      vscrollbar_policy = Gtk.PolicyType.AUTOMATIC
    };
    this.scrolled.child = twig;

    this.append (this.scrolled);
    twig.grab_focus ();

    this.search_toolbar = new SearchToolbar (this.terminal) {
      hexpand = true,
      halign = Gtk.Align.FILL,
      valign = Gtk.Align.END
    };
    this.append (this.search_toolbar);

    var click = new Gtk.GestureClick () {
      button = Gdk.BUTTON_SECONDARY,
    };

    click.pressed.connect (this.show_menu);

    this.terminal.add_controller (click);

    this.connect_signals ();
    if (startup_profile != null) {
      this.apply_profile_overrides (startup_profile);
    }
    else {
      this.assign_profile_name (this.profile_name);
    }
    this.scrolled.add_css_class ("transparent-bg");
    this.terminal.add_css_class ("transparent-bg");
  }

  public bool assign_profile_name (string profile_name) {
    var profile_manager = ProfileManager.get_default ();
    var profile = profile_manager.get_profile_snapshot (profile_name);
    if (profile == null) {
      return false;
    }

    this.apply_profile_overrides (profile);
    this.profile_name = profile_name;
    return true;
  }

  private void apply_profile_overrides (Profile profile) {
    this.profile_overrides_enabled = true;
    this.profile_show_scrollbars = profile.show_scrollbars;
    this.profile_use_overlay_scrolling = profile.use_overlay_scrolling;

    this.terminal.apply_profile_overrides (profile);
    this.update_scrollbar_visibility (this.profile_show_scrollbars);
    this.scrolled.overlay_scrolling = this.profile_use_overlay_scrolling;
  }

  private void update_scrollbar_visibility (bool show_scrollbars) {
    var is_scrollbar_being_used = this.scrolled.child == this.terminal;

    if (show_scrollbars && !is_scrollbar_being_used) {
      this.remove (this.terminal);
      this.scrolled.child = this.terminal;
      this.prepend (this.scrolled);
    }
    else if (!show_scrollbars && is_scrollbar_being_used) {
      this.remove (this.scrolled);
      this.scrolled.child = null;
      this.prepend (this.terminal);
    }
  }

  private void connect_signals () {
    var settings = Settings.get_default ();

    this.terminal.notify["window-title"].connect (() => {
      this.title = this.terminal.window_title;
    });

    this.terminal.exit.connect (() => {
      this.close_request ();
    });

    settings.notify["show-scrollbars"].connect (() => {
      if (this.profile_overrides_enabled) {
        return;
      }

      this.update_scrollbar_visibility (settings.show_scrollbars);
    });
    settings.notify_property ("show-scrollbars");

    settings.notify["use-overlay-scrolling"].connect (() => {
      if (this.profile_overrides_enabled) {
        return;
      }
      this.scrolled.overlay_scrolling = settings.use_overlay_scrolling;
    });
    settings.notify_property ("use-overlay-scrolling");

    settings.bind_property (
      "use-sixel",
      this.terminal as Object,
      "enable-sixel",
      BindingFlags.SYNC_CREATE
    );
  }

  public void show_menu (int n_pressed, double x, double y) {
    var menu = new Menu ();
    var edit_section = new Menu ();
    var preferences_section = new Menu ();
    var profile_submenu = new Menu ();
    var bottom_section = new Menu ();
    var profile_manager = ProfileManager.get_default ();
    if (!profile_manager.has_profile (this.profile_name)) {
      this.assign_profile_name (profile_manager.session_profile_name);
    }

    menu.append (_("New Tab"), "win.new_tab");
    menu.append (_("New Window"), "app.new-window");

    edit_section.append (_("Copy"), "win.copy");
    edit_section.append (_("Paste"), "win.paste");

    menu.append_section (null, edit_section);

    foreach (unowned string profile_name in profile_manager.get_profile_names ()) {
      var label = profile_name == this.profile_name
        ? "[x] " + profile_name
        : profile_name;

      var item = new MenuItem (label, null);
      item.set_action_and_target_value (
        "win.set-profile",
        new Variant.string (profile_name)
      );
      profile_submenu.append_item (item);
    }

    preferences_section.append_submenu (_("Profiles"), profile_submenu);
    preferences_section.append (_("Preferences"), "win.edit_preferences");
    menu.append_section (null, preferences_section);

    bottom_section.append (_("Keyboard Shortcuts"), "win.show-help-overlay");
    bottom_section.append (_("About"), "app.about");
    menu.append_section (null, bottom_section);

    var pop = new Gtk.PopoverMenu.from_model (menu);

    Gdk.Rectangle r = {0};
    r.x = (int) (x + Settings.get_default ().get_padding ().left);
    r.y = (int) (y + Settings.get_default ().get_padding ().top);

    pop.closed.connect_after (() => {
      pop.destroy ();
    });

    pop.set_parent (this);
    pop.set_pointing_to (r);
    pop.popup ();
  }

  public void search () {
    this.search_toolbar.open ();
  }
}
