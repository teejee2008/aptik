/*
 * FsTabEntry.vala
 *
 * Copyright 2017 Tony George <teejeetech@gmail.com>
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

using TeeJee.Logging;
using TeeJee.FileSystem;
using TeeJee.ProcessHelper;

public class FsTabEntry : GLib.Object {

	public string device = "";
	public string mount_point = "";
	public string fs_type = "";
	public string options = "";
	public string dump = "";
	public string pass = "";

	public bool is_selected = false;

	public string get_line(){
		return "%s\t%s\t%s\t%s\t%s\t%s".printf(device,mount_point,fs_type,options,dump,pass);
	}

	public void print_line(){
		log_msg("%-45s %-40s %-10s %-45s %2s %2s".printf(device,mount_point,fs_type,options,dump,pass));
	}
}

