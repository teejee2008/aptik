/*
 * UserHomeDataManager.vala
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

public class UserHomeDataManager : GLib.Object {
	
	private bool dry_run = false;
	private string basepath = "";
	private bool use_xz = false;
	private bool redist = false;
	private User current_user;
	
	public UserHomeDataManager(bool _dry_run, bool _redist, User _current_user){

		dry_run = _dry_run;
		redist = _redist;
		current_user = _current_user;
	}

	// backup and restore ----------------------
	
	public bool backup_home(string _basepath, string userlist, bool exclude_hidden, bool _use_xz){

		basepath = _basepath;

		use_xz = _use_xz;
		
		string backup_path = path_combine(basepath, "home");

		if (redist){ dir_delete(backup_path); } // delete existing backups
		
		dir_create(backup_path);
		chmod(backup_path, "a+rwx");
		
		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Backup"), Messages.TASK_HOME));
		log_msg(string.nfill(70,'-'));

		bool status = true;

		var users = get_users(userlist, true);

		// backup --------------------------------------
		
		bool ok = backup_home_tar(backup_path, users, current_user, exclude_hidden);

		if (!ok){ status = false; }
		
		if (status){
			log_msg(Messages.BACKUP_OK);
		}
		else{
			log_error(Messages.BACKUP_ERROR);
		}

		return status;
	}

	public bool backup_home_tar(string backup_path, Gee.ArrayList<User> users, User current_user, bool exclude_hidden){

		bool status = true;
		int retval = 0;
		
		foreach(var user in users){

			if (user.is_system){ continue; }

			log_msg("%s: %s ~ %s\n".printf(_("User"), user.name, user.full_name));
			
			if (!dir_exists(user.home_path)){
				log_error("%s: %s".printf(Messages.DIR_MISSING, user.home_path));
				log_msg(string.nfill(70,'-'));
				continue;
			}
			
			string backup_path_user = "";

			if (redist){
				backup_path_user = backup_path;
			}
			else{
				path_combine(backup_path, user.name);
				dir_delete(backup_path_user); // remove existing backups if any
				dir_create(backup_path_user);
				chmod(backup_path_user, "a+rwx");
			}

			// save exclude list -----------------------
			
			var exclude_list = path_combine(backup_path_user, "exclude.list");
			if (file_exists(exclude_list)){
				file_delete(exclude_list);
			}
			file_write(exclude_list, exclude_list_create(user, exclude_hidden, true));
			chmod(exclude_list, "a+rw");
			
			// prepare -----------------------------------------

			string tar_file = path_combine(backup_path_user, "data.tar." + (use_xz ? "xz" : "gz"));

			string tar_file_gz = path_combine(backup_path_user, "data.tar.gz");

			string tar_file_xz = path_combine(backup_path_user, "data.tar.xz");

			if (file_exists(tar_file_gz)){
				file_delete(tar_file_gz);
			}

			if (file_exists(tar_file_xz)){
				file_delete(tar_file_xz);
			}

			string compressor = use_xz ? "xz" : "gzip";

			// create script -----------------------------------------
			
			string temp_file = tar_file + ".temp";
			
			var cmd = "";

			cmd += "tar cf -";

			cmd += " --exclude-from='%s'".printf(escape_single_quote(exclude_list));

			cmd += " -C '%s'".printf(escape_single_quote(file_parent(user.home_path)));
			
			cmd += " '%s'".printf(escape_single_quote(file_basename(user.home_path)));

			//cmd += " 2>/dev/null";

			cmd += " | pv -s $(du -sb '%s' | awk '{print $1}')".printf(escape_single_quote(user.home_path));

			cmd += " | %s > '%s'".printf(compressor, escape_single_quote(temp_file));

			// execute ---------------------------------

			log_msg("%s: '%s'\n".printf(_("Archiving"), user.home_path));
			
			if (dry_run){
				log_msg("$ %s".printf(cmd));
			}
			else{
				log_debug("$ %s".printf(cmd));
				retval = Posix.system(cmd);
			}
			
			if (retval != 0){
				status = false;
				file_delete(temp_file);
				log_msg("Deleted: %s".printf(temp_file.replace(basepath, "$basepath/")));
			}
			else{
				file_move(temp_file, tar_file, false);
				chmod(tar_file, "a+rw");
				log_msg("Created: %s".printf(tar_file.replace(basepath, "$basepath/")));
			}

			log_msg(string.nfill(70,'-'));
		}

		return status;
	}

	public bool backup_home_duplicity(string backup_path, Gee.ArrayList<User> users, string _password, bool full_backup, bool exclude_hidden){

		string password = _password;
		
		bool status = true;
		int retval = 0;
		
		foreach(var user in users){

			if (user.is_system){ continue; }

			log_msg("%s: %s ~ %s\n".printf(_("User"), user.name, user.full_name));
			
			if (!dir_exists(user.home_path)){
				log_error("%s: %s".printf(Messages.DIR_MISSING, user.home_path));
				log_msg(string.nfill(70,'-'));
				continue;
			}
			
			var backup_path_user = path_combine(backup_path, user.name);
			dir_create(backup_path_user);

			// remove TAR backup if any
			string tar_file = path_combine(backup_path_user, "data.tar.gz");
			file_delete(tar_file);

			// save exclude list -----------------------
			
			var exclude_list = path_combine(backup_path_user, "exclude.list");
			if (file_exists(exclude_list)){
				file_delete(exclude_list);
			}
			file_write(exclude_list, exclude_list_create(user, exclude_hidden, false));
 
			// check for existing backup -----------------------
			
			var list = dir_list_names(backup_path_user, false);
			bool backup_found = false;
			foreach(var name in list){
				if (name.has_suffix(".manifest.gpg") || name.has_suffix(".difftar.gpg") || name.has_suffix(".sigtar.gpg")){
					backup_found = true;
					break;
				}
			}

			// create script ---------------------------
			
			var cmd = "";

			if (password.length == 0){ password = "aptik"; } 
			
			cmd += "export PASSPHRASE='%s' ; ".printf(escape_single_quote(password));
			
			cmd += "duplicity";

			if (full_backup || !backup_found){
				cmd += " full";
			}
			else{
				cmd += " incr";
			}

			cmd += " --verbosity i --force";
			
			cmd += " --exclude-filelist '%s'".printf(escape_single_quote(exclude_list));

			cmd += " '%s'".printf(escape_single_quote(user.home_path));

			cmd += " 'file://%s' ; ".printf(escape_single_quote(backup_path_user));

			cmd += "unset PASSPHRASE\n";

			// execute ---------------------------------

			if (dry_run){
				log_msg("$ %s".printf(cmd));
			}
			else{
				log_debug("$ %s".printf(cmd));
				retval = Posix.system(cmd);
			}
			
			if (retval != 0){ status = false; }

			log_msg(string.nfill(70,'-'));
		}

		return status;
	}

	public string exclude_list_create(User user, bool exclude_hidden, bool tar_format){
		
		string txt = "";

		var list = new Gee.ArrayList<string>();
		
		list.add(path_combine(user.home_path, ".thumbnails"));
		list.add(path_combine(user.home_path, ".cache"));
		list.add(path_combine(user.home_path, ".dbus"));
		list.add(path_combine(user.home_path, ".gvfs"));
		list.add(path_combine(user.home_path, ".config/dconf/user"));
		list.add(path_combine(user.home_path, ".local/share/Trash"));
		list.add(path_combine(user.home_path, ".local/share/trash"));
		list.add(path_combine(user.home_path, ".mozilla/firefox/*.default/Cache"));
		list.add(path_combine(user.home_path, ".mozilla/firefox/*.default/OfflineCache"));
		list.add(path_combine(user.home_path, ".opera/cache"));
		list.add(path_combine(user.home_path, ".kde/share/apps/kio_http/cache"));
		list.add(path_combine(user.home_path, ".kde/share/cache/http"));

		if (exclude_hidden){
			list.add(path_combine(user.home_path, ".*"));
		}

		int index = file_parent(user.home_path).length + 1; // +1 for / after parent path
		
		foreach(var item in list){
			if (tar_format){
				txt += "%s\n".printf(item[index:item.length]);
			}
			else{
				txt += "%s\n".printf(item);
			}
		}

		if (dry_run || LOG_DEBUG){
			log_msg("Exclude:\n%s\n".printf(txt));
		}

		return txt;
	}

	public bool restore_home(string _basepath, string userlist){

		basepath = _basepath;
		
		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Restore"), Messages.TASK_HOME));
		log_msg(string.nfill(70,'-'));
		
		string backup_path = path_combine(basepath, "home");

		if (!dir_exists(backup_path)) {
			string msg = "%s: %s".printf(Messages.DIR_MISSING, backup_path);
			log_error(msg);
			return false;
		}

		bool status = true;

		var users = get_users(userlist, false);

		// restore ----------------------------------------

		bool ok = restore_home_tar(backup_path, users, current_user);

		if (!ok){ status = false; }
		
		if (status){
			log_msg(Messages.RESTORE_OK);
		}
		else{
			log_error(Messages.RESTORE_ERROR);
		}

		return status;
	}

	public bool restore_home_tar(string backup_path, Gee.ArrayList<User> users, User current_user){

		bool status = true;

		var grpmgr = new GroupManager(dry_run);
		grpmgr.query_groups(false);

		string backup_path_user = "";
		
		foreach(var user in users){

			if (user.is_system){ continue; }

			log_msg("%s: %s ~ %s\n".printf(_("User"), user.name, user.full_name));
			
			if (!dir_exists(user.home_path)){
				log_error("%s: %s".printf(Messages.DIR_MISSING, user.home_path));
				log_msg(string.nfill(70,'-'));
				continue;
			}

			if (redist){
				backup_path_user = backup_path;
			}
			else{
				backup_path_user = path_combine(backup_path, user.name);
			}
			
			if (!dir_exists(backup_path_user)){
				log_error("%s: %s".printf(Messages.DIR_MISSING, user.home_path));
				log_error(_("No backup found for this user"));
				log_msg(string.nfill(70,'-'));
				continue;
			}

			// prepare ------------------------------------------
			
			string tar_file_gz = path_combine(backup_path_user, "data.tar.gz");

			string tar_file_xz = path_combine(backup_path_user, "data.tar.xz");

			string tar_file = "";
			
			if (file_exists(tar_file_xz)){
				tar_file = tar_file_xz;
			}
			else if (file_exists(tar_file_gz)){
				tar_file = tar_file_gz;
			}
			else {
				log_error("%s: %s".printf(Messages.FILE_MISSING, tar_file_gz));
				log_error(_("No backup found"));
				log_msg(string.nfill(70,'-'));
				continue;
			}

			// save exclude list -----------------------
			
			//var exclude_list = path_combine(backup_path_user, "exclude.list");
			//if (file_exists(exclude_list)){
			//	file_delete(exclude_list);
			//}
			//file_write(exclude_list, exclude_list_create(user));

			// create script ---------------------------

			var cmd = "";

			cmd += "pv '%s' | ".printf(escape_single_quote(tar_file));
			
			cmd += "tar xf -";
			
			cmd += " -C '%s'".printf(escape_single_quote(file_parent(user.home_path)));

			//cmd += " >/dev/null 2>&1";

			// execute ---------------------------------

			int retval = 0;

			log_msg("%s '%s'...\n".printf(_("Extracting"), user.home_path));
			
			if (dry_run){
				log_msg("$ %s".printf(cmd));
			}
			else{
				log_debug("$ %s".printf(cmd));
				retval = Posix.system(cmd);
			}
			
			if (retval != 0){ status = false; }

			// update ownership --------------------------

			update_owner_for_directory_contents(user, grpmgr.groups_sorted);

			log_msg(string.nfill(70,'-'));
		}

		return status;
	}

	public bool restore_home_duplicity(string backup_path, Gee.ArrayList<User> users, string _password){

		string password = _password;
		
		bool status = true;

		var grpmgr = new GroupManager(dry_run);
		grpmgr.query_groups(false);
		
		foreach(var user in users){

			if (user.is_system){ continue; }

			log_msg("%s: %s ~ %s\n".printf(_("User"), user.name, user.full_name));
			
			if (!dir_exists(user.home_path)){
				log_error("%s: %s".printf(Messages.DIR_MISSING, user.home_path));
				log_msg(string.nfill(70,'-'));
				continue;
			}

			var backup_path_user = path_combine(backup_path, user.name);

			if (!dir_exists(backup_path_user)){
				log_error("%s: %s".printf(Messages.DIR_MISSING, user.home_path));
				log_error(_("No backup found for this user"));
				log_msg(string.nfill(70,'-'));
				continue;
			}

			// create script ---------------------------
			
			var cmd = "";

			if (password.length == 0){ password = "aptik"; } 
			
			cmd += "export PASSPHRASE='%s'\n".printf(escape_single_quote(password));
			
			cmd += "duplicity";

			cmd += " restore";

			cmd += " --verbosity i --force";

			cmd += " 'file://%s'".printf(escape_single_quote(backup_path_user));

			cmd += " '%s'".printf(escape_single_quote(user.home_path));

			cmd += "\n";
			
			cmd += "unset PASSPHRASE\n";

			// execute ---------------------------------

			int retval = 0;
			
			if (dry_run){
				log_msg("$ %s".printf(cmd));
			}
			else{
				log_debug("$ %s".printf(cmd));
				retval = Posix.system(cmd);
			}
			
			if (retval != 0){ status = false; }

			// update ownership --------------------------
			
			update_owner_for_directory_contents(user, grpmgr.groups_sorted);

			log_msg(string.nfill(70,'-'));
		}

		return status;
	}

	public bool fix_home_ownership(string userlist){

		if (!dry_run){
			log_msg(_("Updating ownership for home directory..."));
		}

		bool status = true;

		// build user list -----------------------
		
		var usmgr = new UserManager();
		usmgr.query_users(false);

		var users = new Gee.ArrayList<User>();
		
		if (userlist.length == 0){
			users = usmgr.users_sorted;
		}
		else{
			foreach(string username in userlist.split(",")){
				foreach(var user in usmgr.users_sorted){
					if (user.name == username){
						users.add(user);
						break;
					}
				}
			}
		}
		
		// update ----------------------------------------

		bool ok = true;

		var grpmgr = new GroupManager(dry_run);
		grpmgr.query_groups(false);
		
		foreach(var user in users){

			if (user.is_system){ continue; }

			log_msg("%s: %s ~ %s\n".printf(_("User"), user.name, user.full_name));
			
			if (!dir_exists(user.home_path)){
				log_error("%s: %s".printf(Messages.DIR_MISSING, user.home_path));
				log_msg(string.nfill(70,'-'));
				continue;
			}

			update_owner_for_directory_contents(user, grpmgr.groups_sorted);

			log_msg(string.nfill(70,'-'));
		}
		
		if (!ok){ status = false; }
		
		if (status){
			log_msg(Messages.RESTORE_OK);
		}
		else{
			log_error(Messages.RESTORE_ERROR);
		}

		log_msg(string.nfill(70,'-'));

		return status;
	}

	public bool update_owner_for_directory_contents(User user, Gee.ArrayList<Group> groups){

		string usergroup = user.get_primary_group_name(groups);

		bool ok = true;
		
		if (!dry_run){
			chown(user.home_path, user.name, usergroup);
		}
		
		log_msg("%s: %s (%s,%s)".printf(_("Updated owner for home directory contents"), user.home_path, user.name, usergroup));

		return ok;
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
	
	// TAR helpers ----------------

	public static bool zip_archive(string src_path, string backup_path, string file_name) {
		
		//string file_name = name + ".tar.gz";
		string tar_file = path_combine(backup_path, file_name);

		if (!dir_exists(backup_path)){
			dir_create(backup_path);
		}

		// prepare -----------------------------------------
		
		//if (file_exists(tar_file)){
		//	file_delete(tar_file);
		//}

		var gz_file = tar_file.replace(".tar.xz",".tar.gz");
		if (file_exists(gz_file)){
			file_delete(gz_file);
		}

		var xz_file = tar_file.replace(".tar.gz",".tar.xz");
		if (file_exists(xz_file)){
			file_delete(xz_file);
		}

		string compressor = tar_file.has_suffix(".xz") ? "xz" : "gzip";
		
		string temp_file = tar_file + ".temp";

		// create script --------------------------------------------
		
		string cmd = "";
		
		//cmd = "tar czvf '%s' '%s'".printf(tar_file, src_path);

		cmd += "tar cf - '%s'".printf(escape_single_quote(src_path));
		
		cmd += " | pv -s $(du -sb '%s' | awk '{print $1}')".printf(escape_single_quote(src_path));
		
		cmd += " | %s > '%s'".printf(compressor, escape_single_quote(temp_file));

		log_debug(cmd);

		//log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Archiving"), src_path));
		log_msg("");
		
		int status = Posix.system(cmd);

		if (status != 0){
			file_delete(temp_file);
			log_msg("%s: %s".printf(_("Deleted"), tar_file));
		}
		else{
			file_move(temp_file, tar_file, false);
			chmod(tar_file, "a+rw");
			log_msg("%s: %s".printf(_("Created"), tar_file));
		}

		if (status == 0){
			log_msg(Messages.BACKUP_OK);
		}
		else{
			log_error(Messages.BACKUP_ERROR);
		}
		
		log_msg(string.nfill(70,'-'));

		return (status == 0);
	}
	
	public static bool unzip_archive(string tar_file, string dst_path, bool dry_run) {

		//check file
		if (!file_exists(tar_file)) {
			log_error(_("File not found") + ": '%s'".printf(tar_file));
			return false;
		}

		if (!dir_exists(dst_path)){
			dir_create(dst_path);
		}

		string cmd = "";

		//cmd += "tar xzvf '%s' --directory='%s'".printf(tar_file, dst_path);

		cmd += "pv '%s'".printf(escape_single_quote(tar_file));
			
		cmd += " | tar xf -";
		
		cmd += " -C '%s'".printf(escape_single_quote(dst_path));

		//cmd += " >/dev/null 2>&1";
		
		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug("$ %s".printf(cmd));
		}

		//log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Extracting"), tar_file));
		log_msg("");
		
		int status = 0;
		
		if (!dry_run){
			
			status = Posix.system(cmd);
		}

		if (status == 0){
			log_msg(Messages.RESTORE_OK);
		}
		else{
			log_error(Messages.RESTORE_ERROR);
		}
		
		log_msg(string.nfill(70,'-'));
		
		return (status == 0);
	}

	public static bool list_archive(string tar_file) {

		//check file
		if (!file_exists(tar_file)) {
			log_error(_("File not found") + ": '%s'".printf(tar_file));
			return false;
		}

		// silent -- no -v
		string cmd = "tar tf '%s'".printf(tar_file);
		
		log_debug("$ %s".printf(cmd));

		log_msg("%s: %s".printf(_("Listing"), tar_file));
		log_msg("");

		int status = 0;
		
		status = Posix.system(cmd);

		log_msg(string.nfill(70,'-'));
		
		return (status == 0);
	}
}

public enum HomeDataBackupMode {
	TAR,
	DUPLICITY
}

