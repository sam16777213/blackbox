/* Utils.vala
 *
 * Copyright 2019 Paulo Queiroz <pvaqueiroz@gmail.com>
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

namespace Marble
{
    /*
     * Copyright (C) 2012-2017 Granite Developers
     *
     * Adapted from https://github.com/elementary/granite which is licensed
     * under GPL-3.0-or-later.
     */
    public Gtk.CssProvider? get_css_provider_for_data(string data) {
      var provider = new Gtk.CssProvider();

#if VALA_0_58
    provider.load_from_data (data);
#else
    provider.load_from_data (data.data);
#endif

    return provider;
  }

  /*
   * Copyright (C) 2012-2017 Granite Developers
   *
   * Adapted from https://github.com/elementary/granite which is licensed
   * under GPL-3.0-or-later.
   */
  public void set_theming_for_data (
    Gtk.Widget widget,
    string data,
    string? class_name = null,
    int priority = Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
  ) {
    var provider = get_css_provider_for_data(data);

    var ctx = widget.get_style_context();

    if (provider != null) {
      ctx.add_provider(provider, priority);
    }

    if (class_name != null) {
      ctx.add_class(class_name);
    }
  }

  public void add_css_provider_from_resource (
    string resource,
    int priority = Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
    Gdk.Display display = Gdk.Display.get_default()
  ) {
    var provider = new Gtk.CssProvider();

    provider.load_from_resource(resource);
    Gtk.StyleContext.add_provider_for_display(display, provider, priority);
  }
}
