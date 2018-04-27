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

	private bool dry_run = false;
	private bool redist = false;
	private string basepath = "";
	private User current_user;

	private bool apply_selections = false;
	private Gee.ArrayList<string> exclude_list = new Gee.ArrayList<string>();
	private Gee.ArrayList<string> include_list = new Gee.ArrayList<string>();
	
	public CronTaskManager(bool _dry_run, bool _redist, User _current_user){

		dry_run = _dry_run;
		redist = _redist;
		current_user = _current_user;
	}

	public string get_backup_path(){
		
		return path_combine(basepath, "cron");
	}
	
	// backup and restore ----------------------
	
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

	public bool backup_cron_tasks(string _basepath, string userlist, PackageManager mgr_pkg, bool _apply_selections){

		basepath = _basepath;

		apply_selections = _apply_selections;
		
		bool status = true;

		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Backup"), Messages.TASK_CRON));
		log_msg(string.nfill(70,'-'));
		
		string backup_path = init_backup_path();

		read_selections();

		// backup users -----------------------------------

		foreach(var user in get_users(userlist, true)){

			if (user.is_system){ continue; }

			if (exclude_list.contains(user.name)){ continue; }

			bool ok = backup_cron_tasks_for_user(backup_path + "/files", user);
			if (!ok){ status = false; }
		}
		
		log_msg(string.nfill(70,'-'));

		// backup system ------------------

		string exclude_list = save_exclude_list(backup_path);
		
		bool ok = rsync_copy("/etc", backup_path + "/files", exclude_list);

		if (!ok){
			status = false;
		}
		
		log_msg(string.nfill(70,'-'));

		update_permissions_for_backup_files(backup_path, dry_run);
		
		if (status){
			log_msg(Messages.BACKUP_OK);
		}
		else{
			log_error(Messages.BACKUP_ERROR);
		}

		//log_msg(string.nfill(70,'-'));

		return status;
	}

	public bool backup_cron_tasks_for_user(string backup_path, User user){

		string fname = redist ? "user" : user.name;
		
		string backup_file = path_combine(backup_path, "%s.crontab".printf(fname));
		
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

	public bool update_permissions_for_backup_files(string path, bool dry_run) {

		string cmd = "";

		int status = 0;

		// dirs -------------
		
		cmd = "find '%s' -type d -exec chmod a+rwx '{}' ';'".printf(path);

		log_debug("$ %s".printf(cmd));

		//log_msg("%s (0%s): (dirs) %s".printf(_("set permissions"), "a+rwx", path));
		
		if (!dry_run){
			status = Posix.system(cmd);
		}

		// files -------------
		
		cmd = "find '%s' -type f -exec chmod a+rw '{}' ';'".printf(path);

		log_debug("$ %s".printf(cmd));

		//log_msg("%s (0%s): (files) %s".printf(_("set permissions"), "a+rwx", path));
		
		if (!dry_run){
			status = Posix.system(cmd);
		}

		return (status == 0);
	}

	public string init_backup_path(){
		
		string backup_path = get_backup_path();
		
		if (!dir_exists(backup_path)){
			dir_create(backup_path);
			chmod(backup_path, "a+rwx");
		}

		string files_path = path_combine(backup_path, "files");
		dir_delete(files_path);
		dir_create(files_path);
		chmod(files_path, "a+rwx");
		
		return backup_path;
	}

	public string save_exclude_list(string backup_path){

		string exclude_list = path_combine(backup_path, "exclude.list");
		
		string txt = "";

		var exlist = new Gee.ArrayList<string>();
		
		if (App.dist_files.size > 0){

			foreach(string path in App.dist_files){
				
				if (path.has_prefix("/etc/cron.d/") || path.has_prefix("/etc/cron.hourly/")
				|| path.has_prefix("/etc/cron.daily/") || path.has_prefix("/etc/cron.weekly/")
				|| path.has_prefix("/etc/cron.monthly/")){

					string relpath = path["/etc/".length: path.length];
					
					txt += relpath + "\n";

					exlist.add(relpath);
				}
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

	public void read_selections(){

		include_list.clear();
		exclude_list.clear();
		
		if (!apply_selections){ return; }

		string backup_path = get_backup_path();

		string selections_list = path_combine(backup_path, "selections.list");

		if (!file_exists(selections_list)){ return; }

		foreach(string name in file_read(selections_list).split("\n")){
			if (name.has_prefix("+ ")){
				include_list.add(name[2:name.length]);
			}
			else if (name.has_prefix("- ")){
				exclude_list.add(name[2:name.length]);
			}
		}
	}
	
	// restore ----------------
	
	public bool restore_cron_tasks(string _basepath, string userlist, bool _apply_selections){

		basepath = _basepath;

		apply_selections = _apply_selections;
		
		bool status = true;

		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Restore"), Messages.TASK_CRON));
		log_msg(string.nfill(70,'-'));
		
		string backup_path = get_backup_path();
		
		if (!dir_exists(backup_path)) {
			string msg = "%s: %s".printf(Messages.DIR_MISSING, backup_path);
			log_error(msg);
			return false;
		}

		read_selections();
		
		// restore users -----------------------------------

		foreach(var user in get_users(userlist, false)){

			if (user.is_system){ continue; }

			if (exclude_list.contains(user.name)){ continue; }

			bool ok = restore_cron_tasks_for_user(backup_path + "/files", user);
			if (!ok){ status = false; }
		}
		
		log_msg(string.nfill(70,'-'));

		// restore system ------------------

		string exclude_list = save_exclude_list(backup_path);
		
		bool ok = rsync_copy(backup_path + "/files", "/etc", exclude_list);
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

	public bool restore_cron_tasks_for_user(string backup_path, User user){

		string fname = redist ? "user" : user.name;
		
		string backup_file = path_combine(backup_path, "%s.crontab".printf(fname));

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

		var mgr = new UserManager();
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
