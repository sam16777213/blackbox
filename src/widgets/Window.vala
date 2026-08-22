/* Window.vala
 *
 * Copyright 2020-2022 Paulo Queiroz
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

public struct Terminal.Padding {
  uint top;
  uint right;
  uint bottom;
  uint left;

  public Variant to_variant () {
    return new Variant (
      "(uuuu)",
      this.top,
      this.right,
      this.bottom,
      this.left
    );
  }

  public static Padding zero () {
    return { 0 };
  }

  public static Padding from_variant (Variant vari) {
    if (!vari.check_format_string ("(uuuu)", false)) {
      return Padding.zero ();
    }

    uint top = 0;
    uint right = 0;
    uint bottom = 0;
    uint left = 0;

    vari.get ("(uuuu)", out top, out right, out bottom, out left);

    return Padding () {
      top = top,
      right = right,
      bottom = bottom,
      left = left,
    };
  }

  public string to_string () {
    return "Padding { %u, %u, %u, %u }".printf (
      this.top,
      this.right,
      this.bottom,
      this.left
    );
  }

  /**
   * Whether padding on all sides is the same.
   */
  public bool is_equilateral () {
    return (
      this.top == this.right &&
      this.right == this.bottom &&
      this.bottom == this.left
    );
  }
}

public class Terminal.Window : Adw.ApplicationWindow {

  public ThemeProvider  theme_provider        { get; private set; }
  public Adw.TabView    tab_view              { get; private set; }
  public Adw.TabBar     tab_bar               { get; private set; }
  public Terminal       active_terminal       { get; private set; }
  public string?        active_terminal_title { get; private set; }

  BaseHeaderBar   header_bar;
  Gtk.Revealer    header_bar_revealer;

  Gtk.HeaderBar   floating_bar;
  Gtk.Box         floating_btns;
  Gtk.MenuButton  floating_menu_btn;
  Gtk.Button      show_headerbar_button;
  Gtk.Button      fullscreen_button;
  Gtk.Revealer    floating_header_bar_revealer;

  Settings        settings = Settings.get_default ();

  const uint header_bar_revealer_duration_ms = 250;
  private uint waiting_for_floating_hb_animation = 0;

  private SimpleAction copy_action;
  private Array<ulong> active_terminal_signal_handlers = new Array<ulong> ();
  private Gtk.CssProvider? window_background_provider = null;
  private Gtk.CssProvider? external_border_provider = null;
  private bool external_border_reset_on_focus = false;
  private ulong profile_renamed_handler_id = 0;
  private ulong profile_deleted_handler_id = 0;

  static PreferencesWindow? preferences_window = null;

  construct {
    if (DEVEL) {
      this.add_css_class ("devel");
    }

    var layout_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
      hexpand = true,
      vexpand = true,
      halign = Gtk.Align.FILL,
      valign = Gtk.Align.FILL,
    };

    this.tab_view = new Adw.TabView () {
      hexpand = true,
      vexpand = true,
      halign = Gtk.Align.FILL,
      valign = Gtk.Align.FILL,
    };
    this.tab_view.add_css_class ("transparent-bg");

    this.tab_bar = new Adw.TabBar () {
      autohide = false,
      view = this.tab_view,

      hexpand = true,
      halign = Gtk.Align.FILL,

      css_classes = { "inline" },

      can_focus = false,
    };

    this.header_bar = new HeaderBar (this);

    this.header_bar_revealer = new Gtk.Revealer () {
      transition_duration = Window.header_bar_revealer_duration_ms,
      child = this.header_bar,
    };

    // Floating controls bar  ===============

    this.fullscreen_button = new Gtk.Button.from_icon_name (
      "com.raggesilver.BlackBox-fullscreen-symbolic"
    ) { tooltip_text = _("Fullscreen") };
    this.show_headerbar_button = new Gtk.Button.from_icon_name (
      "com.raggesilver.BlackBox-show-headerbar-symbolic"
    ) { tooltip_text = _("Show headerbar") };
    this.floating_btns = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
      css_classes = { "floating-btn-box" },
      overflow = Gtk.Overflow.HIDDEN,
      valign = Gtk.Align.CENTER,
    };
    this.floating_btns.append (this.fullscreen_button);
    this.floating_btns.append (new Gtk.Separator(Gtk.Orientation.VERTICAL));
    this.floating_btns.append (this.show_headerbar_button);

    this.floating_menu_btn = new Gtk.MenuButton () {
      menu_model = get_window_menu_model (),
      icon_name = "open-menu-symbolic",
      css_classes = { "circular" },
      valign = Gtk.Align.CENTER,
      can_focus = false,
      tooltip_text = _("Menu")
    };

    this.floating_bar = new Gtk.HeaderBar () {
      css_classes = {"flat" },
      title_widget = new Gtk.Label ("") { hexpand = true },
    };

    this.floating_header_bar_revealer = new Gtk.Revealer () {
      transition_duration = Window.header_bar_revealer_duration_ms,
      transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN,

      valign = Gtk.Align.START,
      vexpand = false,
      child = floating_bar,

      css_classes = { "floating-revealer" },
    };

    this.on_decoration_layout_changed ();

    layout_box.append (this.header_bar_revealer);
    layout_box.append (this.tab_view);

    var overlay = new Gtk.Overlay () {
      hexpand = true,
      vexpand = true,
      halign = Gtk.Align.FILL,
      valign = Gtk.Align.FILL,
      overflow = Gtk.Overflow.HIDDEN
    };
    overlay.add_css_class ("window-content-clip");
    overlay.child = layout_box;
    overlay.add_overlay (this.floating_header_bar_revealer);

    this.content = overlay;

    this.set_name ("blackbox-main-window");
  }

  public Window (
    Gtk.Application app,
    string? command = null,
    string? cwd = null,
    bool skip_initial_tab = false
  ) {
    var sett = Settings.get_default ();
    var wwidth = (int) (sett.remember_window_size ? sett.window_width : 700);
    var wheight = (int) (sett.remember_window_size ? sett.window_height : 450);

    Object (
      application: app,
      default_width: wwidth,
      default_height: wheight,
      fullscreened: sett.remember_window_size && sett.was_fullscreened,
      maximized: sett.remember_window_size && sett.was_maximized
    );

    Marble.add_css_provider_from_resource (
      "/com/raggesilver/BlackBox/resources/style.css"
    );

    this.theme_provider = ThemeProvider.get_default ();

    this.header_bar.new_tab_button.clicked.connect (() => {
      this.new_tab (null, null);
    });

    this.add_actions ();
    this.connect_signals ();

    if (!skip_initial_tab) {
      this.new_tab (command, cwd);
    }
    this.set_title(":) wow new blackbox");

}

	  private void connect_signals () {
    this.settings.schema.bind (
      "fill-tabs",
      this.tab_bar,
      "expand-tabs",
      SettingsBindFlags.GET
    );

    this.settings.schema.bind (
      "show-headerbar",
      this.header_bar_revealer,
      "reveal-child",
      SettingsBindFlags.GET
    );

    this.settings.notify["show-menu-button"].connect (
      this.on_decoration_layout_changed
    );

    settings.notify["floating-controls"].connect(() => {
      if (!settings.floating_controls) {
        this.floating_header_bar_revealer.reveal_child = false;
      }
    });

    settings.notify["show-headerbar"].connect(() => {
      if (settings.show_headerbar) {
        this.floating_header_bar_revealer.reveal_child = false;
      }
    });

    settings.notify ["window-show-borders"].connect (() => {
      set_css_class (this, "with-borders", settings.window_show_borders);
    });
    set_css_class (this, "with-borders", settings.window_show_borders);

    this.settings.notify ["opacity"].connect (this.on_window_background_changed);
    this.theme_provider.notify ["current-theme"].connect (
      this.on_window_background_changed
    );
    this.on_window_background_changed ();

    this.tab_view.create_window.connect (() => {
      var w = this.new_window (null, true);
      return w.tab_view;
    });

    this.tab_view.close_page.connect ((page) => {
      (page.child as TerminalTab)?.destroy ();
      return false;
    });

    // Close the window if all tabs were closed
    this.tab_view.notify["n-pages"].connect (() => {
      if (this.tab_view.n_pages < 1) {
        this.close ();
      }
    });

    this.tab_view.notify["selected-page"].connect (() => {
      this.on_tab_selected ();
    });

    this.notify["is-active"].connect (() => {
      if (this.is_active) {
        this.apply_selected_tab_profile ();
        if (this.external_border_reset_on_focus) {
          this.clear_external_border ();
        }
      }
    });

    var profile_manager = ProfileManager.get_default ();
    this.profile_renamed_handler_id = profile_manager.profile_renamed.connect ((
      old_name,
      new_name
    ) => {
      this.on_profile_renamed (old_name, new_name);
    });
    this.profile_deleted_handler_id = profile_manager.profile_deleted.connect ((
      deleted_name,
      fallback_name
    ) => {
      this.on_profile_deleted (deleted_name, fallback_name);
    });

    this.notify["default-width"].connect (() => {
      this.settings.window_width = this.default_width;
    });

    this.notify["default-height"].connect (() => {
      this.settings.window_height = this.default_height;
    });

    this.fullscreen_button.clicked.connect (this.toggle_fullscreen);

    this.show_headerbar_button.clicked.connect (() => {
      this.settings.show_headerbar = true;
      this.floating_header_bar_revealer.reveal_child = false;
    });

    var s = Gtk.Settings.get_default ();
    s.notify["gtk-decoration-layout"].connect(this.on_decoration_layout_changed);

    this.notify["active-terminal"].connect (this.on_active_terminal_changed);

    var c = new Gtk.EventControllerMotion ();
    c.motion.connect ((_, _mouseX, mouseY) => {
      // Ignore mouse motion if standard headerbars are shown or if floating
      // controls are disabled
      if (this.settings.show_headerbar || !this.settings.floating_controls) {
        return;
      }

      var h = this.floating_bar.get_height ();
      var is_shown = this.floating_header_bar_revealer.reveal_child;

      var trigger_area = settings.floating_controls_hover_area;

      bool is_hovering_trigger_area =
        mouseY >= 0 && mouseY <= (is_shown ? h : trigger_area);

      if (is_hovering_trigger_area && !is_shown) {
        // Only schedule animation if there aren't any scheduled
        if (this.waiting_for_floating_hb_animation == 0) {
          // Wait for delay to show floating controls
          this.waiting_for_floating_hb_animation = Timeout.add (
            settings.delay_before_showing_floating_controls,
            () => {
              this.floating_header_bar_revealer.reveal_child = true;
              this.waiting_for_floating_hb_animation = 0;
              return false;
            }
          );
        }
      }
      else if (
        !is_hovering_trigger_area &&
        (is_shown || this.waiting_for_floating_hb_animation != 0)
      ) {
        if (this.waiting_for_floating_hb_animation != 0) {
          Source.remove (this.waiting_for_floating_hb_animation);
          this.waiting_for_floating_hb_animation = 0;
        }
        this.floating_header_bar_revealer.reveal_child = false;
      }
    });

    (this as Gtk.Widget)?.add_controller (c);

    this.close_request.connect (() => {
      this.disconnect_profile_manager_handlers ();
      Settings.get_default ().was_fullscreened = this.fullscreened;
      Settings.get_default ().was_maximized = this.maximized;
      return false;
    });
  }

  private void disconnect_profile_manager_handlers () {
    var profile_manager = ProfileManager.get_default ();

    if (this.profile_renamed_handler_id != 0) {
      profile_manager.disconnect (this.profile_renamed_handler_id);
      this.profile_renamed_handler_id = 0;
    }

    if (this.profile_deleted_handler_id != 0) {
      profile_manager.disconnect (this.profile_deleted_handler_id);
      this.profile_deleted_handler_id = 0;
    }
  }

  private void on_window_background_changed () {
    if (this.window_background_provider != null) {
      this.get_style_context ().remove_provider (this.window_background_provider);
      this.window_background_provider = null;
    }

    var theme = this.theme_provider.themes.get (this.theme_provider.current_theme);
    if (theme == null || theme.background_color == null) {
      return;
    }

    var bg = theme.background_color.copy ();
    bg.alpha = this.settings.opacity * 0.01f;

    this.window_background_provider = Marble.get_css_provider_for_data (
      """
      #blackbox-main-window { background-color: %s; }
      """.printf (bg.to_string ())
    );

    this.get_style_context ().add_provider (
      this.window_background_provider,
      Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
    );
  }

  private Adw.TabPage? find_terminal_page (int terminal_pid) {
    for (int i = 0; i < this.tab_view.n_pages; i++) {
      var page = this.tab_view.get_nth_page (i);
      var tab = page.child as TerminalTab;
      if (tab != null && (int) tab.terminal.pid == terminal_pid) {
        return page;
      }
    }
    return null;
  }

  public bool owns_terminal_pid (int terminal_pid) {
    return this.find_terminal_page (terminal_pid) != null;
  }

  public string? terminal_title_for_pid (int terminal_pid) {
    var page = terminal_pid == 0
      ? this.tab_view.selected_page
      : this.find_terminal_page (terminal_pid);
    return page?.title;
  }

  public void focus_terminal_pid (int terminal_pid) {
    var page = terminal_pid == 0
      ? this.tab_view.selected_page
      : this.find_terminal_page (terminal_pid);
    if (page == null) {
      return;
    }

    this.tab_view.set_selected_page (page);
    var x11_surface = this.get_surface () as Gdk.X11.Surface;
    if (x11_surface != null) {
      this.present_with_time (x11_surface.get_server_time ());
    } else {
      this.present ();
    }
  }

  public void set_external_border (
    string color,
    bool animate,
    string border_type
  ) {
    var rgba = rgba_from_string (color);
    if (rgba == null) {
      warning ("Invalid external border color: %s", color);
      return;
    }

    if (
      border_type != "persistent" &&
      border_type != "resettable_on_focus"
    ) {
      warning ("Invalid external border type: %s", border_type);
      return;
    }

    var reset_on_focus = (
      border_type == "resettable_on_focus"
    );
    this.clear_external_border ();
    if (reset_on_focus && this.is_active) {
      return;
    }
    this.external_border_reset_on_focus = reset_on_focus;

    var css_color = rgba.to_string ();
    var css = animate
      ? """
        @keyframes blackbox-external-border-pulse {
          from { border-color: alpha(%1$s, 0.25); }
          to { border-color: %1$s; }
        }
        @keyframes blackbox-external-border-pulse-backdrop {
          from { border-color: alpha(shade(%1$s, 0.95), 0.25); }
          to { border-color: shade(%1$s, 0.95); }
        }
        #blackbox-main-window:not(.fullscreen) {
          border: 1px solid %1$s;
          animation: blackbox-external-border-pulse 900ms ease-in-out infinite alternate;
        }
        #blackbox-main-window:not(.fullscreen):backdrop {
          animation-name: blackbox-external-border-pulse-backdrop;
        }
        """.printf (css_color)
      : """
        #blackbox-main-window:not(.fullscreen) {
          border: 1px solid %1$s;
          animation: none;
        }
        #blackbox-main-window:not(.fullscreen):backdrop {
          border-color: shade(%1$s, 0.95);
        }
        """.printf (css_color);

    this.external_border_provider = Marble.get_css_provider_for_data (css);
    this.get_style_context ().add_provider (
      this.external_border_provider,
      Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1
    );
  }

  private void clear_external_border () {
    if (this.external_border_provider != null) {
      this.get_style_context ().remove_provider (
        this.external_border_provider
      );
      this.external_border_provider = null;
    }
    this.external_border_reset_on_focus = false;
  }

  private void add_actions () {
    var sa = new SimpleAction ("new_tab", null);
    sa.activate.connect (() => {
      this.new_tab (null, null);
    });
    this.add_action (sa);

    sa = new SimpleAction ("edit_preferences", null);
    sa.activate.connect (() => {
      if (preferences_window == null) {
        preferences_window = new PreferencesWindow (this);
        preferences_window.close_request.connect (() => {
          preferences_window = null;
          return false;
        });
      }

      preferences_window.present ();
    });
    this.add_action (sa);

    sa = new SimpleAction ("paste", null);
    sa.activate.connect (() => {
      this.on_paste_activated ();
    });
    this.add_action (sa);

    this.copy_action = new SimpleAction ("copy", null);
    copy_action.activate.connect (() => {
      this.on_copy_activated ();
    });
    this.copy_action.set_enabled (false);
    this.add_action (this.copy_action);

    sa = new SimpleAction ("switch-headerbar-mode", null);
    sa.activate.connect (() => {
      this.settings.show_headerbar = !this.settings.show_headerbar;
    });
    this.add_action (sa);

    sa = new SimpleAction ("fullscreen", null);
    sa.activate.connect (this.toggle_fullscreen);
    this.add_action (sa);

    sa = new SimpleAction ("search", null);
    sa.activate.connect (this.search);
    this.add_action (sa);

    sa = new SimpleAction ("zoom-in", null);
    sa.activate.connect (this.zoom_in);
    this.add_action (sa);

    sa = new SimpleAction ("zoom-out", null);
    sa.activate.connect (this.zoom_out);
    this.add_action (sa);

    sa = new SimpleAction ("zoom-default", null);
    sa.activate.connect (this.zoom_default);
    this.add_action (sa);

    sa = new SimpleAction ("close-tab", null);
    sa.activate.connect (this.close_active_tab);
    this.add_action (sa);

    sa = new SimpleAction ("set-profile", VariantType.STRING);
    sa.activate.connect ((parameter) => {
      if (parameter == null) {
        return;
      }

      this.set_active_tab_profile (parameter.get_string ());
    });
    this.add_action (sa);

    for (uint i = 1; i < 10; i++) {
      sa = new SimpleAction ("switch-tab-%u".printf (i), null);
      sa.activate.connect (() => {
        this.focus_nth_tab ((int) i);
      });
      this.add_action (sa);
    }

    sa = new SimpleAction ("switch-tab-last", null);
    sa.activate.connect (() => {
      this.focus_nth_tab (-1);
    });
    this.add_action (sa);
  }

  public void search () {
    (this.tab_view.selected_page?.child as TerminalTab)?.search ();
  }

  public void zoom_in () {
    (this.tab_view.selected_page?.child as TerminalTab)?.terminal
      .zoom_in ();
  }

  public void zoom_out () {
    (this.tab_view.selected_page?.child as TerminalTab)?.terminal
      .zoom_out ();
  }

  public void zoom_default () {
    (this.tab_view.selected_page?.child as TerminalTab)?.terminal
      .zoom_default ();
  }

  public void close_active_tab () {
    (this.tab_view.selected_page?.child as TerminalTab)?.close_request ();
  }

  public string? get_active_tab_profile_name () {
    return (this.tab_view.selected_page?.child as TerminalTab)?.profile_name;
  }

  public bool set_active_tab_profile (string profile_name) {
    var tab = this.tab_view.selected_page?.child as TerminalTab;
    if (tab == null || !tab.assign_profile_name (profile_name)) {
      return false;
    }

    return ProfileManager.get_default ().set_session_profile (tab.profile_name);
  }

  public void new_tab (string? command, string? cwd) {
    var profile_manager = ProfileManager.get_default ();
    var profile_name = this.get_active_tab_profile_name ()
      ?? profile_manager.session_profile_name;

    var tab = new TerminalTab (
      this,
      command,
      cwd,
      profile_name
    );
    var page = this.tab_view.add_page (tab, null);

    page.title = command ?? @"tab $(this.tab_view.n_pages)";
    tab.notify["title"].connect (() => {
      page.title = tab.title;
    });
    tab.close_request.connect (() => {
      this.tab_view.close_page (page);
    });
    this.tab_view.set_selected_page (page);
  }

  private void on_paste_activated () {
    (this.tab_view.selected_page?.child as TerminalTab)?.terminal
      .do_paste_clipboard ();
  }

  private void on_copy_activated () {
    (this.tab_view.selected_page?.child as TerminalTab)?.terminal
      .do_copy_clipboard ();
  }

  private void on_tab_selected () {
    this.apply_selected_tab_profile ();

    if (this.active_terminal != null) {
      foreach (unowned ulong id in this.active_terminal_signal_handlers) {
        this.active_terminal.disconnect (id);
      }
      this.active_terminal_signal_handlers.remove_range (
        0,
        this.active_terminal_signal_handlers.length
      );
    }
    var terminal = (this.tab_view.selected_page?.child as TerminalTab)?.terminal;
    this.active_terminal = terminal;
    terminal?.grab_focus ();
  }

  private void apply_selected_tab_profile () {
    var profile_manager = ProfileManager.get_default ();
    var tab = this.tab_view.selected_page?.child as TerminalTab;

    if (tab == null) {
      return;
    }

    if (!profile_manager.has_profile (tab.profile_name)) {
      tab.assign_profile_name (profile_manager.session_profile_name);
    }

    profile_manager.set_session_profile (tab.profile_name);
  }

  private void on_profile_renamed (string old_name, string new_name) {
    for (int i = 0; i < this.tab_view.n_pages; i++) {
      var page = this.tab_view.get_nth_page (i);
      var tab = page?.child as TerminalTab;

      if (tab != null && tab.profile_name == old_name) {
        tab.assign_profile_name (new_name);
      }
    }
  }

  private void on_profile_deleted (string deleted_name, string fallback_name) {
    for (int i = 0; i < this.tab_view.n_pages; i++) {
      var page = this.tab_view.get_nth_page (i);
      var tab = page?.child as TerminalTab;

      if (tab != null && tab.profile_name == deleted_name) {
        tab.assign_profile_name (fallback_name);
      }
    }

    this.apply_selected_tab_profile ();
  }

  private void on_active_terminal_changed () {
    if (this.active_terminal == null) {
      return;
    }

    ulong handler;

    this.on_active_terminal_selection_changed ();
    handler = this.active_terminal
      .selection_changed
      .connect (this.on_active_terminal_selection_changed);

    this.active_terminal_signal_handlers.append_val (handler);

    this.on_active_terminal_title_changed ();
    handler = this.active_terminal
      .window_title_changed
      .connect (this.on_active_terminal_title_changed);

    this.active_terminal_signal_handlers.append_val (handler);
  }

  private void on_active_terminal_title_changed () {
    this.active_terminal_title = this.active_terminal.window_title;
    this.title=this.active_terminal_title;
    message(this.active_terminal.window_title);
  }

  private void on_active_terminal_selection_changed () {
    bool enabled = false;
    if (this.active_terminal?.get_has_selection ()) {
      enabled = true;
    }
    this.copy_action.set_enabled (enabled);
  }

  private void on_decoration_layout_changed () {
    var layout = Gtk.Settings.get_default ().gtk_decoration_layout;

    debug ("Decoration layout: %s", layout);

    var window_controls_in_end = layout.split (":", 2)[0].contains ("menu");

    this.floating_bar.remove (this.floating_btns);
    this.floating_bar.remove (this.floating_menu_btn);
    if (this.settings.show_menu_button) {
      this.floating_bar.pack_end (this.floating_menu_btn);
    }

    if (window_controls_in_end) {
      this.floating_bar.pack_start (this.floating_btns);
    } else {
      this.floating_bar.pack_end (this.floating_btns);
    }
  }

  private void toggle_fullscreen () {
    if (this.fullscreened) {
      this.unfullscreen ();
    } else {
      this.fullscreen ();
    }
  }

  public Window new_window (
    string? cwd = null,
    bool skip_initial_tab = false
  ) {

    var w = new Window (this.application, null, cwd, skip_initial_tab);
    w.show ();
    w.close_request.connect (() => {
      return false;
    });
    return w;
  }

  public void focus_next_tab () {
    if (!this.tab_view.select_next_page ()) {
      this.tab_view.set_selected_page (this.tab_view.get_nth_page (0));
    }
  }

  public void focus_previous_tab () {
    if (!this.tab_view.select_previous_page ()) {
      this.tab_view.set_selected_page (this.tab_view.get_nth_page (this.tab_view.n_pages - 1));
    }
  }

  public void focus_nth_tab (int index) {
    if (this.tab_view.n_pages <= 1) {
      return;
    }
    if (index < 0) {
      // Go to last tab
      this.tab_view.set_selected_page (
        this.tab_view.get_nth_page (this.tab_view.n_pages - 1)
      );
      return;
    }
    if (index > this.tab_view.n_pages) {
      return;
    }
    else {
      this.tab_view.set_selected_page (this.tab_view.get_nth_page (index - 1));
      return;
    }
  }
}
