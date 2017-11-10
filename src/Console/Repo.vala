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
	public string deb_line = "";
	public string deb_src_line = "";

	public bool is_selected = false;
	public bool is_installed = false;
	public bool is_disabled = false;

	public Repo.from_name(string _name){
		
		name = _name;
	}

	public Repo.from_list_file_debian(string file_path){
		
		list_file_path = file_path;
		
		name = file_basename(file_path).replace(".list","");
		
		read_lines_debian(file_path);
		
		if ((deb_line.length == 0) || (deb_line.strip().has_prefix("#"))){
			is_disabled = true;
			description = "(disabled)";
		}
	}

	private void read_lines_debian(string file_path){

		if (!file_exists(file_path)){ return; }

		foreach(string line in file_read(file_path).split("\n")){

			if (line.strip().length == 0){ continue; }
			
			var match = regex_match("""^[ \t]*#*[ \t]*deb (.*)""", line);
					
			if (match != null){
				deb_line = line;
				continue;
			}

			var match2 = regex_match("""^[ \t]*#*[ \t]*deb-src (.*)""", line);
					
			if (match2 != null){
				deb_src_line = line;
			}
		}
	}

	public string suggested_list_file_name(){

		if (deb_line.length == 0){ return ""; }

		string list_name = "";

		// samples:
		// deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main
		// deb https://deb.opera.com/opera-developer/ stable non-free #Opera Browser (final releases)
		// deb https://download.sublimetext.com/ apt/stable/
		
		var match = regex_match("""deb .*https*:\/\/([^ ]+) ([^#]+)""", deb_line);
					
		if (match != null){
			
			string domain = match.fetch(1).strip();
			if (domain.has_suffix("/")){ domain = domain[0:domain.length - 1]; }
			
			string channels = match.fetch(2).strip();
			if (channels.has_suffix("/")){ channels = channels[0:channels.length - 1]; }
			
			list_name += domain.replace("/","_");

			if (!channels.contains("/")){
				list_name += "_dists";
			}

			list_name += "_%s".printf(channels.replace("/","_").replace(" ","_"));
		}

		return list_name;
	}
}
