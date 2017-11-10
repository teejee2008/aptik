
/*
 * User.vala
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

public class User : GLib.Object {

	public string name = "";
	public string password = "";
	public int uid = -1;
	public int gid = -1;
	public string user_info = "";
	public string home_path = "";
	public string shell_path = "";

	public string full_name = "";
	public string room_num = "";
	public string phone_work = "";
	public string phone_home = "";
	public string other_info = "";

	//public string
	public string shadow_line = "";
	public string pwd_hash = "";
	public string pwd_last_changed = "";
	public string pwd_age_min = "";
	public string pwd_age_max = "";
	public string pwd_warning_period = "";
	public string pwd_inactivity_period = "";
	public string pwd_expiraton_date = "";
	public string reserved_field = "";
	
	public bool is_selected = false;

	public User(string name){
		
		this.name = name;
	}

	public int add(bool dry_run){
		
		return UserManager.add_user(name, is_system, dry_run);
	}
	
	public bool is_system{
		get {
			return ((uid != 0) && (uid < 1000)) || (uid == 65534) || (name == "PinguyBuilder"); // 65534 - nobody
		}
	}

	public string get_primary_group_name(Gee.ArrayList<Group> groups){
		
		foreach(var grp in groups){
			if (grp.gid == gid){
				return grp.name;
			}
		}

		log_error("%s: %s".printf("Failed to find primary group for user", name));
		return name; // assume group name = user name
	}

	// get line ------------------------------------

	public string get_passwd_line(){
		string txt = "";
		txt += "%s".printf(name);
		txt += ":%s".printf(password);
		txt += ":%d".printf(uid);
		txt += ":%d".printf(gid);
		txt += ":%s".printf(user_info);
		txt += ":%s".printf(home_path);
		txt += ":%s".printf(shell_path);
		return txt;
	}

	public string get_shadow_line(){
		string txt = "";
		txt += "%s".printf(name);
		txt += ":%s".printf(pwd_hash);
		txt += ":%s".printf(pwd_last_changed);
		txt += ":%s".printf(pwd_age_min);
		txt += ":%s".printf(pwd_age_max);
		txt += ":%s".printf(pwd_warning_period);
		txt += ":%s".printf(pwd_inactivity_period);
		txt += ":%s".printf(pwd_expiraton_date);
		txt += ":%s".printf(reserved_field);
		return txt;
	}

	public int compare_fields(User b){

		// compares every field except name and id
		
		if ((password != b.password)
		|| (user_info != b.user_info)
		|| (home_path != b.home_path)
		|| (shell_path != b.shell_path)
		){
			return 1; // passwd mismatch
		}
		else if ((pwd_hash != b.pwd_hash)
		|| (pwd_last_changed != b.pwd_last_changed)
		|| (pwd_age_min != b.pwd_age_min)
		|| (pwd_age_max != b.pwd_age_max)
		|| (pwd_warning_period != b.pwd_warning_period)
		|| (pwd_inactivity_period != b.pwd_inactivity_period)
		|| (pwd_expiraton_date != b.pwd_expiraton_date)
		|| (reserved_field != b.reserved_field)
		){
			return -1; // shadow mismatch
		}
		
		return 0;
	}

	// update file ------------------------------------

	public bool update_passwd_file(bool dry_run){
		
		string file_path = "/etc/passwd";
		string txt = file_read(file_path);
		
		var txt_new = "";
		
		foreach(string line in txt.split("\n")){
			
			if (line.strip().length == 0) { continue; }
			
			string[] parts = line.split(":");

			if (parts.length != 7){
				log_error("'passwd' file contains a record with non-standard fields" + ": %d".printf(parts.length));
				return false;
			}
			
			if (parts[0].strip() == name){
				txt_new += get_passwd_line() + "\n";
			}
			else{
				txt_new += line + "\n";
			}
		}

		if (!dry_run){
			file_write(file_path, txt_new);
		}
		
		log_msg("%s %s: %s".printf(_("Updated"), "/etc/passwd", name));
		
		return true;
	}

	public bool update_shadow_file(bool dry_run){
		
		string file_path = "/etc/shadow";
		string txt = file_read(file_path);
		
		var txt_new = "";
		
		foreach(string line in txt.split("\n")){
			
			if (line.strip().length == 0) { continue; }
			
			string[] parts = line.split(":");

			if (parts.length != 9){
				log_error("'shadow' file contains a record with non-standard fields" + ": %d".printf(parts.length));
				return false;
			}
			
			if (parts[0].strip() == name){
				txt_new += get_shadow_line() + "\n";
			}
			else{
				txt_new += line + "\n";
			}
		}

		if (!dry_run){
			file_write(file_path, txt_new);
		}
		
		log_msg("%s %s: %s".printf(_("Updated"), "/etc/shadow", name));
		
		return true;
	}
}

