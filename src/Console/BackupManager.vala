/*
 * BackupManager.vala
 *
 * Copyright 2012-2017 Tony George <teejeetech@gmail.com>
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

using GLib;
using Gee;

using TeeJee.Logging;
using TeeJee.FileSystem;
using TeeJee.ProcessHelper;
using TeeJee.System;
using TeeJee.Misc;

public class BackupManager : GLib.Object {
	
	protected LinuxDistro? distro;
	protected User? current_user;
	
	protected bool dry_run = false;
	protected bool redist = false;
	protected string basepath = "";
	protected string item_name = "";

	protected bool apply_selections = false;
	protected Gee.ArrayList<string> exclude_list = new Gee.ArrayList<string>();
	protected Gee.ArrayList<string> include_list = new Gee.ArrayList<string>();
	
	public BackupManager(LinuxDistro? _distro,  User? _current_user, string _basepath, bool _dry_run, bool _redist, bool _apply_selections,  string _item_name){

		distro = _distro;

		current_user = _current_user;

		basepath = _basepath;

		dry_run = _dry_run;

		redist = _redist;

		apply_selections = _apply_selections;

		item_name = _item_name;
	}
	
	public string backup_path {
		owned get {
			return path_combine(basepath, item_name);
		}
	}

	public string files_path {
		owned get{
			return path_combine(backup_path, "files");
		}
	}

	public void init_backup_path(bool restore){
		
		if (!dir_exists(backup_path)){
			dir_create(backup_path);
			chmod(backup_path, "a+rwx");
		}
	}

	public void init_files_path(bool restore){
		
		init_backup_path(restore);
		
		if (!restore){
			dir_delete(files_path);
		}
		
		if (!dir_exists(files_path)){
			dir_create(files_path);
			chmod(files_path, "a+rwx");
		}
	}
	
	public void read_selections(){

		include_list.clear();
		exclude_list.clear();
		
		if (!apply_selections){ return; }

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

	public virtual bool update_permissions_for_backup_files() {

		if (dry_run){ return true; }
		
		bool ok = true;
		bool status = true;

		ok = chmod(backup_path, "a+rwx");
		if (!ok){ status = false; }
		
		ok = chmod_dir_contents(backup_path, "d", "a+rwx");
		if (!ok){ status = false; }
		
		ok = chmod_dir_contents(backup_path, "f", "a+rw");
		if (!ok){ status = false; }

		//ok = chown(backup_path, "root", "root");
		//if (!ok){ status = false; }
		
		return status;
	}

	public virtual bool update_permissions_for_restored_files(string path) {

		if (dry_run){ return true; }
		
		bool ok = true;
		bool status = true;

		ok = chmod(path, "755");
		if (!ok){ status = false; }
		
		ok = chmod_dir_contents(path, "d", "755");
		if (!ok){ status = false; }
		
		ok = chmod_dir_contents(path, "f", "644");
		if (!ok){ status = false; }

		ok = chown(path, "root", "root");
		if (!ok){ status = false; }
		
		return status;
	}
}
