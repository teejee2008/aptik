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

public class CronTaskManager : BackupManager {

	public CronTaskManager(LinuxDistro _distro, User _current_user, string _basepath, bool _dry_run, bool _redist, bool _apply_selections){

		base(_distro, _current_user, _basepath, _dry_run, _redist, _apply_selections, "cron");
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

			string bkup_file = path_combine(files_path, "%s.crontab".printf(user.name));

			if (!file_exists(bkup_file)){ continue; }
			
			txt += "NAME='%s'".printf(user.name);
			
			txt += ",DESC='%s'".printf(user.full_name);

			txt += ",ACT='%s'".printf("1");
			
			txt += ",SENS='%s'".printf("1");
			
			txt += "\n";
		}

		log_msg(txt);
	}
	
	public void list_cron_tasks(string userlist){

		foreach(var user in get_users(userlist, false)){

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

	// backup ---------------------------
	
	public bool backup_cron_tasks(string userlist){

		bool status = true;

		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Backup"), Messages.TASK_CRON));
		log_msg(string.nfill(70,'-'));
		
		init_backup_path();
		
		read_selections();

		// backup users -----------------------------------

		foreach(var user in get_users(userlist, true)){

			if (user.is_system){ continue; }

			if (exclude_list.contains(user.name)){ continue; }

			bool ok = backup_cron_tasks_for_user(user);
			if (!ok){ status = false; }
		}
		
		log_msg(string.nfill(70,'-'));

		// backup system ------------------

		string exclude_list = save_exclude_list();
		
		bool ok = rsync_copy("/etc", files_path, exclude_list);

		if (!ok){
			status = false;
		}
		
		log_msg(string.nfill(70,'-'));

		update_permissions_for_backup_files();
		
		if (status){
			log_msg(Messages.BACKUP_OK);
		}
		else{
			log_error(Messages.BACKUP_ERROR);
		}

		//log_msg(string.nfill(70,'-'));

		return status;
	}

	public bool backup_cron_tasks_for_user(User user){

		string fname = redist ? "user" : user.name;
		
		string backup_file = path_combine(files_path, "%s.crontab".printf(fname));
		
		file_delete(backup_file);
		
		string cmd = "crontab -u %s -l > '%s'".printf(user.name, backup_file);

		int status = 0;
	
		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug("$ %s".printf(cmd));
			status = Posix.system(cmd);
		}
		
		if (status == 0){
			log_msg("%s: (%s) %s".printf(_("Saved"), user.name, backup_file.replace(basepath, "$basepath")));
		}
		else{
			log_error("%s (%s) %s".printf(_("Error"), user.name, backup_file.replace(basepath, "$basepath")));
		}

		return (status == 0);
	}

	public string save_exclude_list(){

		string exclude_list = path_combine(backup_path, "exclude.list");
		
		string txt = "";

		var exlist = new Gee.ArrayList<string>();
		
		if (App.dist_files_cron.size > 0){

			foreach(string path in App.dist_files_cron){
			
				string relpath = path["/etc/".length: path.length];
				
				txt += relpath + "\n";

				exlist.add(relpath);
			}
		}

		txt += "+ cron.d/***\n";
		txt += "+ cron.daily/***\n";
		txt += "+ cron.hourly/***\n";
		txt += "+ cron.monthly/***\n";
		txt += "+ cron.weekly/***\n";
		txt += "*\n";

		exlist.sort();
		foreach(var path in exlist){
			log_msg("%s: %s".printf(_("exclude"), path));
		}
		log_msg("");
		
		file_write(exclude_list, txt);
		log_msg("%s: %s".printf(_("saved"), exclude_list.replace(basepath, "$basepath")));
		log_msg("");
		
		return exclude_list;
	}

	// restore ----------------
	
	public bool restore_cron_tasks(string userlist){

		bool status = true;

		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Restore"), Messages.TASK_CRON));
		log_msg(string.nfill(70,'-'));
		
		if (!dir_exists(files_path)) {
			string msg = "%s: %s".printf(Messages.DIR_MISSING, files_path);
			log_error(msg);
			return false;
		}

		read_selections();
		
		// restore users -----------------------------------

		foreach(var user in get_users(userlist, false)){

			if (user.is_system){ continue; }

			if (exclude_list.contains(user.name)){ continue; }

			bool ok = restore_cron_tasks_for_user(user);
			if (!ok){ status = false; }
		}
		
		log_msg(string.nfill(70,'-'));

		// restore system ------------------

		string exclude_list = save_exclude_list();
		
		bool ok = rsync_copy(files_path, "/etc", exclude_list);
		if (!ok){ status = false; }

		log_msg(string.nfill(70,'-'));
		
		foreach(string dirname in new string[] { "cron.d", "cron.daily", "cron.hourly", "cron.monthly", "cron.weekly" }){ 
			string cron_dir = path_combine("/etc", dirname);
			update_permissions_for_cron_directory(cron_dir);
		}

		log_msg("");

		if (status){
			log_msg(Messages.RESTORE_OK);
		}
		else{
			log_error(Messages.RESTORE_ERROR);
		}

		log_msg(string.nfill(70,'-'));

		return status;
	}

	public bool restore_cron_tasks_for_user(User user){

		string fname = redist ? "user" : user.name;
		
		string backup_file = path_combine(files_path, "%s.crontab".printf(fname));

		if (!file_exists(backup_file)) {
			return true; // not an error
		}

		string cmd = "crontab -u %s '%s'".printf(user.name, escape_single_quote(backup_file));

		int status = 0;
	
		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug("$ %s".printf(cmd));
			status = Posix.system(cmd);
		}

		if (status == 0){
			log_msg("%s: (%s) %s".printf(_("Restored"), user.name, backup_file.replace(basepath, "$basepath")));
		}
		else{
			log_error("%s: (%s) %s".printf(_("Error"), user.name, backup_file.replace(basepath, "$basepath")));
		}
		
		return (status == 0);
	}

	public bool rsync_copy(string src_path, string dst_path, string exclude_list){

		// NOTE: copy links as links (no -L)

		string cmd = "rsync -avh '%s/' '%s/'".printf(escape_single_quote(src_path), escape_single_quote(dst_path));

		if (exclude_list.length > 0){
			cmd += " --exclude-from='%s'".printf(escape_single_quote(exclude_list));
		}

		int status = 0;
	
		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug("$ %s".printf(cmd));
			status = Posix.system(cmd);
		}
		
		return (status == 0);
	}

	public bool update_permissions_for_cron_directory(string path){

		if (dry_run){
			return true;
		}
		
		string permissions = "755"; // rwx r-x r-x

		if (path.has_suffix("cron.d")){
			permissions = "644"; // rw- r-- r-- not executable by anyone since these are not valid shell scripts
		}

		int status = 0;

		// update contents ---------------
		
		string cmd = "find '%s' -type f -exec chmod %s '{}' ';'".printf(path, permissions);
		log_debug("$ %s".printf(cmd));
		status = Posix.system(cmd);

		cmd = "find '%s' -exec chown -h %s '{}' ';'".printf(path, "root:root");
		log_debug("$ %s".printf(cmd));
		status = Posix.system(cmd);

		// update cron dir -------------
		
		cmd = "chmod 755 '%s'".printf(path);
		log_debug("$ %s".printf(cmd));
		status = Posix.system(cmd);

		cmd = "chown root:root '%s'".printf(path);
		log_debug("$ %s".printf(cmd));
		status = Posix.system(cmd);

		log_msg("%s: %s".printf(_("Updated permissions"), path));
		
		return (status == 0);
	}

	public bool update_owner_for_cron_directory(string path){

		string permissions = "755"; // rwx r-x r-x

		if (path.has_suffix("cron.d")){
			permissions = "644"; // rw- r-- r-- not executable by anyone since these are not valid shell scripts
		}

		log_msg("%s (0%s): %s".printf(_("Updating permissions"), permissions, path));
		
		string cmd = "find '%s' -type f -exec chown root:root '{}' ';'".printf(path);
		log_debug(cmd);

		int status = 0;
	
		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug("$ %s".printf(cmd));
			status = Posix.system(cmd);
		}
		
		return (status == 0);
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
