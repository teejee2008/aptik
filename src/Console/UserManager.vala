/*
 * UserManager.vala
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

public class UserManager : GLib.Object {
	
	public Gee.HashMap<string,User> users;

	public bool dry_run = false;
	
	public UserManager(bool _dry_run = false){

		dry_run = _dry_run;

		users = new Gee.HashMap<string,User>();
		
		//query_users(query_passwords);
	}

	public void query_users(bool query_passwords){
		
		if (query_passwords){
		    read_users_from_file("/etc/passwd","/etc/shadow","");
		}
		else{
			read_users_from_file("/etc/passwd","","");
		}
	}

	public Gee.ArrayList<User> users_sorted {
		
		owned get{
			
			var list = new Gee.ArrayList<User>();
		
			foreach(var user in users.values) {
				list.add(user);
			}

			list.sort((a, b) => {
				return strcmp(a.name, b.name);
			});

			return list;
		}
	}

	public Gee.ArrayList<string> user_names_sorted {
		
		owned get{
			
			var list = new Gee.ArrayList<string>();
		
			foreach(var user in users_sorted) {
				list.add(user.name);
			}

			return list;
		}
	}

	public void read_users_from_file(string passwd_file, string shadow_file, string password){

		// read 'passwd' file ---------------------------------
		
		string txt = "";

		txt = file_read(passwd_file);

		if (txt.length == 0){
			log_error("%s: %s".printf(_("Failed to read file"),passwd_file));
			return;
		}

		foreach(string line in txt.split("\n")){
			
			if ((line == null) || (line.length == 0)){ continue; }
			
			parse_line_passwd(line);
		}

		if (shadow_file.length == 0){ return; }

		// read 'shadow' file ---------------------------------
		
		txt = "";
		
		txt = file_read(shadow_file);

		if (txt.length == 0){ return; }

		foreach(string line in txt.split("\n")){
			
			if ((line == null) || (line.length == 0)){ continue; }
			
			parse_line_shadow(line);
		}

		log_debug("read_users_from_file(): %d".printf(users.size));
	}

	public void read_users_from_folder(string backup_path){

		log_debug("backup_path=%s".printf(backup_path));

		var list = dir_list_names(backup_path, true);
		
		foreach(string backup_file in list){

			string file_name = file_basename(backup_file);

			if (!file_name.has_suffix(".passwd")){ continue; }

			parse_line_passwd(file_read(backup_file)); 
		}

		foreach(string backup_file in list){

			string file_name = file_basename(backup_file);

			if (!file_name.has_suffix(".shadow")){ continue; }

			parse_line_shadow(file_read(backup_file));
		}

		log_debug("read_users_from_folder(): %d".printf(users.size));
	}

	private void parse_line_passwd(string line){
		
		if ((line == null) || (line.length == 0)){ return; }
		
		User user = null;

		//teejee:x:504:504:Tony George:/home/teejee:/bin/bash
		string[] fields = line.split(":");

		if (fields.length == 7){
			
			user = new User(fields[0].strip());
			user.password = fields[1].strip();
			user.uid = int.parse(fields[2].strip());
			user.gid = int.parse(fields[3].strip());
			user.user_info = fields[4].strip();
			user.home_path = fields[5].strip();
			user.shell_path = fields[6].strip();

			string[] arr = user.user_info.split(",");
			if (arr.length >= 1){
				user.full_name = arr[0];
			}
			if (arr.length >= 2){
				user.room_num = arr[1];
			}
			if (arr.length >= 3){
				user.phone_work = arr[2];
			}
			if (arr.length >= 4){
				user.phone_home = arr[3];
			}
			if (arr.length >= 5){
				user.other_info = arr[4];
			}

			users[user.name] = user;
		}
		else{
			log_error("'passwd' file contains a record with non-standard fields" + ": %d".printf(fields.length));
		}
	}

	private User? parse_line_shadow(string line){
		
		if ((line == null) || (line.length == 0)){ return null; }
		
		User user = null;

		//root:$1$Etg2ExUZ$F9NTP7omafhKIlqaBMqng1:15651:0:99999:7:::
		//<username>:$<hash-algo>$<salt>$<hash>:<last-changed>:<change-interval-min>:<change-interval-max>:<change-warning-interval>:<disable-expired-account-after-days>:<days-since-account-disbaled>:<not-used>

		string[] fields = line.split(":");

		if (fields.length == 9){
			string name = fields[0].strip();
			if (users.has_key(name)){
				user = users[name];
				user.shadow_line = line;
				user.pwd_hash = fields[1].strip();
				user.pwd_last_changed = fields[2].strip();
				user.pwd_age_min = fields[3].strip();
				user.pwd_age_max = fields[4].strip();
				user.pwd_warning_period = fields[5].strip();
				user.pwd_inactivity_period = fields[6].strip();
				user.pwd_expiraton_date = fields[7].strip();
				user.reserved_field = fields[8].strip();
				return user;
			}
			else{
				log_error("user in file 'shadow' does not exist in file 'passwd'" + ": %s".printf(name));
				return null;
			}
		}
		else{
			log_error("'shadow' file contains a record with non-standard fields" + ": %d".printf(fields.length));
			return null;
		}
	}

	public static int add_user(string name, bool system_account, bool dry_run){
		
		int status = 0;
		
		string cmd = "adduser%s --gecos '' --disabled-login %s".printf((system_account ? " --system" : ""), name);

		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug("$ %s".printf(cmd));
			status = Posix.system(cmd);
		}
		
		return status;
	}

	// backup and restore ----------------------
	
	public void list_users(bool all){
		
		foreach(var user in users_sorted){
			
			if (!all && user.is_system) { continue; }

			string txt = (user.full_name.length > 0) ? "-- " + user.full_name : "" ;
			log_msg("%5d %-20s %s".printf(user.uid, user.name, txt));
		}
	}

	public bool backup_users(string basepath){

		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Backup"), Messages.TASK_USERS));
		log_msg(string.nfill(70,'-'));
		
		string backup_path = path_combine(basepath, "users");
		dir_create(backup_path);
		chmod(backup_path, "a+rwx");
		
		bool status = true;

		foreach(var user in users_sorted){
			
			if (user.is_system) { continue; }
	
			string backup_file = path_combine(backup_path, "%s.passwd".printf(user.name));
			bool ok = file_write(backup_file, user.get_passwd_line());
			chmod(backup_file, "a+rw");
			
			if (ok){ log_msg("%s: %s".printf(_("Saved"), backup_file)); }
			else{ status = false; }

			backup_file = path_combine(backup_path, "%s.shadow".printf(user.name));
			ok = file_write(backup_file, user.get_shadow_line());
			chmod(backup_file, "a+rw");
			
			if (ok){ log_msg("%s: %s".printf(_("Saved"), backup_file)); }
			else{ status = false; }
		}

		if (status){
			log_msg(Messages.BACKUP_OK);
		}
		else{
			log_error(Messages.BACKUP_ERROR);
		}

		//log_msg(string.nfill(70,'-'));

		return status;
	}

	public bool restore_users(string basepath){

		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Restore"), Messages.TASK_USERS));
		log_msg(string.nfill(70,'-'));
		
		string backup_path = path_combine(basepath, "users");
		
		if (!dir_exists(backup_path)) {
			string msg = "%s: %s".printf(Messages.DIR_MISSING, backup_path);
			log_error(msg);
			return false;
		}
		
		bool status = true, ok;
		
		ok = add_missing_users_from_backup(basepath);
		if (!ok){ status = false; }
		
		ok = update_users_from_backup(basepath);
		if (!ok){ status = false; }

		return status;
	}
	
	private bool add_missing_users_from_backup(string basepath){

		log_debug("add_missing_users_from_backup()");

		string backup_path = path_combine(basepath, "users");
		
		if (!dir_exists(backup_path)) {
			string msg = "%s: %s".printf(Messages.DIR_MISSING, backup_path);
			log_error(msg);
			return false;
		}

		bool status = true, ok;
		
		query_users(true);
		
		var mgr = new UserManager(dry_run);
		mgr.read_users_from_folder(backup_path);

		foreach(var user in mgr.users_sorted){
			
			if (users.has_key(user.name)){ continue; }

			ok = (user.add(dry_run) == 0);

			if (!ok){
				log_error(Messages.USER_ADD_ERROR + ": %s".printf(user.name));
				status = false;
			}
			else{
				log_msg(Messages.USER_ADD_OK + ": %s".printf(user.name));
			}
			log_msg(string.nfill(70,'-'));
		}

		return status;
	}

	private bool update_users_from_backup(string basepath){

		log_debug("update_users_from_backup()");

		string backup_path = path_combine(basepath, "users");
		
		if (!dir_exists(backup_path)) {
			string msg = "%s: %s".printf(Messages.DIR_MISSING, backup_path);
			log_error(msg);
			return false;
		}

		bool status = true;
		
		query_users(true);

		var mgr = new UserManager(dry_run);
		mgr.read_users_from_folder(backup_path);
		
		foreach(var old_user in mgr.users_sorted){

			if (!users.has_key(old_user.name)){ continue; }
			
			var user = users[old_user.name];

			if (user.compare_fields(old_user) > 0){
				// passwd mismatch
				user.password = old_user.password;
				user.user_info = old_user.user_info;
				user.home_path = old_user.home_path;
				user.shell_path = old_user.shell_path;
				// keep name, uid, gid

				bool ok = user.update_passwd_file(dry_run);
				if (!ok){ status = false; }
			}

			if (user.compare_fields(old_user) < 0){
				// shadow mismatch
				user.pwd_hash = old_user.pwd_hash;
				user.pwd_last_changed = old_user.pwd_last_changed;
				user.pwd_age_min = old_user.pwd_age_min;
				user.pwd_age_max = old_user.pwd_age_max;
				user.pwd_warning_period = old_user.pwd_warning_period;
				user.pwd_inactivity_period = old_user.pwd_inactivity_period;
				user.pwd_expiraton_date = old_user.pwd_expiraton_date;
				user.reserved_field = old_user.reserved_field;
				// keep name
				
				bool ok = user.update_shadow_file(dry_run);
				if (!ok){ status = false; }
			}
		}

		return status;
	}
}

