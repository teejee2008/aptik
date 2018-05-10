/*
 * DconfManager.vala
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
using TeeJee.System;
using TeeJee.Misc;

public class DconfManager : BackupManager {

	public DconfManager(LinuxDistro _distro, User _current_user, string _basepath, bool _dry_run, bool _redist, bool _apply_selections){

		base(_distro, _current_user, _basepath, _dry_run, _redist, _apply_selections, "dconf");
	}

	// list ----------------------

	public void dump_info(){

		string txt = "";

		var mgr = new UserManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.query_users(false);
		
		foreach(var user in mgr.users_sorted){
			
			if (user.is_system) { continue; }
			
			txt += "NAME='%s'".printf(user.name);
			
			txt += ",DESC='%s'".printf(user.full_name);

			txt += ",ACT='%s'".printf("1");
			
			txt += ",SENS='%s'".printf("1");
			
			txt += "\n";
		}

		log_msg(txt);
	}

	public void dump_info_backup(){

		if (!dir_exists(files_path)) {
			string msg = "%s: %s".printf(Messages.DIR_MISSING, files_path);
			log_error(msg);
			return;
		}

		string txt = "";

		var mgr = new UserManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.query_users(false);
		
		foreach(var user in mgr.users_sorted){
			
			if (user.is_system) { continue; }

			string bkup_file = path_combine(files_path, "%s.dconf-settings".printf(user.name));

			if (!file_exists(bkup_file)){ continue; }
			
			txt += "NAME='%s'".printf(user.name);
			
			txt += ",DESC='%s'".printf(user.full_name);

			txt += ",ACT='%s'".printf("1");
			
			txt += ",SENS='%s'".printf("1");
			
			txt += "\n";
		}

		log_msg(txt);
	}
	
	public void list_dconf_settings(string userlist){

		foreach(var user in get_users(userlist, false)){

			if (user.is_system){ continue; }

			string txt = "%s: %s%s\n".printf(_("dconf Settings"), user.name, (user.full_name.length > 0) ? " -- " + user.full_name : "");
			log_msg(txt);
			
			string cmd = "su -s /bin/bash -c 'dconf dump /' %s".printf(user.name);
			log_debug(cmd);
			Posix.system(cmd);

			log_msg(string.nfill(70,'-'));
		}
	}

	// backup ----------------------
	
	public bool backup_dconf_settings( string userlist){

		bool status = true;

		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Backup"), Messages.TASK_DCONF));
		log_msg(string.nfill(70,'-'));
		
		init_backup_path();

		read_selections();
		
		// backup -----------------------------------

		foreach(var user in get_users(userlist, true)){

			if (user.is_system){ continue; }

			if (exclude_list.contains(user.name)){ continue; }

			bool ok = backup_dconf_settings_for_user(files_path, user);
			if (!ok){ status = false; }
		}

		update_permissions_for_backup_files();

		if (status){
			log_msg(Messages.BACKUP_OK);
		}
		else{
			log_error(Messages.BACKUP_ERROR);
		}

		return status;
	}

	public bool backup_dconf_settings_for_user(string backup_path, User user){

		bool status = true;

		string fname = redist ? "user" : user.name;
		
		string backup_file = path_combine(backup_path, "%s.dconf-settings".printf(fname));
		file_delete(backup_file);
		
		string cmd = "su -s /bin/bash -c 'dconf dump /' %s".printf(user.name);
		log_debug(cmd);
		
		string std_out, std_err;
		int retval = exec_sync(cmd, out std_out, out std_err);
		status = (retval == 0);
		
		if (retval == 0){
			
			bool ok = file_write(backup_file, std_out);
			
			if (ok){
				log_msg("%s: (%s) %s".printf(_("Saved"), user.name, backup_file.replace(basepath, "$basepath")));
			}

			// ignore errrors (dconf db may be empty for some users) ----------
			
			//else {
			//	status = false;
			//	log_error("%s: (%s) %s".printf(_("Error"), user.name, backup_file.replace(basepath, "$basepath")));
			//}
		}
		else{
			log_error(std_err);
		}

		return status;
	}

	// restore ------------
	
	public bool restore_dconf_settings( string userlist){

		bool status = true;

		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Restore"), Messages.TASK_DCONF));
		log_msg(string.nfill(70,'-'));

		if (!dir_exists(backup_path)) {
			string msg = "%s: %s".printf(Messages.DIR_MISSING, backup_path);
			log_error(msg);
			return false;
		}

		read_selections();
		
		// backup -----------------------------------

		foreach(var user in get_users(userlist, false)){

			if (user.is_system){ continue; }

			if (exclude_list.contains(user.name)){ continue; }

			bool ok = restore_dconf_settings_for_user(backup_path, user);
			if (!ok){ status = false; }
		}

		if (status){
			log_msg(Messages.RESTORE_OK);
		}
		else{
			log_error(Messages.RESTORE_ERROR);
		}

		return status;
	}

	public bool restore_dconf_settings_for_user(string backup_path, User user){

		string fname = redist ? "user" : user.name;
		
		string backup_file = path_combine(files_path, "%s.dconf-settings".printf(fname));

		if (!file_exists(backup_file)) {
			string msg = "%s: %s".printf(Messages.FILE_MISSING, backup_file);
			log_error(msg);
			return false;
		}

		string temp_dir = user.home_path + "/.config/aptik";
		string temp_file = temp_dir + "/dconf.settings";

		dir_create(temp_dir);
		chown(temp_dir, user.name, user.name);
		
		file_copy(backup_file, temp_file, false);
		chown(temp_file, user.name, user.name);

		var startup = new StartupEntry(user.name, "aptik", "restore-dconf", 5);
		
		string cmd = "#!/bin/bash\n";
		cmd += "cd '%s'\n".printf(escape_single_quote(temp_dir));
		cmd += "dconf reset -f /\n";
		cmd += "dconf load / < dconf.settings\n";
		cmd += "rm -vf '%s'\n".printf(escape_single_quote(startup.STARTUP_DESKTOP_FILE));
		
		startup.create(cmd, true);
		
		log_msg("%s: (%s) %s".printf(_("Restored"), user.name, _("Created autostart script for next user login")));

		return true;
	}

	public Gee.ArrayList<User> get_users(string userlist, bool is_backup){

		var mgr = new UserManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.query_users(false);
		
		var users = new Gee.ArrayList<User>();
		
		if (redist && is_backup){
			users.add(current_user);
		}
		else if (userlist.length == 0){
			users = mgr.users_sorted;
		}
		else{
			foreach(string username in userlist.split(",")){
				foreach(var user in mgr.users_sorted){
					if (user.name == username){
						users.add(user);
						break;
					}
				}
			}
		}

		return users;
	}
}
