/*
 * GroupManager.vala
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

public class GroupManager : BackupManager {

	public Gee.HashMap<string,Group> groups = new Gee.HashMap<string,Group>();

	public GroupManager(LinuxDistro _distro, User _current_user, string _basepath, bool _dry_run, bool _redist, bool _apply_selections){

		base(_distro, _current_user, _basepath, _dry_run, _redist, _apply_selections, "groups");
	}

	// query -----------------------
	
	public void query_groups(bool query_passwords){
		
		if (query_passwords){
		    read_groups_from_file("/etc/group","/etc/gshadow","");
		}
		else{
			read_groups_from_file("/etc/group","","");
		}
	}

	public Gee.ArrayList<Group> groups_sorted {
		owned get{
			return get_sorted_array(groups);
		}
	}
	
	public void read_groups_from_file(string group_file, string gshadow_file, string password){

		// read 'group' file -------------------------------
		
		string txt = "";
		
		txt = file_read(group_file);

		if (txt.length == 0){
			log_error("%s: %s".printf(_("Failed to read file"), group_file));
			return;
		}
		
		foreach(string line in txt.split("\n")){
			
			if ((line == null) || (line.length == 0)){ continue; }
			
			parse_line_group(line);
		}

		if (gshadow_file.length == 0){ return; }

		// read 'gshadow' file -------------------------------

		txt = "";
		
		txt = file_read(gshadow_file);

		if (txt.length == 0){ return; }
		
		foreach(string line in txt.split("\n")){

			if ((line == null) || (line.length == 0)){ continue; }
			
			parse_line_gshadow(line);
		}

		log_debug("read_groups_from_file(): %d".printf(groups.size));
	}

	public void read_groups_from_folder(string path){

		var list = dir_list_names(path, true);
		
		foreach(string backup_file in list){

			string file_name = file_basename(backup_file);

			if (!file_name.has_suffix(".group")){ continue; }

			parse_line_group(file_read(backup_file)); 
		}

		foreach(string backup_file in list){

			string file_name = file_basename(backup_file);

			if (!file_name.has_suffix(".gshadow")){ continue; }

			parse_line_gshadow(file_read(backup_file));
		}

		log_debug("read_groups_from_folder(): %d".printf(groups.size));
	}

	private void parse_line_group(string line){
		
		if ((line == null) || (line.length == 0)){ return; }
		
		Group group = null;

		//cdrom:x:24:teejee,user2
		string[] fields = line.split(":");

		if (fields.length == 4){
			group = new Group(fields[0].strip());
			group.password = fields[1].strip();
			group.gid = int.parse(fields[2].strip());
			group.user_names = fields[3].strip();
			groups[group.name] = group;
		}
		else{
			log_error("'group' file contains a record with non-standard fields" + ": %d".printf(fields.length));
		}
	}

	private void parse_line_gshadow(string line){
		
		if ((line == null) || (line.length == 0)){ return; }
		
		Group group = null;

		//adm:*::syslog,teejee
		//<groupname>:<encrypted-password>:<admins>:<members>
		string[] fields = line.split(":");

		if (fields.length == 4){
			string group_name = fields[0].strip();
			if (groups.has_key(group_name)){
				group = groups[group_name];
				group.shadow_line = line;
				group.password_hash = fields[1].strip();
				group.admin_names = fields[2].strip();
				group.member_names = fields[3].strip();
				return;
			}
			else{
				log_error("group in file 'gshadow' does not exist in file 'group'" + ": %s".printf(group_name));
				return;
			}
		}
		else{
			log_error("'gshadow' file contains a record with non-standard fields" + ": %d".printf(fields.length));
			return;
		}
	}

	public static int add_group(string group_name, bool system_account, bool dry_run){

		int status = 0;
		
		string cmd = "groupadd%s %s".printf((system_account)? " --system" : "", group_name);

		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug("$ %s".printf(cmd));
			status = Posix.system(cmd);
		}
		
		return status;
	}

	public static int add_user_to_group(string user_name, string group_name, bool dry_run){
		
		int status = 0;
		
		string cmd = "adduser %s %s".printf(user_name, group_name);
		
		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug("$ %s".printf(cmd));
			status = Posix.system(cmd);
		}
		
		return status;
	}

	// list ----------------------

	public void dump_info(){

		string txt = "";
		
		foreach(var group in groups_sorted){
			
			if (group.is_system) { continue; }
			
			txt += "NAME='%s'".printf(group.name);
			
			//txt += ",DESC='%s'".printf("");

			txt += ",ACT='%s'".printf("1");
			
			txt += ",SENS='%s'".printf("1");
			
			txt += "\n";
		}
		
		log_msg(txt);
	}

	public void dump_info_backup(){

		init_backup_path(false);

		if (!dir_exists(files_path)) {
			string msg = "%s: %s".printf(Messages.DIR_MISSING, files_path);
			log_error(msg);
			return;
		}
		
		string txt = "";

		query_groups(false);
		
		var mgr = new GroupManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.read_groups_from_folder(files_path);
	
		foreach(var group in mgr.groups_sorted){
			
			bool is_installed = false;
			
			if (groups.has_key(group.name)){
				
				is_installed = true;
			}

			txt += "NAME='%s'".printf(group.name);
			
			//txt += ",DESC='%s'".printf("");

			txt += ",ACT='%s'".printf(is_installed ? "0" : "1");
			
			txt += ",SENS='%s'".printf(is_installed ? "0" : "1");
			
			txt += "\n";
		}

		log_msg(txt);
	}

	public void list_groups(bool all){
		
		foreach(var group in groups_sorted){
			
			if (!all && group.is_system) { continue; }

			string txt = (group.user_names.length > 0) ? "-- " + group.user_names : "" ;
			
			log_msg("%5d %-20s %s".printf(group.gid, group.name, txt));
		}
	}

	// backup ------------------
	
	public bool backup_groups(){

		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Backup"), Messages.TASK_GROUPS));
		log_msg(string.nfill(70,'-'));

		init_backup_path(false);
		
		init_files_path(false);

		read_selections();
		
		bool status = true;

		foreach(var group in groups_sorted){
			
			if (group.is_system) { continue; }

			if (exclude_list.contains(group.name)){ continue; }
	
			string backup_file = path_combine(files_path, "%s.group".printf(group.name));
			bool ok = file_write(backup_file, group.get_group_line());
			chmod(backup_file, "a+rw");

			if (ok){ log_msg("%s: %s".printf(_("Saved"), backup_file.replace(basepath, "$basepath"))); }
			else{ status = false; }

			backup_file = path_combine(files_path, "%s.gshadow".printf(group.name));
			ok = file_write(backup_file, group.get_gshadow_line());
			chmod(backup_file, "a+rw");

			if (ok){ log_msg("%s: %s".printf(_("Saved"), backup_file.replace(basepath, "$basepath"))); }
			else{ status = false; }
		}

		bool ok = backup_memberships(files_path);
		if (!ok){ status = false; }
		
		if (status){
			log_msg(Messages.BACKUP_OK);
		}
		else{
			log_error(Messages.BACKUP_ERROR);
		}

		//log_msg(string.nfill(70,'-'));

		return status;
	}

	private bool backup_memberships(string path){
		
		string backup_file = path_combine(path, "memberships.list");
		
		string txt = "";
		
		foreach(var group in groups_sorted){
			txt += "%s:%s\n".printf(group.name, group.user_names);
		}

		bool ok = file_write(backup_file, txt);
		
		if (ok){
			chmod(backup_file, "a+rw");
			log_msg("%s: %s".printf(_("Saved"), backup_file.replace(basepath, "$basepath")));
		}

		return ok;
	}

	// restore ---------------------
	
	public bool restore_groups(){

		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Restore"), Messages.TASK_GROUPS));
		log_msg(string.nfill(70,'-'));
		
		if (!dir_exists(files_path)) {
			string msg = "%s: %s".printf(Messages.DIR_MISSING, files_path);
			log_error(msg);
			return false;
		}

		read_selections();
		
		bool status = true, ok;
		
		ok = add_missing_groups_from_backup();
		if (!ok){ status = false; }
		
		ok = update_groups_from_backup();
		if (!ok){ status = false; }

		ok = add_missing_members_from_backup();
		if (!ok){ status = false; }
		
		return status;
	}

	private bool add_missing_groups_from_backup(){

		log_debug("add_missing_groups_from_backup()");

		bool status = true;
		
		query_groups(true);
		
		var mgr = new GroupManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.read_groups_from_folder(files_path);
	
		foreach(var group in mgr.groups_sorted){
			
			if (groups.has_key(group.name)){ continue; }

			if (exclude_list.contains(group.name)){ continue; }

			bool ok = (group.add(dry_run) == 0);
		
			if (!ok){
				log_error(Messages.GROUP_ADD_ERROR + ": %s".printf(group.name));
				status = false;
			}
			else{
				log_msg(Messages.GROUP_ADD_OK + ": %s".printf(group.name));
			}
		}
		
		return status;
	}

	private bool update_groups_from_backup(){

		log_debug("update_groups_from_backup()");

		bool status = true;
		
		query_groups(true);

		var grp_mgr = new GroupManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		grp_mgr.read_groups_from_folder(files_path);

		var usr_mgr = new UserManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		usr_mgr.query_users(false);
		var current_user_names = usr_mgr.user_names_sorted;
		
		foreach(var old_group in grp_mgr.groups_sorted){

			if (!groups.has_key(old_group.name)){ continue; }

			if (exclude_list.contains(old_group.name)){ continue; }

			var group = groups[old_group.name];

			if (group.compare_fields(old_group) > 0){
				// group mismatch
				group.password = old_group.password;
				group.user_names = Group.remove_missing_user_names(current_user_names, old_group.user_names); 
				// keep name, gid
				
				bool ok = group.update_group_file(dry_run);
				if (!ok){ status = false; }
			}

			if (group.compare_fields(old_group) < 0){
				// gshadow mismatch
				group.password = old_group.password;
				group.admin_names = Group.remove_missing_user_names(current_user_names, old_group.admin_names); 
				group.member_names = Group.remove_missing_user_names(current_user_names, old_group.member_names);
				// keep name

				bool ok = group.update_gshadow_file(dry_run);
				if (!ok){ status = false; }
			}
		}

		return status;
	}

	private bool add_missing_members_from_backup(){

		log_debug("add_missing_members_from_backup()");
		
		if (!dir_exists(files_path)) {
			string msg = "%s: %s".printf(Messages.DIR_MISSING, files_path);
			log_error(msg);
			return false;
		}

		string backup_file = path_combine(files_path, "memberships.list");

		if (!file_exists(backup_file)) {
			string msg = "%s: %s".printf(Messages.FILE_MISSING, backup_file);
			log_error(msg);
			return false;
		}

		bool status = true;

		var usr_mgr = new UserManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		usr_mgr.query_users(false);
		var current_user_names = usr_mgr.user_names_sorted;
		
		string txt = file_read(backup_file);
		
		foreach(var line in txt.split("\n")){

			var match = regex_match("""(.*):(.*)""", line);
			
			if (match != null){
				
				string name = match.fetch(1);
				string user_names = match.fetch(2);
				
				if (groups.has_key(name)){
					
					var group = groups[name];
					
					if (group.user_names != user_names){
						
						group.user_names = Group.remove_missing_user_names(current_user_names, user_names);
						
						bool ok = group.update_group_file(dry_run);
						
						if (!ok){ status = false; }
					}
				}
			}
		}

		return status;
	}
	
	// static ----------------------

	public static Gee.ArrayList<Group> get_sorted_array(Gee.HashMap<string,Group> dict){

		var list = new Gee.ArrayList<Group>();
		
		foreach(var pkg in dict.values) {
			list.add(pkg);
		}

		list.sort((a, b) => {
			return strcmp(a.name, b.name);
		});

		return list;
	}
}
