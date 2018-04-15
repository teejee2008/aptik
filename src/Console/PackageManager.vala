/*
 * PackageManager.vala
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

public class PackageManager : GLib.Object {

	public Gee.HashMap<string,Package> packages;

	public bool dist_installed_known = false;
	public bool auto_installed_known = false;
	public bool description_available = false;
	
	public static string DEF_PKG_LIST = "/var/log/installer/initial-status.gz";
	public static string DEF_PKG_LIST_UNPACKED = "/var/log/installer/initial-status";
	public bool default_list_missing = false;

	public LinuxDistro distro;
	public bool dry_run = false;
	public bool list_only = false;
	public string basepath = "";

	public Gee.ArrayList<string> exclude_list = new Gee.ArrayList<string>();
	
	public PackageManager(LinuxDistro _distro, bool _dry_run){

		distro = _distro;

		dry_run = _dry_run;

		check_packages();
	}

	// check --------------------------------
	
	private void check_packages(){

		//log_msg("Checking installed packages...");
	
		log_debug("check_packages()");

		packages = new Gee.HashMap<string,Package>();

		switch(distro.dist_type){
		case "fedora":
			check_packages_fedora();
			break;
		case "arch":
			check_packages_arch();
			break;
		case "debian":
			check_packages_debian();
			break;
		}
	}

	private void check_packages_fedora(){

		log_debug("check_packages_fedora()");

		string std_out, std_err;
		string cmd = "%s list installed".printf(distro.package_manager);
		log_debug(cmd);
		exec_sync(cmd, out std_out, out std_err);

		foreach(string line in std_out.split("\n")){

			// NetworkManager.x86_64                            1:1.4.2-1.fc25                       @anaconda
			var match = regex_match("""^([^.]*)\.([^ \t]*)[ \t]+([^ \t]*)[ \t]+([^ \t]*)""", line);

			if (match == null){ continue; }

			string name = match.fetch(1);
			string arch = match.fetch(2);
			string version_installed = match.fetch(3);

			if (name == null){ continue; }
			
			if (!packages.has_key(name)){
				packages[name] = new Package(name);
			}

			var pkg = packages[name];
			pkg.is_installed = true;
			pkg.is_available = true;
			pkg.version_installed = version_installed;
			pkg.arch = arch;
		}

		cmd = "%s list available".printf(distro.package_manager);
		log_debug(cmd);
		exec_sync(cmd, out std_out, out std_err);
		
		foreach(string line in std_out.split("\n")){
			
			var match = regex_match("""^([^.]*)\.([^ \t]*)[ \t]+([^ \t]*)[ \t]+([^ \t]*)""", line);

			if (match == null){ continue; }

			string name = match.fetch(1);
			string arch = match.fetch(2);
			string version_available = match.fetch(3);

			if (name == null){ continue; }
			
			if (!packages.has_key(name)){
				packages[name] = new Package(name);
			}
			
			var pkg = packages[name];
			pkg.is_available = true;
			pkg.version_available = version_available;
			pkg.arch = arch;
		}

		if (cmd_exists("dnf")){

			var packages_qualified = new Gee.HashMap<string,Package>();
			foreach(var pkg in packages.values){
				if (!pkg.is_installed) { continue; }
				string qualified_name = "%s-%s.%s".printf(pkg.name, pkg.version_installed, pkg.arch);
				packages_qualified[qualified_name] = pkg;
				log_debug(qualified_name);
			}

			cmd = "dnf history userinstalled";
			log_debug(cmd);
			exec_sync(cmd, out std_out, out std_err);
		
			foreach(string line in std_out.split("\n")){
				
				string[] arr = line.split(" ");
				if (arr.length == 0) { continue; }
				string name = arr[0].strip();

				if (!packages_qualified.has_key(name)){
					continue;
				}
				
				packages_qualified[name].is_user = true;
			}
		}
	}

	private void check_packages_arch(){

		log_debug("check_packages_pacman()");

		string std_out, std_err;
		exec_sync("pacman -Qq", out std_out, out std_err);
		
		foreach(string line in std_out.split("\n")){
			
			string[] arr = line.split(" ");
			if (arr.length == 0) { continue; }
			string name = arr[0].strip();

			if (!packages.has_key(name)){
				packages[name] = new Package(name);
			}
			
			packages[name].is_installed = true;
			packages[name].is_available = true;
		}

		exec_sync("pacman -Ssq", out std_out, out std_err);
		
		foreach(string line in std_out.split("\n")){
			
			string[] arr = line.split(" ");
			if (arr.length == 0) { continue; }
			string name = arr[0].strip();

			if (!packages.has_key(name)){
				packages[name] = new Package(name);
			}
			
			packages[name].is_available = true;
		}

		// explictly installed, no deps
		// without version numbers (-q)
        // explicitly installed (-t)
        // not required directly by other packages (-tt)
        
		exec_sync("pacman -Qqett", out std_out, out std_err);

		foreach(string line in std_out.split("\n")){
			
			string[] arr = line.split(" ");
			if (arr.length == 0) { continue; }
			string name = arr[0].strip();

			if (!packages.has_key(name)){
				packages[name] = new Package(name);
			}

			var pkg = packages[name];
			pkg.is_user = true;
		}
	}

	private void check_packages_debian(){
		
		if (cmd_exists("aptitude")){
			check_packages_aptitude();
		}
		else{
			check_packages_apt();
		}

		check_packages_apt_default();
	}
	
	private void check_packages_apt(){

		log_debug("check_packages_apt()");

		string std_out, std_err;
		exec_sync("dpkg --get-selections", out std_out, out std_err);
		
		foreach(string line in std_out.split("\n")){
			
			if (line.contains("deinstall")){ continue; }
			
			var arr = line.split("\t");
			if (arr.length == 0) { continue; }
			
			var parts = arr[0].strip().split(":");
			string name = parts[0]; // remove :amd64 :i386 etc
			
			string arch = "";
			bool is_foreign = false;
					
			if (name.contains(":")) {
				arch = name.split(":")[1].strip();
				name = name.split(":")[0].strip();
			}
			else{
				arch = distro.package_arch;
			}

			if (arch != distro.package_arch){
				name = "%s:%s".printf(name, arch);
				is_foreign = true;
			}

			//log_debug("%s,%s".printf(name, arch));
			
			if (!packages.has_key(name)){
				packages[name] = new Package(name);
				packages[name].arch = arch;
			}

			packages[name].is_installed = true;
			packages[name].is_available = true;
			packages[name].is_foreign = is_foreign;
		}

		exec_sync("apt-cache pkgnames", out std_out, out std_err);
		
		foreach(string line in std_out.split("\n")){
			
			string[] arr = line.split("\t");
			if (arr.length == 0) { continue; }
			string name = arr[0].strip();
			name = name.split(":")[0]; // remove :amd64 :i386 etc

			string arch = "";
			bool is_foreign = false;
					
			if (name.contains(":")) {
				arch = name.split(":")[1].strip();
				name = name.split(":")[0].strip();
			}
			else{
				arch = distro.package_arch;
			}

			if (arch != distro.package_arch){
				name = "%s:%s".printf(name, arch);
				is_foreign = true;
			}

			if (!packages.has_key(name)){
				packages[name] = new Package(name);
				packages[name].arch = arch;
			}

			packages[name].is_available = true;
			packages[name].is_foreign = is_foreign;
		}
	}

	private void check_packages_aptitude() {

		log_debug("check_packages_aptitude()");

		string temp_file = get_temp_file_path();

		string std_out, std_err;
		exec_sync("aptitude search --disable-columns -F '%p|%v|%C|%M|%d' '?true'", out std_out, out std_err);
		file_write(temp_file, std_out);

		try {
			string line;
			var file = File.new_for_path(temp_file);
			
			if (!file.query_exists()) {
				log_error ("%s: %s".printf(_("File not found"), temp_file));
			}
				
			var dis = new DataInputStream (file.read());
			
			while ((line = dis.read_line (null)) != null) {
				
				string[] arr = line.split("|");
				if (arr.length != 5) { continue; }

				string name = arr[0].strip();
				
				string arch = "";

				bool is_foreign = false;
				
				if (name.contains(":")) {
					arch = name.split(":")[1].strip();
					name = name.split(":")[0].strip();
				}
				else{
					arch = distro.package_arch;
				}

				if (arch != distro.package_arch){
					name = "%s:%s".printf(name, arch);
					is_foreign = true;
				}

				string version = arr[1].strip();
				string state = arr[2].strip();
				string auto = arr[3].strip();
				string desc = arr[4].strip();
				
				if (!packages.has_key(name)){
					packages[name] = new Package(name);
				}

				var pkg = packages[name];
				pkg.description = desc;
				pkg.arch = arch;
				pkg.is_available = true;
				pkg.is_installed = (state == "installed");
				pkg.is_auto = (auto == "A");
				pkg.is_foreign = is_foreign;
				pkg.version_installed = version;
			}

			auto_installed_known = true; // is_automatic flag is available
			description_available = true; 
		}
		catch (Error e) {
			log_error (e.message);
		}
	}

	private void check_packages_apt_default() {

		int count = 0;

		string DEF_PKG_LIST = "/var/log/installer/initial-status.gz";
		string DEF_PKG_LIST_UNPACKED = "/tmp/initial-status";

		log_debug("check_packages_apt_default()");

		if (!file_exists(DEF_PKG_LIST)) {
			log_error("%s: %s".printf(Messages.FILE_MISSING, DEF_PKG_LIST_UNPACKED));
			return;
		}

		var tmr = timer_start();

		if (!file_exists(DEF_PKG_LIST_UNPACKED)){
			string std_out, std_err;
			string cmd = "gzip -dc '%s'".printf(DEF_PKG_LIST);
			log_debug(cmd);
			exec_script_sync(cmd, out std_out, out std_err);
			file_write(DEF_PKG_LIST_UNPACKED, std_out);
		}

		if (!file_exists(DEF_PKG_LIST_UNPACKED)){
			return;
		}
		
		foreach(string line in file_read(DEF_PKG_LIST_UNPACKED).split("\n")){

			if (line.strip().length == 0) { continue; }
			if (line.index_of(":") == -1) { continue; }

			//Note: split on ': ' since version string can have colons
			
			string p_name = line.split(":",2)[0].strip();
			string p_value = line.split(":",2)[1].strip();
			
			switch(p_name.down()){
				case "package":
				
					string name = p_value;
					string arch = "";
					bool is_foreign = false;
					
					if (name.contains(":")) {
						arch = name.split(":",2)[1].strip();
						name = name.split(":",2)[0].strip();
					}
					else{
						arch = distro.package_arch;
					}

					if (arch != distro.package_arch){
						name = "%s:%s".printf(name, arch);
						is_foreign = true;
					}

					if (!packages.has_key(name)){
						packages[name] = new Package(name);
					}

					count++;
					
					var pkg = packages[name];
					pkg.is_available = true;
					pkg.is_installed = true;
					pkg.is_dist = true;
					pkg.is_foreign = is_foreign;
					break;
			}
		}

		//log_msg("time_taken: %s".printf(timer_elapsed_string(tmr)));

		dist_installed_known = true;

		if (count > 0){
			log_debug("Installed-Dist: %'6d".printf(count));
		}
	}
	
	public Gee.ArrayList<Package> packages_sorted {
		owned get{
			return get_sorted_array(packages);
		}
	}

	// list --------------------------

	public void dump_info(){

		string txt = "";
		
		foreach(var pkg in packages_sorted){
			
			if (!pkg.is_installed){ continue; }
			
			txt += "NAME='%s',ARCH='%s',DESC='%s'".printf(pkg.name, pkg.arch, pkg.description);
			txt += ",I='%s'".printf(pkg.is_installed ? "1" : "0");
			txt += ",D='%s'".printf(pkg.is_dist ? "1" : "0");
			txt += ",A='%s'".printf(pkg.is_auto ? "1" : "0");
			txt += ",U='%s'".printf((pkg.is_user || (!pkg.is_dist && !pkg.is_auto)) ? "1" : "0");
			txt += ",F='%s'".printf(pkg.is_foreign ? "1" : "0");
			txt += ",M='%s'".printf(pkg.is_manual ? "1" : "0");
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

		string backup_file = path_combine(backup_path, "selected.list");

		if (!file_exists(backup_file)) {
			string msg = "%s: %s".printf(Messages.FILE_MISSING, backup_file);
			log_error(msg);
			return;
		}
		
		string txt = "";
		
		foreach(string line in file_read(backup_file).split("\n")) {

			if (line.strip().length == 0) { continue; }

			if (line.strip().has_prefix("#")) { continue; }
			
			string name = line.split("#",2)[0].strip();
			string desc = line.split("#",2)[1].strip();
			bool is_available = false;
			bool is_installed = false;
			
			if (packages.has_key(name)){
				is_available = true;
				is_installed = packages[name].is_installed;
			}

			txt += "NAME='%s',DESC='%s'".printf(name, desc);
			txt += ",A='%s'".printf(is_available ? "1" : "0");
			txt += ",I='%s'".printf(is_installed ? "1" : "0");
			txt += "\n";
		}
		
		log_msg(txt);
	}
	
	public void list_available(){

		string txt = "";
		int count = 0;

		foreach(var pkg in packages_sorted){
			
			if (pkg.is_available){

				txt += "%-50s".printf(pkg.name);
				
				if (description_available){
					txt += " -- %s".printf(pkg.description);
				}

				txt += "\n";

				count++;
			}
		}

		if (txt.length > 0){
			txt = txt[0:txt.length-1];
		}

		log_msg("%d packages".printf(count));
		log_msg(string.nfill(70,'-'));
		log_msg(txt);
	}

	public void list_installed(){

		string txt = "";
		int count = 0;
		
		foreach(var pkg in packages_sorted){
			
			if (pkg.is_installed){

				txt += "%-50s".printf(pkg.name);
				
				if (description_available){
					txt += " -- %s".printf(pkg.description);
				}

				txt += "\n";

				count++;
			}
		}

		if (txt.length > 0){
			txt = txt[0:txt.length-1];
		}

		log_msg("%d packages".printf(count));
		log_msg(string.nfill(70,'-'));
		log_msg(txt);
	}

	public void list_dist(){

		string txt = "";
		int count = 0;
		
		foreach(var pkg in packages_sorted){
			
			if (pkg.is_dist && pkg.is_installed){

				txt += "%-50s".printf(pkg.name);
				
				if (description_available){
					txt += " -- %s".printf(pkg.description);
				}

				txt += "\n";

				count++;
			}
		}

		if (txt.length > 0){
			txt = txt[0:txt.length-1];
		}

		log_msg("%d packages".printf(count));
		log_msg(string.nfill(70,'-'));
		log_msg(txt);
	}

	public void list_auto_installed(){

		string txt = "";
		int count = 0;
		
		foreach(var pkg in packages_sorted){
			
			if (pkg.is_installed && pkg.is_auto){

				txt += "%-50s".printf(pkg.name);
				
				if (description_available){
					txt += " -- %s".printf(pkg.description);
				}

				txt += "\n";

				count++;
			}
		}

		if (txt.length > 0){
			txt = txt[0:txt.length-1];
		}

		log_msg("%d packages".printf(count));
		log_msg(string.nfill(70,'-'));
		log_msg(txt);
	}

	public void list_user_installed(){

		string txt = "";
		int count = 0;
		
		foreach(var pkg in packages_sorted){
			
			if (pkg.is_installed && !pkg.is_auto && !pkg.is_dist){

				txt += "%-50s".printf(pkg.name);
				
				if (description_available){
					txt += " -- %s".printf(pkg.description);
				}

				txt += "\n";

				count++;
			}
		}

		if (txt.length > 0){
			txt = txt[0:txt.length-1];
		}

		log_msg("%d packages".printf(count));
		log_msg(string.nfill(70,'-'));
		log_msg(txt);
	}

	public void list_foreign(){
		
		string txt = "";
		int count = 0;
		
		foreach(var pkg in packages_sorted){
			
			if (pkg.is_installed && pkg.is_foreign){

				txt += "%-50s".printf(pkg.name);
				
				if (description_available){
					txt += " -- %s".printf(pkg.description);
				}

				txt += "\n";

				count++;
			}
		}

		if (txt.length > 0){
			txt = txt[0:txt.length-1];
		}

		log_msg("%d packages".printf(count));
		log_msg(string.nfill(70,'-'));
		log_msg(txt);
	}

	public string init_backup_path(){
		
		string backup_path = path_combine(basepath, "packages");
		
		if (dir_exists(backup_path)){

			var files = dir_list_names(backup_path, true);

			foreach(var file in files){
				
				if (file_basename(file) != "exclude.list"){
					
					file_delete(file);
				}
			}
		}
		else{
			dir_create(backup_path);
			chmod(backup_path, "a+rwx");
		}

		return backup_path;
	}

	public void read_exclude_file(){

		string backup_path = path_combine(basepath, "packages");
		
		string exclude_list_file = path_combine(backup_path, "exclude.list");

		exclude_list.clear();
		
		if (file_exists(exclude_list_file)){
			
			foreach(string line in file_read(exclude_list_file).split("\n")){
				
				exclude_list.add(line.strip());
			}
		}
	}
	
	// save --------------------------
	
	public bool save_package_list(string _basepath, bool include_foreign, bool exclude_icons, bool exclude_themes, bool exclude_fonts){

		basepath = _basepath;
		
		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Backup"), Messages.TASK_PACKAGES));
		log_msg(string.nfill(70,'-'));
		
		bool ok, status = true;

		string backup_path = init_backup_path();

		read_exclude_file();

		ok = save_package_list_installed(backup_path);
		if (!ok){ status = false; }
		
		ok = save_package_list_selected(backup_path, include_foreign, exclude_icons, exclude_themes, exclude_fonts);
		if (!ok){ status = false; }

		switch(distro.dist_type){
		case "fedora":
			// NOT IMPLEMENTED
			break;
		case "arch":
			// NOT IMPLEMENTED
			break;
		case "debian":
			string deb_dir = path_combine(basepath, "debs");
			string deb_readme = path_combine(deb_dir, "README");
			string msg = _("DEB files placed in this directory will be installed on restore");
			dir_create(deb_dir);
			chmod(deb_dir, "a+rwx");
			file_write(deb_readme, msg);
			break;
		}

		if (status){
			log_msg(Messages.BACKUP_OK);
		}
		else{
			log_error(Messages.BACKUP_ERROR);
		}

		//log_msg(string.nfill(70,'-'));

		return status;
	}

	public bool save_package_list_installed(string backup_path) {

		string backup_file = path_combine(backup_path, "installed.list");

		string txt = "\n# Do not edit - This list is not used for restore\n\n";

		int count = 0;
		
		foreach(var pkg in packages_sorted){
			
			if (!pkg.is_installed){ continue; }
			
			txt += "%s".printf(pkg.name);
			
			if (pkg.description.length > 0){
				txt += " # %s".printf(pkg.description);
			}

			txt += "\n";
			
			count++;
		}

		bool ok = file_write(backup_file, txt);

		if (ok){
			chmod(backup_file, "a+rw");
			log_msg("%s: %s (%d packages)".printf(_("Saved"), backup_file.replace(basepath, "$basepath/"), count));
		}

		return ok;
	}

	public bool save_package_list_selected(string backup_path, bool include_foreign, bool exclude_icons, bool exclude_themes, bool exclude_fonts) {

		string backup_file = path_combine(backup_path, "selected.list");

		string txt = "\n";

		txt += "# %s\n".printf(_("Packages listed in this file will be installed on restore"));
		txt += "# %s\n\n".printf(_("Comment-out or remove lines for unwanted items"));

		int count = 0;
		
		foreach(var pkg in packages_sorted){

			if (!pkg.is_installed){ continue; }

			if (exclude_list.contains(pkg.name)){ continue; }

			if (auto_installed_known && pkg.is_auto){ continue; }

			if (dist_installed_known && pkg.is_dist){ continue; }

			if (pkg.name.has_prefix("linux-headers")){ continue; }
			if (pkg.name.has_prefix("linux-signed")){ continue; }
			if (pkg.name.has_prefix("linux-tools")){ continue; }
			if (pkg.name.has_prefix("linux-image")){ continue; }

			if (!include_foreign && pkg.is_foreign){ continue; }
			if (exclude_icons && pkg.name.contains("-icon-theme")){ continue; }
			if (exclude_themes && pkg.name.contains("-theme") && !pkg.name.contains("-icon-theme")){ continue; }
			if (exclude_fonts && pkg.name.has_prefix("fonts-")){ continue; }

			if (pkg.name.has_prefix("lib") || (pkg.name == "ttf-mscorefonts-installer")){
					
				txt += "#"; // comment and keep
			}
			else{
				count++;
			}

			txt += "%s".printf(pkg.name);
			
			if (pkg.description.length > 0){
				txt += " # %s".printf(pkg.description);
			}

			txt += "\n";
		}

		bool ok = file_write(backup_file, txt);

		if (ok){
			chmod(backup_file, "a+rw");
			log_msg("%s: %s (%d packages)".printf(_("Saved"), backup_file.replace(basepath, "$basepath/"), count));
		}

		return ok;
	}

	public bool save_list_file(string backup_file, string text){

		bool ok = file_write(backup_file, text);

		if (ok){
			chmod(backup_file, "a+rw");
			//log_msg("%s: %s (%d packages)".printf(_("Saved"), backup_file, count));
		}

		return ok;
	}

	// restore ---------------------

	public bool restore_packages(string _basepath, bool no_prompt){

		basepath = _basepath;
		
		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Restore"), Messages.TASK_PACKAGES));
		log_msg(string.nfill(70,'-'));

		//check_packages();
		
		string backup_path = path_combine(basepath, "packages");
		
		if (!dir_exists(backup_path)) {
			string msg = "%s: %s".printf(Messages.DIR_MISSING, backup_path);
			log_error(msg);
			return false;
		}

		read_exclude_file();
		
		string backup_file = path_combine(backup_path, "selected.list");

		if (!file_exists(backup_file)) {
			string msg = "%s: %s".printf(Messages.FILE_MISSING, backup_file);
			log_error(msg);
			return false;
		}

		if (!check_internet_connectivity()) {
			log_error(Messages.INTERNET_OFFLINE);
			return false;
		}

		string list_missing, list_install;
		read_package_list_from_backup_file(backup_file, out list_missing, out list_install);

		bool ok = install_packages(basepath, list_install, list_missing, no_prompt);

		if (ok){
			log_msg(Messages.RESTORE_OK);
		}
		else{
			log_error(Messages.RESTORE_ERROR);
		}

		return ok;
	}

	private void read_package_list_from_backup_file(string backup_file, out string list_missing, out string list_install) {

		log_msg("Reading package list...");
		
		list_missing = "";
		list_install = "";
		
		if (!file_exists(backup_file)) { return; }

		foreach(string line in file_read(backup_file).split("\n")) {
			
			if (line.strip().length == 0) { continue; }

			if (line.strip().has_prefix("#")) { continue; }
			
			string name = line.strip();
			string desc = "";
			
			if (line.strip().contains("#")){
				name = line.split("#",2)[0].strip();
				desc = line.split("#",2)[1].strip();
			}

			if (exclude_list.contains(name)){ continue; }
			
			if (packages.has_key(name)){
				if (!packages[name].is_installed){
					list_install += " %s".printf(name);
				}
			}
			else{
				list_missing += " %s".printf(name);
			}
		}

		list_missing = list_missing.strip();
		list_install = list_install.strip();

		log_msg("Not installed: %d".printf(list_install.split(" ").length));
		log_msg("Not available: %d".printf(list_missing.split(" ").length));

		log_msg(string.nfill(70,'-'));
	}

	private bool install_packages(string basepath, string list_install, string list_missing, bool no_prompt){

		if (dry_run){
			
			log_msg("Packages to install: %'d\n".printf(list_install.split(" ").length));
			if (list_install.length > 0){
				log_msg(list_install);
			}
			log_msg(string.nfill(70,'-'));

			log_msg("Packages not available: %'d\n".printf(list_missing.split(" ").length));
			if (list_missing.length > 0){
				log_msg(list_missing);
			}
			log_msg(string.nfill(70,'-'));
		}

		switch(distro.dist_type){
		case "fedora":
			return install_packages_fedora(list_install, no_prompt);
		case "arch":
			return install_packages_arch(list_install, no_prompt);
		case "debian":
			return install_packages_debian(basepath, list_install, no_prompt);
		}

		return false;
	}

	private bool install_packages_fedora(string list_install, bool no_prompt){

		if (list_install.length == 0){ return true; }
		
		log_debug("install_packages_fedora()");
		
		log_msg("%s\n".printf("Installing packages..."));
		
		string cmd = distro.package_manager;

		if (no_prompt){
			cmd += " -y";
		}

		cmd += " install %s".printf(list_install);

		int status = 0;
		
		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug("$ %s".printf(cmd));
			status = Posix.system(cmd);
		}

		log_msg(string.nfill(70,'-'));
		log_msg(Messages.RESTORE_OK);
		
		return (status == 0);
	}

	private bool install_packages_arch(string list_install, bool no_prompt){

		if (list_install.length == 0){ return true; }
		
		log_debug("install_packages_arch()");

		log_msg("%s\n".printf("Installing packages..."));

		string cmd = distro.package_manager;

		if (no_prompt){
			cmd += " --noconfirm";
		}

		cmd += " -S %s".printf(list_install);

		int status = 0;
		
		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug("$ %s".printf(cmd));
			status = Posix.system(cmd);
		}

		log_msg(string.nfill(70,'-'));
		log_msg(Messages.RESTORE_OK);
		
		return (status == 0);
	}

	private bool install_packages_debian(string basepath, string list_install, bool no_prompt){

		log_debug("install_packages_debian()");

		bool status = true, ok = true;

		if (list_install.length > 0){
			
			ok = install_packages_apt(basepath, list_install, no_prompt);
			if (!ok){ status = false; }

			log_msg(string.nfill(70,'-'));
		}
		
		ok = install_packages_deb(basepath);
		if (!ok){ status = false; }

		log_msg(Messages.RESTORE_OK);

		return status;
	}

	private bool install_packages_apt(string basepath, string list_install, bool no_prompt, bool try_resolve = true){
		
		if (list_install.length == 0){ return true; }

		log_debug("install_packages_apt()");

		log_msg("%s\n".printf("Installing packages..."));

		string cmd = distro.package_manager;
		
		if (no_prompt){
			cmd += " -y";
		}

		cmd += " install %s".printf(list_install);

		int status = 0;
		
		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug("$ %s".printf(cmd));
			
			status = Posix.system(cmd + " ; echo $? > status");

			if (file_exists("status")){
				status = int.parse(file_read("status"));
			}
		}

		if ((status != 0) && try_resolve){

			Posix.system(cmd + " > output");

			string txt = file_read("output");
			
			log_msg(string.nfill(70,'-'));
			log_msg("%s\n".printf("Attempting to resolve issue..."));

			string list = list_install;
			
			foreach(string line in txt.split("\n")){
				
				var match = regex_match("""^ ([a-zA-Z0-9-+._]+) : """, line);
				
				if (match != null){

					string pkg = match.fetch(1);
					
					if (list.contains(" " + pkg + " ")){
						list = list.replace(" " + pkg + " ", " ");
					}
					else if (list.has_prefix(pkg + " ")){
						list = list.replace(pkg + " ", "");
					}
					else if (list.has_suffix(" " + pkg)){
						list = list.replace(" " + pkg, "");
					}
						
					log_msg("%s: %s".printf(_("Unselected"), pkg));
				}
			}

			if (list.strip().length != list_install.strip().length){
				return install_packages_apt(basepath, list, no_prompt, false);
			}
		}

		return (status == 0);
	}

	private bool install_packages_deb(string basepath){

		log_debug("install_packages_deb()");

		string backup_path = path_combine(basepath, "debs");
		
		if (!dir_exists(backup_path)){ return true; }
		
		// check count ---------------------
		
		var list = dir_list_names(backup_path, true);
		int count = 0;
		
		foreach(var file_path in list){
			if (file_path.has_suffix(".deb")) { count++; }
		}
		
		if (count == 0){ return true; }

		// install ------------------------------

		log_msg("%s\n".printf(_("Installing DEB packages...")));
		
		if (cmd_exists("gdebi")){
			return install_packages_deb_gdebi(list);
		}
		else if (cmd_exists("apt")){
			return install_packages_deb_apt(list);
		}
		else {
			return false;
		}
	}

	private bool install_packages_deb_apt(Gee.ArrayList<string> list){

		log_debug("install_packages_deb_apt()");

		if (!cmd_exists("apt")){
			log_error("%s: %s".printf(Messages.MISSING_COMMAND, "apt"));
			return false; // exit method
		}

		string txt = "";
		foreach(string file_path in list){
			if (!file_path.has_suffix(".deb")) { continue; }
			txt += " '%s'".printf(escape_single_quote(file_path));
		}

		string cmd = "apt install %s".printf(txt.strip());

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

	private bool install_packages_deb_gdebi(Gee.ArrayList<string> list){

		log_debug("install_packages_deb_gdebi(): %d".printf(list.size));

		if (!cmd_exists("gdebi")){
			log_error("%s: %s".printf(Messages.MISSING_COMMAND, "gdebi"));
			return false; // exit method
		}

		bool status = true, ok = true;

		foreach(string file_path in list){
			
			ok = install_package_with_gdebi(file_path);
			if (!ok){ status = false; }
		}

		return status;
	}

	private bool install_package_with_gdebi(string file_path){

		log_debug("install_package_with_gdebi()");

		string cmd = "gdebi -n '%s'".printf(escape_single_quote(file_path));

		int status = 0;
		
		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug("$ %s".printf(cmd));
			status = Posix.system(cmd);
		}

		log_msg(string.nfill(70,'-'));
		
		return (status == 0);
	}

	// static ----------------------

	public static Gee.ArrayList<Package> get_sorted_array(Gee.HashMap<string,Package> dict_packages){

		var list = new Gee.ArrayList<Package>();
		
		foreach(var pkg in dict_packages.values) {
			list.add(pkg);
		}

		list.sort((a, b) => {
			return strcmp(a.name, b.name);
		});

		return list;
	}

	public static void install_package(string pkgnames_deb, string pkgnames_arch, string pkgnames_fedora){

		var dist = new LinuxDistro();

		string cmd = "";
		
		switch (dist.dist_type){
		case "fedora":
			cmd = "dnf -y install %s".printf(pkgnames_fedora);
			break;
		case "arch":
			cmd = "pacman --noconfirm -S %s".printf(pkgnames_arch);
			break;
		case "debian":
			cmd = "apt-get -y install %s".printf(pkgnames_deb);
			break;
		}

		if (cmd.length > 0){
			Posix.system(cmd);
		}
	}
}
