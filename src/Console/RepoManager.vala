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
	
	public RepoManager(LinuxDistro _distro, bool _dry_run){

		distro = _distro;

		dry_run = _dry_run;

		check_repos();
	}
	
	// check -------------------------------------------

	public void check_repos(){

		log_msg("Checking installed repos...");

		log_debug("check_repos()");

		repos = new Gee.HashMap<string,Repo>();
		
		switch(distro.package_manager){
		case "dnf":
			check_repos_dnf();
			break;
		case "yum":
			check_repos_yum();
			break;
		case "pacman":
			check_repos_pacman();
			break;
		case "apt":
			check_repos_apt();
			break;
		}

		log_msg("Found: %d".printf(repos.size));

		log_msg(string.nfill(70,'-'));
	}

	public void check_repos_dnf(){
		
		// NOT IMPLEMENTED

		log_msg(_("Not Implemented"));
	}

	public void check_repos_yum(){
		
		// NOT IMPLEMENTED

		log_msg(_("Not Implemented"));
	}

	public void check_repos_pacman(){
		
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

		repos_sorted.foreach((repo) => {
			if (repo.name.length > 0){
				log_msg("repo: %s".printf(repo.name));
			}
			return true;
		});
	}

	public void check_repos_apt(){
		
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
					repos[name] = repo;

					log_msg("repo: %s".printf(name));
					
					repo_added = true;
				}
			}

			if (!repo_added){
				var repo = new Repo.from_list_file(list_file);
				repo.is_selected = true;
				repo.is_installed = true;

				string name = file_basename(list_file).replace(".list","");
				repos[name] = repo;
			}
		}

		repos_sorted.foreach((repo) => {
			
			if (repo.name.length > 0){
				log_msg("repo-launchpad: %s".printf(repo.name));
			}
			else if (repo.list_file_path.length > 0){
				log_msg("repo-custom: %s".printf(repo.list_file_path));
			}

			return true;
		});
	}

	public Gee.ArrayList<Repo> repos_sorted {
		owned get{
			return get_sorted_array(repos);
		}
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
		dir_create(backup_path);

		switch(distro.package_manager){
		case "dnf":
			return save_repos_dnf(backup_path);
		case "yum":
			return save_repos_yum(backup_path);
		case "pacman":
			return save_repos_pacman(backup_path);
		case "apt":
			return save_repos_apt(backup_path);
		}

		log_msg(_("Nothing to save"));
		log_msg(string.nfill(70,'-'));

		return false;
	}

	public bool save_repos_dnf(string backup_path){

		// NOT IMPLEMENTED

		log_msg(_("Not Implemented"));
		return false;
	}

	public bool save_repos_yum(string backup_path){

		// NOT IMPLEMENTED

		log_msg(_("Not Implemented"));
		return false;
	}

	public bool save_repos_pacman(string backup_path){

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

		bool ok = export_pacman_keys(backup_path);
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

	public bool save_repos_apt(string backup_path){
	
		bool ok, status = true;

		ok = save_repos_apt_launchpad(backup_path);
		if (!ok){ status = false; }
		
		ok = save_repos_apt_custom(backup_path);
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

		string list_file = path_combine(backup_path, "installed.list");

		string text = "";

		repos_sorted.foreach((repo) => {
	
			if (repo.is_installed && (repo.name.length > 0)){
				text += "%s\n".printf(repo.name);
				//text += "%s #%s\n".printf(ppa.name, ppa.description); // TODO: ppa description
			}
			return true;
		});

		return file_write(list_file, text);
	}

	public bool save_repos_apt_custom(string backup_path) {

		bool status = true;
		
		repos_sorted.foreach((repo) => {
			
			if (repo.is_installed && (repo.name.length == 0) && (repo.list_file_path.length > 0)){

				string backup_name = file_basename(repo.list_file_path).replace(distro.codename, "CODENAME");
				string backup_file = path_combine(backup_path, backup_name);
				
				bool ok = file_copy(repo.list_file_path, backup_file);
				if (!ok){ status = false; return true; }
				
				string txt = file_read(backup_file);
				txt = txt.replace(distro.codename, "CODENAME");
				ok = file_write(backup_file, txt);
				if (!ok){ status = false; return true; }
			}
			
			return true;
		});

		return status;
	}

	public bool export_pacman_keys(string backup_path){

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

	// restore ---------------------------

	public bool restore_repos(string basepath){

		string backup_path = path_combine(basepath, "repos");
		
		if (!dir_exists(backup_path)) {
			string msg = "%s: %s".printf(Message.DIR_MISSING, backup_path);
			log_error(msg);
			return false;
		}

		switch(distro.package_manager){
		case "dnf":
			return restore_repos_dnf(backup_path);
		case "yum":
			return restore_repos_yum(backup_path);
		case "pacman":
			return restore_repos_pacman(backup_path);
		case "apt":
			return restore_repos_apt(backup_path);
		}

		return false;
	}

	public bool restore_repos_dnf(string backup_path){

		// NOT IMPLEMENTED

		log_msg(_("Not Implemented"));
		return false;
	}

	public bool restore_repos_yum(string backup_path){

		// NOT IMPLEMENTED

		log_msg(_("Not Implemented"));
		return false;
	}

	public bool restore_repos_pacman(string backup_path){

		bool status = true;

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

		bool ok = import_pacman_keys(backup_path);
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

	public bool restore_repos_apt(string backup_path){

		bool status = true;

		bool ok = restore_repos_apt_launchpad(backup_path);
		if (!ok){ status = false; }
		
		ok = restore_repos_apt_custom(backup_path);
		if (!ok){ status = false; }
				
		if (dry_run){
			
			log_msg(_("Nothing to do (--dry-run mode)"));
			log_msg(string.nfill(70,'-'));
			return true;
		}

		// run 'apt update' and import missing keys if not --dry-run
		import_apt_keys(false);
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

		string backup_file = path_combine(backup_path, "installed.list");

		if (!file_exists(backup_file)) {
			string msg = "%s: %s".printf(Message.FILE_MISSING, backup_file);
			log_error(msg);
			return false;
		}

		var added_list = new Gee.ArrayList<string>();
		
		foreach(string name in file_read(backup_file).split("\n")){

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

			string cmd = "add-apt-repository -y ppa:%s\n".printf(name);
			Posix.system(cmd);
			log_msg(string.nfill(70,'-'));
		}
		
		return true;
	}

	public bool restore_repos_apt_custom(string backup_path) {

		bool status = true;

		var list = dir_list_names(backup_path, true);
		
		list.foreach((backup_file) => {

			if (file_basename(backup_file) == "sources.list"){
				return true;
			}

			if (file_basename(backup_file) == "installed.list"){
				return true;
			}

			string name = file_basename(backup_file).replace(".list","");

			if (name.contains("CODENAME") && (distro.codename.length == 0)){
				log_error("%s: %s".printf(_("Skipping File"), backup_file));
				log_error(_("This repo cannot be added to this system"));
				log_error(Message.UNKNOWN_CODENAME);
				return true;
			}

			name = name.replace("CODENAME", distro.codename);
			
			if (repos.has_key(name)){ return true; }

			string list_name = file_basename(backup_file).replace("CODENAME", distro.codename);
			string list_file = path_combine("/etc/apt/sources.list.d", list_name);

			if (dry_run){
				log_msg("Install source list: %s".printf(list_file));
				return true;
			}
			
			bool ok = file_copy(backup_file, list_file);
			if (!ok){ status = false; return true; }
			
			string txt = file_read(backup_file);
			txt = txt.replace("CODENAME", distro.codename);
			ok = file_write(backup_file, txt);
			if (!ok){ status = false; return true; }

			log_msg("%s: %s".printf(_("Installed"), list_file));

			return true;
		});

		return status;
	}

	public static bool import_apt_keys(bool show_message){

		if (!cmd_exists("apt-key")){
			log_error("%s: %s".printf(_("Missing command"), "apt-key"));
			log_error(_("Install required packages and try again"));
			return false; // exit method
		}

		bool ok = true;

		string temp_file;
		update_repos_apt(out temp_file);

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
			
			if (!update_repos_apt(out temp_file)){
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

	public bool import_pacman_keys(string backup_path){

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
	
	// update ----------------------

	public bool update_repos(string basepath, out string temp_file){

		temp_file = "";
		
		if (dry_run){
			log_msg(_("Nothing to do (--dry-run mode)"));
			log_msg(string.nfill(70,'-'));
			return true;
		}

		switch(distro.package_manager){
		case "dnf":
			return update_repos_dnf(out temp_file);
		case "yum":
			return update_repos_yum(out temp_file);
		case "pacman":
			return update_repos_pacman(out temp_file);
		case "apt":
			return update_repos_apt(out temp_file);
		}

		temp_file = "";

		return false;
	}

	public static bool update_repos_dnf(out string temp_file){

		// NOT IMPLEMENTED

		temp_file = "";
		log_msg(_("Not Implemented"));
		return false;
	}

	public static bool update_repos_yum(out string temp_file){

		// NOT IMPLEMENTED

		temp_file = "";
		log_msg(_("Not Implemented"));
		return false;
	}

	public static bool update_repos_pacman(out string temp_file){

		// NOT IMPLEMENTED

		temp_file = "";
		log_msg(_("Not Implemented"));
		return false;
	}

	public static bool update_repos_apt(out string temp_file){
	
		log_msg(_("Running apt update..."));
		
		temp_file = get_temp_file_path();
		log_debug(temp_file);

		string pm = "";
		
		if (cmd_exists("apt-fast")){
			pm = "apt-fast";
		}
		else if (cmd_exists("apt-get")){
			pm = "apt-get";
		}
		// NOTE: avoid using apt in scripts
		else if (cmd_exists("apt")){
			pm = "apt";
		}
		else{
			log_error(Message.MISSING_PACKAGE_MANAGER);
			return false;
		}

		string cmd = "%s update | tee '%s'".printf(pm, escape_single_quote(temp_file));
		log_debug(cmd);
		
		int status = Posix.system(cmd);

		log_msg(string.nfill(70,'-'));
		
		return (status == 0);
	}
		
	// static ----------------------

	public static Gee.ArrayList<Repo> get_sorted_array(Gee.HashMap<string,Repo> dict){

		var list = new Gee.ArrayList<Repo>();
		
		foreach(var pkg in dict.values) {
			list.add(pkg);
		}

		list.sort((a, b) => {
			return strcmp(a.name, b.name);
		});

		return list;
	}

}
