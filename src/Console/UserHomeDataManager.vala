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

public class UserHomeDataManager : GLib.Object {
	
	public bool dry_run = false;
	
	public UserHomeDataManager(bool _dry_run = false){

		dry_run = _dry_run;
	}

	// backup and restore ----------------------
	
	public bool backup_home(string basepath, string userlist, HomeDataBackupMode mode, string password, bool full_backup, bool exclude_hidden){

		string backup_path = path_combine(basepath, "home");

		if (!dry_run){
			dir_create(backup_path);
		}

		if (!dry_run){
			log_msg(_("Saving home directory data..."));
		}

		bool status = true;

		// build user list -----------------------
		
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

		// backup --------------------------------------
		
		bool ok = true;

		switch(mode){
		case HomeDataBackupMode.DUPLICITY:
			ok = backup_home_duplicity(backup_path, users, password, full_backup, exclude_hidden);
			break;
		default:
			ok = backup_home_tar(backup_path, users);
			break;
		}

		if (!ok){ status = false; }
		
		if (status){
			log_msg(Message.BACKUP_OK);
		}
		else{
			log_error(Message.BACKUP_ERROR);
		}

		log_msg(string.nfill(70,'-'));

		return status;
	}

	public bool backup_home_tar(string backup_path, Gee.ArrayList<User> users){

		bool status = true;
		
		foreach(var user in users){

			if (user.is_system){ continue; }

			log_msg(string.nfill(70,'-'));
			log_msg("%s: %s ~ %s\n".printf(_("User"), user.name, user.full_name));
			
			if (!dir_exists(user.home_path)){
				log_error("%s: %s".printf(Message.DIR_MISSING, user.home_path));
				log_msg(string.nfill(70,'-'));
				continue;
			}
			
			var backup_path_user = path_combine(backup_path, user.name);
			dir_delete(backup_path_user); // removes duplicity backups if any
			dir_create(backup_path_user);

			// save exclude list -----------------------
			
			//var exclude_list = path_combine(backup_path_user, "exclude.list");
			//if (file_exists(exclude_list)){
			//	file_delete(exclude_list);
			//}
			//file_write(exclude_list, exclude_list_create(user));

			// create script ---------------------------

			string tar_file = path_combine(backup_path_user, "data.tar.gz");
			file_delete(tar_file);
			
			var cmd = "";

			cmd += "cd '%s'\n".printf(escape_single_quote(file_parent(user.home_path)));
			
			cmd += "tar -zvcf";
			
			cmd += " '%s'".printf(escape_single_quote(tar_file));
			
			cmd += " '%s'".printf(escape_single_quote(file_basename(user.home_path)));

			cmd += "\n";

			// execute ---------------------------------

			if (!dry_run){
				log_debug(cmd);
				string sh_file = save_bash_script_temp(cmd);
				int retval = Posix.system(sh_file);
				if (retval != 0){ status = false; }
			}
			else{
				log_msg("cmd: %s".printf(cmd));
			}

			log_msg(string.nfill(70,'-'));
		}

		return status;
	}

	public bool backup_home_duplicity(string backup_path, Gee.ArrayList<User> users, string _password, bool full_backup, bool exclude_hidden){

		string password = _password;
		
		bool status = true;
		
		foreach(var user in users){

			if (user.is_system){ continue; }

			log_msg(string.nfill(70,'-'));
			log_msg("%s: %s ~ %s\n".printf(_("User"), user.name, user.full_name));
			
			if (!dir_exists(user.home_path)){
				log_error("%s: %s".printf(Message.DIR_MISSING, user.home_path));
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
			file_write(exclude_list, exclude_list_create(user, exclude_hidden));
 
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
			
			cmd += "export PASSPHRASE='%s'\n".printf(escape_single_quote(password));
			
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

			cmd += " 'file://%s'".printf(escape_single_quote(backup_path_user));

			cmd += "\n";
			
			cmd += "unset PASSPHRASE\n";

			// execute ---------------------------------

			if (!dry_run){
				log_debug(cmd);
				string sh_file = save_bash_script_temp(cmd);
				int retval = Posix.system(sh_file);
				if (retval != 0){ status = false; }
			}
			else{
				log_msg("cmd: %s".printf(cmd));
			}

			log_msg(string.nfill(70,'-'));
		}

		return status;
	}

	public string exclude_list_create(User user, bool exclude_hidden){
		
		string txt = "";
		string path = "";

		path = path_combine(user.home_path, ".thumbnails");
		txt += "%s\n".printf(path);

		path = path_combine(user.home_path, ".cache");
		txt += "%s\n".printf(path);

		path = path_combine(user.home_path, ".dbus");
		txt += "%s\n".printf(path);

		path = path_combine(user.home_path, ".gvfs");
		txt += "%s\n".printf(path);

		path = path_combine(user.home_path, ".local/share/Trash");
		txt += "%s\n".printf(path);

		path = path_combine(user.home_path, ".local/share/trash");
		txt += "%s\n".printf(path);

		path = path_combine(user.home_path, ".mozilla/firefox/*.default/Cache");
		txt += "%s\n".printf(path);

		path = path_combine(user.home_path, ".mozilla/firefox/*.default/OfflineCache");
		txt += "%s\n".printf(path);

		path = path_combine(user.home_path, ".opera/cache");
		txt += "%s\n".printf(path);

		path = path_combine(user.home_path, ".kde/share/apps/kio_http/cache");
		txt += "%s\n".printf(path);

		path = path_combine(user.home_path, ".kde/share/cache/http");
		txt += "%s\n".printf(path);

		if (exclude_hidden){
			path = path_combine(user.home_path, ".*");
			txt += "%s\n".printf(path);
		}

		if (dry_run || LOG_DEBUG){
			log_msg("Exclude:\n%s\n".printf(txt));
		}

		return txt;
	}

	public bool restore_home(string basepath, string userlist, string password){

		string backup_path = path_combine(basepath, "home");

		if (!dir_exists(backup_path)) {
			string msg = "%s: %s".printf(Message.DIR_MISSING, backup_path);
			log_error(msg);
			return false;
		}

		log_msg(_("Restoring home directory data..."));

		bool status = true;

		// build user list -----------------------
		
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

		// detect mode ------------------------------------

		HomeDataBackupMode mode = HomeDataBackupMode.TAR;
		
		var list = dir_list_names(backup_path, true);
		foreach(string backup_path_user in list){
			string tar_file = path_combine(backup_path_user, "data.tar.gz");
			if (file_exists(tar_file)){
				mode = HomeDataBackupMode.TAR;
				break;
			}
			else {
				mode = HomeDataBackupMode.DUPLICITY;
				break;
			}
		}

		log_msg("%s: %s".printf(_("Backup mode detected"), mode.to_string().replace("HOME_DATA_BACKUP_MODE_", "")));
		
		// restore ----------------------------------------

		bool ok = true;

		switch(mode){
		case HomeDataBackupMode.DUPLICITY:
			ok = restore_home_duplicity(backup_path, users, password);
			break;
		default:
			ok = restore_home_tar(backup_path, users);
			break;
		}
		
		if (!ok){ status = false; }
		
		if (status){
			log_msg(Message.RESTORE_OK);
		}
		else{
			log_error(Message.RESTORE_ERROR);
		}

		log_msg(string.nfill(70,'-'));

		return status;
	}

	public bool restore_home_tar(string backup_path, Gee.ArrayList<User> users){

		bool status = true;

		var grpmgr = new GroupManager();
		grpmgr.query_groups(false);
		
		foreach(var user in users){

			if (user.is_system){ continue; }

			log_msg(string.nfill(70,'-'));
			log_msg("%s: %s ~ %s\n".printf(_("User"), user.name, user.full_name));
			
			if (!dir_exists(user.home_path)){
				log_error("%s: %s".printf(Message.DIR_MISSING, user.home_path));
				log_msg(string.nfill(70,'-'));
				continue;
			}

			var backup_path_user = path_combine(backup_path, user.name);
			
			if (!dir_exists(backup_path_user)){
				log_error("%s: %s".printf(Message.DIR_MISSING, user.home_path));
				log_error(_("No backup found for this user"));
				log_msg(string.nfill(70,'-'));
				continue;
			}

			string tar_file_user = path_combine(backup_path_user, "data.tar.gz");

			if (!file_exists(tar_file_user)){
				log_error("%s: %s".printf(Message.FILE_MISSING, tar_file_user));
				log_error(_("No backup found for this user"));
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

			//cmd += "cd '%s'\n".printf(escape_single_quote());
			
			cmd += "tar -zvxf";
			
			cmd += " '%s'".printf(escape_single_quote(tar_file_user));
			
			cmd += " -C '%s'".printf(escape_single_quote(file_parent(user.home_path)));

			cmd += "\n";

			// execute ---------------------------------

			if (!dry_run){
				log_debug(cmd);
				string sh_file = save_bash_script_temp(cmd);
				int retval = Posix.system(sh_file);
				if (retval != 0){ status = false; }
			}
			else{
				log_msg("cmd: %s".printf(cmd));
			}

			// update ownership --------------------------

			update_owner_for_directory_contents(user, grpmgr.groups_sorted);

			log_msg(string.nfill(70,'-'));
		}

		return status;
	}

	public bool restore_home_duplicity(string backup_path, Gee.ArrayList<User> users, string _password){

		string password = _password;
		
		bool status = true;

		var grpmgr = new GroupManager();
		grpmgr.query_groups(false);
		
		foreach(var user in users){

			if (user.is_system){ continue; }

			log_msg(string.nfill(70,'-'));
			log_msg("%s: %s ~ %s\n".printf(_("User"), user.name, user.full_name));
			
			if (!dir_exists(user.home_path)){
				log_error("%s: %s".printf(Message.DIR_MISSING, user.home_path));
				log_msg(string.nfill(70,'-'));
				continue;
			}

			var backup_path_user = path_combine(backup_path, user.name);

			if (!dir_exists(backup_path_user)){
				log_error("%s: %s".printf(Message.DIR_MISSING, user.home_path));
				log_error(_("No backup found for this user"));
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

			if (password.length == 0){ password = "aptik"; } 
			
			cmd += "export PASSPHRASE='%s'\n".printf(escape_single_quote(password));
			
			cmd += "duplicity";

			cmd += " restore";

			cmd += " --verbosity i --force";
			
			//cmd += " --exclude-filelist '%s'".printf(escape_single_quote(exclude_list));

			cmd += " 'file://%s'".printf(escape_single_quote(backup_path_user));

			cmd += " '%s'".printf(escape_single_quote(user.home_path));

			cmd += "\n";
			
			cmd += "unset PASSPHRASE\n";

			// execute ---------------------------------

			if (!dry_run){
				log_debug(cmd);
				string sh_file = save_bash_script_temp(cmd);
				int retval = Posix.system(sh_file);
				if (retval != 0){ status = false; }
			}
			else{
				log_msg("cmd: %s".printf(cmd));
			}

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

		var grpmgr = new GroupManager();
		grpmgr.query_groups(false);
		
		foreach(var user in users){

			if (user.is_system){ continue; }

			log_msg("%s: %s ~ %s\n".printf(_("User"), user.name, user.full_name));
			
			if (!dir_exists(user.home_path)){
				log_error("%s: %s".printf(Message.DIR_MISSING, user.home_path));
				log_msg(string.nfill(70,'-'));
				continue;
			}

			update_owner_for_directory_contents(user, grpmgr.groups_sorted);

			log_msg(string.nfill(70,'-'));
		}
		
		if (!ok){ status = false; }
		
		if (status){
			log_msg(Message.RESTORE_OK);
		}
		else{
			log_error(Message.RESTORE_ERROR);
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
		
		log_msg("%s: %s (%s,%s)".printf(_("Updated owner for directory contents"), user.home_path, user.name, usergroup));

		return ok;
	}
}

public enum HomeDataBackupMode {
	TAR,
	DUPLICITY
}

