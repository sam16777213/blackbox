/* Settings.vala
 *
 * The following code is a derivative work of the code from
 * https://github.com/elementary/granite/blob/master/lib/Services/Settings.vala
 * which is licensed under GNU Lesser General Public version 3 of the License,
 * or (at your option) any later version.
 *
 * Copyright 2020-2022 Paulo Queiroz <pvaqueiroz@gmail.com>
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

public abstract class PQMarble.Settings : Object {
  public GLib.Settings schema { get; construct set; }

  private bool updating = false;
  private bool doing_setup = true;

  protected Settings (string path) {
    Object(schema: new GLib.Settings(path));
  }

  // Runs after Settings()
  construct {
    debug("Started settings from '%s'", this.schema.schema_id);

    var obj_class = (ObjectClass) this.get_type().class_ref();
    var properties = obj_class.list_properties();

    foreach (var prop in properties) {
      this.load_key(prop.name);
    }

    this.doing_setup = false;
    this.schema.changed.connect(this.load_key);
  }

  private void load_key (string key) {
    if (key == "schema") {
      return;
    }

    var obj_class = (ObjectClass) this.get_type().class_ref();
    var prop = obj_class.find_property(key);

    if (prop == null) {
      return;
    }

    this.notify.disconnect(this.on_notify);

    var type = prop.value_type;
    var val = Value(type);
    this.get_property(key, ref val);

    // Unsupported type
    if (val.type() != prop.value_type) {
      warning("Unsupported type %s for key %s", type.to_string(), key);
      this.notify.connect(this.on_notify);
      return;
    }

    if (type == typeof(int)) {
      this.set_property(prop.name, schema.get_int(key));
    }
    else if (type == typeof(uint)) {
      this.set_property(prop.name, schema.get_uint(key));
    }
    else if (type == typeof(double)) {
      this.set_property(prop.name, schema.get_double(key));
    }
    else if (type == typeof(bool)) {
      this.set_property(prop.name, schema.get_boolean(key));
    }
    else if (type == typeof(string)) {
      this.set_property(prop.name, schema.get_string(key));
    }
    else if (type == typeof(string[])) {
      this.set_property(prop.name, schema.get_strv(key));
    }
    else if (type == typeof(int64)) {
      this.set_property(prop.name, schema.get_value(key).get_int64());
    }
    else if (type == typeof(uint64)) {
      this.set_property(
        prop.name,
        schema.get_value(key).get_uint64()
      );
    }
    else if (type.is_enum()) {
      this.set_property(prop.name, schema.get_enum(key));
    }
    else if (type == typeof(Variant)) {
      this.set_property (prop.name, schema.get_value (key));
    }

    this.notify.connect(this.on_notify);
  }

  private void save_key (string key) {
    if (key == "schema" || this.updating) {
      return;
    }

    var obj_class = (ObjectClass) this.get_type().class_ref();
    var prop = obj_class.find_property(key);

    if (prop == null) {
      return;
    }

    this.notify.disconnect(this.on_notify);

    bool res = true;
    this.updating = true;

    var type = prop.value_type;
    var val = Value(type);
    this.get_property(prop.name, ref val);

    // Unsupported type
    if (val.type() != prop.value_type) {
      warning("Unsupported type %s for key %s", type.to_string(), key);
    }

    if (
      type == typeof(int) && val.get_int() != schema.get_int(key)
    ) {
      res = this.schema.set_int(key, val.get_int());
    }
    else if (
      type == typeof(uint) && val.get_uint() != schema.get_uint(key)
    ) {
      res = this.schema.set_uint(key, val.get_uint());
    }
    else if (
      type == typeof(double) &&
      val.get_double() != schema.get_double(key)
    ) {
      res = this.schema.set_double(key, val.get_double());
    }
    else if (
      type == typeof(bool) &&
      val.get_boolean() != schema.get_boolean(key)
    ) {
      res = this.schema.set_boolean(key, val.get_boolean());
    }
    else if (
      type == typeof(string) &&
      val.get_string() != schema.get_string(key)
    ) {
      res = this.schema.set_string(key, val.get_string());
    }
    else if (type == typeof(string[])) {
      string[] strv = null;
      this.get(key, &strv);
      if (strv != this.schema.get_strv(key)) {
        res = this.schema.set_strv(key, strv);
      }
    }
    else if (
      type == typeof(int64) &&
      val.get_int64() != schema.get_value(key).get_int64()
    ) {
      res = this.schema.set_value(
        key,
        new Variant.int64(val.get_int64())
      );
    }
    else if (
      type == typeof(uint64) &&
      val.get_uint64() != schema.get_value(key).get_uint64()
    ) {
      res = this.schema.set_value(
        key,
        new Variant.uint64(val.get_uint64())
      );
    }
    else if (
      type.is_enum() && val.get_enum() != this.schema.get_enum(key)
    ) {
      res = this.schema.set_enum(key, val.get_enum());
    }
    else if (type == typeof(Variant)) {
      res = this.schema.set_value (key, val.get_variant ());
    }

    if (!res) {
      warning("Could not update %s", key);
    }

    this.updating = false;
    this.notify.connect(this.on_notify);
  }

  private void on_notify (Object sender, ParamSpec prop) {
    this.save_key(prop.name);
  }
}
