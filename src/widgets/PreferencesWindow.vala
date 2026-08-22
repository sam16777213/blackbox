/* PreferencesWindow2.vala
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

bool dark_themes_filter_func (Gtk.FlowBoxChild child) {
  var thumbnail = child as Terminal.ColorSchemeThumbnail;
  return thumbnail.scheme.is_dark;
}

bool light_themes_filter_func (Gtk.FlowBoxChild child) {
  var thumbnail = child as Terminal.ColorSchemeThumbnail;
  return !thumbnail.scheme.is_dark;
}

[GtkTemplate (ui = "/com/raggesilver/BlackBox/gtk/preferences-window.ui")]
public class Terminal.PreferencesWindow : Adw.PreferencesWindow {
  [GtkChild] unowned Adw.PreferencesPage  general_page;
  [GtkChild] unowned Adw.PreferencesPage  terminal_page;
  [GtkChild] unowned Adw.PreferencesPage  profiles_page;
  [GtkChild] unowned ShortcutEditor       shortcut_editor;
  [GtkChild] unowned Adw.PreferencesPage  advanced_page;
  [GtkChild] unowned Adw.ComboRow         cursor_shape_combo_row;
  [GtkChild] unowned Adw.ComboRow         cursor_blink_mode_combo_row;
  [GtkChild] unowned Adw.ComboRow         terminal_editing_profile_combo_row;
  [GtkChild] unowned Adw.ComboRow         profiles_startup_profile_combo_row;
  [GtkChild] unowned Adw.ComboRow         profiles_selected_profile_combo_row;
  [GtkChild] unowned Adw.ComboRow         style_preference_combo_row;
  [GtkChild] unowned Adw.EntryRow         custom_command_entry_row;
  [GtkChild] unowned Adw.EntryRow         profile_name_entry_row;
  [GtkChild] unowned Gtk.Adjustment       cell_height_spacing_adjustment;
  [GtkChild] unowned Gtk.Adjustment       cell_width_spacing_adjustment;
  [GtkChild] unowned Gtk.Adjustment       custom_scrollback_adjustment;
  [GtkChild] unowned Gtk.Adjustment       floating_controls_delay_adjustment;
  [GtkChild] unowned Gtk.Adjustment       floating_controls_hover_area_adjustment;
  [GtkChild] unowned Gtk.CheckButton      filter_themes_check_button;
  [GtkChild] unowned Gtk.FlowBox          preview_flow_box;
  [GtkChild] unowned Gtk.Label            font_label;
  [GtkChild] unowned Gtk.SpinButton       custom_scrollback_spin_button;
  [GtkChild] unowned Gtk.SpinButton       padding_spin_button;
  [GtkChild] unowned Gtk.Switch           easy_copy_paste_switch;
  [GtkChild] unowned Gtk.Switch           fill_tabs_switch;
  [GtkChild] unowned Gtk.Switch           floating_controls_switch;
  [GtkChild] unowned Gtk.Switch           hide_single_tab_switch;
  [GtkChild] unowned Gtk.Switch           use_sixel_switch;
  [GtkChild] unowned Gtk.Switch           pretty_switch;
  [GtkChild] unowned Gtk.SpinButton       opacity_spin_button;
  [GtkChild] unowned Gtk.Switch           remember_window_size_switch;
  [GtkChild] unowned Gtk.Switch           run_command_as_login_switch;
  [GtkChild] unowned Gtk.Switch           show_headerbar_switch;
  [GtkChild] unowned Gtk.Switch           show_menu_button_switch;
  [GtkChild] unowned Gtk.Switch           show_scrollbars_switch;
  [GtkChild] unowned Gtk.Switch           show_window_borders_switch;
  [GtkChild] unowned Gtk.Switch           stealth_single_tab_switch;
  [GtkChild] unowned Gtk.Switch           use_custom_scrollback_switch;
  [GtkChild] unowned Gtk.Switch           use_custom_shell_command_switch;
  [GtkChild] unowned Gtk.Switch           use_overlay_scrolling_switch;
  [GtkChild] unowned Gtk.Switch           draw_line_single_tab_switch;
  [GtkChild] unowned Gtk.Switch           drag_area_switch;
  [GtkChild] unowned Gtk.ToggleButton     dark_theme_toggle;
  [GtkChild] unowned Gtk.ToggleButton     light_theme_toggle;

  private Window window;
  private ProfileManager profile_manager;
  private Gtk.StringList profile_names_model;
  private bool is_updating_profile_ui = false;

  public string selected_theme {
    get {
      return this.light_theme_toggle.active
        ? Settings.get_default ().theme_light
        : Settings.get_default ().theme_dark;
    }
    set {
      if (this.light_theme_toggle.active) {
        Settings.get_default ().theme_light = value;
      }
      else {
        Settings.get_default ().theme_dark = value;
      }
    }
  }

  static construct {
    typeof (ShortcutEditor).class_ref ();
  }

  construct {
    if (DEVEL) {
      this.add_css_class ("devel");
    }
  }

  public PreferencesWindow (Window window) {
    Object (
      application: window.application,
      transient_for: window,
      destroy_with_parent: true
    );

    this.window = window;
    this.profile_manager = ProfileManager.get_default ();
    this.profile_names_model = new Gtk.StringList ({});

    this.custom_scrollback_adjustment.upper = uint.MAX;

    this.build_ui ();
    this.bind_data ();
    this.expand_page_contents (this.general_page);
    this.expand_page_contents (this.terminal_page);
    this.expand_page_contents (this.profiles_page);
    this.expand_page_contents (this.shortcut_editor);
    this.expand_page_contents (this.advanced_page);
  }

  // Build UI

  private void build_ui () {
    ColorSchemeThumbnailProvider.init_resource ();

    //  var model = new GLib.ListStore (typeof (ColorSchemeThumbnail));

    this.window.theme_provider.themes.for_each ((name, scheme) => {
      if (scheme != null) {
        var t = new ColorSchemeThumbnail (scheme);

        this.bind_property (
          "selected-theme",
          t,
          "selected",
          BindingFlags.SYNC_CREATE,
          (_, from, ref to) => {
            to = from.get_string () == t.scheme.name;
            return true;
          },
          null
        );

        //  model.append (t);
        this.preview_flow_box.append (t);
      }
    });

    this.preview_flow_box.set_sort_func ((child1, child2) => {
      var a = child1 as ColorSchemeThumbnail;
      var b = child2 as ColorSchemeThumbnail;

      return strcmp (a.scheme.name.down (), b.scheme.name.down ());
    });
  }

  // Connections

  private void bind_data () {
    var settings = Settings.get_default ();

    settings.schema.bind (
      "font",
      this.font_label,
      "label",
      SettingsBindFlags.DEFAULT
    );

    settings.schema.bind (
      "command-as-login-shell",
      this.run_command_as_login_switch,
      "active",
      SettingsBindFlags.DEFAULT
    );

    settings.schema.bind (
      "custom-shell-command",
      this.custom_command_entry_row,
      "text",
      SettingsBindFlags.DEFAULT
    );

    settings.schema.bind (
      "use-custom-command",
      this.custom_command_entry_row,
      "sensitive",
      SettingsBindFlags.DEFAULT
    );

    settings.schema.bind (
      "use-custom-command",
      this.use_custom_shell_command_switch,
      "active",
      SettingsBindFlags.DEFAULT
    );

    settings.schema.bind(
      "pretty",
      this.pretty_switch,
      "active",
      SettingsBindFlags.DEFAULT
    );

    settings.schema.bind_with_mapping(
      "opacity",
      this.opacity_spin_button,
      "value",
      SettingsBindFlags.DEFAULT,
      // From settings to spin button
      (to_val, settings_variant) => {
        to_val = settings_variant.get_uint32();
        return true;
      },
      // From spin button to settings
      (value) => {
        return new GLib.Variant.uint32((uint)value.get_double());
      },
      null,
      null
    );

    settings.schema.bind(
      "window-show-borders",
      this.show_window_borders_switch,
      "active",
      SettingsBindFlags.DEFAULT
    );

    settings.schema.bind(
      "fill-tabs",
      this.fill_tabs_switch,
      "active",
      SettingsBindFlags.DEFAULT
    );

    settings.schema.bind(
      "show-menu-button",
      this.show_menu_button_switch,
      "active",
      SettingsBindFlags.DEFAULT
    );

    settings.schema.bind(
      "show-headerbar",
      this.show_headerbar_switch,
      "active",
      SettingsBindFlags.DEFAULT
    );

    settings.schema.bind(
      "headerbar-draw-line-single-tab",
      this.draw_line_single_tab_switch,
      "active",
      SettingsBindFlags.DEFAULT
    );

    settings.schema.bind(
      "headerbar-drag-area",
      this.drag_area_switch,
      "active",
      SettingsBindFlags.DEFAULT
    );

    settings.schema.bind(
      "easy-copy-paste",
      this.easy_copy_paste_switch,
      "active",
      SettingsBindFlags.DEFAULT
    );

    settings.schema.bind(
      "hide-single-tab",
      this.hide_single_tab_switch,
      "active",
      SettingsBindFlags.DEFAULT
    );

    settings.schema.bind(
      "stealth-single-tab",
      this.stealth_single_tab_switch,
      "active",
      SettingsBindFlags.DEFAULT
    );

    settings.schema.bind (
      "show-scrollbars",
      this.show_scrollbars_switch,
      "active",
      SettingsBindFlags.DEFAULT
    );

    settings.schema.bind (
      "use-overlay-scrolling",
      this.use_overlay_scrolling_switch,
      "active",
      SettingsBindFlags.DEFAULT
    );

    settings.schema.bind (
      "use-custom-scrollback",
      this.use_custom_scrollback_switch,
      "active",
      SettingsBindFlags.DEFAULT
    );

    settings.schema.bind (
      "scrollback-lines",
      this.custom_scrollback_spin_button,
      "value",
      SettingsBindFlags.DEFAULT
    );

    settings.schema.bind_with_mapping (
      "scrollback-lines",
      this.custom_scrollback_spin_button,
      "value",
      GLib.SettingsBindFlags.DEFAULT,
      (to_value, settings_vari) => {
        to_value = (double) settings_vari.get_uint32 ();
        return true;
      },
      (value) => {;
        return new Variant.uint32 ((uint32) value.get_double ());
      },
      null,
      null
    );

    settings.schema.bind (
      "use-sixel",
      this.use_sixel_switch,
      "active",
      SettingsBindFlags.DEFAULT
    );

    settings.schema.bind (
      "remember-window-size",
      this.remember_window_size_switch,
      "active",
      SettingsBindFlags.DEFAULT
    );

    settings.schema.bind_with_mapping (
      "terminal-padding",
      this.padding_spin_button,
      "value",
      SettingsBindFlags.DEFAULT,
      // From settings to spin button
      (to_val, settings_vari) => {
        var pad = Padding.from_variant (settings_vari);

        to_val = pad.top;
        return true;
      },
      // From spin button to settings
      (spin_val, _) => {
        var pad = (uint) spin_val.get_double ();
        var _pad = Padding () {
          top = pad,
          right = pad,
          bottom = pad,
          left = pad
        };

        return _pad.to_variant ();
      },
      null,
      null
    );

    // 0 = Block, 1 = IBeam, 2 = Underline
    settings.schema.bind(
      "cursor-shape",
      this.cursor_shape_combo_row,
      "selected",
      SettingsBindFlags.DEFAULT
    );

    // 0 = Follow System, 1 = On, 2 = Off
    settings.schema.bind(
      "cursor-blink-mode",
      this.cursor_blink_mode_combo_row,
      "selected",
      SettingsBindFlags.DEFAULT
    );

    //  0 = Follow System, 1 = Light Style, 2 = Dark Style
    settings.schema.bind(
      "style-preference",
      this.style_preference_combo_row,
      "selected",
      SettingsBindFlags.DEFAULT
    );

    settings.schema.bind (
      "floating-controls",
      this.floating_controls_switch,
      "active",
      SettingsBindFlags.DEFAULT
    );

    settings.schema.bind (
      "floating-controls-hover-area",
      this.floating_controls_hover_area_adjustment,
      "value",
      SettingsBindFlags.DEFAULT
    );

    settings.schema.bind (
      "delay-before-showing-floating-controls",
      this.floating_controls_delay_adjustment,
      "value",
      SettingsBindFlags.DEFAULT
    );

    settings.schema.bind (
      "terminal-cell-width",
      this.cell_width_spacing_adjustment,
      "value",
      SettingsBindFlags.DEFAULT
    );

    settings.schema.bind (
      "terminal-cell-height",
      this.cell_height_spacing_adjustment,
      "value",
      SettingsBindFlags.DEFAULT
    );

    this.preview_flow_box.child_activated.connect ((child) => {
      var name = (child as ColorSchemeThumbnail)?.scheme.name;
      this.selected_theme = name;
    });

    this.light_theme_toggle.notify["active"].connect (() => {
      this.notify_property ("selected-theme");
      this.set_themes_filter_func ();
    });

    settings.notify["theme-light"].connect (() => {
      if (this.light_theme_toggle.active) {
        this.notify_property ("selected-theme");
      }
    });

    settings.notify["theme-dark"].connect (() => {
      if (this.dark_theme_toggle.active) {
        this.notify_property ("selected-theme");
      }
    });

    if (ThemeProvider.get_default ().is_dark_style_active) {
      this.dark_theme_toggle.active = true;
    }
    else {
      this.light_theme_toggle.active = true;
    }

    ThemeProvider.get_default ().notify ["is-dark-style-active"].connect (() => {
      if (ThemeProvider.get_default ().is_dark_style_active) {
        this.dark_theme_toggle.active = true;
      }
      else {
        this.light_theme_toggle.active = true;
      }
    });

    // themes-filter-func

    this.filter_themes_check_button.notify ["active"].connect (() => {
      this.set_themes_filter_func ();
    });

    this.set_themes_filter_func ();
    this.bind_profiles ();
  }

  // Methods

  private bool expand_page_contents (Gtk.Widget widget) {
    var clamp = widget as Adw.Clamp;
    if (clamp != null) {
      clamp.maximum_size = int.MAX;
      return true;
    }

    for (
      var child = widget.get_first_child ();
      child != null;
      child = child.get_next_sibling ()
    ) {
      if (this.expand_page_contents (child)) {
        return true;
      }
    }

    return false;
  }

  private void set_themes_filter_func () {
    if (!this.filter_themes_check_button.active) {
      this.preview_flow_box.set_filter_func (null);
    }
    else {
      if (this.light_theme_toggle.active) {
        this.preview_flow_box.set_filter_func (light_themes_filter_func);
      }
      else {
        this.preview_flow_box.set_filter_func (dark_themes_filter_func);

      }
    }
  }

  private string? get_selected_profile_name (Adw.ComboRow row) {
    var names = this.profile_manager.get_profile_names ();
    var idx = (int) row.selected;

    if (idx < 0 || idx >= names.length) {
      return null;
    }

    return names[idx];
  }

  private void set_selected_profile_name (Adw.ComboRow row, string profile_name) {
    var idx = this.profile_manager.get_profile_index (profile_name);
    if (idx >= 0) {
      row.selected = (uint) idx;
    }
  }

  private void refresh_profile_ui () {
    var current_selected = this.get_selected_profile_name (
      this.profiles_selected_profile_combo_row
    );
    var editing_profile = this.profile_manager.session_profile_name;

    this.is_updating_profile_ui = true;

    while (this.profile_names_model.get_n_items () > 0) {
      this.profile_names_model.remove (this.profile_names_model.get_n_items () - 1);
    }

    foreach (unowned string name in this.profile_manager.get_profile_names ()) {
      this.profile_names_model.append (name);
    }

    this.set_selected_profile_name (
      this.terminal_editing_profile_combo_row,
      editing_profile
    );
    this.set_selected_profile_name (
      this.profiles_startup_profile_combo_row,
      this.profile_manager.startup_profile_name
    );

    var selected_name = current_selected;
    if (
      selected_name == null ||
      !this.profile_manager.has_profile (selected_name)
    ) {
      selected_name = editing_profile;
    }

    if (selected_name != null) {
      this.set_selected_profile_name (
        this.profiles_selected_profile_combo_row,
        selected_name
      );
      this.profile_name_entry_row.text = selected_name;
    }

    this.is_updating_profile_ui = false;
  }

  private void bind_profiles () {
    this.terminal_editing_profile_combo_row.model = this.profile_names_model;
    this.profiles_startup_profile_combo_row.model = this.profile_names_model;
    this.profiles_selected_profile_combo_row.model = this.profile_names_model;

    this.terminal_editing_profile_combo_row.notify["selected"].connect (() => {
      if (this.is_updating_profile_ui) {
        return;
      }

      var selected = this.get_selected_profile_name (
        this.terminal_editing_profile_combo_row
      );
      if (selected != null) {
        this.profile_manager.set_session_profile (selected);
      }
    });

    this.profiles_startup_profile_combo_row.notify["selected"].connect (() => {
      if (this.is_updating_profile_ui) {
        return;
      }

      var selected = this.get_selected_profile_name (
        this.profiles_startup_profile_combo_row
      );
      if (selected != null) {
        this.profile_manager.set_startup_profile (selected);
      }
    });

    this.profiles_selected_profile_combo_row.notify["selected"].connect (() => {
      if (this.is_updating_profile_ui) {
        return;
      }

      var selected = this.get_selected_profile_name (
        this.profiles_selected_profile_combo_row
      );
      if (selected != null) {
        this.profile_name_entry_row.text = selected;
      }
    });

    this.profile_manager.active_profile_changed.connect ((_name) => {
      this.refresh_profile_ui ();
    });
    this.profile_manager.profiles_changed.connect (this.refresh_profile_ui);

    this.refresh_profile_ui ();
  }

  private void do_reset_preferences () {
    var settings = Settings.get_default ();
    foreach (var key in settings.schema.settings_schema.list_keys ()) {
      settings.schema.reset (key);
    }
  }

  // Callbacks

  [GtkCallback]
  private void on_font_row_activated () {
    var fc = new Gtk.FontChooserDialog (_("Terminal Font"), this) {
      level = Gtk.FontChooserLevel.FAMILY | Gtk.FontChooserLevel.SIZE | Gtk.FontChooserLevel.STYLE,
      // Setting the font seems to have no effect
      font = Settings.get_default ().font,
    };

    fc.set_filter_func ((desc) => {
      return desc.is_monospace ();
    });

    fc.response.connect_after ((response) => {
      if (response == Gtk.ResponseType.OK && fc.font != null) {
        Settings.get_default ().font = fc.font;
      }
      fc.destroy ();
    });

    fc.show ();
  }


  [GtkCallback]
  private void on_reset_request () {
    var d = new Gtk.MessageDialog (
      this,
      Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT,
      Gtk.MessageType.QUESTION,
      Gtk.ButtonsType.YES_NO,
      "Are you sure you want to reset all settings?"
    );

    var yes_button = d.get_widget_for_response (Gtk.ResponseType.YES);
    yes_button?.add_css_class ("destructive-action");

    var no_button = d.get_widget_for_response (Gtk.ResponseType.NO);
    no_button?.add_css_class ("suggested-action");

    d.set_default_response (Gtk.ResponseType.NO);

    d.response.connect ((response) => {
      if (response == Gtk.ResponseType.YES) {
        this.do_reset_preferences ();
      }
      d.destroy ();
    });

    d.present ();
  }

  [GtkCallback]
  private void on_create_profile_clicked () {
    var name = this.profile_name_entry_row.text.strip ();
    if (name == "") {
      return;
    }

    if (this.profile_manager.create_profile (name)) {
      this.refresh_profile_ui ();
      this.set_selected_profile_name (this.profiles_selected_profile_combo_row, name);
      this.profile_name_entry_row.text = name;
    }
  }

  [GtkCallback]
  private void on_rename_profile_clicked () {
    var selected_name = this.get_selected_profile_name (
      this.profiles_selected_profile_combo_row
    );
    var new_name = this.profile_name_entry_row.text.strip ();

    if (selected_name == null || new_name == "") {
      return;
    }

    if (this.profile_manager.rename_profile (selected_name, new_name)) {
      this.refresh_profile_ui ();
      this.set_selected_profile_name (
        this.profiles_selected_profile_combo_row,
        new_name
      );
      this.profile_name_entry_row.text = new_name;
    }
  }

  [GtkCallback]
  private void on_delete_profile_clicked () {
    var selected_name = this.get_selected_profile_name (
      this.profiles_selected_profile_combo_row
    );

    if (selected_name == null) {
      return;
    }

    if (this.profile_manager.delete_profile (selected_name)) {
      this.refresh_profile_ui ();
    }
  }

  [GtkCallback]
  private void on_import_tilix_profiles_clicked () {
    if (this.profile_manager.import_tilix_profiles () > 0) {
      this.refresh_profile_ui ();
    }
  }

  [GtkCallback]
  private void on_get_more_themes_online () {
    Gtk.show_uri (
      this,
      "https://github.com/storm119/Tilix-Themes",
      (int32) (get_monotonic_time () / 1000)
    );
  }

  [GtkCallback]
  private void on_open_themes_folder () {
    Gtk.show_uri (
      this,
      "file://" + Constants.get_user_schemes_dir (),
      (int32) (get_monotonic_time () / 1000)
    );
  }
}
