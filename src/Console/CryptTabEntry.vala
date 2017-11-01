/*
 * CryptTabEntry.vala
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

public class CryptTabEntry : GLib.Object {

	public string name = "";
	public string device = "";
	public string password = "";
	public string options = "";
	
	public bool is_selected = false;

	public string get_line(){
		return "%s\t%s\t%s\t%s".printf(name,device,password,options);
	}

	public void print_line(){
		log_msg("%-30s %-30s %-30s %-30s".printf(name,device,password,options));
	}

	public bool uses_keyfile {
		get {
			return (password.length > 0) && (password != "none") && !password.has_prefix("/dev/");
		}
	}
}

