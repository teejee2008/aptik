/*
 * AptikConsole.vala
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

public const string AppName = "Aptik";
public const string AppShortName = "aptik";
public const string AppVersion = "18.6";
public const string AppAuthor = "Tony George";
public const string AppAuthorEmail = "teejeetech@gmail.com";

const string GETTEXT_PACKAGE = "";
const string LOCALE_DIR = "/usr/share/locale";

extern void exit(int exit_code);

public AptikConsole App = null;

public class AptikConsole : GLib.Object {

	public string basepath = "";
	public LinuxDistro distro = null;
	public bool no_prompt = false;
	public bool dry_run = false;
	public bool list_only = false;
	public bool robot = false;
	public bool use_xz = false;
	public bool redist = false;
	public bool apply_selections = false;
	
	public User current_user;
	public PackageManager? mgr_pkg = null;
	
	// info
	//public string user_name = "";
	//public string user_name_effective = "";

	// options
	public string userlist = "";
	public string password = "aptik";
	public bool full_backup = false;
	public string add_path = "";
	public bool exclude_hidden = false;
	public bool include_foreign = false;
	public bool exclude_icons = false;
	public bool exclude_themes = false;
	public bool exclude_fonts = false;
	public string exclude_from_file = "";
	
	public bool skip_repos = false;
	public bool skip_cache = false;
	public bool skip_packages = false;
	public bool skip_fonts = false;
	public bool skip_themes = false;
	public bool skip_icons = false;
	public bool skip_users = false;
	public bool skip_groups = false;
	public bool skip_home = false;
	public bool skip_mounts = false;
	public bool skip_dconf = false;
	public bool skip_cron = false;
	public bool skip_files = false;
	public bool skip_scripts = false;

	public uint64 config_size_limit = 0;

	//public Gee.ArrayList<string> dist_files = new Gee.ArrayList<string>();
	public Gee.ArrayList<string> dist_files_fonts = new Gee.ArrayList<string>();
	public Gee.ArrayList<string> dist_files_icons = new Gee.ArrayList<string>();
	public Gee.ArrayList<string> dist_files_themes = new Gee.ArrayList<string>();
	public Gee.ArrayList<string> dist_files_cron = new Gee.ArrayList<string>();
	
	public static int main (string[] args) {
		
		set_locale();

		//handle_signals();

		LOG_TIMESTAMP = false;

		init_tmp(AppShortName);

		check_dependencies();
		
		var console =  new AptikConsole();
		App = console;
		
		bool is_success = console.parse_arguments(args);
		return (is_success) ? 0 : 1;
	}

	private static void set_locale() {
		Intl.setlocale(GLib.LocaleCategory.MESSAGES, "aptik");
		Intl.textdomain(GETTEXT_PACKAGE);
		Intl.bind_textdomain_codeset(GETTEXT_PACKAGE, "utf-8");
		Intl.bindtextdomain(GETTEXT_PACKAGE, LOCALE_DIR);
	}

	public static void check_dependencies(){

		string[] dependencies = {
			"rsync","cp","rm","touch","ln","grep","find","awk","mount","umount","crontab","sync", "lsblk"
		};

		string missing = "";
		
		foreach(string cmd in dependencies){
			
			if (!cmd_exists(cmd)){
				
				if (missing.length > 0){
					missing = ", ";
				}
				missing += cmd;
			}
		}

		if (missing.length > 0){
			string msg ="%s: %s".printf(Messages.MISSING_COMMAND, missing);
			log_error(msg);
			log_error(_("Install required packages for missing commands"));
			exit(1);
		}
	}

	public void check_admin_access(){

		if (!user_is_admin()) {
			log_msg(_("Aptik needs admin access to backup and restore packages."));
			log_msg(_("Run the application as admin (using 'sudo' or 'pkexec')"));
			exit(0);
		}
	}
	
	public AptikConsole(){

		//stdout.printf("AptikConsole()\n");

		distro = new LinuxDistro();

		basepath = Environment.get_current_dir();

		//stdout.printf("query_users()\n");
		var mgr = new UserManager(distro, null, basepath, dry_run, redist, apply_selections);
		mgr.query_users(false);
		current_user = mgr.get_current_user();

		string home_config_aptik = path_combine(current_user.home_path, ".config/aptik");
		dir_create(home_config_aptik);
		chown(home_config_aptik, current_user.name, current_user.name);

		install_dependencies();

		read_distfiles();
	}

	public void read_distfiles(){

		//stdout.printf("read_distfiles()\n");
		
		//string list_file = path_combine(current_user.home_path, ".config/aptik/initial-files.list");
		string list_file_fonts = path_combine(current_user.home_path, ".config/aptik/initial-files-fonts.list");
		string list_file_icons = path_combine(current_user.home_path, ".config/aptik/initial-files-icons.list");
		string list_file_themes = path_combine(current_user.home_path, ".config/aptik/initial-files-themes.list");
		string list_file_cron = path_combine(current_user.home_path, ".config/aptik/initial-files-cron.list");

		dist_files_fonts = load_distfile(list_file_fonts);
		dist_files_icons = load_distfile(list_file_icons);
		dist_files_themes = load_distfile(list_file_themes);
		dist_files_cron = load_distfile(list_file_cron);

		//stdout.printf("read_distfiles(): done\n");
	}

	private Gee.ArrayList<string> load_distfile(string list_file){

		var list = new Gee.ArrayList<string>();
		
		if (file_exists(list_file)){
			
			foreach(string line in file_read(list_file).split("\n")){
				
				list.add(line);
			}
		}
		else{
			log_debug("not_found: %s".printf(list_file));
		}

		return list;
	}
	
	public void install_dependencies(){

		//stdout.printf("install_dependencies()\n");
		
		if (!cmd_exists("pv") || !cmd_exists("xz")){

			log_msg(string.nfill(70,'-'));
			log_msg(_("Installing Dependencies"));
			log_msg(string.nfill(70,'-'));
		
			var mgr = new RepoManager(distro, current_user, basepath, dry_run, redist, apply_selections);
			mgr.update_repos();
		}

		if (!cmd_exists("pv")){
			PackageManager.install_package("pv", "pv", "pv");
		}

		if (!cmd_exists("xz")){
			PackageManager.install_package("xz-utils", "xz", "xz");
		}

		if (!cmd_exists("pv")){
			log_error("%s: %s".printf(_("Missing dependency"), "pv"));
			exit(1);
		}

		if (!cmd_exists("xz")){
			log_error("%s: %s".printf(_("Missing dependency"), "xz"));
			exit(1);
		}
	}

	public void print_backup_path(){
		
		log_msg("Backup path: %s".printf(basepath));
		log_msg(string.nfill(70,'-'));
	}

	public string help_message() {

		string fmt = "  %-30s %s\n";

		string fmt2 = "%s -----------------------------------\n\n"; //▰▰▰ ◈
		
		string msg = "\n" + AppName + " v" + AppVersion + " by %s (%s)".printf(AppAuthor, AppAuthorEmail) + "\n\n";

		msg += _("Usage") + ": aptik <command> [options]\n\n";

		msg += fmt2.printf(Messages.TASK_REPOS);
		
		msg += "%s:\n".printf(_("Commands"));
		msg += fmt.printf("--list-repos", _("List software repositories"));
		msg += fmt.printf("--backup-repos", _("Save list of software repositories"));
		msg += fmt.printf("--restore-repos", _("Add missing software repositories from backup"));
		msg += fmt.printf("--import-missing-keys", _("Find and import missing keys for apt repos"));
		msg += "\n";

		msg += "%s: %s, %s,\n%s\n\n".printf(_("Supports"), "apt (Debian & Derivatives)", "pacman (Arch & Derivatives)", "dnf/yum (Fedora & Derivatives)");
		
		msg += fmt2.printf(Messages.TASK_CACHE);

		msg += "%s:\n".printf(_("Commands"));
		msg += fmt.printf("--backup-cache", _("Copy downloaded packages from system cache"));
		msg += fmt.printf("--restore-cache", _("Copy packages to system cache from backup"));
		msg += fmt.printf("--clear-cache", _("Remove downloaded packages from system cache"));
		msg += "\n";

		msg += "%s: %s, %s\n\n".printf(_("Supports"), "apt (Debian & Derivatives)", "pacman (Arch & Derivatives)");

		msg += fmt2.printf(Messages.TASK_PACKAGES);

		msg += "%s:\n".printf(_("Commands"));
		msg += fmt.printf("--list-installed", _("List all installed packages"));
		msg += fmt.printf("--list-installed-dist", _("List base packages installed by Linux distribution"));
		msg += fmt.printf("--list-installed-user", _("List packages installed by user"));
		msg += fmt.printf("--list-installed-auto", _("List packages auto-installed to satisfy dependencies"));
		msg += fmt.printf("--list-installed-foreign ", _("List installed non-native packages"));
		msg += fmt.printf("--backup-packages", _("Save list of installed packages"));
		msg += fmt.printf("--restore-packages", _("Install missing packages from backup"));
		msg += "\n";
		
		msg += "%s (--backup-packages):\n".printf(_("Options"));
		msg += fmt.printf("--include-pkg-foreign", _("Include non-native packages (excluded by default)"));
		msg += fmt.printf("--exclude-pkg-icons", _("Exclude icon-theme packages (included by default)"));
		msg += fmt.printf("--exclude-pkg-themes", _("Exclude theme packages (included by default)"));
		msg += fmt.printf("--exclude-pkg-fonts", _("Exclude font packages (included by default)"));
		msg += "\n";

		msg += "%s: %s, %s,\n%s\n\n".printf(_("Supports"), "apt (Debian & Derivatives)", "pacman (Arch & Derivatives)", "dnf/yum (Fedora & Derivatives)");

		msg += fmt2.printf(Messages.TASK_USERS);

		msg += "%s:\n".printf(_("Commands"));
		msg += fmt.printf("--list-users", _("List users"));
		msg += fmt.printf("--list-users-all", _("List all users (including system user accounts)"));
		msg += fmt.printf("--backup-users", _("Backup users"));
		msg += fmt.printf("--restore-users", _("Restore users from backup"));
		msg += "\n";
		
		msg += fmt2.printf(Messages.TASK_GROUPS);

		msg += "%s:\n".printf(_("Commands"));
		msg += fmt.printf("--list-groups", _("List groups"));
		msg += fmt.printf("--list-groups-all", _("List all groups (including system groups)"));
		msg += fmt.printf("--backup-groups", _("Backup groups"));
		msg += fmt.printf("--restore-groups", _("Restore groups from backup"));
		msg += "\n";

		msg += fmt2.printf(Messages.TASK_HOME);

		msg += "%s:\n".printf(_("Commands"));
		msg += fmt.printf("--backup-home", _("Backup data in users' home directories"));
		msg += fmt.printf("--restore-home", _("Restore data in users' home directories from backup"));
		msg += fmt.printf("--fix-ownership", _("Updates ownership for users' home directory contents"));
		msg += "\n";
		
		msg += "%s:\n".printf(_("Options"));
		msg += fmt.printf("--users <usr1,usr2,..>", _("Users to backup and restore"));
		msg += fmt.printf("", _("(default: all users)"));
		msg += "\n";
		//msg += fmt.printf("--duplicity", _("Use duplicity for backup instead of TAR"));
		//msg += fmt.printf("", _("default: TAR"));
		//msg += "\n";
		//msg += fmt.printf("--password <string>", _("Password for encryption/decryption with duplicity"));
		//msg += fmt.printf("", _("default: 'aptik'"));
		//msg += "\n";
		//msg += fmt.printf("--full", _("Do full backup with duplicity"));
		//msg += fmt.printf("", _("default: incremental if backup exists, else full"));
		//msg += "\n";
		msg += fmt.printf("--exclude-home-hidden", _("Exclude hidden files and directories (app configs)"));
		msg += fmt.printf("", _("(default: include)"));
		msg += fmt.printf("--exclude-from <file>", _("Exclude files which match patterns in specified file"));
		msg += "\n";
		
		msg += fmt2.printf(Messages.TASK_MOUNTS);

		msg += "%s:\n".printf(_("Commands"));
		msg += fmt.printf("--list-mounts", _("List /etc/fstab and /etc/crypttab entries"));
		msg += fmt.printf("--backup-mounts", _("Backup /etc/fstab and /etc/crypttab entries"));
		msg += fmt.printf("--restore-mounts", _("Restore /etc/fstab and /etc/crypttab entries from backup"));
		msg += "\n";

		msg += fmt2.printf(Messages.TASK_ICONS);

		msg += "%s:\n".printf(_("Commands"));
		msg += fmt.printf("--list-icons", _("List installed icon themes"));
		msg += fmt.printf("--backup-icons", _("Backup installed icon themes"));
		msg += fmt.printf("--restore-icons", _("Restore missing icon themes from backup"));
		msg += "\n";

		msg += fmt2.printf(Messages.TASK_THEMES);

		msg += "%s:\n".printf(_("Commands"));
		msg += fmt.printf("--list-themes", _("List installed themes"));
		msg += fmt.printf("--backup-themes", _("Backup installed themes"));
		msg += fmt.printf("--restore-themes", _("Restore missing themes from backup"));
		msg += "\n";

		msg += fmt2.printf(Messages.TASK_FONTS);

		msg += "%s:\n".printf(_("Commands"));
		msg += fmt.printf("--list-fonts", _("List installed fonts"));
		msg += fmt.printf("--backup-fonts", _("Backup installed fonts"));
		msg += fmt.printf("--restore-fonts", _("Restore missing fonts from backup"));
		msg += "\n";

		msg += fmt2.printf(Messages.TASK_DCONF);

		msg += "%s:\n".printf(_("Commands"));
		msg += fmt.printf("--list-dconf", _("List dconf settings changed by user"));
		msg += fmt.printf("--backup-dconf", _("Backup dconf settings changed by user"));
		msg += fmt.printf("--restore-dconf", _("Restore dconf settings from backup"));
		msg += "\n";
		
		msg += "%s:\n".printf(_("Options"));
		msg += fmt.printf("--users <usr1,usr2,..>", _("Users to backup and restore"));
		msg += fmt.printf("", _("(default: all users)"));
		msg += "\n";
		
		msg += fmt2.printf(Messages.TASK_CRON);

		msg += "%s:\n".printf(_("Commands"));
		msg += fmt.printf("--list-cron", _("List cron tasks"));
		msg += fmt.printf("--backup-cron", _("Backup cron tasks"));
		msg += fmt.printf("--restore-cron", _("Restore cron tasks"));
		msg += "\n";
		
		msg += "%s:\n".printf(_("Options"));
		msg += fmt.printf("--users <usr1,usr2,..>", _("Users to backup and restore"));
		msg += fmt.printf("", _("(default: all users)"));
		msg += "\n";

		msg += fmt2.printf(Messages.TASK_FILES);

		msg += "%s:\n".printf(_("Commands"));
		msg += fmt.printf("--list-files", _("List files from backup"));
		msg += fmt.printf("--backup-files", _("Backup files and directories (specify with --add)"));
		msg += fmt.printf("--restore-files", _("Restore files and directories from backup"));
		msg += "\n";
		
		msg += "%s:\n".printf(_("Options"));
		msg += fmt.printf("--add <path>", _("Add file or directory to backups"));
		msg += "\n";

		msg += fmt2.printf(Messages.TASK_SCRIPTS);

		msg += "%s:\n".printf(_("Commands"));
		msg += fmt.printf("--list-scripts", _("List scripts from backup"));
		msg += fmt.printf("--exec-scripts", _("Execute scripts from backup"));
		msg += "\n";
		
		msg += fmt2.printf(_("All Items"));

		msg += "%s:\n".printf(_("Commands"));
		msg += fmt.printf("--backup-all", _("Backup all items"));
		msg += fmt.printf("--restore-all", _("Restore all items from backup"));
		msg += fmt.printf("--remove-all", _("Remove all items from backup"));
		msg += fmt.printf("--sysinfo", _("Show system information"));
		msg += "\n";

		msg += "%s:\n".printf(_("Options"));
		msg += fmt.printf("--users <usr1,usr2,..>", _("Users to backup and restore"));
		msg += fmt.printf("", _("(default: all users)"));
		msg += fmt.printf("--skip-repos", _("Skip item: repos"));
		msg += fmt.printf("--skip-cache", _("Skip item: cache"));
		msg += fmt.printf("--skip-packages", _("Skip item: packages"));
		msg += fmt.printf("--skip-fonts", _("Skip item: fonts"));
		msg += fmt.printf("--skip-themes", _("Skip item: themes"));
		msg += fmt.printf("--skip-icons", _("Skip item: icons"));
		msg += fmt.printf("--skip-users", _("Skip item: users"));
		msg += fmt.printf("--skip-groups", _("Skip item: groups"));
		msg += fmt.printf("--skip-home", _("Skip item: home"));
		msg += fmt.printf("--skip-mounts", _("Skip item: mounts"));
		msg += fmt.printf("--skip-dconf", _("Skip item: dconf"));
		msg += fmt.printf("--skip-cron", _("Skip item: cron"));
		msg += fmt.printf("--skip-files", _("Skip copying files in $basepath/files"));
		msg += fmt.printf("--skip-scripts", _("Skip execution of post-restore scripts in $basepath/scripts"));
		msg += "\n";

		msg += "%s\n".printf(_("Note: Options for individual items listed in previous sections can also be used"));
		msg += "\n";
		
		msg += fmt2.printf(("Common Options"));
		
		msg += fmt.printf("--basepath <dir>", _("Backup directory (default: current directory)"));
		msg += fmt.printf("--scripted", _("Run in non-interactive mode"));
		msg += fmt.printf("--dry-run", _("Simulate actions for --restore commands"));
		msg += fmt.printf("--version", _("Show version and exit"));
		msg += fmt.printf("--help", _("Show all options"));
		msg += "\n";
		
		return msg;
	}

	public bool parse_arguments(string[] args) {

		log_debug("parse_arguments()");
		
		if (args.length == 1) {
			//no args given
			log_msg(help_message());
			return false;
		}

		string command = "";
		
		// parse options and commands -----------------
		
		for (int k = 1; k < args.length; k++) {// Oth arg is app path

			switch (args[k].down()) {
			case "--basepath":
				k += 1;
				basepath = args[k];

				if (basepath.has_prefix("./")){
					basepath = path_combine(Environment.get_current_dir(), basepath[2:basepath.length]);
				}
				else if (basepath.has_prefix("../")){
					basepath = path_combine(file_parent(Environment.get_current_dir()), basepath[3:basepath.length]);
				}
				else if (!basepath.has_prefix("/")){
					basepath = path_combine(Environment.get_current_dir(), basepath);
				}

				if (!file_exists(basepath)){
					log_error("%s: %s".printf(_("Path not found"), basepath));
					exit(1);
				}

				break;

			case "--password":
				k++;
				password = args[k];
				break;

			case "--add":
				k++;
				add_path = args[k];
				break;
				
			case "--users":
				k++;
				userlist = args[k];
				break;

			case "--exclude-from":
				k++;
				exclude_from_file = args[k];
				break;

			case "--full":
				full_backup = true;
				break;

			case "--xz":
				use_xz = true;
				break;

			case "--exclude-home-hidden":
				exclude_hidden = true;
				break;

			case "--include-pkg-foreign":
				include_foreign = true;
				break;

			case "--exclude-pkg-icons":
				exclude_icons = true;
				break;

			case "--exclude-pkg-themes":
				exclude_themes = true;
				break;

			case "--exclude-pkg-fonts":
				exclude_fonts = true;
				break;

			case "--skip-repos":
				skip_repos = true;
				break;

			case "--skip-cache":
				skip_cache = true;
				break;

			case "--skip-packages":
				skip_packages = true;
				break;

			case "--skip-fonts":
				skip_fonts = true;
				break;

			case "--skip-themes":
				skip_themes = true;
				break;

			case "--skip-icons":
				skip_icons = true;
				break;

			case "--skip-users":
				skip_users = true;
				break;

			case "--skip-groups":
				skip_groups = true;
				break;

			case "--skip-mounts":
				skip_mounts = true;
				break;

			case "--skip-home":
				skip_home = true;
				break;

			case "--skip-dconf":
				skip_dconf = true;
				break;

			case "--skip-cron":
				skip_cron = true;
				break;

			case "--skip-files":
				skip_files = true;
				break;

			case "--skip-scripts":
				skip_scripts = true;
				break;

			case "--debug":
				LOG_DEBUG = true;
				break;
				
			case "--dry-run":
				dry_run = true;
				break;

			case "--scripted":
				no_prompt = true;
				break;

			case "--robot":
				robot = true;
				break;

			case "--redist":
				redist = true;
				break;

			case "--apply-selections":
				apply_selections = true;
				break;
				
			case "--dump-repos":
			case "--dump-repos-backup":
			case "--list-repos":
			case "--backup-repos":
			case "--restore-repos":
			case "--import-missing-keys":
			
			case "--list-installed":
			case "--list-installed-dist":
			case "--list-installed-user":
			case "--list-installed-auto":
			case "--list-installed-foreign":

			case "--dump-packages":
			case "--dump-packages-backup":
			case "--backup-packages":
			case "--restore-packages":

			case "--dump-cache":
			case "--dump-cache-backup":
			case "--backup-cache":
			case "--backup-pkg-cache":
			case "--restore-cache":
			case "--restore-pkg-cache":
			case "--clear-cache":
			case "--clear-pkg-cache":

			case "--dump-fonts":
			case "--dump-fonts-backup":
			case "--list-fonts":
			case "--backup-fonts":
			case "--restore-fonts":

			case "--dump-themes":
			case "--dump-themes-backup":
			case "--list-themes":
			case "--backup-themes":
			case "--restore-themes":

			case "--dump-icons":
			case "--dump-icons-backup":
			case "--list-icons":
			case "--backup-icons":
			case "--restore-icons":

			case "--dump-users":
			case "--dump-users-backup":
			case "--list-users":
			case "--list-users-all":
			case "--backup-users":
			case "--restore-users":

			case "--dump-groups":
			case "--dump-groups-backup":
			case "--list-groups":
			case "--list-groups-all":
			case "--backup-groups":
			case "--restore-groups":

			case "--dump-home":
			case "--dump-home-backup":
			case "--backup-home":
			case "--restore-home":
			case "--fix-ownership":

			case "--dump-mounts":
			case "--dump-mounts-backup":
			case "--list-mounts":
			case "--backup-mounts":
			case "--restore-mounts":

			case "--dump-dconf":
			case "--dump-dconf-backup":
			case "--list-dconf":
			case "--backup-dconf":
			case "--restore-dconf":

			case "--dump-cron":
			case "--dump-cron-backup":
			case "--list-cron":
			case "--backup-cron":
			case "--restore-cron":

			case "--dump-files":
			case "--dump-files-backup":
			case "--list-files":
			case "--backup-files":
			case "--restore-files":

			case "--dump-scripts":
			case "--dump-scripts-backup":
			case "--list-scripts":
			case "--exec-scripts":
			case "--restore-scripts":
			
			case "--backup-all":
			case "--restore-all":
			case "--remove-all":
			case "--sysinfo":
			case "--version":

				command = args[k].down();
				break;
				
			case "--help":
			case "--h":
			case "-h":
				log_msg(help_message());
				return true;

			default:
				// unknown option. show help and exit
				log_error(_("Unknown option") + ": %s".printf(args[k]));
				log_error(_("Run 'aptik --help' for available commands and options"));
				return false;
			}
		}

		if (command.length == 0){
			// no command specified
			log_error(_("No command specified!"));
			log_error(_("Run 'aptik --help' for available commands and options"));
			return false;
		}

		if (redist){
			
			//basepath = path_combine(basepath, "distribution");

			skip_cache = true;
			skip_users = true;
			skip_groups = true;

			use_xz = true;

			no_prompt = true;
		}
		else if (command == "--restore-all"){

			no_prompt = true;
		}

		// process command ----------------------------------
		
		switch (command) {

		// repos --------------------------------------------

		case "--dump-repos":
			return dump_repos();

		case "--dump-repos-backup":
			return dump_repos_backup();
			
		case "--list-repos":
			return list_repos();

		case "--backup-repos":
			//distro.print_system_info();
			log_msg("basepath='%s'".printf(basepath));
			return backup_repos();
			
		case "--restore-repos":
			//distro.print_system_info();
			check_network_connection(); // check once before starting
			log_msg("basepath='%s'".printf(basepath));
			return restore_repos();
			
		case "--import-missing-keys":
			//distro.print_system_info();
			log_msg("basepath='%s'".printf(basepath));
			return import_missing_keys();

		// package ---------------------------------------

		case "--dump-packages":
			return dump_packages();

		case "--dump-packages-backup":
			return dump_packages_backup();
			
		case "--list-installed":
			return list_packages_installed();
			
		case "--list-installed-dist":
			return list_packages_installed_dist();

		case "--list-installed-user":
			return list_packages_user_installed();

		case "--list-installed-auto":
			return list_packages_auto_installed();

		case "--list-installed-foreign":
			return list_packages_installed_foreign();

		case "--backup-packages":
			//distro.print_system_info();
			log_msg("basepath='%s'".printf(basepath));
			return backup_packages();
			
		case "--restore-packages":
			//distro.print_system_info();
			check_network_connection(); // check once before starting
			log_msg("basepath='%s'".printf(basepath));
			return restore_packages();
							
		// package cache -------------------------------------

		case "--dump-cache":
			return dump_cache();

		case "--dump-cache-backup":
			return dump_cache_backup();
			
		case "--backup-cache":
		case "--backup-pkg-cache":
			//distro.print_system_info();
			log_msg("basepath='%s'".printf(basepath));
			return backup_cache();
			
		case "--restore-cache":
		case "--restore-pkg-cache":
			//distro.print_system_info();
			log_msg("basepath='%s'".printf(basepath));
			return restore_cache();

		case "--clear-cache":
		case "--clear-pkg-cache":
			//distro.print_system_info();
			log_msg("basepath='%s'".printf(basepath));
			return clear_cache();

		// fonts -------------------------------------

		case "--dump-fonts":
			return dump_fonts();

		case "--dump-fonts-backup":
			return dump_fonts_backup();
			
		case "--list-fonts":
			return list_fonts();
			
		case "--backup-fonts":
			//distro.print_system_info();
			log_msg("basepath='%s'".printf(basepath));
			return backup_fonts();
			
		case "--restore-fonts":
			//distro.print_system_info();
			log_msg("basepath='%s'".printf(basepath));
			return restore_fonts();
						
		// themes ---------------------------------------------

		case "--dump-themes":
			return dump_themes();

		case "--dump-themes-backup":
			return dump_themes_backup();
			
		case "--list-themes":
			//distro.print_system_info();
			return list_themes();

		case "--backup-themes":
			//distro.print_system_info();
			log_msg("basepath='%s'".printf(basepath));
			return backup_themes();
			
		case "--restore-themes":
			//distro.print_system_info();
			log_msg("basepath='%s'".printf(basepath));
			return restore_themes();

		// icons ---------------------------------------------

		case "--dump-icons":
			return dump_icons();

		case "--dump-icons-backup":
			return dump_icons_backup();
			
		case "--list-icons":
			//distro.print_system_info();
			return list_icons();

		case "--backup-icons":
			//distro.print_system_info();
			log_msg("basepath='%s'".printf(basepath));
			return backup_icons();
			
		case "--restore-icons":
			//distro.print_system_info();
			log_msg("basepath='%s'".printf(basepath));
			return restore_icons();

		// users -------------------------------------------

		case "--dump-users":
			return dump_users();

		case "--dump-users-backup":
			return dump_users_backup();
			
		case "--list-users":
			return list_users();

		case "--list-users-all":
			return list_users(true);

		case "--backup-users":
			log_msg("basepath='%s'".printf(basepath));
			return backup_users();

		case "--restore-users":
			log_msg("basepath='%s'".printf(basepath));
			return restore_users();

		// groups -------------------------------------------

		case "--dump-groups":
			return dump_groups();

		case "--dump-groups-backup":
			return dump_groups_backup();
			
		case "--list-groups":
			return list_groups();

		case "--list-groups-all":
			return list_groups(true);

		case "--backup-groups":
			log_msg("basepath='%s'".printf(basepath));
			return backup_groups();

		case "--restore-groups":
			log_msg("basepath='%s'".printf(basepath));
			return restore_groups();

		// home -------------------------------------

		case "--dump-home":
			return dump_home();

		case "--dump-home-backup":
			return dump_home_backup();
			
		case "--backup-home":
			return backup_home();

		case "--restore-home":
			log_msg("basepath='%s'".printf(basepath));
			return restore_home();

		case "--fix-ownership":
			log_msg("basepath='%s'".printf(basepath));
			return fix_home_ownership();

		// mounts -------------------------------------------

		case "--dump-mounts":
			return dump_mounts();

		case "--dump-mounts-backup":
			return dump_mounts_backup();
			
		case "--list-mounts":
			return list_mount_entries();

		case "--backup-mounts":
			log_msg("basepath='%s'".printf(basepath));
			return backup_mount_entries();

		case "--restore-mounts":
			log_msg("basepath='%s'".printf(basepath));
			return restore_mount_entries();

		// dconf -------------------------------------------

		case "--dump-dconf":
			return dump_dconf();

		case "--dump-dconf-backup":
			return dump_dconf_backup();
			
		case "--list-dconf":
			return list_dconf_settings();

		case "--backup-dconf":
			log_msg("basepath='%s'".printf(basepath));
			return backup_dconf_settings();

		case "--restore-dconf":
			log_msg("basepath='%s'".printf(basepath));
			return restore_dconf_settings();

		// cron -------------------------------------------

		case "--dump-cron":
			return dump_cron();

		case "--dump-cron-backup":
			return dump_cron_backup();
			
		case "--list-cron":
			return list_cron_tasks();

		case "--backup-cron":
			log_msg("basepath='%s'".printf(basepath));
			return backup_cron_tasks();

		case "--restore-cron":
			log_msg("basepath='%s'".printf(basepath));
			return restore_cron_tasks();

		// files -------------------------------------------

		case "--dump-files":
			return dump_files();

		case "--dump-files-backup":
			return dump_files_backup();
			
		case "--list-files":
			log_msg("basepath='%s'".printf(basepath));
			return list_files();

		case "--backup-files":
			log_msg("basepath='%s'".printf(basepath));
			return backup_files();

		case "--restore-files":
			log_msg("basepath='%s'".printf(basepath));
			return restore_files();

		// scripts -------------------------------------------

		case "--dump-scripts":
			return dump_scripts();

		case "--dump-scripts-backup":
			return dump_scripts_backup();

		case "--list-scripts":
			log_msg("basepath='%s'".printf(basepath));
			return list_scripts();

		case "--exec-scripts":
		case "--restore-scripts":
			log_msg("basepath='%s'".printf(basepath));
			return execute_scripts();

		// all ---------------------------------------------

		case "--backup-all":
			//distro.print_system_info();
			log_msg("basepath='%s'".printf(basepath));
			return backup_all();

		case "--restore-all":
			//distro.print_system_info();
			log_msg("basepath='%s'".printf(basepath));
			return restore_all();

		case "--remove-all":
			//distro.print_system_info();
			log_msg("basepath='%s'".printf(basepath));
			return remove_all();

		case "--sysinfo":
			distro.print_system_info();
			return true;

		case "--version":
			log_msg(AppVersion);
			return true;
		}

		return true;
	}

	// all ------------------------------
	
	public bool backup_all(){

		bool status = true;

		bool ok = true;
		
		if (!skip_repos){
			ok = backup_repos();
			if (!ok) { status = false; }
		}

		if (!skip_cache){
			ok = backup_cache();
			if (!ok) { status = false; }
		}

		if (!skip_packages){
			ok = backup_packages();
			if (!ok) { status = false; }
		}

		if (!skip_users){
			ok = backup_users();
			if (!ok) { status = false; }
		}

		if (!skip_groups){
			ok = backup_groups();
			if (!ok) { status = false; }
		}

		if (!skip_home){
			ok = backup_home();
			if (!ok) { status = false; }
		}
		
		if (!skip_mounts){
			ok = backup_mount_entries();
			if (!ok) { status = false; }
		}

		if (!skip_icons){
			ok = backup_icons();
			if (!ok) { status = false; }
		}

		if (!skip_themes){
			ok = backup_themes();
			if (!ok) { status = false; }
		}

		if (!skip_fonts){
			ok = backup_fonts();
			if (!ok) { status = false; }
		}

		if (!skip_dconf){
			ok = backup_dconf_settings();
			if (!ok) { status = false; }
		}

		if (!skip_cron){
			ok = backup_cron_tasks();
			if (!ok) { status = false; }
		}

		/*if (!skip_files && redist){
			ok = copy_files_for_dist();
			if (!ok) { status = false; }
		}*/
		
		/*if (!skip_scripts && redist){
			ok = copy_scripts_for_dist();
			if (!ok) { status = false; }
		}*/
		
		return status;
	}

	public bool restore_all(){

		bool status = true;

		bool ok = true;

		// keeps steps independant; allow remaining steps to run if one step fails

		check_network_connection(); // check once before starting
		
		if (!skip_repos){
			ok = restore_repos();
			if (!ok) { status = false; }
		}

		if (!skip_cache){
			ok = restore_cache();
			if (!ok) { status = false; }
		}

		if (!skip_packages){
			ok = restore_packages();
			if (!ok) { status = false; }
		}

		if (!skip_users){
			ok = restore_users();
			if (!ok) { status = false; }
		}

		if (!skip_groups){
			ok = restore_groups();
			if (!ok) { status = false; }
		}

		if (!skip_home){
			ok = restore_home();
			if (!ok) { status = false; }
		}
		
		if (!skip_mounts){
			ok = restore_mount_entries();
			if (!ok) { status = false; }
		}

		if (!skip_icons){
			ok = restore_icons();
			if (!ok) { status = false; }
		}

		if (!skip_themes){
			ok = restore_themes();
			if (!ok) { status = false; }
		}

		if (!skip_fonts){
			ok = restore_fonts();
			if (!ok) { status = false; }
		}

		if (!skip_dconf){
			ok = restore_dconf_settings();
			if (!ok) { status = false; }
		}

		if (!skip_cron){
			ok = restore_cron_tasks();
			if (!ok) { status = false; }
		}

		if (!skip_files){
			ok = restore_files();
			if (!ok) { status = false; }
		}
		
		if (!skip_scripts){
			ok = execute_scripts();
			if (!ok) { status = false; }
		}

		return status;
	}

	public void check_basepath(){
		
		if (!dir_exists(basepath)){
			log_msg("%s: %s".printf(Messages.DIR_MISSING, basepath));
			exit(1);
		}
	}

	public bool check_backup_dir_exists(BackupType type){

		string backup_path = "";
		
		switch (type){
		case BackupType.PACKAGES:
			backup_path = path_combine(basepath, "packages");
			break;
		case BackupType.REPOS:
			backup_path = path_combine(basepath, "repos");
			break;
		case BackupType.CACHE:
			backup_path = path_combine(basepath, "cache");
			break;
		case BackupType.ICONS:
			backup_path = path_combine(basepath, "icons");
			break;
		case BackupType.THEMES:
			backup_path = path_combine(basepath, "themes");
			break;
		case BackupType.FONTS:
			backup_path = path_combine(basepath, "fonts");
			break;
		case BackupType.USERS:
			backup_path = path_combine(basepath, "users");
			break;
		case BackupType.GROUPS:
			backup_path = path_combine(basepath, "groups");
			break;
		case BackupType.MOUNTS:
			backup_path = path_combine(basepath, "mounts");
			break;
		case BackupType.HOME:
			backup_path = path_combine(basepath, "home");
			break;
		case BackupType.CRON:
			backup_path = path_combine(basepath, "cron");
			break;
		}

		if ((backup_path.length > 0) && dir_exists(backup_path)){
			return true;
		}
		else {
			log_error("%s: %s".printf(Messages.DIR_MISSING, backup_path));
			return false;
		}
	}
	
	public bool remove_all(){

		log_msg(string.nfill(70,'-'));
		
		bool ok = true, status = true;
		
		ok = remove_backup("repos");
		if (!ok) { status = false; }
		
		ok = remove_backup("cache");
		if (!ok) { status = false; }
		
		ok = remove_backup("packages");
		if (!ok) { status = false; }
		
		ok = remove_backup("users");
		if (!ok) { status = false; }
		
		ok = remove_backup("groups");
		if (!ok) { status = false; }
		
		ok = remove_backup("home");
		if (!ok) { status = false; }
		
		ok = remove_backup("mounts");
		if (!ok) { status = false; }
		
		ok = remove_backup("icons");
		if (!ok) { status = false; }
		
		ok = remove_backup("themes");
		if (!ok) { status = false; }
		
		ok = remove_backup("fonts");
		if (!ok) { status = false; }
		
		ok = remove_backup("dconf");
		if (!ok) { status = false; }
		
		ok = remove_backup("cron");
		if (!ok) { status = false; }

		string path = path_combine(basepath, AppShortName);
		if (file_exists(path)){
			file_delete(path);
			log_msg("%s: %s".printf(_("Removed"), path));
		}

		path = path_combine(basepath, "restore-all.sh");
		if (file_exists(path)){
			file_delete(path);
			log_msg("%s: %s".printf(_("Removed"), path));
		}

		foreach(string dirname in new string[]{ "debs", "files", "scripts"}){
			path = path_combine(basepath, dirname);
			delete_if_empty(path);
		}
		
		return status;
	}

	public bool delete_if_empty(string dirname){

		string path = path_combine(basepath, dirname);
		
		if (!dir_exists(path)){ return true; }
		
		var list = dir_list_names(path, false);

		if (list.size > 0){
			// skip if not empty
			log_msg("%s: %s (%d files found)".printf(_("Skipped"), path, list.size));
		}
		else{
			// remove if empty
			remove_backup(dirname);
		}

		return true;
	}

	public bool remove_backup(string item_name){

		string path = path_combine(basepath, item_name);

		bool ok = dir_delete(path);
		if (ok) {
			log_msg("%s: %s".printf(_("Removed"), path));
		}
		else {
			log_msg("%s: %s".printf(_("Error"), path));
		}

		return ok;
	}

	// repos --------------------------

	public bool dump_repos(){
		
		//check_admin_access();
		
		var mgr = new RepoManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.dump_info();
		return true;
	}

	public bool dump_repos_backup(){
		
		//check_admin_access();
		
		var mgr = new RepoManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.dump_info_backup();
		return true;
	}
	
	public bool list_repos(){

		check_admin_access();
		
		var mgr = new RepoManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		return mgr.list_repos();
	}
	
	public bool backup_repos(){

		check_admin_access();
		
		dir_create(basepath);

		copy_binary();
		
		var mgr = new RepoManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		return mgr.save_repos();
	}

	public bool restore_repos(){

		check_admin_access();
		
		check_basepath();
		if (!check_backup_dir_exists(BackupType.REPOS)) { return false; }

		var mgr = new RepoManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		return mgr.restore_repos();
	}

	public bool import_missing_keys(){
		var mgr = new RepoManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		return mgr.import_missing_keys(true);
	}

	// cache  ---------------------

	public bool dump_cache(){
		
		//check_admin_access();
		
		var mgr = new PackageCacheManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.dump_info();
		return true;
	}

	public bool dump_cache_backup(){
		
		//check_admin_access();
		
		var mgr = new PackageCacheManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.dump_info_backup();
		return true;
	}
	
	public bool backup_cache(){

		check_admin_access();
		
		dir_create(basepath);

		copy_binary();
		
		var mgr = new PackageCacheManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		return mgr.backup_cache(false);
	}

	public bool restore_cache(){

		check_admin_access();
		
		check_basepath();
		if (!check_backup_dir_exists(BackupType.CACHE)) { return false; }
		
		var mgr = new PackageCacheManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		return mgr.restore_cache();
	}

	public bool clear_cache(){
		var mgr = new PackageCacheManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		return mgr.clear_system_cache(no_prompt);
	}

	// packages ------------------------------

	public bool dump_packages(){
		
		//check_admin_access();

		var mgr = new PackageManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.dump_info(include_foreign, exclude_icons, exclude_themes, exclude_fonts);
		return true;
	}

	public bool dump_packages_backup(){
		
		//check_admin_access();
		
		var mgr = new PackageManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.dump_info_backup();
		return true;
	}
	
	public bool list_packages_available(){
		
		//check_admin_access();
		
		var mgr = new PackageManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.list_available();
		return true;
	}
	
	public bool list_packages_installed(){
		
		//check_admin_access();
		
		var mgr = new PackageManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.list_installed();
		return true;
	}

	public bool list_packages_installed_foreign(){
		
		//check_admin_access();
		
		var mgr = new PackageManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.list_foreign();
		return true;
	}

	public bool list_packages_installed_dist(){
		
		//check_admin_access();
		
		var mgr = new PackageManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.list_dist();
		return true;
	}

	public bool list_packages_auto_installed(){
		
		//check_admin_access();
		
		var mgr = new PackageManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.list_auto_installed();
		return true;
	}
	
	public bool list_packages_user_installed(){
		
		//check_admin_access();
		
		var mgr = new PackageManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.list_user_installed();
		return true;
	}

	public bool backup_packages(){

		check_admin_access();
		
		dir_create(basepath);

		copy_binary();
		
		mgr_pkg = new PackageManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		return mgr_pkg.save_package_list(include_foreign, exclude_icons, exclude_themes, exclude_fonts);
	}

	public bool restore_packages(){

		check_admin_access();
		
		check_basepath();
		if (!check_backup_dir_exists(BackupType.PACKAGES)) { return false; }
		
		var mgr = new PackageManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		bool ok = mgr.restore_packages(no_prompt);

		if (ok && !dry_run){
			
			var mgr2 = new PackageCacheManager(distro, current_user, basepath, dry_run, redist, apply_selections);

			if (!redist){
				ok = mgr2.backup_cache(true);
			}
			
			ok = ok && mgr2.clear_system_cache(true);
		}

		return ok;
	}

	// themes -----------------------------

	public bool dump_themes(){
		
		//check_admin_access();

		var mgr = new ThemeManager(distro, current_user, basepath, dry_run, redist, apply_selections, "themes");
		mgr.check_installed_themes();
		mgr.dump_info();
		return true;
	}

	public bool dump_themes_backup(){
		
		//check_admin_access();

		var mgr = new ThemeManager(distro, current_user, basepath, dry_run, redist, apply_selections, "themes");
		mgr.check_archived_themes();
		mgr.dump_info_backup();
		return true;
	}
	
	public bool list_themes(){

		check_admin_access();

		var mgr = new ThemeManager(distro, current_user, basepath, dry_run, redist, apply_selections, "themes");
		mgr.check_installed_themes();
		mgr.list_themes();
		return true;
	}
	
	public bool backup_themes(){

		check_admin_access();
		
		dir_create(basepath);

		copy_binary();

		var mgr = new ThemeManager(distro, current_user, basepath, dry_run, redist, apply_selections, "themes");
		mgr.check_installed_themes();
		return mgr.save_themes(use_xz);
	}

	public bool restore_themes(){

		check_admin_access();
		
		check_basepath();
		if (!check_backup_dir_exists(BackupType.THEMES)) { return false; }
		
		var mgr = new ThemeManager(distro, current_user, basepath, dry_run, redist, apply_selections, "themes");
		mgr.check_archived_themes();
		return mgr.restore_themes();
	}

	// icons -----------------------------

	public bool dump_icons(){
		
		//check_admin_access();

		var mgr = new ThemeManager(distro, current_user, basepath, dry_run, redist, apply_selections, "icons");
		mgr.check_installed_themes();
		mgr.dump_info();
		return true;
	}

	public bool dump_icons_backup(){
		
		//check_admin_access();

		var mgr = new ThemeManager(distro, current_user, basepath, dry_run, redist, apply_selections, "icons");
		mgr.check_archived_themes();
		mgr.dump_info_backup();
		return true;
	}
	
	public bool list_icons(){

		check_admin_access();

		var mgr = new ThemeManager(distro, current_user, basepath, dry_run, redist, apply_selections, "icons");
		mgr.check_installed_themes();
		return true;
	}
	
	public bool backup_icons(){

		check_admin_access();
		
		dir_create(basepath);

		copy_binary();

		var mgr = new ThemeManager(distro, current_user, basepath, dry_run, redist, apply_selections, "icons");
		mgr.check_installed_themes();
		return mgr.save_themes(use_xz);
	}

	public bool restore_icons(){

		check_admin_access();
		
		check_basepath();
		if (!check_backup_dir_exists(BackupType.ICONS)) { return false; }
		
		var mgr = new ThemeManager(distro, current_user, basepath, dry_run, redist, apply_selections, "icons");
		mgr.check_archived_themes();
		return mgr.restore_themes();
	}

	// fonts -----------------------------

	public bool dump_fonts(){
		
		//check_admin_access();
		
		var mgr = new FontManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.dump_info();
		return true;
	}

	public bool dump_fonts_backup(){
		
		//check_admin_access();
		
		var mgr = new FontManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.dump_info_backup();
		return true;
	}

	public bool list_fonts(){

		check_admin_access();
		
		var mgr = new FontManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.list_fonts();
		return true;
	}
	
	public bool backup_fonts(){

		check_admin_access();
		
		dir_create(basepath);

		copy_binary();

		var mgr = new FontManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		return mgr.backup_fonts();
	}

	public bool restore_fonts(){

		check_admin_access();
		
		check_basepath();
		if (!check_backup_dir_exists(BackupType.ICONS)) { return false; }
		
		var mgr = new FontManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		return mgr.restore_fonts();
	}

	// users -----------------------------

	public bool dump_users(){
		
		//check_admin_access();
		
		var mgr = new UserManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.dump_info();
		return true;
	}

	public bool dump_users_backup(){
		
		//check_admin_access();
		
		var mgr = new UserManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.dump_info_backup();
		return true;
	}
	
	public bool list_users(bool all = false){

		check_admin_access();
		
		var mgr = new UserManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.query_users(true);
		mgr.list_users(all);
		return true;
	}

	public bool backup_users(){

		check_admin_access();
		
		dir_create(basepath);

		copy_binary();

		bool status = true;

		var us_mgr = new UserManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		us_mgr.query_users(true);
		bool ok = us_mgr.backup_users();
		if (!ok){ status = false; }

		return status; 
	}

	public bool restore_users(){

		check_admin_access();
		
		check_basepath();
		if (!check_backup_dir_exists(BackupType.USERS)) { return false; }

		bool status = true, ok;
		
		var usr_mgr = new UserManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		ok = usr_mgr.restore_users();
		if (!ok){ status = false; }
		
		return status;
	}

	// groups -----------------------------

	public bool dump_groups(){
		
		//check_admin_access();
		
		var mgr = new GroupManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.query_groups(dry_run);
		mgr.dump_info();
		return true;
	}

	public bool dump_groups_backup(){
		
		//check_admin_access();
		
		var mgr = new GroupManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.query_groups(dry_run);
		mgr.dump_info_backup();
		return true;
	}
	
	public bool list_groups(bool all = false){

		check_admin_access();
		
		var mgr = new GroupManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.query_groups(true);
		mgr.list_groups(all);
		return true;
	}
	
	public bool backup_groups(){

		check_admin_access();
		
		dir_create(basepath);

		copy_binary();

		bool status = true;

		var mgr = new GroupManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.query_groups(true);
		bool ok = mgr.backup_groups();
		if (!ok){ status = false; }
		
		return status; 
	}

	public bool restore_groups(){

		check_admin_access();
		
		check_basepath();
		if (!check_backup_dir_exists(BackupType.GROUPS)) { return false; }

		bool status = true;
		
		var mgr = new GroupManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		bool ok = mgr.restore_groups();
		if (!ok){ status = false; }
		
		return status;
	}

	// mounts -----------------------------

	public bool dump_mounts(){
		
		//check_admin_access();
		
		var mgr = new MountEntryManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.query_mount_entries();
		mgr.dump_info();
		return true;
	}

	public bool dump_mounts_backup(){
		
		//check_admin_access();
		
		var mgr = new MountEntryManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.dump_info_backup();
		return true;
	}
	
	public bool list_mount_entries(){

		check_admin_access();
		
		var mgr = new MountEntryManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.query_mount_entries();
		mgr.list_mount_entries();
		return true;
	}
	
	public bool backup_mount_entries(){

		check_admin_access();
		
		dir_create(basepath);
		chmod(basepath, "a+rwx");
		
		copy_binary();

		bool status = true;

		var mgr = new MountEntryManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.query_mount_entries();
		bool ok = mgr.backup_mount_entries();
		if (!ok){ status = false; }
		
		return status; 
	}

	public bool restore_mount_entries(){

		check_admin_access();
		
		check_basepath();
		if (!check_backup_dir_exists(BackupType.MOUNTS)) { return false; }

		bool status = true;
		
		var mgr = new MountEntryManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		bool ok = mgr.restore_mount_entries();
		if (!ok){ status = false; }
		
		return status;
	}

	// home -----------------------------

	public bool dump_home(){
		
		//check_admin_access();
		
		var mgr = new UserHomeDataManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.dump_info();
		return true;
	}

	public bool dump_home_backup(){
		
		//check_admin_access();
		
		var mgr = new UserHomeDataManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.dump_info_backup();
		return true;
	}
	
	public bool backup_home(){

		check_admin_access();
		
		bool status = true;

		var mgr = new UserHomeDataManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		bool ok = mgr.backup_home(userlist, exclude_hidden, use_xz, exclude_from_file);
		if (!ok){ status = false; }
		
		return status; 
	}

	public bool restore_home(){

		check_admin_access();
		
		check_basepath();
		if (!check_backup_dir_exists(BackupType.HOME)) { return false; }

		bool status = true;
		
		var mgr = new UserHomeDataManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		bool ok = mgr.restore_home(userlist);
		if (!ok){ status = false; }
		
		return status;
	}

	public bool fix_home_ownership(){
		
		//check_basepath();
		//if (!check_backup_dir_exists(BackupType.HOME)) { return false; }

		bool status = true;
		
		var mgr = new UserHomeDataManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		bool ok = mgr.fix_home_ownership(userlist);
		if (!ok){ status = false; }
		
		return status;
	}

	// dconf -----------------------------

	public bool dump_dconf(){
		
		//check_admin_access();
		
		var mgr = new DconfManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.dump_info();
		return true;
	}

	public bool dump_dconf_backup(){
		
		//check_admin_access();
		
		var mgr = new DconfManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.dump_info_backup();
		return true;
	}
	
	public bool list_dconf_settings(){

		check_admin_access();
		
		var mgr = new DconfManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.list_dconf_settings(userlist);
		return true;
	}
	
	public bool backup_dconf_settings(){

		check_admin_access();
		
		dir_create(basepath);

		copy_binary();

		bool status = true;

		var mgr = new DconfManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		bool ok = mgr.backup_dconf_settings(userlist);
		if (!ok){ status = false; }
		
		return status; 
	}

	public bool restore_dconf_settings(){

		check_admin_access();
		
		check_basepath();
		if (!check_backup_dir_exists(BackupType.MOUNTS)) { return false; }

		bool status = true;
		
		var mgr = new DconfManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		bool ok = mgr.restore_dconf_settings(userlist);
		if (!ok){ status = false; }
		
		return status;
	}

	// cron -----------------------------

	public bool dump_cron(){
		
		//check_admin_access();
		
		var mgr = new CronTaskManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.dump_info();
		return true;
	}

	public bool dump_cron_backup(){
		
		//check_admin_access();
		
		var mgr = new CronTaskManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.dump_info_backup();
		return true;
	}

	
	public bool list_cron_tasks(){

		check_admin_access();
		
		var mgr = new CronTaskManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		mgr.list_cron_tasks(userlist);
		return true;
	}
	
	public bool backup_cron_tasks(){

		check_admin_access();
		
		dir_create(basepath);

		copy_binary();

		bool status = true;

		var mgr = new CronTaskManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		bool ok = mgr.backup_cron_tasks(userlist);
		if (!ok){ status = false; }
		
		return status; 
	}

	public bool restore_cron_tasks(){

		check_admin_access();
		
		check_basepath();
		if (!check_backup_dir_exists(BackupType.CRON)) { return false; }

		bool status = true;
		
		var mgr = new CronTaskManager(distro, current_user, basepath, dry_run, redist, apply_selections);
		bool ok = mgr.restore_cron_tasks(userlist);
		if (!ok){ status = false; }
		
		return status;
	}

	// files ----------------

	public bool dump_files(){
		
		return dump_files_backup();
	}

	public bool dump_files_backup(){

		//check_admin_access();

		string txt = "";
		
		var files_path = path_combine(basepath, "files");

		var data_path = path_combine(files_path, "data");

		var files = dir_list_names(data_path, true);
		
		foreach(string f in files){

			txt += "NAME='%s'".printf(file_basename(f));

			string sz = format_file_size(file_get_size(f));

			txt += ",DESC='%s'".printf(sz);
			
			txt += ",ACT='%s'".printf("0");
			
			txt += ",SENS='%s'".printf("1");
			
			txt += "\n";
		}
		
		log_msg(txt);

		return true;
	}

	public bool list_files(){

		//check_admin_access();
		
		var files_path = path_combine(basepath, "files");

		var data_path = path_combine(files_path,"data");

		if (dir_exists(data_path)){

			var files = dir_list_names(data_path, true);
			
			if (files.size > 0){

				log_msg(string.nfill(70,'-'));
				
				foreach(var file in files){
					UserHomeDataManager.list_archive(file);
				}
			}
			else{
				log_msg(_("no files found for copy"));
				log_msg(string.nfill(70,'-'));
			}
		}
		else{
			log_msg("%s: %s".printf(Messages.DIR_MISSING, data_path));
			log_msg(string.nfill(70,'-'));
		}

		return true;
	}
	
	public bool backup_files(){

		check_admin_access();
		
		dir_create(basepath);

		copy_binary();

		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Backup"), Messages.TASK_FILES));
		log_msg(string.nfill(70,'-'));

		bool status = true;

		var files_path = path_combine(basepath, "files");

		if (!dir_exists(files_path)){
			dir_create(files_path);
			chmod(files_path, "a+rwx");
		}

		var data_path = path_combine(files_path, "data");

		if (!dir_exists(data_path)){
			dir_create(data_path);
			chmod(data_path, "a+rwx");
		}

		var src_path = add_path;

		if (file_exists(src_path)){
		
			string tar_file_name = src_path.replace("/","_") + ".tar." + (use_xz ? "xz" : "gz");

			UserHomeDataManager.zip_archive(src_path, data_path, tar_file_name);
			
			log_msg(string.nfill(70,'-'));
		}
		else{
			log_msg("%s: %s".printf(Messages.DIR_MISSING, data_path));
			log_msg(string.nfill(70,'-'));
		}
		
		return status; 
	}
	
	public bool restore_files(){

		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Restore"), Messages.TASK_FILES));
		log_msg(string.nfill(70,'-'));
		
		var files_path = path_combine(basepath, "files");

		var data_path = path_combine(files_path,"data");

		if (dir_exists(data_path)){

			var files = dir_list_names(data_path, true);
			
			if (files.size > 0){

				foreach(var file in files){
					UserHomeDataManager.unzip_archive(file, "/", dry_run);
				}
			}
			else{
				log_msg(_("no files found"));
				//log_msg(string.nfill(70,'-'));
			}
		}
		else{
			log_msg("%s: %s".printf(Messages.DIR_MISSING, data_path));
			//log_msg(string.nfill(70,'-'));
		}

		return true;
	}

	public bool copy_files_for_dist(){

		string src = path_combine(file_parent(basepath), "files");
		string dst = path_combine(basepath, "files");

		if (!file_exists(src)){ return true; }
		
		string cmd = "cp -vf '%s' '%s'".printf(escape_single_quote(src), escape_single_quote(dst));

		log_debug(cmd);
		
		Posix.system(cmd);

		log_msg(_("copied files to distribution directory"));
		log_msg(string.nfill(70,'-'));

		return true;
	}

	// scripts --------------

	public bool dump_scripts(){
		
		return dump_scripts_backup();
	}

	public bool dump_scripts_backup(){

		//check_admin_access();

		string txt = "";
		
		var scripts_path = path_combine(basepath, "scripts");
		
		var files_path = path_combine(scripts_path, "files");

		var files = dir_list_names(files_path, true);
		
		foreach(string f in files){

			txt += "NAME='%s'".printf(file_basename(f));

			string desc = "";
			foreach(var line in file_read(f).split("\n")){
				if (line.strip().has_prefix("# aptik-desc:")){
					desc = line.split("# aptik-desc:")[1].strip();
				}
			}

			txt += ",DESC='%s'".printf(desc);
			
			txt += ",ACT='%s'".printf("0");
			
			txt += ",SENS='%s'".printf("1");
			
			txt += "\n";
		}
		
		log_msg(txt);

		return true;
	}

	public bool list_scripts(){

		//check_admin_access();
		
		var scripts_path = path_combine(basepath, "scripts");
		
		var files_path = path_combine(scripts_path, "files");

		if (dir_exists(files_path)){

			var files = dir_list_names(files_path, true);
			
			if (files.size > 0){

				log_msg(string.nfill(70,'-'));
				
				foreach(var file in files){

					string desc = "";
					foreach(var line in file_read(file).split("\n")){
						if (line.strip().has_prefix("# aptik-desc:")){
							desc = line.split("# aptik-desc:")[1].strip();
						}
					}

					string txt = file_basename(file);

					txt += file_basename(file).has_suffix("~") ? " (%s)".printf(_("disabled")) : "";

					if (desc.length > 0){
						txt += " -- %s".printf(desc);
					}

					log_msg(txt);
				}
			}
			else{
				log_msg(_("No scripts found"));
				log_msg(string.nfill(70,'-'));
			}
		}
		else{
			log_msg("%s: %s".printf(Messages.DIR_MISSING, files_path));
			log_msg(string.nfill(70,'-'));
		}

		return true;
	}
	
	public bool execute_scripts(){

		var scripts_path = path_combine(basepath, "scripts");

		var files_path = path_combine(scripts_path, "files");

		log_msg(string.nfill(70,'-'));
		log_msg("%s:".printf(_("Execute Post-Restore Scripts")));
		log_msg(string.nfill(70,'-'));
				
		if (dir_exists(files_path)){

			var files = dir_list_names(files_path, true);
			files.sort();

			if (files.size > 0){

				bool scripts_found = false;
				
				foreach(string file in files){

					if (file.has_suffix("~")){ continue; }

					if (file.has_suffix("README")){ continue; }

					scripts_found = true;
					
					chmod(file, "a+x");
					log_msg("%s: %s\n".printf(_("Execute"), file_basename(file)));
					Posix.system("sh '%s'".printf(escape_single_quote(file)));
					log_msg(string.nfill(70,'-'));
				}

				if (!scripts_found){
					log_msg(_("No scripts found"));
				}
			}
			else{
				log_msg(_("No scripts found"));
				//log_msg(string.nfill(70,'-'));
			}
		}
		else{
			log_msg("%s: %s".printf(Messages.DIR_MISSING, files_path));
			//log_msg(string.nfill(70,'-'));
		}

		return true;
	}

	public bool copy_scripts_for_dist2(){

		string src = path_combine(file_parent(basepath), "scripts");
		string dst = path_combine(basepath, "scripts");

		if (!file_exists(src)){ return true; }
		
		string cmd = "cp -vf '%s' '%s'".printf(escape_single_quote(src), escape_single_quote(dst));

		log_debug(cmd);
		
		Posix.system(cmd);

		log_msg(_("Copied scripts to distribution directory"));
		log_msg(string.nfill(70,'-'));

		return true;
	}
	
	// common ---------------
	
	public void copy_binary(){

		string src = get_cmd_path(AppShortName);
		string dst = path_combine(basepath, AppShortName);

		string cmd = "cp -f '%s' '%s'".printf(escape_single_quote(src), escape_single_quote(dst));
			
		log_debug(cmd);
		Posix.system(cmd);

		copy_restore_script();

		create_files_and_scripts();
	}

	public void copy_restore_script(){

		string s = "#!/bin/bash" + "\n";
		s += """basepath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" """ + "\n";
		s += "sudo chmod a+x \"$basepath/aptik\"" + "\n";
		s += "sudo \"$basepath/aptik\" --restore-all --basepath \"$basepath\"" + (redist ? " --redist" : "") + "\n";

		string sh_file = path_combine(basepath, "restore-all.sh");
		file_write(sh_file, s);
		chmod(sh_file, "a+x");
	}

	public void create_files_and_scripts(){

		var scripts_path = path_combine(basepath,"scripts");
		if (!dir_exists(scripts_path)){
			dir_create(scripts_path);
			chmod(scripts_path, "a+rwx");
		}

		var readme = path_combine(scripts_path,"README");
		if (!file_exists(readme)){
			string txt = _("Scripts placed in this folder will be executed on restore. Name scripts in the order in which they should be executed.");
			file_write(readme, txt);
			chmod(readme, "a+rw");
		}

		var files_path = path_combine(basepath,"files");
		if (!dir_exists(files_path)){
			dir_create(files_path);
			chmod(files_path, "a+rwx");
		}

		readme = path_combine(files_path,"README");
		if (!file_exists(readme)){
			string txt = _("TAR files placed in 'data' folder will be extracted to file system root after restore.");
			file_write(readme, txt);
			chmod(readme, "a+rw");
		}

		var data_path = path_combine(files_path,"data");
		if (!dir_exists(data_path)){
			dir_create(data_path);
			chmod(data_path, "a+rwx");
		}
	}
	
	public void check_network_connection(){

		bool connected = check_internet_connectivity();

		if (!connected){
			log_error(_("Internet connection not active"));
			log_error(_("Internet is required for restoring repositories and packages"));
			exit(2);
		}
	}

	// input ----------

	public static void handle_signals(){
		
		//Unix.signal_add(Posix.Signal.HUP,  () => { log_msg("Received interrupt signal"); exit(0); return false; });
        //Unix.signal_add(Posix.Signal.INT,  () => { log_msg("Received interrupt signal"); exit(0); return false; });
        //Unix.signal_add(Posix.Signal.TERM, () => { log_msg("Received interrupt signal"); exit(0); return false; });
	}
}

public class BackupConfig : GLib.Object{
	
}

public enum BackupType {
	PACKAGES,
	REPOS,
	CACHE,
	ICONS,
	THEMES,
	FONTS,
	USERS,
	GROUPS,
	MOUNTS,
	HOME,
	DCONF,
	CRON
}
