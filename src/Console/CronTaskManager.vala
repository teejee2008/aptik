/*
 * CronTaskManager.vala
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
using TeeJee.Misc;

public class CronTaskManager : GLib.Object {

	public bool dry_run = false;

	public CronTaskManager(bool _dry_run = false){

		dry_run = _dry_run;
	}
	
	// backup and restore ----------------------
	
	public void list_cron_tasks(string userlist){

		foreach(var user in get_users(userlist)){

			if (user.is_system){ continue; }

			string txt = "%s: %s%s\n".printf(_("crontab"), user.name, (user.full_name.length > 0) ? " -- " + user.full_name : "");
			log_msg(txt);
			
			string cmd = "su -s /bin/bash -c 'crontab -l' %s".printf(user.name);
			log_debug(cmd);
			Posix.system(cmd);

			log_msg(string.nfill(70,'-'));
		}

		string txt = "%s:\n".printf(_("cron and anacron scripts"));
		log_msg(txt);

		foreach(string subdir in new string[] { "cron.d", "cron.daily", "cron.hourly", "cron.monthly", "cron.weekly" }){

			string cron_path = "/etc/%s".printf(subdir);
			
			var list = dir_list_names(cron_path, true);
			
			foreach(string path in list){
				
				if (file_basename(path) == ".placeholder"){ continue; }
				
				log_msg(path);
			}
		}

		log_msg(string.nfill(70,'-'));
	}

	public bool backup_cron_tasks(string basepath, string userlist){

		bool status = true;

		log_msg("%s\n".printf(_("Saving cron tasks...")));
		
		string backup_path = path_combine(basepath, "cron");
		dir_create(backup_path);

		// backup -----------------------------------

		foreach(var user in get_users(userlist)){

			if (user.is_system){ continue; }

			bool ok = backup_cron_tasks_for_user(backup_path, user);
			if (!ok){ status = false; }
		}
		
		log_msg(string.nfill(70,'-'));

		// backup system folders -------------------------

		foreach(string subdir in new string[] { "cron.d", "cron.daily", "cron.hourly", "cron.monthly", "cron.weekly" }){

			string cron_path = "/etc/%s".printf(subdir);
			
			string backup_subdir = path_combine(backup_path, subdir);
			dir_create(backup_subdir);

			log_msg("%s: /etc/%s\n".printf(_("Saving"), subdir));

			bool ok = rsync_copy(cron_path, backup_subdir);
			if (!ok){ status = false; }
			
			log_msg(string.nfill(70,'-'));
		}
		
		if (status){
			log_msg(Message.BACKUP_OK);
		}
		else{
			log_error(Message.BACKUP_ERROR);
		}

		log_msg(string.nfill(70,'-'));

		return status;
	}

	public bool backup_cron_tasks_for_user(string backup_path, User user){

		bool status = true;
		
		string backup_file = path_combine(backup_path, "%s.crontab".printf(user.name));
		file_delete(backup_file);
		
		string cmd = "su -s /bin/bash -c 'crontab -l' %s".printf(user.name);
		log_debug(cmd);
		
		string std_out, std_err;
		int retval = exec_sync(cmd, out std_out, out std_err);
		status = (retval == 0);
		
		if (retval == 0){
			
			bool ok = file_write(backup_file, std_out);
			
			if (ok){
				log_msg("%s: (%s) %s".printf(_("Saved"), user.name, backup_file));
			}
			else {
				status = false;
				log_error("%s (%s) %s".printf(_("Error"), user.name, backup_file));
			}
		}
		else{
			log_error(std_err);
			file_write(backup_file, "");
		}

		return status;
	}

	public bool restore_cron_tasks(string basepath, string userlist){

		bool status = true;

		log_msg(_("Restoring cron tasks..."));
		
		string backup_path = path_combine(basepath, "cron");
		
		if (!dir_exists(backup_path)) {
			string msg = "%s: %s".printf(Message.DIR_MISSING, backup_path);
			log_error(msg);
			return false;
		}
		
		// backup -----------------------------------

		foreach(var user in get_users(userlist)){

			if (user.is_system){ continue; }

			bool ok = restore_cron_tasks_for_user(backup_path, user);
			if (!ok){ status = false; }
		}
		
		log_msg(string.nfill(70,'-'));

		// restore system folders -------------------------

		foreach(string subdir in new string[] { "cron.d", "cron.daily", "cron.hourly", "cron.monthly", "cron.weekly" }){

			string cron_path = "/etc/%s".printf(subdir);
			
			string backup_subdir = path_combine(backup_path, subdir);
			if (!dir_exists(backup_subdir)){ continue; }
			
			log_msg("%s: /etc/%s\n".printf(_("Restoring"), subdir));

			bool ok = rsync_copy(backup_subdir, cron_path);
			if (!ok){ status = false; }

			log_msg("");
			
			update_permissions_for_cron_directory(cron_path);
			
			log_msg(string.nfill(70,'-'));
		}

		if (status){
			log_msg(Message.RESTORE_OK);
		}
		else{
			log_error(Message.RESTORE_ERROR);
		}

		log_msg(string.nfill(70,'-'));

		return status;
	}

	public bool restore_cron_tasks_for_user(string backup_path, User user){

		bool status = true;
		
		string backup_file = path_combine(backup_path, "%s.crontab".printf(user.name));

		if (!file_exists(backup_file)) {
			string msg = "%s: %s".printf(Message.FILE_MISSING, backup_file);
			log_error(msg);
			return false;
		}
		
		string cmd = "su -s /bin/bash -c \"crontab '%s'\" %s".printf(escape_single_quote(backup_file), user.name);
		log_debug(cmd);

		int retval = Posix.system(cmd);
		status = (retval == 0);

		if (status){
			log_msg("%s: (%s) %s".printf(_("Restored"), user.name, backup_file));
		}
		else{
			log_error("%s: (%s) %s".printf(_("Error"), user.name, backup_file));
		}
		
		return status;
	}

	public bool rsync_copy(string src_path, string dst_path){

		// NOTE: copy links as links (no -L)
		
		string cmd = "rsync -avh '%s/' '%s/'".printf(escape_single_quote(src_path), escape_single_quote(dst_path));
		log_debug(cmd);
		
		int retval = Posix.system(cmd);
		return (retval == 0);
	}

	public bool update_permissions_for_cron_directory(string path){

		string permissions = "755"; // rwx r-x r-x

		if (path.has_suffix("cron.d")){
			permissions = "644"; // rw- r-- r-- not executable by anyone since these are not valid shell scripts
		}

		log_msg("%s (0%s): %s".printf(_("Updating permissions"), permissions, path));
		
		string cmd = "find '%s' -type f -exec chmod %s '{}' ';'".printf(path, permissions);
		log_debug(cmd);
		int retval = Posix.system(cmd);
		return (retval == 0);
	}

	public Gee.ArrayList<User> get_users(string userlist){

		var mgr = new UserManager();
		mgr.query_users(false);

		var users = new Gee.ArrayList<User>();
		
		if (userlist.length == 0){
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
