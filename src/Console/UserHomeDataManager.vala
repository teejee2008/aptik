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

public class UserHomeDataManager : BackupManager {
	
	private bool use_xz = false;

	public UserHomeDataManager(LinuxDistro _distro, User _current_user, string _basepath, bool _dry_run, bool _redist, bool _apply_selections){

		base(_distro, _current_user, _basepath, _dry_run, _redist, _apply_selections, "home");
	}

	public void dump_info(){

		string txt = "";
		
		var mgr = new UserManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.query_users(false);
		
		foreach(var user in mgr.users_sorted){
			
			if (user.is_system) { continue; }
			
			txt += "NAME='%s'".printf(user.name);
			
			txt += ",DESC='%s'".printf(user.home_path);
			
			txt += ",ENC='%s'".printf(user.has_encrypted_home ? "1" : "0");

			txt += ",ACT='%s'".printf(user.has_encrypted_home ? "0" : "1");
			
			txt += ",SENS='%s'".printf(user.has_encrypted_home ? "0" : "1");
			
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

			string bkup_file1 = path_combine(files_path, "%s/data.tar.gz".printf(user.name));
			string bkup_file2 = path_combine(files_path, "%s/data.tar.xz".printf(user.name));

			if (!file_exists(bkup_file1) && !file_exists(bkup_file2)){ continue; }
			
			txt += "NAME='%s'".printf(user.name);
			
			txt += ",DESC='%s'".printf(user.full_name);

			txt += ",ENC='%s'".printf(user.has_encrypted_home ? "1" : "0");

			txt += ",ACT='%s'".printf(user.has_encrypted_home ? "0" : "1"); // check on target system
			
			txt += ",SENS='%s'".printf(user.has_encrypted_home ? "0" : "1"); // check on target system
			
			txt += "\n";
		}
		
		log_msg(txt);
	}

	// backup ----------------------
	
	public bool backup_home(string userlist, bool exclude_hidden, bool _use_xz,
		string exclude_from_file){

		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Backup"), Messages.TASK_HOME));
		log_msg(string.nfill(70,'-'));

		use_xz = _use_xz;

		init_backup_path();

		if (redist){ dir_delete(backup_path); } // delete existing backups

		bool status = true;

		var users = get_users(userlist, true);

		read_selections();

		// backup --------------------------------------
		
		bool ok = backup_home_tar(users, exclude_hidden, exclude_from_file);

		if (!ok){ status = false; }
		
		if (status){
			log_msg(Messages.BACKUP_OK);
		}
		else{
			log_error(Messages.BACKUP_ERROR);
		}

		return status;
	}

	public bool backup_home_tar(Gee.ArrayList<User> users, bool exclude_hidden, string exclude_from_file){

		bool status = true;
		int retval = 0;
		
		foreach(var user in users){

			if (user.is_system){ continue; }

			if (exclude_list.contains(user.name)){ continue; }

			log_msg("%s: %s ~ %s\n".printf(_("User"), user.name, user.full_name));
			
			if (!dir_exists(user.home_path)){
				log_error("%s: %s".printf(Messages.DIR_MISSING, user.home_path));
				log_msg(string.nfill(70,'-'));
				continue;
			}
			
			string backup_path_user = "";

			string src_path_user = "";

			if (redist){
				
				backup_path_user = backup_path;

				src_path_user = user.home_path; // always use home data in redist mode. use decrypted home data for encrypted home.
			}
			else{
				backup_path_user = path_combine(files_path, user.name);

				dir_delete(backup_path_user); // remove existing backups if any
				dir_create(backup_path_user);
				chmod(backup_path_user, "a+rwx");

				if (user.has_encrypted_home){
					src_path_user = user.get_home_ecryptfs_path();
				}
				else{
					src_path_user = user.home_path;
				}
			}

			// save exclude list -----------------------

			string exclude_list = "";
			
			if (redist || !user.has_encrypted_home){

				exclude_list = path_combine(backup_path_user, "exclude.list");
				if (file_exists(exclude_list)){
					file_delete(exclude_list);
				}
				file_write(exclude_list, exclude_list_create(user, exclude_hidden, exclude_from_file, true));
				chmod(exclude_list, "a+rw");
			}

			// prepare -----------------------------------------

			string basename = "data.tar";

			if (!redist && user.has_encrypted_home){
				basename = "data-ecryptfs.tar";
			}
			
			string tar_file = path_combine(backup_path_user, basename + (use_xz ? ".xz" : ".gz"));

			string tar_file_gz = path_combine(backup_path_user, basename +".gz");

			string tar_file_xz = path_combine(backup_path_user, basename +".xz");

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

			cmd += "cd '%s' ; ".printf(escape_single_quote(src_path_user));

			cmd += "tar cf -";

			if (exclude_list.length > 0){
				cmd += " --exclude-from='%s'".printf(escape_single_quote(exclude_list));
			}
			
			cmd += " -C '%s'".printf(escape_single_quote(src_path_user));

			if (!redist && exclude_hidden){
				cmd += " *";
			}
			else{
				cmd += " .";
			}
			
			//.printf(escape_single_quote(file_basename(user.home_path)));

			//cmd += " 2>/dev/null";

			string cmd_exc = "";
			if (exclude_list.length > 0){
				cmd_exc = " --exclude-from='%s'".printf(escape_single_quote(exclude_list));
			}
	
			cmd += " | pv -s $(du -sb '%s' %s | awk '{print $1}')".printf(escape_single_quote(src_path_user), cmd_exc);

			cmd += " | %s > '%s'".printf(compressor, escape_single_quote(temp_file));

			cmd += " ; cd - ; "; // 'cd -' will restore last directory

			// execute ---------------------------------

			log_msg("%s: '%s'\n".printf(_("Archiving"), src_path_user));
			
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
				log_msg("Deleted: %s".printf(temp_file.replace(basepath, "$basepath")));
			}
			else{
				file_move(temp_file, tar_file, false);
				chmod(tar_file, "a+rw");
				log_msg("Created: %s".printf(tar_file.replace(basepath, "$basepath")));
			}

			log_msg(string.nfill(70,'-'));
		}

		return status;
	}

	public string exclude_list_create(User user, bool exclude_hidden, string exclude_from_file, bool tar_format){
		
		string txt = "";

		var list = new Gee.ArrayList<string>();
		
		list.add(".thumbnails");
		list.add(".cache");
		list.add(".dbus");
		list.add(".gvfs");
		list.add(".config/dconf/user");
		list.add(".local/share/Trash");
		list.add(".local/share/trash");
		list.add(".mozilla/firefox/*.default/Cache");
		list.add(".mozilla/firefox/*.default/Cache2");
		list.add(".mozilla/firefox/*.default/OfflineCache");
		list.add(".mozilla/firefox/*.default/startupCache");
		list.add(".opera/cache");
		list.add(".kde/share/apps/kio_http/cache");
		list.add(".kde/share/cache/http");
		list.add(".gksu.lock");
		list.add(".temp");
		list.add(".xsession-errors*");
		list.add(".Xauthority");
		list.add(".ICEauthority");
		list.add(".sudo_as_admin_successful");

		if (redist){
			list.add(".bazaar/bazaar.conf");
			list.add(".gitconfig");
			list.add(".gnupg");
			list.add(".ssh");
			list.add(".config/google-chrome/Default/Login Data");
		}

		if ((exclude_from_file.length > 0) && file_exists(exclude_from_file)){

			foreach(string line in file_read(exclude_from_file).split("\n")){
				
				if (line.strip().length > 0){
					
					list.add(line); // don't strip
				}
			}
		}

		foreach(var item in list){
			log_msg("%s: %s".printf(_("exclude"), path_combine(user.home_path, item)));
		}

		log_msg("");

		/*int index = user.home_path.length + 1;

		foreach(var item in list){
			if (tar_format){
				txt += "%s\n".printf(item[index:item.length]);
			}
			else{
				txt += "%s\n".printf(item);
			}
		}*/

		//if (dry_run || LOG_DEBUG){
			//log_msg("Exclude:\n%s\n".printf(txt));
		//}

		foreach(var item in list){
			txt += "%s\n".printf(item);
		}

		return txt;
	}

	// restore -----------------------------
	
	public bool restore_home(string userlist){

		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Restore"), Messages.TASK_HOME));
		log_msg(string.nfill(70,'-'));
		
		if (!dir_exists(backup_path)) {
			string msg = "%s: %s".printf(Messages.DIR_MISSING, backup_path);
			log_error(msg);
			return false;
		}

		bool status = true;

		var users = get_users(userlist, false);

		read_selections();
		
		// restore ----------------------------------------

		bool ok = restore_home_tar(users);

		if (!ok){ status = false; }
		
		if (status){
			log_msg(Messages.RESTORE_OK);
		}
		else{
			log_error(Messages.RESTORE_ERROR);
		}

		return status;
	}

	public bool restore_home_tar(Gee.ArrayList<User> users){

		bool status = true;

		var grpmgr = new GroupManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		grpmgr.query_groups(false);

		string backup_path_user = "";
		
		foreach(var user in users){

			if (user.is_system){ continue; }

			if (exclude_list.contains(user.name)){ continue; }

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
				backup_path_user = path_combine(files_path, user.name);
			}
			
			if (!dir_exists(backup_path_user)){
				log_error("%s: %s".printf(Messages.DIR_MISSING, user.home_path));
				log_error(_("No backup found for this user"));
				log_msg(string.nfill(70,'-'));
				continue;
			}

			// prepare ------------------------------------------

			string basename = "data.tar";

			string tar_file = path_combine(backup_path_user, basename);

			bool encrypted_home = false;

			if (file_exists(tar_file + ".xz")){
				tar_file = tar_file + ".xz";
			}
			else if (file_exists(tar_file + ".gz")){
				tar_file = tar_file + ".gz";
			}
			else{

				// check for ecryptfs backup
				
				basename = "data-ecryptfs.tar";

				tar_file = path_combine(backup_path_user, basename);

				if (file_exists(tar_file + ".xz")){
					tar_file = tar_file + ".xz";
					encrypted_home = true;
				}
				else if (file_exists(tar_file + ".gz")){
					tar_file = tar_file + ".gz";
					encrypted_home = true;
				}
				else{
					log_error(_("No backup found"));
					log_msg(string.nfill(70,'-'));
					continue;
				}
			}

			string dst_path_user = "";

			if (!redist && encrypted_home){
				dst_path_user = user.get_home_ecryptfs_path();
			}
			else{
				dst_path_user = user.home_path;
			}
			
			// create script ---------------------------

			string comp_option = tar_file.has_suffix(".xz") ? "J" : "z";
			
			var cmd = "";

			cmd += "pv '%s' | ".printf(escape_single_quote(tar_file));
			
			cmd += "tar x%sf -".printf(comp_option);
			
			cmd += " -C '%s'".printf(escape_single_quote(dst_path_user));

			//cmd += " >/dev/null 2>&1";

			// execute ---------------------------------

			int retval = 0;

			log_msg("%s '%s'...\n".printf(_("Extracting"), dst_path_user));
			
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

			if (encrypted_home && !cmd_exists("ecryptfs-migrate-home")){
				PackageManager.install_package("ecryptfs-utils", "ecryptfs-utils", "ecryptfs-utils");
			}

			log_msg(string.nfill(70,'-'));
		}

		if (redist){

			string tar_file_gz = path_combine(backup_path, "data.tar.gz");

			string tar_file_xz = path_combine(backup_path, "data.tar.xz");

			if (file_exists(tar_file_xz)){
				extract_to_etc_skel(tar_file_xz);
			}
			else if (file_exists(tar_file_gz)){
				extract_to_etc_skel(tar_file_gz);
			}
		}
		
		return status;
	}

	public bool extract_to_etc_skel(string tar_file){

		bool status = true;

		string comp_option = tar_file.has_suffix(".xz") ? "J" : "z";
		
		var cmd = "";

		cmd += "pv '%s' | ".printf(escape_single_quote(tar_file));
		
		cmd += "tar x%sf -".printf(comp_option);
		
		cmd += " -C '%s'".printf("/etc/skel");

		// execute ---------------------------------

		int retval = 0;

		log_msg("%s '%s'...\n".printf(_("Extracting"), "/etc/skel"));
		
		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug("$ %s".printf(cmd));
			retval = Posix.system(cmd);
		}
		
		if (retval != 0){ status = false; }

		return status;
	}

	public bool fix_home_ownership(string userlist){

		if (!dry_run){
			log_msg(_("Updating ownership for home directory..."));
		}

		bool status = true;

		// build user list -----------------------
		
		var usmgr = new UserManager(distro, current_user, basepath, dry_run, redist, apply_selections);
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

		var grpmgr = new GroupManager(distro, current_user, basepath, dry_run, redist, apply_selections);
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

		if (redist){
			
			User? root = null;
			
			foreach(var user in users){
				if (user.name == "root"){
					root = user;
					break;
				}
			}
			if (root != null){
				users.remove(root);
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
			
		cmd += " | tar xaf -";
		
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
