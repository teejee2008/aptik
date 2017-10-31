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

	public bool auto_installed_known = false;
	public bool description_available = false;
	
	public static string DEF_PKG_LIST = "/var/log/installer/initial-status.gz";
	public static string DEF_PKG_LIST_UNPACKED = "/var/log/installer/initial-status";
	public bool default_list_missing = false;

	public LinuxDistro distro;
	public bool dry_run = false;
	public bool list_only = false;

	public PackageManager(LinuxDistro _distro, bool _dry_run, bool _list_only){

		distro = _distro;

		dry_run = _dry_run;

		list_only = _list_only;
		
		check_packages();
	}

	// check --------------------------------
	
	private void check_packages(){

		if (!list_only){
			log_msg("Checking installed packages...");
		}

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

		// check counts -----------------------------

		int installed_count = 0;
		int available_count = 0;
		int selected_count = 0;
		
		packages_sorted.foreach((pkg)=> {
			if (pkg.is_installed){ installed_count++; }
			if (pkg.is_available){ available_count++; }
			if (pkg.is_selected){ selected_count++; }
			return true;
		});

		if (!list_only){
			log_msg("Available: %'6d".printf(available_count));
			log_msg("Installed: %'6d".printf(installed_count));
			log_msg("Selected : %'6d".printf(selected_count));
			log_msg(string.nfill(70,'-'));
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
				
				packages_qualified[name].is_selected = true;
			}
		}
		else{
			foreach(var pkg in packages.values){
				pkg.is_selected = pkg.is_installed;
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
			
			packages[name].is_selected = true; // explictly installed, may be default package also
		}
	}

	private void check_packages_debian(){
		
		switch(distro.package_manager){
		case "aptitude":
			check_packages_aptitude();
			break;
		default:
			check_packages_apt();
			break;
		}

		check_packages_apt_default();

		foreach(var pkg in packages.values){
			pkg.is_selected = pkg.is_installed && !pkg.is_automatic && !pkg.is_default;
		}
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
				pkg.is_automatic = (auto == "A");
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
		string DEF_PKG_LIST_UNPACKED = "/var/log/installer/initial-status";
	
		log_debug("check_packages_apt_default()");

		if (!file_exists(DEF_PKG_LIST)) {
			log_error("%s: %s".printf(Message.FILE_MISSING, DEF_PKG_LIST_UNPACKED));
			return;
		}

		if (!file_exists(DEF_PKG_LIST_UNPACKED)){
			string txt = "";
			exec_script_sync("gzip -dc '%s'".printf(DEF_PKG_LIST),out txt,null);
			file_write(DEF_PKG_LIST_UNPACKED,txt);
		}
		
		try {
			string line;
			var file = File.new_for_path(DEF_PKG_LIST_UNPACKED);
			if (!file.query_exists ()) {
				log_error(_("Failed to unzip: '%s'").printf(DEF_PKG_LIST_UNPACKED));
				return;
			}

			var dis = new DataInputStream (file.read());
			while ((line = dis.read_line (null)) != null) {

				if (line.strip().length == 0) { continue; }
				if (line.index_of(": ") == -1) { continue; }

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
						pkg.is_default = true;
						pkg.is_foreign = is_foreign;
						break;
				}
			}

			if ((count > 0) && !list_only){
				log_msg("Dist-Base: %'6d".printf(count));
			}
		}
		catch (Error e) {
			log_error (e.message);
		}
	}
	
	public Gee.ArrayList<Package> packages_sorted {
		owned get{
			return get_sorted_array(packages);
		}
	}
	
	// save --------------------------
	
	public bool save_package_list(string basepath){

		if (dry_run){
			log_msg(_("Nothing to do (--dry-run mode)"));
			return true;
		}
		
		log_msg(_("Saving list of packages..."));
		
		bool ok, status = true;

		string backup_path = path_combine(basepath, "packages");
		dir_create(backup_path);

		ok = save_package_list_selected(backup_path);
		if (!ok){ status = false; }
		
		ok = save_package_list_installed(backup_path);
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
			chmod(deb_dir, "a+rw");
			file_write(deb_readme, msg);
			break;
		}

		log_msg(string.nfill(70,'-'));
		
		if (status){
			log_msg(Message.BACKUP_OK);
		}
		else{
			log_error(Message.BACKUP_ERROR);
		}

		log_msg(string.nfill(70,'-'));

		return status;
	}

	public bool save_package_list_installed(string backup_path) {

		string list_file = path_combine(backup_path, "installed.list");

		string text = "\n# DO NOT EDIT - This list is not used for restore\n\n";

		packages_sorted.foreach((pkg)=> {
			if (pkg.is_installed){
				text += "%s #%s\n".printf(pkg.name, pkg.description);
			}
			return true;
		});

		bool ok = file_write(list_file, text);

		if (ok){
			chmod(list_file, "a+r"); // not writable
			log_msg("%s: %s".printf(_("Saved"), list_file));
		}

		return ok;
	}

	public bool save_package_list_selected(string backup_path) {

		string list_file = path_combine(backup_path, "selected.list");

		string text = "\n# Comment-out or remove lines for unwanted items\n\n";

		packages_sorted.foreach((pkg)=> {

			if (pkg.name.has_prefix("linux-headers")){ return true; }
			if (pkg.name.has_prefix("linux-signed")){ return true; }
			if (pkg.name.has_prefix("linux-tools")){ return true; }
			
			if (pkg.is_selected){
				text += "%s #%s\n".printf(pkg.name, pkg.description);
			}
			return true;
		});

		bool ok = file_write(list_file, text);

		if (ok){
			chmod(list_file, "a+rw");
			log_msg("%s: %s".printf(_("Saved"), list_file));
		}

		return ok;
	}

	// restore ---------------------

	public bool restore_packages(string basepath, bool no_prompt){
		
		string backup_path = path_combine(basepath, "packages");
		
		if (!dir_exists(backup_path)) {
			string msg = "%s: %s".printf(Message.DIR_MISSING, backup_path);
			log_error(msg);
			return false;
		}
		
		string backup_file = path_combine(backup_path, "selected.list");

		if (!file_exists(backup_file)) {
			string msg = "%s: %s".printf(Message.FILE_MISSING, backup_file);
			log_error(msg);
			return false;
		}

		if (!check_internet_connectivity()) {
			log_error(Message.INTERNET_OFFLINE);
			return false;
		}

		string list_missing, list_install;
		read_package_list_from_backup_file(backup_file, out list_missing, out list_install);

		return install_packages(basepath, list_install, list_missing, no_prompt);

		/*
		App.read_package_info();
		App.update_pkg_list_master_for_restore(true);
		
		if (App.pkg_list_missing.length > 0) {
			log_msg(_("Following packages are not available") + ":\n%s\n".printf(App.pkg_list_missing));
		}

		if ((App.pkg_list_install.length == 0) && (App.pkg_list_deb.length == 0)) {
			log_msg(_("Selected packages are already installed"));
		}
		else{
			if (App.pkg_list_install.length > 0){
				log_msg(_("Following packages will be installed") + ":\n%s\n".printf(App.pkg_list_install));

				var command = "apt-get";
				var cmd_path = get_cmd_path ("apt-fast");
				if ((cmd_path != null) && (cmd_path.length > 0)) {
					command = "apt-fast";
				}

				int status = Posix.system("%s%s install %s".printf(command, (no_prompt) ? " -y" : "", App.pkg_list_install));

				if (status != 0){
					Posix.system("echo '\n\n%s' \n".printf(string.nfill(70,'=')));
					Posix.system("echo '%s' \n".printf(Message.APT_GET_ERROR));
					Posix.system("echo '%s\n\n' \n".printf(string.nfill(70,'=')));
					return false;
				}
	
				ok = ok && (status == 0);
			}
			if (App.pkg_list_deb.length > 0){
				log_msg(_("Following packages will be installed") + ":\n%s\n".printf(App.pkg_list_deb));
				foreach(string line in App.gdebi_list.split("\n")){
					Posix.system("gdebi -n %s".printf(line));
				}
			}
		}

		if (ok){
			log_msg(Message.RESTORE_OK);
		}
		else{
			log_msg(Message.RESTORE_ERROR);
		}
		*
		* */
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

		if (list_install.length == 0){
			log_msg("Nothing to install");
			return true;
		}

		if (dry_run){
			
			log_msg("Packages to install: %'d".printf(list_install.split(" ").length));
			if (list_install.length > 0){
				log_msg(list_install);
			}
			log_msg(string.nfill(70,'-'));

			log_msg("Packages not available: %'d".printf(list_missing.split(" ").length));
			if (list_missing.length > 0){
				log_msg(list_missing);
			}
			log_msg(string.nfill(70,'-'));

			log_msg(_("Nothing to do (--dry-run mode)"));

			return true;
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

		log_debug("install_packages_fedora()");
		
		if (list_install.length == 0){ return true; }
		
		string cmd = distro.package_manager;

		if (no_prompt){
			cmd += " -y";
		}

		cmd += " install %s".printf(list_install);
		
		int status = Posix.system(cmd);

		log_msg(string.nfill(70,'-'));
		log_msg(Message.RESTORE_OK);
		
		return (status == 0);
	}

	private bool install_packages_arch(string list_install, bool no_prompt){

		log_debug("install_packages_arch()");

		if (list_install.length == 0){ return true; }

		string cmd = distro.package_manager;

		if (no_prompt){
			cmd += " --noconfirm";
		}

		cmd += " -S %s".printf(list_install);
		
		int status = Posix.system(cmd);

		log_msg(string.nfill(70,'-'));
		log_msg(Message.RESTORE_OK);
		
		return (status == 0);
	}

	private bool install_packages_debian(string basepath, string list_install, bool no_prompt){

		log_debug("install_packages_debian()");
		
		if (list_install.length == 0){ return true; }

		string cmd = distro.package_manager;
		
		if (no_prompt){
			cmd += " -y";
		}

		cmd += " install %s".printf(list_install);
		
		int status = Posix.system(cmd);
		log_msg(string.nfill(70,'-'));

		install_packages_deb(basepath);
		
		log_msg(Message.RESTORE_OK);
		log_msg(string.nfill(70,'-'));
		
		return (status == 0);
	}

	private bool install_packages_deb(string basepath){

		log_debug("install_packages_deb()");

		string backup_path = path_combine(basepath, "debs");
		if (!dir_exists(backup_path)){ return true; }

		var list = dir_list_names(backup_path, true);
		if (list.size == 0){ return true; }

		log_msg(_("Installing DEB packages..."));
		
		if (cmd_exists("apt")){
			return install_packages_deb_apt(list);
		}
		else if (cmd_exists("gdebi")){
			return install_packages_deb_gdebi(list);
		}
		else {
			return false;
		}
	}

	private bool install_packages_deb_apt(Gee.ArrayList<string> list){

		log_debug("install_packages_deb_apt()");

		if (!cmd_exists("apt")){
			log_error("%s: %s".printf(Message.MISSING_COMMAND, "apt"));
			return false; // exit method
		}

		string txt = "";
		foreach(string file_path in list){
			txt += " '%s'".printf(escape_single_quote(file_path));
		}

		string cmd = "apt install %s".printf(txt.strip());
		log_debug(cmd);
		
		int status = Posix.system(cmd);
		log_msg(string.nfill(70,'-'));

		return (status == 0);
	}

	private bool install_packages_deb_gdebi(Gee.ArrayList<string> list){

		log_debug("install_packages_deb_gdebi()");

		if (!cmd_exists("gdebi")){
			log_error("%s: %s".printf(Message.MISSING_COMMAND, "gdebi"));
			return false; // exit method
		}

		string txt = "";
		foreach(string file_path in list){
			txt += " '%s'".printf(escape_single_quote(file_path));
		}

		string cmd = "gdebi -n %s".printf(txt.strip());
		log_debug(cmd);
		
		int status = Posix.system(cmd);
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
}
