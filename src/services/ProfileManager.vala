/* ProfileManager.vala
 *
 * Copyright 2026
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Terminal {
  public class Profile : Object {
    public string name;

    public string font;
    public double terminal_cell_width;
    public double terminal_cell_height;
    public bool easy_copy_paste;
    public uint cursor_shape;
    public uint cursor_blink_mode;
    public uint padding_top;
    public uint padding_right;
    public uint padding_bottom;
    public uint padding_left;
    public uint opacity;
    public bool show_scrollbars;
    public bool use_overlay_scrolling;
    public bool use_custom_scrollback;
    public uint scrollback_lines;
    public bool command_as_login_shell;
    public bool use_custom_command;
    public string custom_shell_command;
    public string theme_light;
    public string theme_dark;

    public Gee.HashMap<string, string?> keymap;

    public Profile (string name) {
      this.name = name;
      this.font = "Monospace 12";
      this.terminal_cell_width = 1.0;
      this.terminal_cell_height = 1.0;
      this.easy_copy_paste = false;
      this.cursor_shape = 0;
      this.cursor_blink_mode = 0;
      this.padding_top = 0;
      this.padding_right = 0;
      this.padding_bottom = 0;
      this.padding_left = 0;
      this.opacity = 100;
      this.show_scrollbars = true;
      this.use_overlay_scrolling = true;
      this.use_custom_scrollback = false;
      this.scrollback_lines = 10000;
      this.command_as_login_shell = true;
      this.use_custom_command = false;
      this.custom_shell_command = "";
      this.theme_light = "Tomorrow";
      this.theme_dark = "Tommorow Night";
      this.keymap = new Gee.HashMap<string, string?> ();
    }
  }

  public class ProfileManager : Object {
    private const string PROFILES_FILE_VERSION = "1";

    private Settings settings;
    private Keymap keymap;
    private Gee.ArrayList<Profile> profiles;
    private string _active_profile_name = "";
    private string _session_profile_name = "";
    private bool is_applying_profile = false;
    private bool tilix_migrated = false;
    private weak Gtk.Application? app = null;

    private static ProfileManager? instance = null;

    public signal void profiles_changed ();
    public signal void active_profile_changed (string profile_name);
    public signal void profile_renamed (string old_name, string new_name);
    public signal void profile_deleted (string deleted_name, string fallback_name);

    public string startup_profile_name {
      get { return this._active_profile_name; }
    }

    public string session_profile_name {
      get { return this._session_profile_name; }
    }

    private ProfileManager () {
      this.settings = Settings.get_default ();
      this.keymap = Keymap.get_default ();
      this.profiles = new Gee.ArrayList<Profile> ();

      this.ensure_user_data_dir_exists ();

      if (!this.load_profiles ()) {
        this.bootstrap_profiles ();
      }

      this._session_profile_name = this._active_profile_name;
      this.apply_session_profile ();
      this.connect_runtime_tracking ();
    }

    public static ProfileManager get_default () {
      if (instance == null) {
        instance = new ProfileManager ();
      }

      return instance;
    }

  public void initialize (Gtk.Application app) {
    this.app = app;
    this.keymap.apply (app);
  }

    public string[] get_profile_names () {
      string[] names = {};

      foreach (Profile profile in this.profiles) {
        names += profile.name;
      }

      return names;
    }

    public int get_profile_index (string profile_name) {
      for (int i = 0; i < this.profiles.size; i++) {
        if (this.profiles[i].name == profile_name) {
          return i;
        }
      }

      return -1;
    }

    public bool has_profile (string profile_name) {
      return this.get_profile_index (profile_name) >= 0;
    }

    public bool set_startup_profile (string profile_name) {
      if (!this.has_profile (profile_name)) {
        return false;
      }

      if (profile_name == this._active_profile_name) {
        return true;
      }

      this._active_profile_name = profile_name;
      this.save_profiles ();
      this.profiles_changed ();

      return true;
    }

    public bool set_session_profile (string profile_name) {
      if (!this.has_profile (profile_name)) {
        return false;
      }

      if (profile_name == this._session_profile_name) {
        return true;
      }

      this.capture_session_profile_state ();
      this._session_profile_name = profile_name;
      this.apply_session_profile ();
      this.active_profile_changed (this._session_profile_name);

      return true;
    }

    public bool create_profile (string requested_name) {
      var name = requested_name.strip ();

      if (name == "" || this.has_profile (name)) {
        return false;
      }

      this.capture_session_profile_state ();
      this.profiles.add (this.snapshot_runtime_profile (name));
      this.save_profiles ();
      this.profiles_changed ();
      return true;
    }

    public bool rename_profile (string old_name, string requested_name) {
      var new_name = requested_name.strip ();

      if (new_name == "" || old_name == "" || old_name == new_name) {
        return false;
      }

      var profile = this.find_profile (old_name);
      if (profile == null || this.has_profile (new_name)) {
        return false;
      }

      profile.name = new_name;

      bool did_change_active_profile = false;

      if (this._active_profile_name == old_name) {
        this._active_profile_name = new_name;
      }
      if (this._session_profile_name == old_name) {
        this._session_profile_name = new_name;
        did_change_active_profile = true;
      }

      if (did_change_active_profile) {
        this.active_profile_changed (new_name);
      }

      this.profile_renamed (old_name, new_name);

      this.save_profiles ();
      this.profiles_changed ();
      return true;
    }

    public bool delete_profile (string profile_name) {
      if (this.profiles.size <= 1) {
        return false;
      }

      var index = this.get_profile_index (profile_name);
      if (index < 0) {
        return false;
      }

      var removed_active = this._active_profile_name == profile_name;
      var removed_session = this._session_profile_name == profile_name;
      this.profiles.remove_at (index);

      if (removed_active) {
        this._active_profile_name = this.profiles[0].name;
      }

      if (removed_session) {
        this._session_profile_name = this._active_profile_name;
        this.apply_session_profile ();
        this.active_profile_changed (this._session_profile_name);
      }

      this.profile_deleted (profile_name, this._session_profile_name);

      this.save_profiles ();
      this.profiles_changed ();
      return true;
    }

    public uint import_tilix_profiles () {
      this.capture_session_profile_state ();

      uint imported = this.import_tilix_profiles_internal (false);
      if (imported > 0) {
        this.save_profiles ();
        this.profiles_changed ();
      }

      return imported;
    }

    private void connect_runtime_tracking () {
      this.settings.notify["font"].connect (this.on_profile_setting_changed);
      this.settings.notify["terminal-cell-width"].connect (this.on_profile_setting_changed);
      this.settings.notify["terminal-cell-height"].connect (this.on_profile_setting_changed);
      this.settings.notify["easy-copy-paste"].connect (this.on_profile_setting_changed);
      this.settings.notify["cursor-shape"].connect (this.on_profile_setting_changed);
      this.settings.notify["cursor-blink-mode"].connect (this.on_profile_setting_changed);
      this.settings.notify["terminal-padding"].connect (this.on_profile_setting_changed);
      this.settings.notify["opacity"].connect (this.on_profile_setting_changed);
      this.settings.notify["show-scrollbars"].connect (this.on_profile_setting_changed);
      this.settings.notify["use-overlay-scrolling"].connect (this.on_profile_setting_changed);
      this.settings.notify["use-custom-scrollback"].connect (this.on_profile_setting_changed);
      this.settings.notify["scrollback-lines"].connect (this.on_profile_setting_changed);
      this.settings.notify["command-as-login-shell"].connect (this.on_profile_setting_changed);
      this.settings.notify["use-custom-command"].connect (this.on_profile_setting_changed);
      this.settings.notify["custom-shell-command"].connect (this.on_profile_setting_changed);
      this.settings.notify["theme-light"].connect (this.on_profile_setting_changed);
      this.settings.notify["theme-dark"].connect (this.on_profile_setting_changed);

      this.keymap.changed.connect (() => {
        this.on_profile_setting_changed ();
      });
    }

    private void on_profile_setting_changed () {
      if (this.is_applying_profile) {
        return;
      }

      this.capture_session_profile_state ();
    }

    private void ensure_user_data_dir_exists () {
      var path = Constants.get_user_data_dir ();
      if (!FileUtils.test (path, FileTest.IS_DIR)) {
        var dir = GLib.File.new_for_path (path);

        try {
          dir.make_directory_with_parents ();
        }
        catch (Error e) {
          warning ("Could not create %s: %s", path, e.message);
        }
      }
    }

    private string get_profiles_path () {
      return Constants.get_user_profiles_path ();
    }

    private Profile? find_profile (string profile_name) {
      foreach (Profile profile in this.profiles) {
        if (profile.name == profile_name) {
          return profile;
        }
      }

      return null;
    }

    private Gee.HashMap<string, string?> clone_keymap (
      Gee.Map<string, string?> source
    ) {
      var clone = new Gee.HashMap<string, string?> ();

      foreach (string action in source.keys) {
        clone.@set (action, source[action]);
      }

      return clone;
    }

    private Profile clone_profile (Profile source) {
      var copy = new Profile (source.name);

      copy.font = source.font;
      copy.terminal_cell_width = source.terminal_cell_width;
      copy.terminal_cell_height = source.terminal_cell_height;
      copy.easy_copy_paste = source.easy_copy_paste;
      copy.cursor_shape = source.cursor_shape;
      copy.cursor_blink_mode = source.cursor_blink_mode;
      copy.padding_top = source.padding_top;
      copy.padding_right = source.padding_right;
      copy.padding_bottom = source.padding_bottom;
      copy.padding_left = source.padding_left;
      copy.opacity = source.opacity;
      copy.show_scrollbars = source.show_scrollbars;
      copy.use_overlay_scrolling = source.use_overlay_scrolling;
      copy.use_custom_scrollback = source.use_custom_scrollback;
      copy.scrollback_lines = source.scrollback_lines;
      copy.command_as_login_shell = source.command_as_login_shell;
      copy.use_custom_command = source.use_custom_command;
      copy.custom_shell_command = source.custom_shell_command;
      copy.theme_light = source.theme_light;
      copy.theme_dark = source.theme_dark;
      copy.keymap = this.clone_keymap (source.keymap);

      return copy;
    }

    public Profile? get_profile_snapshot (string profile_name) {
      var profile = this.find_profile (profile_name);
      if (profile == null) {
        return null;
      }

      return this.clone_profile (profile);
    }

    private Profile snapshot_runtime_profile (string name) {
      var profile = new Profile (name);

      var pad = this.settings.get_padding ();

      profile.font = this.settings.font;
      profile.terminal_cell_width = this.settings.terminal_cell_width;
      profile.terminal_cell_height = this.settings.terminal_cell_height;
      profile.easy_copy_paste = this.settings.easy_copy_paste;
      profile.cursor_shape = this.settings.cursor_shape;
      profile.cursor_blink_mode = this.settings.cursor_blink_mode;
      profile.padding_top = pad.top;
      profile.padding_right = pad.right;
      profile.padding_bottom = pad.bottom;
      profile.padding_left = pad.left;
      profile.opacity = this.settings.opacity;
      profile.show_scrollbars = this.settings.show_scrollbars;
      profile.use_overlay_scrolling = this.settings.use_overlay_scrolling;
      profile.use_custom_scrollback = this.settings.use_custom_scrollback;
      profile.scrollback_lines = this.settings.scrollback_lines;
      profile.command_as_login_shell = this.settings.command_as_login_shell;
      profile.use_custom_command = this.settings.use_custom_command;
      profile.custom_shell_command = this.settings.custom_shell_command;
      profile.theme_light = this.settings.theme_light;
      profile.theme_dark = this.settings.theme_dark;

      profile.keymap = this.clone_keymap (this.keymap.export_flat_keymap ());

      return profile;
    }

    private void apply_profile (Profile profile) {
      this.is_applying_profile = true;

      this.settings.font = profile.font;
      this.settings.terminal_cell_width = profile.terminal_cell_width;
      this.settings.terminal_cell_height = profile.terminal_cell_height;
      this.settings.easy_copy_paste = profile.easy_copy_paste;
      this.settings.cursor_shape = profile.cursor_shape;
      this.settings.cursor_blink_mode = profile.cursor_blink_mode;
      this.settings.set_padding (Padding () {
        top = profile.padding_top,
        right = profile.padding_right,
        bottom = profile.padding_bottom,
        left = profile.padding_left,
      });
      this.settings.opacity = profile.opacity;
      this.settings.show_scrollbars = profile.show_scrollbars;
      this.settings.use_overlay_scrolling = profile.use_overlay_scrolling;
      this.settings.use_custom_scrollback = profile.use_custom_scrollback;
      this.settings.scrollback_lines = profile.scrollback_lines;
      this.settings.command_as_login_shell = profile.command_as_login_shell;
      this.settings.use_custom_command = profile.use_custom_command;
      this.settings.custom_shell_command = profile.custom_shell_command;
      this.settings.theme_light = profile.theme_light;
      this.settings.theme_dark = profile.theme_dark;

      this.keymap.import_flat_keymap (profile.keymap);

      if (this.app != null) {
        this.keymap.apply (this.app);
      }

      this.keymap.save ();
      this.is_applying_profile = false;
    }

    private void apply_session_profile () {
      var profile = this.find_profile (this._session_profile_name);
      if (profile != null) {
        this.apply_profile (profile);
      }
    }

    private void capture_session_profile_state () {
      if (this.is_applying_profile) {
        return;
      }

      var idx = this.get_profile_index (this._session_profile_name);
      if (idx < 0) {
        return;
      }

      this.profiles[idx] = this.snapshot_runtime_profile (this._session_profile_name);
      this.save_profiles ();
    }

    private Json.Object profile_to_json (Profile profile) {
      var obj = new Json.Object ();
      var terminal = new Json.Object ();
      var keymap_obj = new Json.Object ();
      var padding = new Json.Array ();

      obj.set_string_member ("name", profile.name);

      terminal.set_string_member ("font", profile.font);
      terminal.set_double_member ("terminal_cell_width", profile.terminal_cell_width);
      terminal.set_double_member ("terminal_cell_height", profile.terminal_cell_height);
      terminal.set_boolean_member ("easy_copy_paste", profile.easy_copy_paste);
      terminal.set_int_member ("cursor_shape", profile.cursor_shape);
      terminal.set_int_member ("cursor_blink_mode", profile.cursor_blink_mode);
      padding.add_int_element ((int) profile.padding_top);
      padding.add_int_element ((int) profile.padding_right);
      padding.add_int_element ((int) profile.padding_bottom);
      padding.add_int_element ((int) profile.padding_left);
      terminal.set_array_member ("padding", padding);
      terminal.set_int_member ("opacity", profile.opacity);
      terminal.set_boolean_member ("show_scrollbars", profile.show_scrollbars);
      terminal.set_boolean_member ("use_overlay_scrolling", profile.use_overlay_scrolling);
      terminal.set_boolean_member ("use_custom_scrollback", profile.use_custom_scrollback);
      terminal.set_int_member ("scrollback_lines", profile.scrollback_lines);
      terminal.set_boolean_member ("command_as_login_shell", profile.command_as_login_shell);
      terminal.set_boolean_member ("use_custom_command", profile.use_custom_command);
      terminal.set_string_member ("custom_shell_command", profile.custom_shell_command);
      terminal.set_string_member ("theme_light", profile.theme_light);
      terminal.set_string_member ("theme_dark", profile.theme_dark);
      obj.set_object_member ("terminal", terminal);

      foreach (string action in profile.keymap.keys) {
        var accel = profile.keymap[action];
        if (accel == null || accel == "") {
          keymap_obj.set_null_member (action);
        }
        else {
          keymap_obj.set_string_member (action, accel);
        }
      }
      obj.set_object_member ("keymap", keymap_obj);

      return obj;
    }

    private static string json_get_string (
      Json.Object obj,
      string key,
      string fallback
    ) {
      return obj.has_member (key) ? obj.get_string_member (key) : fallback;
    }

    private static bool json_get_bool (
      Json.Object obj,
      string key,
      bool fallback
    ) {
      return obj.has_member (key) ? obj.get_boolean_member (key) : fallback;
    }

    private static double json_get_double (
      Json.Object obj,
      string key,
      double fallback
    ) {
      return obj.has_member (key) ? obj.get_double_member (key) : fallback;
    }

    private static uint json_get_uint (
      Json.Object obj,
      string key,
      uint fallback
    ) {
      return obj.has_member (key)
        ? (uint) obj.get_int_member (key)
        : fallback;
    }

    private void parse_keymap_json_into_profile (Json.Object obj, Profile profile) {
      var map = new Gee.HashMap<string, string?> ();

      obj.foreach_member ((_obj, action, node) => {
        switch (node.get_node_type ()) {
          case Json.NodeType.NULL:
            map.@set (action, null);
            break;
          case Json.NodeType.VALUE:
            map.@set (action, node.get_string ());
            break;
          case Json.NodeType.ARRAY: {
            var arr = node.get_array ();
            if (arr == null || arr.get_length () == 0) {
              map.@set (action, null);
            }
            else {
              map.@set (action, arr.get_string_element (0));
            }
            break;
          }
          default:
            break;
        }
      });

      profile.keymap = map;
    }

    private Profile? profile_from_json (Json.Object? obj) {
      if (obj == null || !obj.has_member ("name")) {
        return null;
      }

      var name = obj.get_string_member ("name");
      if (name.strip () == "") {
        return null;
      }

      var profile = this.snapshot_runtime_profile (name);

      if (obj.has_member ("terminal")) {
        var terminal = obj.get_object_member ("terminal");

        profile.font = ProfileManager.json_get_string (
          terminal,
          "font",
          profile.font
        );
        profile.terminal_cell_width = ProfileManager.json_get_double (
          terminal,
          "terminal_cell_width",
          profile.terminal_cell_width
        );
        profile.terminal_cell_height = ProfileManager.json_get_double (
          terminal,
          "terminal_cell_height",
          profile.terminal_cell_height
        );
        profile.easy_copy_paste = ProfileManager.json_get_bool (
          terminal,
          "easy_copy_paste",
          profile.easy_copy_paste
        );
        profile.cursor_shape = ProfileManager.json_get_uint (
          terminal,
          "cursor_shape",
          profile.cursor_shape
        );
        profile.cursor_blink_mode = ProfileManager.json_get_uint (
          terminal,
          "cursor_blink_mode",
          profile.cursor_blink_mode
        );

        if (terminal.has_member ("padding")) {
          var padding = terminal.get_array_member ("padding");

          if (padding != null && padding.get_length () == 4) {
            profile.padding_top = (uint) padding.get_int_element (0);
            profile.padding_right = (uint) padding.get_int_element (1);
            profile.padding_bottom = (uint) padding.get_int_element (2);
            profile.padding_left = (uint) padding.get_int_element (3);
          }
        }

        profile.opacity = ProfileManager.json_get_uint (
          terminal,
          "opacity",
          profile.opacity
        );
        profile.show_scrollbars = ProfileManager.json_get_bool (
          terminal,
          "show_scrollbars",
          profile.show_scrollbars
        );
        profile.use_overlay_scrolling = ProfileManager.json_get_bool (
          terminal,
          "use_overlay_scrolling",
          profile.use_overlay_scrolling
        );
        profile.use_custom_scrollback = ProfileManager.json_get_bool (
          terminal,
          "use_custom_scrollback",
          profile.use_custom_scrollback
        );
        profile.scrollback_lines = ProfileManager.json_get_uint (
          terminal,
          "scrollback_lines",
          profile.scrollback_lines
        );
        profile.command_as_login_shell = ProfileManager.json_get_bool (
          terminal,
          "command_as_login_shell",
          profile.command_as_login_shell
        );
        profile.use_custom_command = ProfileManager.json_get_bool (
          terminal,
          "use_custom_command",
          profile.use_custom_command
        );
        profile.custom_shell_command = ProfileManager.json_get_string (
          terminal,
          "custom_shell_command",
          profile.custom_shell_command
        );
        profile.theme_light = ProfileManager.json_get_string (
          terminal,
          "theme_light",
          profile.theme_light
        );
        profile.theme_dark = ProfileManager.json_get_string (
          terminal,
          "theme_dark",
          profile.theme_dark
        );
      }

      if (obj.has_member ("keymap")) {
        this.parse_keymap_json_into_profile (obj.get_object_member ("keymap"), profile);
      }

      return profile;
    }

    private bool load_profiles () {
      var path = this.get_profiles_path ();
      var file = new File (path);

      if (!FileUtils.test (path, FileTest.EXISTS | FileTest.IS_REGULAR)) {
        return false;
      }

      try {
        string? data = file.read_all (null);
        if (data == null || data.strip () == "") {
          return false;
        }

        var parser = new Json.Parser ();
        parser.load_from_data (data, -1);

        var root_node = parser.get_root ();
        if (root_node == null || root_node.get_node_type () != Json.NodeType.OBJECT) {
          return false;
        }

        var root = root_node.get_object ();
        if (root == null || !root.has_member ("profiles")) {
          return false;
        }

        var loaded_profiles = new Gee.ArrayList<Profile> ();
        var profiles_array = root.get_array_member ("profiles");

        profiles_array?.foreach_element ((_arr, _idx, profile_node) => {
          if (profile_node.get_node_type () != Json.NodeType.OBJECT) {
            return;
          }

          var profile = this.profile_from_json (profile_node.get_object ());
          if (profile != null) {
            loaded_profiles.add (profile);
          }
        });

        if (loaded_profiles.size == 0) {
          return false;
        }

        this.profiles = loaded_profiles;

        if (root.has_member ("active_profile")) {
          this._active_profile_name = root.get_string_member ("active_profile");
        }

        if (this.find_profile (this._active_profile_name) == null) {
          this._active_profile_name = this.profiles[0].name;
        }

        if (root.has_member ("tilix_migrated")) {
          this.tilix_migrated = root.get_boolean_member ("tilix_migrated");
        }

        return true;
      }
      catch (Error e) {
        warning ("Could not load profiles: %s", e.message);
      }

      return false;
    }

    private void save_profiles () {
      if (this.profiles.size == 0) {
        return;
      }

      var root = new Json.Object ();
      var profiles_array = new Json.Array ();

      root.set_string_member ("version", ProfileManager.PROFILES_FILE_VERSION);
      root.set_string_member ("active_profile", this._active_profile_name);
      root.set_boolean_member ("tilix_migrated", this.tilix_migrated);

      foreach (Profile profile in this.profiles) {
        profiles_array.add_object_element (this.profile_to_json (profile));
      }

      root.set_array_member ("profiles", profiles_array);

      var root_node = new Json.Node (Json.NodeType.OBJECT);
      root_node.set_object (root);

      var generator = new Json.Generator ();
      generator.set_pretty (true);
      generator.set_root (root_node);

      try {
        string output = generator.to_data (null);
        var file = new File (this.get_profiles_path ());
        file.write_plus (output);
      }
      catch (Error e) {
        warning ("Could not save profiles: %s", e.message);
      }
    }

    private void bootstrap_profiles () {
      var default_profile = this.snapshot_runtime_profile ("Default");
      this.profiles.add (default_profile);
      this._active_profile_name = default_profile.name;

      this.import_tilix_profiles_internal (true);
      this.save_profiles ();
    }

    private bool has_tilix_schema (string schema_id) {
      var source = GLib.SettingsSchemaSource.get_default ();
      if (source == null) {
        return false;
      }

      return source.lookup (schema_id, true) != null;
    }

    private string make_unique_profile_name (string requested_name) {
      var root_name = requested_name.strip ();
      if (root_name == "") {
        root_name = "Profile";
      }

      var candidate = root_name;
      uint i = 2;

      while (this.has_profile (candidate)) {
        candidate = @"$(root_name) ($(i))";
        i++;
      }

      return candidate;
    }

    private string? normalize_tilix_accelerator (string accel) {
      var value = accel.strip ();

      if (value == "" || value == "disabled") {
        return null;
      }

      return value.replace ("<Ctrl>", "<Control>");
    }

    private void map_tilix_keybinding (
      Profile profile,
      GLib.Settings keybindings,
      string tilix_key,
      string action
    ) {
      var accel = this.normalize_tilix_accelerator (
        keybindings.get_string (tilix_key)
      );
      profile.keymap.@set (action, accel);
    }

    private void map_tilix_keybindings (Profile profile, GLib.Settings keybindings) {
      this.map_tilix_keybinding (profile, keybindings, "app-new-window", ACTION_NEW_WINDOW);
      this.map_tilix_keybinding (profile, keybindings, "app-new-session", ACTION_WIN_NEW_TAB);
      this.map_tilix_keybinding (profile, keybindings, "app-preferences", ACTION_WIN_EDIT_PREFERENCES);
      this.map_tilix_keybinding (profile, keybindings, "app-shortcuts", ACTION_WIN_SHOW_HELP_OVERLAY);
      this.map_tilix_keybinding (profile, keybindings, "session-close", ACTION_WIN_CLOSE_TAB);
      this.map_tilix_keybinding (profile, keybindings, "terminal-copy", ACTION_WIN_COPY);
      this.map_tilix_keybinding (profile, keybindings, "terminal-paste", ACTION_WIN_PASTE);
      this.map_tilix_keybinding (profile, keybindings, "terminal-find", ACTION_WIN_SEARCH);
      this.map_tilix_keybinding (profile, keybindings, "terminal-zoom-in", ACTION_WIN_ZOOM_IN);
      this.map_tilix_keybinding (profile, keybindings, "terminal-zoom-out", ACTION_WIN_ZOOM_OUT);
      this.map_tilix_keybinding (profile, keybindings, "terminal-zoom-normal", ACTION_WIN_ZOOM_DEFAULT);
      this.map_tilix_keybinding (profile, keybindings, "win-fullscreen", ACTION_WIN_FULLSCREEN);
      this.map_tilix_keybinding (profile, keybindings, "win-switch-to-session-1", ACTION_WIN_SWITCH_TAB_1);
      this.map_tilix_keybinding (profile, keybindings, "win-switch-to-session-2", ACTION_WIN_SWITCH_TAB_2);
      this.map_tilix_keybinding (profile, keybindings, "win-switch-to-session-3", ACTION_WIN_SWITCH_TAB_3);
      this.map_tilix_keybinding (profile, keybindings, "win-switch-to-session-4", ACTION_WIN_SWITCH_TAB_4);
      this.map_tilix_keybinding (profile, keybindings, "win-switch-to-session-5", ACTION_WIN_SWITCH_TAB_5);
      this.map_tilix_keybinding (profile, keybindings, "win-switch-to-session-6", ACTION_WIN_SWITCH_TAB_6);
      this.map_tilix_keybinding (profile, keybindings, "win-switch-to-session-7", ACTION_WIN_SWITCH_TAB_7);
      this.map_tilix_keybinding (profile, keybindings, "win-switch-to-session-8", ACTION_WIN_SWITCH_TAB_8);
      this.map_tilix_keybinding (profile, keybindings, "win-switch-to-session-9", ACTION_WIN_SWITCH_TAB_9);
      this.map_tilix_keybinding (profile, keybindings, "win-switch-to-session-0", ACTION_WIN_SWITCH_TAB_LAST);

      var next = this.normalize_tilix_accelerator (
        keybindings.get_string ("win-switch-to-next-session")
      );
      if (next == null) {
        next = this.normalize_tilix_accelerator (
          keybindings.get_string ("session-switch-to-next-terminal")
        );
      }
      profile.keymap.@set (ACTION_FOCUS_NEXT_TAB, next);

      var previous = this.normalize_tilix_accelerator (
        keybindings.get_string ("win-switch-to-previous-session")
      );
      if (previous == null) {
        previous = this.normalize_tilix_accelerator (
          keybindings.get_string ("session-switch-to-previous-terminal")
        );
      }
      profile.keymap.@set (ACTION_FOCUS_PREVIOUS_TAB, previous);
    }

    private uint import_tilix_profiles_internal (bool is_initial_bootstrap) {
      if (!this.has_tilix_schema ("com.gexperts.Tilix.ProfilesList") ||
          !this.has_tilix_schema ("com.gexperts.Tilix.Profile") ||
          !this.has_tilix_schema ("com.gexperts.Tilix.Keybindings")) {
        return 0;
      }

      if (!is_initial_bootstrap && this.tilix_migrated) {
        return 0;
      }

      var tilix_profiles = new GLib.Settings ("com.gexperts.Tilix.ProfilesList");
      var tilix_global = new GLib.Settings ("com.gexperts.Tilix.Settings");
      var tilix_keybindings = new GLib.Settings ("com.gexperts.Tilix.Keybindings");

      var profile_ids = tilix_profiles.get_strv ("list");
      if (profile_ids.length == 0) {
        return 0;
      }

      var default_profile_id = tilix_profiles.get_string ("default");
      string? imported_default_name = null;
      uint imported = 0;

      foreach (unowned string profile_id in profile_ids) {
        var path = "/com/gexperts/Tilix/profiles/%s/".printf (profile_id);
        var tilix_profile = new GLib.Settings.with_path (
          "com.gexperts.Tilix.Profile",
          path
        );

        var tilix_visible_name = tilix_profile.get_string ("visible-name");
        if (tilix_visible_name.strip () == "") {
          tilix_visible_name = "Unnamed";
        }

        var new_profile_name = this.make_unique_profile_name (
          "Tilix: " + tilix_visible_name
        );

        var profile = this.snapshot_runtime_profile (new_profile_name);

        profile.font = tilix_profile.get_string ("font");
        profile.terminal_cell_width = tilix_profile.get_double ("cell-width-scale");
        profile.terminal_cell_height = tilix_profile.get_double ("cell-height-scale");
        profile.cursor_shape = (uint) tilix_profile.get_enum ("cursor-shape");
        profile.cursor_blink_mode = (uint) tilix_profile.get_enum ("cursor-blink-mode");
        profile.show_scrollbars = tilix_profile.get_boolean ("show-scrollbar");
        profile.use_overlay_scrolling = tilix_global.get_boolean ("use-overlay-scrollbar");
        profile.use_custom_scrollback = !tilix_profile.get_boolean ("scrollback-unlimited");
        profile.command_as_login_shell = tilix_profile.get_boolean ("login-shell");
        profile.use_custom_command = tilix_profile.get_boolean ("use-custom-command");
        profile.custom_shell_command = tilix_profile.get_string ("custom-command");

        var trans = tilix_profile.get_int ("background-transparency-percent");
        if (trans < 0) {
          trans = 0;
        }
        if (trans > 100) {
          trans = 100;
        }
        profile.opacity = (uint) (100 - trans);

        var lines = tilix_profile.get_int ("scrollback-lines");
        if (lines < 0) {
          lines = 0;
        }
        profile.scrollback_lines = (uint) lines;

        this.map_tilix_keybindings (profile, tilix_keybindings);

        this.profiles.add (profile);
        imported++;

        if (profile_id == default_profile_id) {
          imported_default_name = profile.name;
        }
      }

      if (is_initial_bootstrap && imported_default_name != null) {
        this._active_profile_name = imported_default_name;
      }

      if (imported > 0) {
        this.tilix_migrated = true;
      }
      return imported;
    }
  }
}
