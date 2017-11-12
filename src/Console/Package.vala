/*
 * Package.vala
 *
 * Copyright 2012-2017 Tony George <teejeetech@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA 02110-1301, USA.
 *
 *
 */

using GLib;
using Gee;

using TeeJee.Logging;
using TeeJee.FileSystem;
using TeeJee.ProcessHelper;
using TeeJee.System;
using TeeJee.Misc;

public class Package : GLib.Object {

	public string name = "";
	public string description = "";
	public string arch = "";

	public string server = "";
	public string repo = "";
	public string repo_section = "";
	public string status = "";
	public string section = "";
	public string version_installed = "";
	public string version_available = "";
	public string depends = "";
	public string gid = "";
	public string deb_file_name = "";
	public string deb_uri = "";
	public int64 deb_size = 0;
	public string deb_md5hash = "";

	//public bool is_selected = false;
	public bool is_available = false;
	public bool is_installed = false;
	public bool is_dist = false;
	public bool is_auto = false;
	public bool is_user = false;
	public bool is_manual = false;
	public bool is_deb = false;
	public bool is_foreign = false;

	public Package(string _name){
		name = _name;
	}
}
