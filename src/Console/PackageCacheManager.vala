/*
 * PackageCacheManager.vala
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

public class PackageCacheManager : GLib.Object {
	
	public LinuxDistro distro;
	public bool dry_run = false;
	public string basepath = "";

	private bool apply_selections = false;
	private Gee.ArrayList<string> exclude_list = new Gee.ArrayList<string>();
	private Gee.ArrayList<string> include_list = new Gee.ArrayList<string>();
	
	public PackageCacheManager(LinuxDistro _distro, bool _dry_run){

		distro = _distro;

		dry_run = _dry_run;
	}

	public string get_backup_path(){
		
		return path_combine(basepath, "cache");
	}
	
	public void dump_info(){

		string txt = "";

		string system_cache = "";

		switch(distro.dist_type){
		case "fedora":
			//not supported
			return;

		case "arch":
			system_cache = "/var/cache/pacman/pkg";
			break;

		case "debian":
			system_cache = "/var/cache/apt/archives";
			break;

		default:
			log_error(Messages.UNKNOWN_DISTRO);
			return;
		}

		if (system_cache.length == 0){ return; }

		var list = dir_list_names(system_cache, false);
		
		foreach(var name in list){
			
			if ((distro.dist_type == "arch") && !name.has_suffix(".tar.xz") && !name.has_suffix(".txz")){
				continue;
			}

			if ((distro.dist_type == "debian") && !name.has_suffix(".deb")){
				continue;
			}
			
			txt += "NAME='%s'".printf(name);
			txt += "\n";
		}
		
		log_msg(txt);
	}

	public void dump_info_backup(string basepath){

		string backup_path = path_combine(basepath, "packages");
		
		if (!dir_exists(backup_path)) {
			string msg = "%s: %s".printf(Messages.DIR_MISSING, backup_path);
			log_error(msg);
			return;
		}

		string txt = "";

		string backup_path_dist = path_combine(backup_path, distro.dist_type);

		var list = dir_list_names(backup_path_dist, false);
		
		foreach(var name in list){
			
			if ((distro.dist_type == "arch") && !name.has_suffix(".tar.xz") && !name.has_suffix(".txz")){
				continue;
			}

			if ((distro.dist_type == "debian") && !name.has_suffix(".deb")){
				continue;
			}
			
			txt += "NAME='%s'".printf(name);
			txt += "\n";
		}
		
		log_msg(txt);
	}
	
	// save -------------------------------------------

	public bool backup_cache(string _basepath, bool copyback, bool _apply_selections){

		basepath = _basepath;

		if (copyback){
			log_msg(string.nfill(70,'-'));
			log_msg(_("Copying new packages to backup path"));
			log_msg("");
		}
		else{
			log_msg(string.nfill(70,'-'));
			log_msg("%s: %s".printf(_("Backup"), Messages.TASK_CACHE));
			log_msg(string.nfill(70,'-'));
		}
		
		string backup_path = init_backup_path();
		
		string backup_path_distro = path_combine(backup_path, distro.dist_type);
		dir_create(backup_path_distro);
		chmod(backup_path_distro, "a+rwx");

		read_selections();
		
		string system_cache = "";
		string filter = "";

		switch(distro.dist_type){
		case "fedora":
			log_error("%s: %s".printf(Messages.CACHE_NOT_SUPPORTED," dnf/yum"));
			return false;

		case "arch":
			system_cache = "/var/cache/pacman/pkg";
			filter = " --include=\"*.tar.xz\" --include=\"*.txz\" --exclude=\"*\"";
			break;

		case "debian":
			system_cache = "/var/cache/apt/archives";
			filter = " --include=\"*.deb\" --exclude=\"*\"";
			break;

		default:
			log_error(Messages.UNKNOWN_DISTRO);
			return false;
		}

		string cmd = "rsync -avh";

		if (dry_run){
			cmd += " --dry-run";
		}
		
		cmd += " --exclude=lock --exclude=partial/ --exclude=apt-fast/";
		
		cmd += filter;
		
		cmd += " '%s/'".printf(escape_single_quote(system_cache));
		
		cmd += " '%s/'".printf(escape_single_quote(backup_path_distro));

		int status = 0;
		
		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug("$ %s".printf(cmd));
			status = Posix.system(cmd);
		}

		log_msg("");
		
		update_permissions_for_backup_files(backup_path, dry_run);
		
		log_msg(string.nfill(70,'-'));
		log_msg(Messages.BACKUP_OK);

		return (status == 0);
	}

	public bool update_permissions_for_backup_files(string path, bool dry_run) {

		if (dry_run){ return true; }
		
		bool ok = true;
		bool status = true;

		ok = chmod(path, "a+rwx");
		if (!ok){ status = false; }
		
		ok = chmod_dir_contents(path, "d", "a+rwx");
		if (!ok){ status = false; }
		
		ok = chmod_dir_contents(path, "f", "a+rw");
		if (!ok){ status = false; }

		//ok = chown(path, "root", "root");
		//if (!ok){ status = false; }
		
		return status;
	}

	public string init_backup_path(){
		
		string backup_path = get_backup_path();

		if (!dir_exists(backup_path)){
			dir_create(backup_path);
			chmod(backup_path, "a+rwx");
		}
		
		return backup_path;
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
	
	// restore ---------------------------------------
	
	public bool restore_cache(string _basepath, bool _apply_selections){

		basepath = _basepath;
		
		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Restore"), Messages.TASK_CACHE));
		log_msg(string.nfill(70,'-'));

		string backup_cache = get_backup_path() + "/%s".printf(distro.dist_type);

		if (!dir_exists(backup_cache)){
			log_error("%s: %s".printf(_("Directory not found"), backup_cache));
			return false;
		}

		read_selections();

		string system_cache = "";
		string filter = "";

		switch(distro.dist_type){
		case "fedora":
			log_error("%s: %s".printf(Messages.CACHE_NOT_SUPPORTED,"dnf/yum"));
			return false;
			
		case "arch":
			system_cache = "/var/cache/pacman/pkg";
			filter = " --include=\"*.tar.xz\" --include=\"*.txz\" --exclude=\"*\"";
			break;

		case "debian":
			system_cache = "/var/cache/apt/archives";
			filter = " --include=\"*.deb\" --exclude=\"*\"";
			break;

		default:
			log_error(Messages.UNKNOWN_DISTRO);
			return false;
		}

		string cmd = "rsync -avh";

		if (dry_run){
			cmd += " --dry-run";
		}
		
		cmd += " --exclude=lock --exclude=partial --exclude=apt-fast";
		cmd += filter;
		cmd += " '%s/'".printf(escape_single_quote(backup_cache));
		cmd += " '%s/'".printf(escape_single_quote(system_cache));

		int status = 0;
		
		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug("$ %s".printf(cmd));
			status = Posix.system(cmd);
		}

		log_msg("");
		update_permissions_for_restored_files(system_cache, dry_run);
		
		log_msg("");
		log_msg(Messages.RESTORE_OK);

		return (status == 0);
	}

	public bool update_permissions_for_restored_files(string path, bool dry_run) {

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

	// clear -----------------------------------------
	
	public bool clear_system_cache(bool no_prompt){

		string cmd = "";
		
		switch(distro.dist_type){
			
		case "fedora":
			log_error("%s: %s".printf(Messages.CACHE_NOT_SUPPORTED,"dnf/yum"));
			return false;

		case "arch":
			cmd = distro.package_manager;
			
			if (no_prompt){
				cmd += " --noconfirm";
			}
			
			cmd += " -Sc";
			break;

		case "debian":
			cmd = distro.package_manager;
			cmd += " clean";
			break;

		default:
			log_error(Messages.UNKNOWN_DISTRO);
			return false;
		}

		int status = 0;
		
		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug("$ %s".printf(cmd));
			status = Posix.system(cmd);
		}

		log_msg(string.nfill(70,'-'));

		if (status == 0){
			log_msg(_("Removed packages from system cache"));
			log_msg(string.nfill(70,'-'));
		}

		return (status == 0);
	}

}
