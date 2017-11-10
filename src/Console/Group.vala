/*
 * Group.vala
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

public class Group : GLib.Object {
	
	public string name = "";
	public string password = "";
	public int gid = -1;
	public string user_names = "";

	public string shadow_line = "";
	public string password_hash = "";
	public string admin_names = "";
	public string member_names = "";

	public bool is_selected = false;

	public Group(string name){
		
		this.name = name;
	}

	public int add(bool dry_run){
		
		return GroupManager.add_group(name, is_system, dry_run);
	}

	public int add_to_group(string user_name, bool dry_run){
		
		return GroupManager.add_user_to_group(user_name, name, dry_run);
	}
	
	public bool is_system{
		get {
			return (gid < 1000) || (gid == 65534); // 65534 - nogroup
		}
	}

	public int compare_fields(Group b){

		// compares every field except name and id
		
		if ((password != b.password)
		|| (user_names != b.user_names)
		){
			return 1; // group mismatch
		}
		else if ((password_hash != b.password_hash)
		|| (admin_names != b.admin_names)
		|| (member_names != b.member_names)
		){
			return -1; // gshadow mismatch
		}
		
		return 0;
	}

	public static string remove_missing_user_names(Gee.ArrayList<string> current_users, string user_list){

		string txt = "";
		
		foreach(string user_name in user_list.split(",")){
			
			if (!current_users.contains(user_name)){ continue; }

			if (txt.length > 0){ txt += ","; }

			txt += user_name;
		}

		return txt.strip();
	}

	// get line ------------------------------------

	public string get_group_line(){
		
		string txt = "";
		txt += "%s".printf(name);
		txt += ":%s".printf(password);
		txt += ":%d".printf(gid);
		txt += ":%s".printf(user_names);
		return txt;
	}

	public string get_gshadow_line(){
		
		string txt = "";
		txt += "%s".printf(name);
		txt += ":%s".printf(password_hash);
		txt += ":%s".printf(admin_names);
		txt += ":%s".printf(member_names);
		return txt;
	}

	// update file ------------------------------------

	public bool update_group_file(bool dry_run){
		
		string file_path = "/etc/group";
		string txt = file_read(file_path);
		
		var txt_new = "";
		foreach(string line in txt.split("\n")){
			if (line.strip().length == 0) {
				continue;
			}

			string[] parts = line.split(":");
			
			if (parts.length != 4){
				log_error("'group' file contains a record with non-standard fields" + ": %d".printf(parts.length));
				return false;
			}

			if (parts[0].strip() == name){
				txt_new += get_group_line() + "\n";
			}
			else{
				txt_new += line + "\n";
			}
		}

		if (!dry_run){
			file_write(file_path, txt_new);
		}
		
		log_msg("%s %s: %s".printf(_("Updated"), "/etc/group", name));
		
		return true;
	}

	public bool update_gshadow_file(bool dry_run){
		
		string file_path = "/etc/gshadow";
		string txt = file_read(file_path);
		
		var txt_new = "";
		foreach(string line in txt.split("\n")){
			if (line.strip().length == 0) {
				continue;
			}

			string[] parts = line.split(":");
			
			if (parts.length != 4){
				log_error("'gshadow' file contains a record with non-standard fields" + ": %d".printf(parts.length));
				return false;
			}

			if (parts[0].strip() == name){
				txt_new += get_gshadow_line() + "\n";
			}
			else{
				txt_new += line + "\n";
			}
		}

		if (!dry_run){
			file_write(file_path, txt_new);
		}
		
		log_msg("%s %s: %s".printf(_("Updated"), "/etc/gshadow", name));
		
		return true;
	}
}

