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

public class GroupManager : GLib.Object {

	public Gee.HashMap<string,Group> groups;

	public bool dry_run = false;

	public GroupManager(bool _dry_run = false){

		dry_run = _dry_run;
		
		this.groups = new Gee.HashMap<string,Group>();
	}

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
		
		if (group_file.has_suffix(".tar.gpg")){
			txt = file_decrypt_untar_read(group_file, password);
		}
		else{
			txt = file_read(group_file);
		}
		
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
		
		if (gshadow_file.has_suffix(".tar.gpg")){
			txt = file_decrypt_untar_read(gshadow_file, password);
		}
		else{
			txt = file_read(gshadow_file);
		}
		
		if (txt.length == 0){ return; }
		
		foreach(string line in txt.split("\n")){

			if ((line == null) || (line.length == 0)){ continue; }
			
			parse_line_gshadow(line);
		}

		log_debug("read_groups_from_file(): %d".printf(groups.size));
	}

	public void read_groups_from_folder(string backup_path){

		var list = dir_list_names(backup_path, true);
		
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
			foreach(string user_name in group.user_names.split(",")){
				group.users.add(user_name);
			}
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
				group.admin_list = fields[2].strip();
				group.member_list = fields[3].strip();
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

	public static int add_group(string group_name, bool system_account = false){
		string std_out, std_err;
		string cmd = "groupadd%s %s".printf((system_account)? " --system" : "", group_name);
		int status = exec_sync(cmd, out std_out, out std_err);
		if (status != 0){
			log_error(std_err);
		}
		else{
			//log_msg(std_out);
		}
		return status;
	}

	public static int add_user_to_group(string user_name, string group_name){
		string std_out, std_err;
		string cmd = "adduser %s %s".printf(user_name, group_name);
		log_debug(cmd);
		int status = exec_sync(cmd, out std_out, out std_err);
		if (status != 0){
			log_error(std_err);
		}
		else{
			//log_msg(std_out);
		}
		return status;
	}

	// backup and restore ----------------------
	
	public void list_groups(bool all){
		
		foreach(var group in groups_sorted){
			
			if (!all && group.is_system) { continue; }

			string txt = (group.user_names.length > 0) ? "-- " + group.user_names : "" ;
			
			log_msg("%5d %-20s %s".printf(group.gid, group.name, txt));
		}
	}

	public bool backup_groups(string basepath){

		string backup_path = path_combine(basepath, "groups");

		dir_create(backup_path);

		log_msg(_("Saving groups..."));

		bool status = true;

		foreach(var group in groups_sorted){
			
			if (group.is_system) { continue; }
	
			string backup_file = path_combine(backup_path, "%s.group".printf(group.name));
			bool ok = file_write(backup_file, group.get_group_line());

			if (ok){ log_msg("%s: %s".printf(_("Saved"), backup_file)); }
			else{ status = false; }

			backup_file = path_combine(backup_path, "%s.gshadow".printf(group.name));
			ok = file_write(backup_file, group.get_gshadow_line());

			if (ok){ log_msg("%s: %s".printf(_("Saved"), backup_file)); }
			else{ status = false; }
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

	public bool restore_groups(string basepath){

		string backup_path = path_combine(basepath, "groups");
		
		if (!dir_exists(backup_path)) {
			string msg = "%s: %s".printf(Message.DIR_MISSING, backup_path);
			log_error(msg);
			return false;
		}
		
		//restore_add_missing_groups(backup_path);
		
		return true;
	}

	public bool add_missing_groups_from_backup(string basepath){

		log_debug("add_missing_groups_from_backup()");

		string backup_path = path_combine(basepath, "groups");
		
		if (!dir_exists(backup_path)) {
			string msg = "%s: %s".printf(Message.DIR_MISSING, backup_path);
			log_error(msg);
			return false;
		}
		
		bool status = true;
		
		query_groups(true);
		
		var mgr = new GroupManager(dry_run);
		mgr.read_groups_from_folder(backup_path);
	
		foreach(var group in mgr.groups_sorted){
			
			if (groups.has_key(group.name)){ continue; }

			bool ok = (group.add() == 0);
		
			if (!ok){
				log_error(Message.GROUP_ADD_ERROR + ": %s".printf(group.name));
				status = false;
			}
			else{
				log_msg(Message.GROUP_ADD_OK + ": %s".printf(group.name));
			}
		}
		
		return status;
	}

	public bool update_groups_from_backup(string basepath){

		log_debug("update_groups_from_backup()");

		string backup_path = path_combine(basepath, "groups");
		
		if (!dir_exists(backup_path)) {
			string msg = "%s: %s".printf(Message.DIR_MISSING, backup_path);
			log_error(msg);
			return false;
		}
		
		bool status = true;
		
		query_groups(true);

		var mgr = new GroupManager(dry_run);
		mgr.read_groups_from_folder(backup_path);
		
		foreach(var old_group in mgr.groups_sorted){

			if (!groups.has_key(old_group.name)){ continue; }

			var group = groups[old_group.name];

			if (group.compare_fields(old_group) > 0){
				// group mismatch
				group.password = old_group.password;
				group.user_names = old_group.user_names;
				// keep name, gid
				
				bool ok = group.update_group_file();
				if (!ok){ status = false; }
			}

			if (group.compare_fields(old_group) < 0){
				// gshadow mismatch
				group.password = old_group.password;
				group.admin_list = old_group.admin_list;
				group.member_list = old_group.member_list;
				// keep name

				bool ok = group.update_gshadow_file();
				if (!ok){ status = false; }
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
