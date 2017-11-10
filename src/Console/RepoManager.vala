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

public class RepoManager : GLib.Object {

	public Gee.HashMap<string,Repo> repos;

	public LinuxDistro distro;
	public bool dry_run = false;
	public bool list_only = false;
	
	public RepoManager(LinuxDistro _distro, bool _dry_run, bool _list_only){

		distro = _distro;

		dry_run = _dry_run;

		list_only = _list_only;

		check_repos();
	}
	
	// check -------------------------------------------

	public void check_repos(){

		if (!list_only){
			log_msg("Checking installed repos...");
		}

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

		if (!list_only){
			log_msg("Found: %d".printf(repos.size));
			log_msg(string.nfill(70,'-'));
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
			
			if (!list_file.has_suffix(".list")){ continue; }
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
					repo.type = "launchpad";
					repos[name] = repo;

					repo_added = true;
				}
			}

			if (!repo_added){
				var repo = new Repo.from_list_file(list_file);
				repo.is_selected = true;
				repo.is_installed = true;
				repo.type = "unoffical";
				repos[repo.name] = repo;
			}
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

	public bool list_repos(){

		repos_sorted.foreach((repo) => {
			
			log_msg("repo-%s: %s".printf(repo.type, repo.name));

			return true;
		});

		return true;
	}

	// save ---------------------------------------

	public bool save_repos(string basepath){

		if (dry_run){
			log_msg(_("Nothing to do (--dry-run mode)"));
			log_msg(string.nfill(70,'-'));
			return true;
		}

		log_msg(_("Saving installed repos..."));

		string backup_path = path_combine(basepath, "repos");
		dir_delete(backup_path); // remove existing .list files
		dir_create(backup_path);

		switch(distro.dist_type){
		case "fedora":
			return save_repos_fedora(backup_path);
		case "arch":
			return save_repos_arch(backup_path);
		case "debian":
			return save_repos_debian(backup_path);
		}

		log_msg(_("Nothing to save"));
		log_msg(string.nfill(70,'-'));

		return false;
	}

	public bool save_repos_fedora(string backup_path){

		// NOT IMPLEMENTED

		log_msg(_("Not Implemented"));
		return false;
	}

	public bool save_repos_arch(string backup_path){

		bool status = true;

		repos_sorted.foreach((repo) => {
	
			if (repo.is_installed && (repo.name.length > 0)){
				string backup_file = path_combine(backup_path, "%s.repo".printf(repo.name));
				bool ok = file_write(backup_file, repo.text);
				if (!ok){ status = false; }
				if (ok){ log_msg("%s: %s".printf(_("Saved"), backup_file)); }
			}
			
			return true;
		});

		bool ok = export_keys_arch(backup_path);
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

	public bool save_repos_debian(string backup_path){
	
		bool ok, status = true;

		ok = save_repos_apt_launchpad(backup_path);
		if (!ok){ status = false; }
		
		ok = save_repos_apt_custom(backup_path);
		if (!ok){ status = false; }

		ok = export_keys_debian(backup_path);
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
	
	public bool save_repos_apt_launchpad(string backup_path) {

		string backup_file = path_combine(backup_path, "launchpad-ppas.list");

		string text = "\n# Comment-out or remove lines for unwanted items\n\n";

		repos_sorted.foreach((repo) => {
	
			if (repo.is_installed && (repo.name.length > 0)){
				text += "%s\n".printf(repo.name);
				//text += "%s #%s\n".printf(ppa.name, ppa.description); // TODO: ppa description
			}
			return true;
		});

		bool ok = file_write(backup_file, text);

		if (ok){
			chmod(backup_file, "a+rw");
			log_msg("%s: %s".printf(_("Saved"), backup_file));
		}

		return ok;
	}

	public bool save_repos_apt_custom(string backup_path) {

		bool status = true;
		
		foreach(var repo in repos_sorted){
			
			if (repo.is_installed && (repo.name.length == 0) && (repo.list_file_path.length > 0)){

				string backup_name = file_basename(repo.list_file_path).replace(distro.codename, "CODENAME");
				string backup_file = path_combine(backup_path, backup_name);
				
				bool ok = file_copy(repo.list_file_path, backup_file);
				if (!ok){ status = false; continue; }
				
				string txt = file_read(backup_file);
				txt = txt.replace(distro.codename, "CODENAME");
				ok = file_write(backup_file, txt);
				if (!ok){ status = false; continue; }

				chmod(backup_file, "a+rw");
				log_msg("%s: %s".printf(_("Saved"), backup_file));
			}
		}

		string backup_file = path_combine(backup_path, "CODENAME");
		bool ok = file_write(backup_file, distro.codename);
		if (!ok){ status = false; }

		return status;
	}

	// restore ---------------------------

	public bool restore_repos(string basepath){

		string backup_path = path_combine(basepath, "repos");
		
		if (!dir_exists(backup_path)) {
			string msg = "%s: %s".printf(Message.DIR_MISSING, backup_path);
			log_error(msg);
			return false;
		}

		switch(distro.dist_type){
		case "fedora":
			return restore_repos_fedora(backup_path);
		case "arch":
			return restore_repos_arch(backup_path);
		case "debian":
			return restore_repos_debian(backup_path);
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

		bool status = true;

		// add repos -------------------------------------
		
		var list = dir_list_names(backup_path, true);
		
		list.foreach((backup_file) => {

			string file_name = file_basename(backup_file);
			
			if (file_name == "sources.list"){ return true; } // ignore debian file

			if (file_name == "installed.list"){ return true; } // ignore debian file

			if (!file_name.has_suffix(".repo")){ return true; }

			string name = file_name.replace(".repo","");

			if (name == "options"){ return true; }
			
			if (repos.has_key(name)){ return true; }

			if (dry_run){
				log_msg("Add repo: %s".printf(name));
				return true;
			}

			string pacman_file = "/etc/pacman.conf";
			string pacman_text = file_read(pacman_file);
			string repo_text = file_read(backup_file);
			pacman_text += "\n%s\n".printf(repo_text);
			
			bool ok = file_write(pacman_file, pacman_text);
			if (!ok){ status = false; return true; }

			log_msg("%s: %s".printf(_("Added Repo"), name));

			return true;
		});

		bool ok = import_keys_arch(backup_path);
		if (!ok){ status = false; }

		// update repos -------------------------------------
		
		string temp_file;
		ok = update_repos_arch(out temp_file);
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

	public bool restore_repos_debian(string backup_path){

		bool status = true;

		int retval = Posix.system("dpkg -s apt-transport-https | grep Status | grep installed > /dev/null");
		if (retval != 0){
			Posix.system("apt-get install -y apt-transport-https");
			log_msg(string.nfill(70,'-'));
		}

		// add repos -------------------------------------
		
		bool ok = restore_repos_apt_launchpad(backup_path);
		if (!ok){ status = false; }
		
		ok = restore_repos_apt_custom(backup_path);
		if (!ok){ status = false; }
				
		if (dry_run){
			log_msg(_("Nothing to do (--dry-run mode)"));
			log_msg(string.nfill(70,'-'));
			return true;
		}

		import_keys_debian(backup_path);

		// update repos and import missing keys -----------------
		
		import_missing_keys_debian(false);
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
	
	public bool restore_repos_apt_launchpad(string backup_path) {

		string backup_file = path_combine(backup_path, "launchpad-ppas.list");

		if (!file_exists(backup_file)) {
			string msg = "%s: %s".printf(Message.FILE_MISSING, backup_file);
			log_error(msg);
			return false;
		}

		var added_list = new Gee.ArrayList<string>();
		
		foreach(string line in file_read(backup_file).split("\n")){

			if (line.strip().length == 0) { continue; }
			
			if (line.strip().has_prefix("#")) { continue; }

			string name = line;
			
			if (name.length == 0){ continue; }
			if (repos.has_key(name)){ continue; }

			if (dry_run){
				log_msg("Add Launchpad PPA: %s".printf(name));
				continue;
			}

			if (!cmd_exists("add-apt-repository")){
				log_error("%s: %s".printf(_("Missing command"), "add-apt-repository"));
				log_error(_("Install required packages and try again"));
				return false; // exit method

				// NOTE: Debian does not have this command, but in that case
				// the installed.list file should be empty. Return error and exit method.
			}

			added_list.add(name);

			log_msg("%s: %s\n".printf(_("Repo"), name)); 
			string cmd = "add-apt-repository -y ppa:%s\n".printf(name);
			Posix.system(cmd);
			log_msg(string.nfill(70,'-'));
		}
		
		return true;
	}

	public bool restore_repos_apt_custom(string backup_path) {

		bool status = true;

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

			if (!name.has_suffix(".list")){ continue; }

			name = name.replace(".list","");

			string txt = file_read(backup_file);

			if (name.contains("CODENAME") || txt.contains("CODENAME")){
				if ((distro.codename.length == 0) || (codename != distro.codename)){
					log_msg("%s: %s\n".printf(_("Repo"), name.replace("CODENAME", codename))); 
					log_error("%s: %s".printf(_("Skipping File"), backup_file.replace("CODENAME", codename)));
					log_error(_("This repo is meant for another OS release and cannot be added to this system"));
					log_error("Release-Repo: %s, Release-Current: %s".printf(codename, distro.codename));
					log_msg(string.nfill(70,'-'));
					continue;
				}
			}

			name = name.replace("CODENAME", distro.codename);
			
			if (repos.has_key(name)){ continue; }

			log_msg("%s: %s\n".printf(_("Repo"), name.replace("CODENAME", distro.codename))); 

			string list_name = file_basename(backup_file).replace("CODENAME", distro.codename);
			string list_file = path_combine("/etc/apt/sources.list.d", list_name);

			if (dry_run){
				log_msg("%s: %s".printf(_("Install source list"), list_file));
				log_msg(string.nfill(70,'-'));
				continue;
			}

			bool ok = file_copy(backup_file, list_file);
			if (!ok){ status = false; }
			else{
				txt = file_read(list_file);
				txt = txt.replace("CODENAME", distro.codename);
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

	// keys ------------------------------------

	public bool import_keys(string basepath){

		string backup_path = path_combine(basepath, "repos");
		
		if (!dir_exists(backup_path)) {
			string msg = "%s: %s".printf(Message.DIR_MISSING, backup_path);
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

		bool ok = true;

		string backup_file = path_combine(backup_path, "pacman.keys");

		file_delete(backup_file); // delete existing

		string cmd = "pacman-key -e > '%s'".printf(escape_single_quote(backup_file));
		log_debug(cmd);
		Posix.system(cmd);
		
		if (file_exists(backup_file)){
			log_msg("%s: %s".printf(_("Keys exported"), backup_file));
			log_msg(string.nfill(70,'-'));
		}
		else{
			log_error(_("Failed to export keys"));
			log_error(string.nfill(70,'-'));
		}

		return ok;
	}
	
	public bool import_keys_arch(string backup_path){

		if (!cmd_exists("pacman-key")){
			log_error("%s: %s".printf(_("Missing command"), "pacman-key"));
			log_error(_("Install required packages and try again"));
			return false; // exit method
		}

		bool ok = true;

		string backup_file = path_combine(backup_path, "pacman.keys");

		if (!file_exists(backup_file)){
			return true;
		}

		string cmd = "pacman-key --add '%s'".printf(escape_single_quote(backup_file));
		log_debug(cmd);
		int retval = Posix.system(cmd);
		
		if (retval == 0){
			log_msg("%s: %s".printf(_("Keys imported"), backup_file));
			log_msg(string.nfill(70,'-'));
		}
		else{
			log_error(_("Error while importing keys"));
			log_error(string.nfill(70,'-'));
		}

		return ok;
	}

	public bool export_keys_debian(string backup_path){

		if (!cmd_exists("apt-key")){
			log_error("%s: %s".printf(_("Missing command"), "apt-key"));
			log_error(_("Install required packages and try again"));
			return false; // exit method
		}

		bool ok = true;

		string backup_file = path_combine(backup_path, "apt.keys");

		file_delete(backup_file);

		string cmd = "apt-key exportall > '%s'".printf(escape_single_quote(backup_file));
		log_debug(cmd);
		int retval = Posix.system(cmd);
		
		if (retval == 0){
			log_msg("%s: %s".printf(_("Keys exported"), backup_file));
			log_msg(string.nfill(70,'-'));
		}
		else{
			//log_error(_("Error while exporting keys"));
			log_error(string.nfill(70,'-'));
		}

		return ok;
	}
	
	public bool import_keys_debian(string backup_path){

		if (!cmd_exists("apt-key")){
			log_error("%s: %s".printf(_("Missing command"), "apt-key"));
			log_error(_("Install required packages and try again"));
			return false; // exit method
		}

		bool ok = true;

		string backup_file = path_combine(backup_path, "apt.keys");

		if (!file_exists(backup_file)){
			return true;
		}

		string cmd = "apt-key add '%s'".printf(escape_single_quote(backup_file));
		log_debug(cmd);
		int retval = Posix.system(cmd);
		
		if (retval == 0){
			log_msg("%s: %s".printf(_("Keys imported"), backup_file));
			log_msg(string.nfill(70,'-'));
		}
		else{
			//log_error(_("Error while importing keys"));
			log_error(string.nfill(70,'-'));
		}

		return ok;
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
				log_debug(cmd);
		
				int retval = Posix.system(cmd);
				if (retval != 0){
					ok = false;
				}

				log_msg(string.nfill(70,'-'));
			}
		}

		if (keys_added.size > 0){

			if (ok){
				log_msg(_("Missing apt keys imported successfully"));
				log_msg(string.nfill(70,'-'));
			}
			
			if (!update_repos_debian(out temp_file)){
				ok = false;
			}
		}
		else{
			if (show_message){
				log_msg(_("No missing apt keys"));
				log_msg(string.nfill(70,'-'));
			}
		}

		return ok;
	}

	// update ----------------------

	public bool update_repos(string basepath, out string temp_file){

		temp_file = "";
		
		if (dry_run){
			log_msg(_("Nothing to do (--dry-run mode)"));
			log_msg(string.nfill(70,'-'));
			return true;
		}

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

		log_msg(_("Updating package information..."));
		
		temp_file = get_temp_file_path();
		log_debug(temp_file);

		string cmd = distro.package_manager;
		cmd += " check-update | tee '%s'".printf(escape_single_quote(temp_file));
		log_debug(cmd);
		
		int status = Posix.system(cmd);

		log_msg(string.nfill(70,'-'));
		
		return (status == 0);
	}

	public bool update_repos_arch(out string temp_file){

		log_msg(_("Updating package information..."));
		
		temp_file = get_temp_file_path();
		log_debug(temp_file);

		string cmd = distro.package_manager;
		cmd += " -Sy | tee '%s'".printf(escape_single_quote(temp_file));
		log_debug(cmd);
		
		int status = Posix.system(cmd);

		log_msg(string.nfill(70,'-'));
		
		return (status == 0);
	}

	public bool update_repos_debian(out string temp_file){
	
		log_msg(_("Updating package information..."));
		
		temp_file = get_temp_file_path();
		log_debug(temp_file);

		string cmd = distro.package_manager;
		cmd += " update | tee '%s'".printf(escape_single_quote(temp_file));
		log_debug(cmd);
		
		int status = Posix.system(cmd);

		log_msg(string.nfill(70,'-'));
		
		return (status == 0);
	}
	
}
