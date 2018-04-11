
/*
 * LinuxDistro.vala
 *
 * Copyright 2012-17 Tony George <teejeetech@gmail.com>
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

public class LinuxDistro : GLib.Object{

	/* Class for getting information about Linux distribution */

	public string dist_id = ""; // Ubuntu
	public string dist_type = ""; // debian
	public string dist_type_name = ""; // Debian / Ubuntu
	
	public string description = ""; // Ubuntu 16.04
	public string release = ""; // 16.04
	public string codename = ""; // xenial
	public string dist_full_name = ""; // Ubuntu 16.04 (xenial)
	
	public string package_manager = ""; // dnf, yum, apt, pacman
	public string package_arch = ""; // x86_64, amd64, i386, i686, ...
	public string kernel_arch = ""; // x86_64, i386, i686, ...
	public int machine_arch = 0; // 32, 64, ...

	public string basepath = ""; // system root or mount path

	// ---------------------------------------
	
	public LinuxDistro(){

		basepath = "/";
		
		read_dist_release_file();
		
		check_dist_type();

		check_system();
	}

	public LinuxDistro.from_path(string root_path){

		basepath = root_path;

		read_dist_release_file();
		
		//check_dist_type(); // Not implemented
	}

	private void read_dist_release_file(){

		/* Returns info about Linux distribution installed at root path */

		string dist_file = path_combine(basepath, "/etc/lsb-release");
		
		var f = File.new_for_path(dist_file);
		
		if (f.query_exists()){

			/*
				DISTRIB_ID=Ubuntu
				DISTRIB_RELEASE=13.04
				DISTRIB_CODENAME=raring
				DISTRIB_DESCRIPTION="Ubuntu 13.04"
			*/

			foreach(string line in file_read(dist_file).split("\n")){

				if (line.split("=").length != 2){ continue; }

				string key = line.split("=")[0].strip();
				string val = line.split("=")[1].strip();

				if (val.has_prefix("\"")){
					val = val[1:val.length];
				}

				if (val.has_suffix("\"")){
					val = val[0:val.length-1];
				}

				switch (key){
					case "DISTRIB_ID":
						dist_id = val;
						break;
					case "DISTRIB_RELEASE":
						release = val;
						break;
					case "DISTRIB_CODENAME":
						codename = val;
						break;
					case "DISTRIB_DESCRIPTION":
						description = val;
						break;
				}
			}
		}
		else{

			dist_file = path_combine(basepath, "/etc/os-release");
			
			f = File.new_for_path(dist_file);
			
			if (f.query_exists()){

				/*
					NAME="Ubuntu"
					VERSION="13.04, Raring Ringtail"
					ID=ubuntu
					ID_LIKE=debian
					PRETTY_NAME="Ubuntu 13.04"
					VERSION_ID="13.04"
					HOME_URL="http://www.ubuntu.com/"
					SUPPORT_URL="http://help.ubuntu.com/"
					BUG_REPORT_URL="http://bugs.launchpad.net/ubuntu/"
				*/

				foreach(string line in file_read(dist_file).split("\n")){

					if (line.split("=").length != 2){ continue; }

					string key = line.split("=")[0].strip();
					string val = line.split("=")[1].strip();

					switch (key){
						case "ID":
							dist_id = val;
							break;
						case "VERSION_ID":
							release = val;
							break;
						//case "DISTRIB_CODENAME":
							//info.codename = val;
							//break;
						case "PRETTY_NAME":
							description = val;
							break;
					}
				}
			}
		}

		if (dist_id.length > 0){
			string val = "";
			val += dist_id;
			val += (release.length > 0) ? " " + release : "";
			val += (codename.length > 0) ? " (" + codename + ")" : "";
			dist_full_name = val;
		}
	}

	private void check_dist_type(){
		
		if (cmd_exists("dpkg")){
			
			dist_type = "debian";

			if (cmd_exists("aptitude")){
				package_manager = "aptitude";
			}
			else if (cmd_exists("apt-get")){
				package_manager = "apt-get";
			}
			else if (cmd_exists("apt-fast")){
				package_manager = "apt-fast";
			}
			else {
				package_manager = "apt";
			}
		}
		else if (cmd_exists("dnf")){
			dist_type = "fedora";
			package_manager = "dnf";
		}
		else if (cmd_exists("yum")){
			dist_type = "fedora";
			package_manager = "yum";
		}
		else if (cmd_exists("pacman")){
			dist_type = "arch";
			package_manager = "pacman";
		}
		else{
			log_error(Messages.UNKNOWN_DISTRO);
			dist_type = "unknown";
			package_manager = "unknown";
		}

		switch(dist_type){
		case "debian":
			dist_type_name = "Debian / Ubuntu";
			break;
		case "fedora":
			dist_type_name = "Fedora / RedHat / Cent OS";
			break;
		case "arch":
			dist_type_name = "Arch";
			break;
		default:
			dist_type_name = "Unknown";
			break;
		}

		check_package_arch();
	}

	private void check_package_arch(){

		string cmd = "";
		
		switch(dist_type){
		case "debian":
			cmd = "dpkg --print-architecture"; // i386, amd64, ...
			break;
			
		case "fedora":
			cmd = "uname -m";
			break;
			
		case "arch":
			cmd = "uname -m";  // x86_64, i386, i686, ...
			break;
		}

		if (cmd.length == 0){ return; }
		
		string std_out, std_err;
		exec_sync(cmd, out std_out, out std_err);
		package_arch = std_out.strip();;
	}

	private void check_system(){
		
		string std_out, std_err;
		int status = exec_sync("uname -m", out std_out, out std_err);
		kernel_arch = std_out.strip();

		status = exec_sync("getconf LONG_BIT", out std_out, out std_err);
		machine_arch = int.parse(std_out);
	}

	// public -----------------------------
	
	public static string get_running_desktop_name(){

		int pid = -1;

		pid = get_pid_by_name("cinnamon");
		if (pid > 0){
			return "Cinnamon";
		}

		pid = get_pid_by_name("xfdesktop");
		if (pid > 0){
			return "Xfce";
		}

		pid = get_pid_by_name("lxsession");
		if (pid > 0){
			return "LXDE";
		}

		pid = get_pid_by_name("gnome-shell");
		if (pid > 0){
			return "Gnome";
		}

		pid = get_pid_by_name("wingpanel");
		if (pid > 0){
			return "Elementary";
		}

		pid = get_pid_by_name("unity-panel-service");
		if (pid > 0){
			return "Unity";
		}

		pid = get_pid_by_name("plasma-desktop");
		if (pid > 0){
			return "KDE";
		}

		return "Unknown";
	}

	public void print_system_info(){
		
		//log_msg(string.nfill(70,'-'));
		
		if (dist_full_name.length > 0){
			log_msg("Distribution: %s".printf(dist_full_name));
		}
		
		log_msg("Dist Type: %s".printf(dist_type_name));
		log_msg("Package Manager: %s".printf(package_manager));
		log_msg("Architecture-Pkgs: %s".printf(package_arch));
		log_msg("Architecture-Kern: %s".printf(kernel_arch));
		log_msg("Architecture-Type: %d-bit".printf(machine_arch));
		
		//log_msg(string.nfill(70,'-'));
	}
}


