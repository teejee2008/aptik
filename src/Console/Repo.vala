/*
 * Repo.vala
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

public class Repo : GLib.Object {
	
	public string name = ""; // launchpad ppa name
	public string description = "";
	public string list_file_path = "";
	public string text = "";
	public string type = "";

	public bool is_selected = false;
	public bool is_installed = false;

	public Repo.from_name(string _name){
		name = _name;
	}

	public Repo.from_list_file(string file_path){
		list_file_path = file_path;
		name = file_basename(file_path).replace(".list","");
	}
}
