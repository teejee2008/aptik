/*
 * RepoManager.vala
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

public class RepoManager : BackupManager {

	public Gee.HashMap<string,Repo> repos = new Gee.HashMap<string,Repo>();

	public RepoManager(LinuxDistro _distro, User _current_user, string _basepath, bool _dry_run, bool _redist, bool _apply_selections){

		base(_distro, _current_user, _basepath, _dry_run, _redist, _apply_selections, "repos");

		check_repos();
	}

	// check -------------------------------------------

	public void check_repos(){

		log_debug("check_repos()");

		repos = new Gee.HashMap<string,Repo>();
		
		switch(distro.dist_type){
		case "fedora":
			check_repos_fedora();
			break;
		case "arch":
			check_repos_arch();
			break;
		case "debian":
			check_repos_debian();
			break;
		}
	}

	public void check_repos_fedora(){
		
		// NOT IMPLEMENTED

		log_msg(_("Not Implemented"));
	}

	public void check_repos_arch(){
		
		string txt = file_read("/etc/pacman.conf");

		Repo repo = null;
		
		foreach(string line in txt.split("\n")){

			if (line.strip().has_prefix("#")){ continue; }

			var match = regex_match("""\[(.*)\]""", line);
				
			if (match != null){
				
				string name = match.fetch(1).strip();

				if (name == "options"){ continue; }

				repo = new Repo.from_name(name);
				repo.is_selected = true;
				repo.is_installed = true;
				repo.type = "unofficial";
				repos[name] = repo;

				repo.text = "%s\n".printf(line);
				
				continue;
			}

			if (repo != null){
				if (line.strip().length > 0){
					repo.text += "%s\n".printf(line);
				}
				else{
					repo = null; // finish appending lines
				}
			}
		}
	}

	public void check_repos_debian(){
		
		var list = dir_list_names("/etc/apt", true);
		var list2 = dir_list_names("/etc/apt/sources.list.d", true);
		list.add_all(list2);

		foreach(string list_file in list){
			
			if (!list_file.has_suffix(".list")){ continue; } // .list.save will be excluded as well
			if (file_basename(list_file) == "sources.list"){ continue; }

			bool repo_added = false;

			string txt = file_read(list_file);
			
			foreach(string line in txt.split("\n")){

				var match = regex_match("""^deb http://ppa.launchpad.net/([a-z0-9.-]+/[a-z0-9.-]+)""", line);
				
				if (match != null){
					
					string name = match.fetch(1).strip();

					var repo = new Repo.from_name(name);
					repo.is_selected = true;
					repo.is_installed = true;
					repo.type = "lp";
					repos[name] = repo;

					repo_added = true;
				}
			}

			if (!repo_added){
				var repo = new Repo.from_list_file_debian(list_file);
				repo.is_selected = true;
				repo.is_installed = true;
				repo.type = "";
				repos[repo.name] = repo;
			}
		}

		check_packages_in_repo_debian();
	}

	private void check_packages_in_repo_debian(){

		try{
			FileInfo info;
			File file = File.new_for_path("/var/lib/apt/lists");
			FileEnumerator enumerator = file.enumerate_children ("%s".printf(FileAttribute.STANDARD_NAME), 0);
			
			while ((info = enumerator.next_file()) != null) {
				
				string file_name = info.get_name();
				if (!file_name.has_suffix("_Packages")){ continue; }

				Repo? repo = null;
				
				var match = regex_match("""ppa\.launchpad\.net_([^_]*)_([^_]*)""", file_name);
				
				if (match != null){
					
					string name = "%s/%s".printf(match.fetch(1), match.fetch(2));
					
					if (repos.has_key(name)){
						repo = repos[name];
					}
				}
				
				if (repo == null){

					//log_debug("file_name: " + file_name);

					foreach(var item in repos.values){
						
						var suggested = item.suggested_list_file_name();

						if ((suggested.length > 0) && file_name.contains(suggested)){
							repo = item;
							//log_debug("repo-match: " + repo.name);
							break;
						}
					}
				}

				if (repo == null){
					//log_msg("W: Repo not found for package list: %s".printf(file_name));
					continue;
				}

				string file_path = path_combine("/var/lib/apt/lists", file_name);

				var list = new Gee.ArrayList<string>();
				
				foreach(string line in file_read(file_path).split("\n")){

					var match2 = regex_match("""Package: (.*)""", line);
					
					if (match2 != null){

						string pkgname = match2.fetch(1);
						
						if (!list.contains(pkgname)){
							list.add(pkgname);
						}
						
						continue;
					}

					// NOTE: A single list file can have info for packages of multiple architectures
				}

				if (list.size == 0) { continue; } // continue with next file

				list.sort((a,b) => {
					return (a.length - b.length);
				});

				repo.description = "";
				for(int i=0; (i < 10) && (i < list.size) && (repo.description.length < 50); i++){
					if (repo.description.length > 0){
						repo.description += " ";
					}
					repo.description += list[i];
				}

				if (repo.is_disabled){
					repo.description += "(disabled) ";
				}
			}
		}
		catch(Error e){
			log_error(e.message);
		}
	}
	
	public Gee.ArrayList<Repo> repos_sorted {
		owned get{

			var list = new Gee.ArrayList<Repo>();
		
			foreach(var pkg in repos.values) {
				list.add(pkg);
			}

			list.sort((a, b) => {
				if (a.type == b.type){
					return strcmp(a.name, b.name);
				}
				else{
					return strcmp(a.type, b.type);
				}
			});

			return list;
		}
	}

	// list ---------------------------------------

	public void dump_info(){

		string txt = "";
		
		foreach(var repo in repos_sorted){
			
			if (!repo.is_installed){ continue; }
			
			txt += "NAME='%s'".printf(repo.name);

			txt += ",DESC='%s'".printf(repo.description);
			
			txt += ",ACT='%s'".printf(repo.is_disabled ? "0" : "1");
			
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

		var list = dir_list_names(files_path, true);
		
		foreach(string file_path in list) {

			string ftext = file_read(file_path);
			
			if (ftext.strip().length == 0) { continue; }

			string name = file_basename(file_path);
			string desc = "";
			bool disabled = false;
			
			if (name == "CODENAME"){ continue; }

			if (name == "apt.keys"){ continue; }

			if (name == "exclude.list"){ continue; }

			if (name == "launchpad-ppas.list"){

				foreach(var line in ftext.split("\n")){

					if (line.strip().length == 0){ continue; }

					if (line.strip().has_prefix("#")){ continue; }
					
					if (line.contains("#")){
						name = line.split("#")[0].strip();
						desc = line.split("#")[1].strip();
					}
					else{
						name = line.strip();
					}

					txt += get_dump_line(name, desc, false);
				}
			}
			else {

				name = name.replace(".list","");
				
				foreach(var line in ftext.split("\n")){
					if (line.strip().has_prefix("# aptik-desc:")){
						desc = line.split("# aptik-desc:")[1].strip();
					}
				}

				bool has_lines = false;
				foreach(var line in ftext.split("\n")){
					if ((line.strip().length > 0) && !line.strip().has_prefix("#")){
						has_lines = true;
						break;
					}
				}
				disabled = !has_lines;
			}

			txt += get_dump_line(name, desc, disabled);
		}
		
		log_msg(txt);
	}

	private string get_dump_line(string name, string desc, bool disabled){

		string txt = "";
		
		bool is_available = false;
		bool is_installed = false;
		
		if (repos.has_key(name)){
			is_available = true;
			is_installed = repos[name].is_installed;
		}

		txt += "NAME='%s'".printf(name);

		txt += ",DESC='%s'".printf(desc);
		
		txt += ",INST='%s'".printf(is_installed ? "1" : "0");

		txt += ",ACT='%s'".printf(is_installed ? "0" : "1");
			
		txt += ",SENS='%s'".printf(is_installed ? "0" : "1");

		txt += ",DIS='%s'".printf(disabled ? "1" : "0");
			
		txt += "\n";

		return txt;
	}
	
	public bool list_repos(){

		repos_sorted.foreach((repo) => {

			string txt = "";
			if (repo.type.length > 0){
				txt += "%s:".printf(repo.type);
			}
			txt += repo.name;
			
			txt = "%-40s".printf(txt);

			if (repo.description.length > 0){
				txt += " -- %s".printf(repo.description);
			}
			
			log_msg(txt);

			return true;
		});

		return true;
	}

	// save ---------------------------------------

	public bool save_repos(){

		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Backup"), Messages.TASK_REPOS));
		log_msg(string.nfill(70,'-'));

		init_backup_path();
		
		read_selections();

		string backup_file = path_combine(backup_path, "CODENAME");
		file_write(backup_file, distro.codename);
		
		switch(distro.dist_type){
		case "fedora":
			return save_repos_fedora(backup_path + "/files");
		case "arch":
			return save_repos_arch(backup_path + "/files");
		case "debian":
			return save_repos_debian(backup_path + "/files");
		default:
			log_msg(_("Nothing to save"));
			return false;
		}
	}

	public bool save_repos_fedora(string backup_path){

		// NOT IMPLEMENTED

		log_msg(_("Not Implemented"));
		return false;
	}

	public bool save_repos_arch(string backup_path){

		bool status = true;

		foreach(var repo in repos_sorted){
	
			if (repo.is_installed && (repo.name.length > 0)){

				if (exclude_list.contains(repo.name)){ continue; }
				
				string backup_file = path_combine(backup_path, "%s.repo".printf(repo.name));
				
				bool ok = file_write(backup_file, repo.text);
				
				if (!ok){ status = false; continue; }
				
				chmod(backup_file, "a+rw");
				log_msg("%s: %s".printf(_("Saved"), backup_file));
			}
		}

		bool ok = export_keys_arch(backup_path);
		if (!ok){ status = false; }

		if (status){
			log_msg(Messages.BACKUP_OK);
		}
		else{
			log_error(Messages.BACKUP_ERROR);
		}

		return status;
	}

	public bool save_repos_debian(string backup_path){
	
		bool ok, status = true;

		ok = save_repos_apt_launchpad(backup_path);
		if (!ok){ status = false; }
		
		ok = save_repos_apt_custom(backup_path);
		if (!ok){ status = false; }

		ok = export_keys_debian(backup_path);
		if (!ok){ status = false; }
		
		if (status){
			log_msg(Messages.BACKUP_OK);
		}
		else{
			log_error(Messages.BACKUP_ERROR);
		}

		return status;
	}
	
	public bool save_repos_apt_launchpad(string backup_path) {

		string backup_file = path_combine(backup_path, "launchpad-ppas.list");

		string text = "\n# Comment-out or remove lines for unwanted items\n\n";

		foreach(var repo in repos_sorted){

			if (exclude_list.contains(repo.name)){ continue; }
	
			if (repo.is_installed && (repo.type == "lp")){
				
				text += "%s".printf(repo.name);
				
				if (repo.description.length > 0){
					text += " # %s".printf(repo.description);
				}
				
				text += "\n";
			}
		}

		bool ok = file_write(backup_file, text);

		if (ok){
			chmod(backup_file, "a+rw");
			log_msg("%s: %s".printf(_("Saved"), backup_file.replace(basepath, "$basepath")));
		}

		return ok;
	}

	public bool save_repos_apt_custom(string backup_path) {

		bool status = true;
		
		foreach(var repo in repos_sorted){

			if (exclude_list.contains(repo.name)){ continue; }
			
			if (repo.is_installed && (repo.type == "") && (repo.list_file_path.length > 0)){

				string backup_name = file_basename(repo.list_file_path);
				string backup_file = path_combine(backup_path, backup_name);
				
				bool ok = file_copy(repo.list_file_path, backup_file, false);
				
				if (!ok){ status = false; continue; }
				
				string txt = file_read(backup_file);

				txt += "\n# aptik-desc: %s\n".printf(repo.description);
				
				ok = file_write(backup_file, txt);
				if (!ok){ status = false; continue; }

				chmod(backup_file, "a+rw");
				log_msg("%s: %s".printf(_("Saved"), backup_file.replace(basepath, "$basepath")));
			}
		}

		return status;
	}

	// restore ---------------------------

	public bool restore_repos(){

		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Restore"), Messages.TASK_REPOS));
		log_msg(string.nfill(70,'-'));

		check_repos();

		if (!dir_exists(backup_path)) {
			string msg = "%s: %s".printf(Messages.DIR_MISSING, backup_path);
			log_error(msg);
			return false;
		}

		read_selections();

		switch(distro.dist_type){
		case "fedora":
			return restore_repos_fedora(backup_path + "/files");
		case "arch":
			return restore_repos_arch(backup_path + "/files");
		case "debian":
			return restore_repos_debian(backup_path + "/files");
		}

		return false;
	}

	public bool restore_repos_fedora(string backup_path){

		bool status = true;

		// add repos -------------------------------------
		
		// NOT IMPLEMENTED

		// update repos -------------------------------------
		
		string temp_file;
		bool ok = update_repos_fedora(out temp_file);
		if (!ok){ status = false; }
		
		return status;
	}

	public bool restore_repos_arch(string backup_path){

		bool status = true, ok = true;

		// add repos -------------------------------------
		
		var list = dir_list_names(backup_path, true);
		
		foreach(var backup_file in list){

			string file_name = file_basename(backup_file);
			
			if (file_name == "sources.list"){ continue; } // ignore debian file

			if (file_name == "installed.list"){ continue; } // ignore debian file

			if (file_name == "exclude.list"){ continue; } // ignore exclude file

			if (!file_name.has_suffix(".repo")){ continue; }

			string name = file_name.replace(".repo","");

			if (exclude_list.contains(name)){ continue; }

			if (name == "options"){ continue; }
			
			if (repos.has_key(name)){ continue; }

			string pacman_file = "/etc/pacman.conf";
			string pacman_text = file_read(pacman_file);
			string repo_text = file_read(backup_file);
			pacman_text += "\n%s\n".printf(repo_text);

			if (dry_run){
				log_msg("updated: %s".printf(pacman_file));
				ok = true;
			}
			else{
				ok = file_write(pacman_file, pacman_text);
				if (!ok){ status = false; continue; }
			}

			log_msg("%s: %s".printf(_("Added Repo"), name));
		}

		ok = import_keys_arch(backup_path);
		if (!ok){ status = false; }

		// update repos -------------------------------------
		
		string temp_file;
		ok = update_repos_arch(out temp_file);
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

	public bool restore_repos_debian(string backup_path){

		bool status = true;

		if (!check_package_installed_debian("apt-transport-https")){
			install_package_debian("apt-transport-https");
		}

		// add repos -------------------------------------
		
		bool ok = restore_repos_apt_launchpad(backup_path);
		if (!ok){ status = false; }
		
		ok = restore_repos_apt_custom(backup_path);
		if (!ok){ status = false; }
				
		import_keys_debian(backup_path);

		// update repos and import missing keys -----------------

		log_msg(string.nfill(70,'-'));
		
		import_missing_keys_debian(false);
		if (!ok){ status = false; }
		
		if (status){
			log_msg(Messages.RESTORE_OK);
		}
		else{
			log_error(Messages.RESTORE_ERROR);
		}
		
		return status;
	}
	
	public bool restore_repos_apt_launchpad(string backup_path) {

		bool status = true;
		
		string backup_file = path_combine(backup_path, "launchpad-ppas.list");

		if (!file_exists(backup_file)) {
			
			string msg = "%s: %s".printf(Messages.FILE_MISSING, backup_file);
			log_error(msg);
			return false;
		}

		if (!check_package_installed_debian("software-properties-common")){
			install_package_debian("software-properties-common");
		}

		if (!cmd_exists("add-apt-repository")){
			
			log_error("%s: %s".printf(_("Missing command"), "add-apt-repository"));
			log_error(_("Install required packages and try again"));
			return false; // exit method

			// NOTE: Debian does not have this command, but in that case
			// the installed.list file should be empty. Return error and exit method.
		}

		var added_list = new Gee.ArrayList<string>();
		
		foreach(string line in file_read(backup_file).split("\n")){

			if (line.strip().length == 0) { continue; }
			
			if (line.strip().has_prefix("#")) { continue; }

			string name = line.split("#",2)[0].strip();

			if (exclude_list.contains(name)){ continue; }
			
			if (name.length == 0){ continue; }
			
			if (repos.has_key(name)){ continue; }

			added_list.add(name);

			log_msg("%s: %s\n".printf(_("Repo"), name)); 
			string cmd = "add-apt-repository -y ppa:%s".printf(name);

			int retval = 0;
		
			if (dry_run){
				log_msg("$ %s".printf(cmd));
			}
			else{
				log_debug("$ %s".printf(cmd));
				retval = Posix.system(cmd);
				if (retval != 0){ status = false; }
			}
		
			log_msg(string.nfill(70,'-'));
		}
		
		return status;
	}

	public bool restore_repos_apt_custom(string backup_path) {

		bool status = true, ok;

		string codename = "";
		string codename_file = path_combine(backup_path, "CODENAME");
		if (file_exists(codename_file)){
			codename = file_read(codename_file);
		}

		var list = dir_list_names(backup_path, true);
		
		foreach(string backup_file in list){

			string name = file_basename(backup_file);

			if (name == "sources.list"){ continue; }

			if (name == "launchpad-ppas.list"){ continue; }

			if (name == "exclude.list"){ continue; }

			if (!name.has_suffix(".list")){ continue; }

			name = name.replace(".list","");

			if (exclude_list.contains(name)){ continue; }

			string txt = file_read(backup_file);

			if (name.contains(codename) || txt.contains(codename)){
				if ((distro.codename.length == 0) || (codename != distro.codename)){
					log_msg("%s: %s\n".printf(_("Repo"), name)); 
					log_error("%s: %s".printf(_("Skipping File"), backup_file));
					log_error(_("This repo is meant for another OS release and cannot be added to this system"));
					log_error("Release-Repo: %s, Release-Current: %s".printf(codename, distro.codename));
					log_msg(string.nfill(70,'-'));
					continue;
				}
			}

			if (repos.has_key(name)){ continue; }

			log_msg("%s: %s\n".printf(_("Repo"), name)); 

			string list_name = file_basename(backup_file);
			string list_file = path_combine("/etc/apt/sources.list.d", list_name);

			if (dry_run){
				log_msg("cp: '%s' -> '%s'".printf(backup_file, list_file));
				log_msg("%s: %s".printf(_("Installed"), list_file));
				log_msg(string.nfill(70,'-'));
				continue;
			}

			ok = file_copy(backup_file, list_file, false);
			
			if (!ok){ status = false; }
			else{
				txt = file_read(list_file);
				ok = file_write(list_file, txt);
				if (!ok){ status = false; }
				else{
					log_msg("%s: %s".printf(_("Installed"), list_file));
				}
			}

			log_msg(string.nfill(70,'-'));
		}

		return status;
	}

	public bool check_package_installed_debian(string pkgname){

		string cmd = "dpkg -s %s 2>/dev/null | grep Status | grep installed > /dev/null".printf(pkgname);
		
		int retval = Posix.system(cmd);

		return (retval == 0);
	}
	
	public bool install_package_debian(string pkgname){

		string cmd = "apt-get install -y %s".printf(pkgname);

		int retval = 0;
		
		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug("$ %s".printf(cmd));
			retval = Posix.system(cmd);
		}

		log_msg(string.nfill(70,'-'));

		return (retval == 0);
	}
	
	// keys ------------------------------------

	public bool import_keys(string basepath){

		
		
		if (!dir_exists(backup_path)) {
			string msg = "%s: %s".printf(Messages.DIR_MISSING, backup_path);
			log_error(msg);
			return false;
		}

		switch(distro.dist_type){
		case "fedora":
			return import_keys_fedora(backup_path);
		case "arch":
			return import_keys_arch(backup_path);
		case "debian":
			return import_keys_debian(backup_path);
		}

		return false;
	}

	public bool import_keys_fedora(string backup_path){

		// NOT IMPLEMENTED

		log_msg(_("Not Implemented"));
		return false;
	}

	public bool export_keys_arch(string backup_path){

		if (!cmd_exists("pacman-key")){
			log_error("%s: %s".printf(_("Missing command"), "pacman-key"));
			log_error(_("Install required packages and try again"));
			return false; // exit method
		}

		string backup_file = path_combine(backup_path, "pacman.keys");

		file_delete(backup_file); // delete existing

		string cmd = "pacman-key -e > '%s'".printf(escape_single_quote(backup_file));

		int retval = 0;
		
		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug("$ %s".printf(cmd));
			retval = Posix.system(cmd);
		}
		
		if (file_exists(backup_file)){
			log_msg("%s: %s".printf(_("Keys exported"), backup_file));
			log_msg(string.nfill(70,'-'));
		}
		else{
			log_error(_("Failed to export keys"));
			log_error(string.nfill(70,'-'));
		}

		return (retval == 0);
	}
	
	public bool import_keys_arch(string backup_path){

		if (!cmd_exists("pacman-key")){
			log_error("%s: %s".printf(_("Missing command"), "pacman-key"));
			log_error(_("Install required packages and try again"));
			return false; // exit method
		}

		string backup_file = path_combine(backup_path, "pacman.keys");

		if (!file_exists(backup_file)){
			return true;
		}

		string cmd = "pacman-key --add '%s'".printf(escape_single_quote(backup_file));

		int retval = 0;
		
		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug("$ %s".printf(cmd));
			retval = Posix.system(cmd);
		}
		
		if (retval == 0){
			log_msg("%s: %s".printf(_("Keys imported"), backup_file));
			log_msg(string.nfill(70,'-'));
		}
		else{
			log_error(_("Error while importing keys"));
			log_error(string.nfill(70,'-'));
		}

		return (retval == 0);
	}

	public bool export_keys_debian(string backup_path){

		if (!cmd_exists("apt-key")){
			log_error("%s: %s".printf(_("Missing command"), "apt-key"));
			log_error(_("Install required packages and try again"));
			return false; // exit method
		}

		string backup_file = path_combine(backup_path, "apt.keys");

		file_delete(backup_file);

		string cmd = "apt-key exportall > '%s'".printf(escape_single_quote(backup_file));

		int retval = 0;
		
		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug("$ %s".printf(cmd));
			retval = Posix.system(cmd);
		}
		
		if (retval == 0){
			log_msg("%s: %s".printf(_("Keys exported"), backup_file));
		}
		else{
			log_error(_("Error while exporting keys"));
		}

		return (retval == 0);
	}
	
	public bool import_keys_debian(string backup_path){

		if (!cmd_exists("apt-key")){
			log_error("%s: %s".printf(_("Missing command"), "apt-key"));
			log_error(_("Install required packages and try again"));
			return false; // exit method
		}

		string backup_file = path_combine(backup_path, "apt.keys");

		if (!file_exists(backup_file)){
			return true;
		}

		string cmd = "apt-key add '%s'".printf(escape_single_quote(backup_file));

		int retval = 0;
		
		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug("$ %s".printf(cmd));
			retval = Posix.system(cmd);
		}
		
		if (retval == 0){
			log_msg("%s: %s".printf(_("Keys imported"), backup_file));
		}
		else{
			log_error(_("Error while importing keys"));
		}

		return (retval == 0);
	}
	
	// missing keys  ----------------------------
	
	public bool import_missing_keys(bool show_message){

		switch(distro.dist_type){
		case "fedora":
			log_error("%s".printf(_("NOT SUPPORTED")));
			return false;
		case "arch":
			log_error("%s".printf(_("NOT SUPPORTED")));
			return false;
		case "debian":
			return import_missing_keys_debian(show_message);
		}

		return false;
	}

	public bool import_missing_keys_debian(bool show_message){

		if (!cmd_exists("apt-key")){
			log_error("%s: %s".printf(_("Missing command"), "apt-key"));
			log_error(_("Install required packages and try again"));
			return false; // exit method
		}

		bool ok = true;

		string temp_file;
		update_repos_debian(out temp_file);

		if (!file_exists(temp_file)){ return true; }

		string txt = file_read(temp_file);

		if (txt.contains("NO_PUBKEY")){
			log_msg(_("Importing missing apt keys..."));
			log_msg(string.nfill(70,'-'));
		}

		var keys_added = new Gee.ArrayList<string>();

		foreach(string line in txt.split("\n")){
			
			if (line.strip().length == 0){ continue; }
			if (!line.contains("NO_PUBKEY")){ continue; }

			var match = regex_match("""NO_PUBKEY ([0-9A-Za-z]*)""", line);
			
			if (match != null){
				
				string key = match.fetch(1);

				if (!cmd_exists("apt-key")){
					log_error("%s: %s".printf(_("Missing command"), "apt-key"));
					log_error(_("Install required packages and try again"));
					return false; // exit method
				}

				if (keys_added.contains(key)){ continue; }
				keys_added.add(key);

				string cmd = "apt-key adv --keyserver keyserver.ubuntu.com --recv-keys %s".printf(key);

				int retval = 0;
		
				if (dry_run){
					log_msg("$ %s".printf(cmd));
				}
				else{
					log_debug("$ %s".printf(cmd));
					retval = Posix.system(cmd);
				}
		
				if (retval != 0){
					ok = false;
				}

				log_msg(string.nfill(70,'-'));
			}
		}

		if (keys_added.size > 0){

			if (ok){
				log_msg(_("Missing apt keys imported successfully"));
			}
			
			if (!update_repos_debian(out temp_file)){
				ok = false;
			}
		}
		else{
			if (show_message){
				log_msg(_("No missing apt keys"));
			}
		}

		log_msg(string.nfill(70,'-'));

		return ok;
	}

	// update ----------------------

	public bool update_repos(){

		string temp_file = "";
		
		switch(distro.dist_type){
		case "fedora":
			return update_repos_fedora(out temp_file);
		case "arch":
			return update_repos_arch(out temp_file);
		case "debian":
			return update_repos_debian(out temp_file);
		}

		temp_file = "";

		return false;
	}

	public bool update_repos_fedora(out string temp_file){

		log_msg("%s\n".printf(_("Updating package information...")));
		
		temp_file = get_temp_file_path();
		log_debug(temp_file);

		string cmd = distro.package_manager;
		cmd += " check-update | tee '%s'".printf(escape_single_quote(temp_file));
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

	public bool update_repos_arch(out string temp_file){

		log_msg("%s\n".printf(_("Updating package information...")));
		
		temp_file = get_temp_file_path();
		log_debug(temp_file);

		string cmd = distro.package_manager;
		cmd += " -Sy | tee '%s'".printf(escape_single_quote(temp_file));
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

	public bool update_repos_debian(out string temp_file){
	
		log_msg("%s\n".printf(_("Updating package information...")));
		
		temp_file = get_temp_file_path();
		log_debug(temp_file);

		string cmd = distro.package_manager;
		cmd += " update | tee '%s'".printf(escape_single_quote(temp_file));
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
}
