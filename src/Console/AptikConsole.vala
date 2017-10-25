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

public const string AppName = "Aptik NG";
public const string AppShortName = "aptik";
public const string AppVersion = "17.10";
public const string AppAuthor = "Tony George";
public const string AppAuthorEmail = "teejeetech@gmail.com";

const string GETTEXT_PACKAGE = "";
const string LOCALE_DIR = "/usr/share/locale";

extern void exit(int exit_code);

public class AptikConsole : GLib.Object {

	public string basepath = "";
	public LinuxDistro distro = null;
	public bool no_prompt = true;
	public bool dry_run = false;
	public bool list_only = false;

	public string password = "";
	public uint64 config_size_limit = 0;
	

	//public UserManager user_mgr;

	public static int main (string[] args) {
		
		set_locale();

		LOG_TIMESTAMP = false;

		init_tmp(AppShortName);

		if (!user_is_admin()) {
			log_msg(_("Aptik needs admin access to backup and restore packages."));
			log_msg(_("Please run the application as admin (using 'sudo' or 'pkexec')"));
			exit(0);
		}

		//App = new Aptik(args);
		
		var console =  new AptikConsole();
		bool is_success = console.parse_arguments(args);
		//App.exit_app();

		return (is_success) ? 0 : 1;
	}

	private static void set_locale() {
		Intl.setlocale(GLib.LocaleCategory.MESSAGES, "aptik");
		Intl.textdomain(GETTEXT_PACKAGE);
		Intl.bind_textdomain_codeset(GETTEXT_PACKAGE, "utf-8");
		Intl.bindtextdomain(GETTEXT_PACKAGE, LOCALE_DIR);
	}

	public AptikConsole(){

		distro = new LinuxDistro();

		basepath = Environment.get_current_dir();

		//user_mgr = new UserManager();
		//user_mgr.query_users(true);
	}

	public void print_backup_path(){
		log_msg("Backup path: %s".printf(basepath));
		log_msg(string.nfill(70,'-'));
	}

	public string help_message() {
		
		string msg = "\n" + AppName + " v" + AppVersion + " by %s (%s)".printf(AppAuthor, AppAuthorEmail) + "\n";
		msg += "\n";
		msg += _("Syntax") + ": aptik [options]\n";
		msg += "\n";
		msg += _("Options") + ":\n";
		msg += "\n";
		
		msg += _("Common") + ":\n";
		msg += "\n";
		msg += "  --basepath <dir>      " + _("Backup directory (defaults to current directory)") + "\n";
		msg += "  --scripted            " + _("Run in non-interactive mode") + "\n";
		msg += "  --dry-run             " + _("Show actions that will be executed on restore") + "\n";
		//msg += "  --user <username>     " + _("Select username for listing config files") + "\n";
		//msg += "  --password <password> " + _("Specify password for encrypting and decrypting backups") + "\n";
		//msg += "  --[show-]desc         " + _("Show package description if available") + "\n";
		msg += "  --help                " + _("Show all options") + "\n";
		msg += "\n";
		
		
		msg += "%s:\n".printf(Message.TASK_PPA);
		msg += "\n";
		//msg += "  --list-repo            " + _("List PPAs") + "\n";
		msg += "  --backup-repos          " + _("Save list of software repositories") + "\n";
		msg += "  --restore-repos         " + _("Add missing software repositories") + "\n";
		msg += "  --import-missing-keys   " + _("Import any missing public keys for software repositories") + "\n";
		msg += "\n";
		
		msg += "%s:\n".printf(Message.TASK_CACHE);
		msg += "\n";
		msg += "  --backup-cache        " + _("Copy downloaded packages from system cache") + "\n";
		msg += "  --restore-cache       " + _("Copy packages to system cache") + "\n";
		msg += "  --clear-cache         " + _("Remove downloaded packages from system cache") + "\n";
		msg += "\n";

		msg += "%s:\n".printf(Message.TASK_PACKAGE);
		msg += "\n";
		//msg += "  --list-available      " + _("List available packages") + "\n";
		//msg += "  --list-installed      " + _("List installed packages") + "\n";
		//msg += "  --list-auto[matic]    " + _("List auto-installed packages") + "\n";
		//msg += "  --list-{manual|extra} " + _("List extra packages installed by user") + "\n";
		//msg += "  --list-default        " + _("List default packages for linux distribution") + "\n";
		msg += "  --backup-packages     " + _("Save list of installed packages") + "\n";
		msg += "  --restore-packages    " + _("Install missing packages") + "\n";
		msg += "\n";

		/*
		msg += "%s:\n".printf(Message.TASK_USER);
		msg += "\n";
		msg += "  --backup-users        " + _("Backup users and groups") + "\n";
		msg += "  --restore-users       " + _("Restore users and groups") + "\n";
		msg += "\n";
		*/
		
		/*
		msg += "%s:\n".printf(Message.TASK_CONFIG);
		msg += "\n";
		msg += "  --list-configs        " + _("List config dirs in /home/<user>") + "\n";
		msg += "  --backup-configs      " + _("Backup config files from /home/<user>") + "\n";
		msg += "  --restore-configs     " + _("Restore config files to /home/<user>") + "\n";
		msg += "  --size-limit <bytes>  " + _("Skip config dirs larger than specified size") + "\n";
		msg += "\n";
		*/
		
		/*
		msg += "%s:\n".printf(Message.TASK_THEME);
		msg += "\n";
		msg += "  --list-themes         " + _("List themes in /usr/share/themes") + "\n";
		msg += "  --backup-themes       " + _("Backup themes from /usr/share/themes") + "\n";
		msg += "  --restore-themes      " + _("Restore themes to /usr/share/themes") + "\n";
		msg += "\n";
		*/
		
		/*
		msg += "%s:\n".printf(Message.TASK_MOUNT);
		msg += "\n";
		msg += "  --backup-mounts       " + _("Backup /etc/fstab and /etc/crypttab entries") + "\n";
		msg += "  --restore-mounts      " + _("Restore /etc/fstab and /etc/crypttab entries") + "\n";
		msg += "\n";
		*/
		
		/*
		msg += "%s:\n".printf(Message.TASK_HOME);
		msg += "\n";
		msg += "  --backup-home         " + _("Backup user-created data in user's home directory") + "\n";
		msg += "  --restore-home        " + _("Restore user-created data in user's home directory") + "\n";
		msg += "\n";
		*/
		
		/*
		msg += "%s:\n".printf(Message.TASK_CRON);
		msg += "\n";
		msg += "  --backup-crontab         " + _("Backup user's scheduled tasks (crontab)") + "\n";
		msg += "  --restore-crontab        " + _("Restore user's scheduled tasks (crontab)") + "\n";
		msg += "\n";
		*/
		
		msg += _("All Items") + ":\n";
		msg += "\n";
		msg += "  --backup-all          " + _("Backup all items") + "\n";
		msg += "  --restore-all         " + _("Restore all items") + "\n";
		//msg += "  --clean               " + _("Remove all backups from backup location") + "\n";
		msg += "\n";

		return msg;
	}

	public bool parse_arguments(string[] args) {

		if (args.length == 1) {
			//no args given
			log_msg(help_message());
			return false;
		}

		//App.select_user("", false); // set by main

		//parse options
		for (int k = 1; k < args.length; k++) {// Oth arg is app path

			switch (args[k].down()) {
			//case "--desc":
			//case "--show-desc":
			//	show_desc = true;
			//	break;
			case "--basepath":
				k += 1;
				basepath = args[k] + (args[k].has_suffix("/") ? "" : "/");
				break;
			case "--user":
			case "--username":
				k += 1;
				//App.select_user(args[k]);
				break;
			case "--size-limit":
			case "--limit-size":
				k += 1;
				config_size_limit = uint64.parse(args[k]);
				break;
			case "-y":
			case "--yes":
			case "--scripted":
				no_prompt = true;
				break;
			case "--debug":
				LOG_DEBUG = true;
				break;
			case "--password":
				k += 1;
				password = args[k];
				break;
			case "--dry-run":
				dry_run = true;
				break;
			case "--help":
			case "--h":
			case "-h":
				log_msg(help_message());
				return true;
			}
		}

		//parse commands
		for (int k = 1; k < args.length; k++) { // Oth arg is app path

			switch (args[k].down()) {

			// ppa --------------------------------------------
			
			//case "--list-repo":
			//case "--list-repos":
				//App.ppa_backup_init(show_desc);
				//foreach(Ppa ppa in App.ppa_list_master.values) {
				//	ppa.is_selected = true;
				//}
				//print_ppa_list(show_desc);
				//TODO: call the faster method for getting ppas?
				//break;

			case "--backup-repos":
				distro.print_system_info();
				return backup_repos();
				
			case "--restore-repos":
				distro.print_system_info();
				return restore_repos();
				
			case "--import-missing-keys":
				distro.print_system_info();
				return import_missing_keys();

			// package ---------------------------------------

			//case "--list-available":
				//App.read_package_info();
				//foreach(Package pkg in App.pkg_list_master.values) {
				//	pkg.is_selected = (pkg.is_available && !pkg.is_foreign());
				//}
				//print_package_list(show_desc);
				//break;

			//case "--list-installed":
				//App.read_package_info();
				//foreach(Package pkg in App.pkg_list_master.values) {
				//	pkg.is_selected = pkg.is_installed;
				//}
				//print_package_list(show_desc);
				//break;

			//case "--list-default":
				//App.read_package_info();
				//foreach(Package pkg in App.pkg_list_master.values) {
				//	pkg.is_selected = pkg.is_default;
				//}
				//print_package_list(show_desc);
				//break;

			//case "--list-auto":
			//case "--list-automatic":
				//App.read_package_info();
				//foreach(Package pkg in App.pkg_list_master.values) {
				//	pkg.is_selected = pkg.is_automatic;
				//}
				//print_package_list(show_desc);
				//break;

			//case "--list-manual":
			//case "--list-extra":
				//App.read_package_info();
				//foreach(Package pkg in App.pkg_list_master.values) {
				//	pkg.is_selected = pkg.is_manual;
				//}
				//print_package_list(show_desc);
				//break;

			//case "--backup-package":
			case "--backup-packages":
				distro.print_system_info();
				return backup_packages();
				
			//case "--restore-package":
			case "--restore-packages":
				distro.print_system_info();
				return restore_packages();
								
			// package cache -------------------------------------

			case "--backup-cache":
			case "--backup-pkg-cache":
				distro.print_system_info();
				return backup_cache();
				
			case "--restore-cache":
			case "--restore-pkg-cache":
				distro.print_system_info();
				return restore_cache();

			case "--clear-cache":
			case "--clear-pkg-cache":
				distro.print_system_info();
				return clear_cache();
								
			// config ---------------------------------------

			//case "--list-config":
			//case "--list-configs":
				//print_config_list(App.list_app_config_directories_from_home(false));
				//break;

			//case "--backup-appsettings":
			//case "--backup-configs":
			//case "--backup-config":
				//return backup_config();
				//return true;

			//case "--restore-appsettings":
			//case "--restore-configs":
				//return restore_config();
				//return true;

			// home -------------------------------------

			//case "--backup-user-data":
			//case "--backup-home":
				//return backup_home();
				//return true;

			//case "--restore-user-data":
			//case "--restore-home":
				//return restore_home();
				//return true;
				
			// theme ---------------------------------------------

			//case "--list-theme":
			//case "--list-themes":
				//print_theme_list(Theme.list_themes_installed(App.current_user.name, true));
				//break;

			case "--list-themes":
				//distro.print_system_info();
				return list_themes();

			case "--backup-themes":
				distro.print_system_info();
				return backup_themes();
				
			case "--restore-themes":
				distro.print_system_info();
				return restore_themes();

			case "--list-icons":
				//distro.print_system_info();
				return list_icons();

			case "--backup-icons":
				distro.print_system_info();
				return backup_icons();
				
			case "--restore-icons":
				distro.print_system_info();
				return restore_icons();

			// mount -------------------------------------------
			
			//case "--backup-mount":
			//case "--backup-mounts":
				//return backup_mounts();
				//return true;

			//case "--restore-mount":
			//case "--restore-mounts":
				//return restore_mounts();
				//return true;

			// users -------------------------------------------

			//case "--list-user":
			//case "--list-users":
				//return list_users_and_groups();
				//return true;

			//case "--backup-user":
			//case "--backup-users":
				//return backup_users_and_groups();
				//return true;

			//case "--restore-user":
			//case "--restore-users":
				//return restore_users_and_groups();
				//return true;

			// crontab -------------------------------------------

			//case "--backup-crontab":
			//case "--backup-crontabs":
				//return backup_crontab();
				//return true;

			//case "--restore-crontab":
			//case "--restore-crontabs":
				//return restore_crontab();
				//return true;
				
			// all ---------------------------------------------

			case "--backup-all":
				distro.print_system_info();
				return backup_all();

			case "--restore-all":
				distro.print_system_info();
				return restore_all();

			case "--clean":
				distro.print_system_info();
				return remove_backups();
				
			// other -------------------------------------------
			
			//case "--take-ownership":
				//App.take_ownership();
				//break;

			//case "--check-perf":
				//check_performance();
				//break;

			//case "--desc":
			//case "--show-desc":
			//case "-y":
			//case "--yes":
			case "--help":
			case "--h":
			case "-h":
			case "--debug":
				//handled already - do nothing
				break;

			//case "--user":
			//case "--username":
			case "--basepath":
			//case "--size-limit":
			//case "--limit-size":
			//case "--password":
				k += 1;
				// handled already - do nothing
				break;

			default:
				//unknown option - show help and exit
				log_error(_("Unknown option") + ": %s".printf(args[k]));
				log_msg(help_message());
				return false;
			}
		}

		return true;
	}

	public bool backup_all(){

		bool status = true;
		
		bool ok = backup_repos();
		if (!ok) { status = false; }
		
		ok = backup_cache();
		if (!ok) { status = false; }

		ok = backup_packages();
		if (!ok) { status = false; }

		return status;
	}

	public bool restore_all(){

		bool status = true;

		// keeps steps independant; allow remaining steps to run if one step fails

		bool ok = restore_repos();
		if (!ok) { status = false; }

		ok = restore_cache();
		if (!ok) { status = false; }
		
		ok = restore_packages();
		if (!ok) { status = false; }

		return status;
	}

	public void check_basepath(){
		
		if (!dir_exists(basepath)){
			log_error(_("Backup directory not found") + ": '%s'".printf(basepath));
			exit(1);
		}
	}

	public bool check_backup_dir_exists(BackupType type){

		switch (type){
		case BackupType.PACKAGES:
			return dir_exists(path_combine(basepath, "packages"));
		case BackupType.REPOS:
			return dir_exists(path_combine(basepath, "repos"));
		case BackupType.CACHE:
			return dir_exists(path_combine(basepath, "cache"));
		case BackupType.ICONS:
			return dir_exists(path_combine(basepath, "icons"));
		case BackupType.THEMES:
			return dir_exists(path_combine(basepath, "themes"));
		case BackupType.FONTS:
			return dir_exists(path_combine(basepath, "fonts"));
		case BackupType.USERS:
			return dir_exists(path_combine(basepath, "users"));
		case BackupType.GROUPS:
			return dir_exists(path_combine(basepath, "groups"));
		case BackupType.MOUNTS:
			return dir_exists(path_combine(basepath, "mounts"));
		case BackupType.HOME:
			return dir_exists(path_combine(basepath, "home"));
		case BackupType.CRON:
			return dir_exists(path_combine(basepath, "cron"));
		}

		return false;
	}
	
	public bool remove_backups(){

		bool status = true;
		bool ok;
		
		ok = dir_delete(path_combine(basepath, "packages"), true);
		if (!ok) { status = false; return status; }

		ok = dir_delete(path_combine(basepath, "repos"), true);
		if (!ok) { status = false; return status; }
		
		ok = dir_delete(path_combine(basepath, "cache"), true);
		if (!ok) { status = false; return status; }

		return status;
	}
	
	public bool backup_packages(){
		
		dir_create(basepath);

		copy_binary();
		
		var mgr = new PackageManager(distro, dry_run);
		return mgr.save_package_list(basepath);
	}

	public bool restore_packages(){

		check_basepath();
		if (!check_backup_dir_exists(BackupType.PACKAGES)) { return false; }
		
		var mgr = new PackageManager(distro, dry_run);
		return mgr.restore_packages(basepath, no_prompt);
	}

	// cache  ---------------------
	
	public bool backup_cache(){

		dir_create(basepath);

		copy_binary();
		
		var mgr = new PackageManagerCache(distro, dry_run);
		return mgr.backup_cache(basepath);
	}

	public bool restore_cache(){

		check_basepath();
		if (!check_backup_dir_exists(BackupType.CACHE)) { return false; }
		
		var mgr = new PackageManagerCache(distro, dry_run);
		return mgr.restore_cache(basepath);
	}

	public bool clear_cache(){
		var mgr = new PackageManagerCache(distro, dry_run);
		return mgr.clear_cache(no_prompt);
	}

	// repos --------------------------
	
	public bool backup_repos(){
		
		dir_create(basepath);

		copy_binary();
		
		var mgr = new RepoManager(distro, dry_run);
		return mgr.save_repos(basepath);
	}

	public bool restore_repos(){

		check_basepath();
		if (!check_backup_dir_exists(BackupType.REPOS)) { return false; }
		
		var mgr = new RepoManager(distro, dry_run);
		return mgr.restore_repos(basepath);
	}

	public bool import_missing_keys(){
		var mgr = new RepoManager(distro, dry_run);
		return mgr.import_missing_keys(true);
	}

	// themes -----------------------------

	public bool list_themes(){

		dir_create(basepath);

		copy_binary();

		var mgr = new ThemeManager(distro, false, true, "themes");
		mgr.check_installed_themes();
		return true;
	}
	
	public bool backup_themes(){

		dir_create(basepath);

		copy_binary();

		var mgr = new ThemeManager(distro, dry_run, false, "themes");
		mgr.check_installed_themes();
		return mgr.save_themes(basepath);
	}

	public bool restore_themes(){
		
		check_basepath();
		if (!check_backup_dir_exists(BackupType.THEMES)) { return false; }
		
		var mgr = new ThemeManager(distro, dry_run, false, "themes");
		mgr.check_archived_themes(basepath);
		return mgr.restore_themes(basepath);
	}

	// icons -----------------------------

	public bool list_icons(){

		dir_create(basepath);

		copy_binary();

		var mgr = new ThemeManager(distro, false, true, "icons");
		mgr.check_installed_themes();
		return true;
	}
	
	public bool backup_icons(){

		dir_create(basepath);

		copy_binary();

		var mgr = new ThemeManager(distro, dry_run, false, "icons");
		mgr.check_installed_themes();
		return mgr.save_themes(basepath);
	}

	public bool restore_icons(){
		
		check_basepath();
		if (!check_backup_dir_exists(BackupType.ICONS)) { return false; }
		
		var mgr = new ThemeManager(distro, dry_run, false, "icons");
		mgr.check_archived_themes(basepath);
		return mgr.restore_themes(basepath);
	}
	
	// common ---------------
	
	public void copy_binary(){

		string src = get_cmd_path(AppShortName);
		string dst = path_combine(basepath, AppShortName);

		string cmd = "cp -f '%s' '%s'".printf(
			escape_single_quote(src),
			escape_single_quote(dst));
			
		log_debug(cmd);
		Posix.system(cmd);
	}

	// packages --------------------------


	/*
	public void check_performance() {
		App.read_package_info();

		var timer = timer_start();

		timer.start();
		//App.list_ppa();
		log_msg("list_ppa: %s".printf(timer_elapsed_string(timer)));

		timer.start();
		//App.list_themes();
		//log_msg("list_themes: %s".printf(timer_elapsed_string(timer)));

		timer.start();
		//App.list_icons();
		//log_msg("list_icons: %s".printf(timer_elapsed_string(timer)));

		timer.start();
		App.list_app_config_directories_from_home(false);
		log_msg("list_apps: %s".printf(timer_elapsed_string(timer)));
	}

	public void print_package_list(bool show_desc) {
		//create an arraylist and sort items for printing
		var pkg_list = new ArrayList<Package>();
		foreach(Package pkg in App.pkg_list_master.values) {
			if (pkg.is_selected) {
				pkg_list.add(pkg);
			}
		}
		CompareDataFunc<Package> func = (a, b) => {
			return strcmp(a.name, b.name);
		};
		pkg_list.sort((owned)func);

		int max_length = 0;
		foreach(Package pkg in pkg_list) {
			if (pkg.name.length > max_length) {
				max_length = pkg.name.length;
			}
			if (pkg.is_foreign()){
				pkg.name = "%s:%s".printf(pkg.name,pkg.arch);
			}
		}
		string fmt = "%%-%ds".printf(max_length + 2);

		if (show_desc) {
			fmt = fmt + "%s";
			foreach(Package pkg in pkg_list) {
				log_msg(fmt.printf(pkg.name, pkg.description));
			}
		}
		else {
			foreach(Package pkg in pkg_list) {
				log_msg(fmt.printf(pkg.name));
			}
		}
	}

	public void print_ppa_list(bool show_desc) {
		//create an arraylist and sort items for printing
		var ppa_list = new ArrayList<Ppa>();
		foreach(Ppa ppa in App.ppa_list_master.values) {
			if (ppa.is_selected) {
				ppa_list.add(ppa);
			}
		}
		CompareDataFunc<Ppa> func = (a, b) => {
			return strcmp(a.name, b.name);
		};
		ppa_list.sort((owned)func);

		int max_length = 0;
		foreach(Ppa ppa in ppa_list) {
			if (ppa.name.length > max_length) {
				max_length = ppa.name.length;
			}
		}
		string fmt = "%%-%ds".printf(max_length + 2);

		if (show_desc) {
			fmt = fmt + "%s";
			foreach(Ppa ppa in ppa_list) {
				log_msg(fmt.printf(ppa.name, ppa.description));
			}
		}
		else {
			foreach(Ppa ppa in ppa_list) {
				log_msg(fmt.printf(ppa.name));
			}
		}
	}

	public void print_theme_list(Gee.ArrayList<Theme> theme_list) {
		int max_length = 0;
		foreach(Theme theme in theme_list) {
			var full_name = "%s/%s".printf(theme.dir_type,theme.name);
			if (full_name.length > max_length) {
				max_length = full_name.length;
			}
		}
		string fmt = "%%-%ds".printf(max_length + 2);
		foreach(Theme theme in theme_list) {
			var full_name = "%s/%s".printf(theme.dir_type,theme.name);
			log_msg(fmt.printf(full_name));
		}
	}

	public void print_config_list(Gee.ArrayList<AppExcludeEntry> config_list) {
		foreach(var config in config_list){
			log_msg("%-60s%10s".printf(config.name, format_file_size(config.size)));
			//TODO: show size in bytes with commas
		}
	}

	// ppa -----------------------

	public bool backup_ppa() {
		App.ppa_backup_init(false);
		foreach(Ppa ppa in App.ppa_list_master.values) {
			ppa.is_selected = true;
		}
		
		//TODO: call the faster method for getting ppas?
		bool ok = App.save_ppa_list_selected();
		
		if (ok){
			log_msg(Message.BACKUP_OK);
		}
		else{
			log_msg(Message.BACKUP_ERROR);
		}

		return ok;
	}
	
	public bool restore_ppa() {
		if (!App.check_backup_file("ppa.list")) {
			return false;
		}
		
		if (!check_internet_connectivity()) {
			log_msg(_("Error") + ": " +  Message.INTERNET_OFFLINE);
			return false;
		}

		App.ppa_restore_init(false);
		
		bool run_apt_update = false;
		foreach(Ppa ppa in App.ppa_list_master.values) {
			if (ppa.is_selected && !ppa.is_installed) {
				log_msg(_("Adding PPA") + " '%s'".printf(ppa.name));

				Posix.system("sudo apt-add-repository -y ppa:%s".printf(ppa.name));
				//exit code is not reliable (always 0?)

				run_apt_update = true;
				log_msg("");
			}
		}

		if (run_apt_update) {
			log_msg(_("Updating Package Information..."));
			Posix.system("sudo apt-get -y update");
		}

		log_msg(Message.RESTORE_OK);
		
		return true;
	}

	// cache ----------------------

	public bool backup_cache(){
		App.backup_apt_cache();
		while (App.is_running) {
			sleep(500);
		}
		log_msg(Message.BACKUP_OK);
		return true;
	}

	public bool restore_cache(){
		App.restore_apt_cache();
		while (App.is_running) {
			sleep(500);
		}
		log_msg(Message.RESTORE_OK);
		return true;
	}
	
	// users and groups ----------------------------

	public bool list_users_and_groups(){
		bool ok = true;

		SystemUser.query_users();
		SystemGroup.query_groups();

		// sort users -----------------
		
		var list = new Gee.ArrayList<SystemUser>();
		foreach(var item in SystemUser.all_users.values){
			list.add(item);
		}
		CompareDataFunc<SystemUser> func_group = (a, b) => {
			return strcmp(a.name, b.name);
		};
		list.sort((owned) func_group);

		// print users -----------------
		
		log_msg("%5s %-15s".printf("UID", "User"));
		log_msg(string.nfill(70,'-'));
		foreach(var user in list){
			if (!user.is_system){
				log_msg("%5d %-15s".printf(user.uid, user.name));
			}
		}
		log_msg("");

		// sort groups -----------------
		
		var list_group = new Gee.ArrayList<SystemGroup>();
		foreach(var item in SystemGroup.all_groups.values){
			list_group.add(item);
		}
		CompareDataFunc<SystemGroup> func = (a, b) => {
			return strcmp(a.name, b.name);
		};
		list_group.sort((owned) func);

		// print groups -----------------
		
		log_msg("%5s %-15s %s".printf("GID","Group","Users"));
		log_msg(string.nfill(70,'-'));
		foreach(var group in list_group){
			if (!group.is_system){
				log_msg("%5d %-15s %s".printf(group.gid, group.name, group.user_names));
			}
		}
		log_msg("");
		
		return ok;
	}

	public bool backup_users_and_groups(){
		bool ok = App.backup_users_and_groups("");
		
		if (ok){
			log_msg(Message.BACKUP_OK);
		}
		else{
			log_msg(Message.BACKUP_ERROR);
		}

		return ok;
	}

	public bool restore_users_and_groups(){
		bool ok = true;

		ok = App.restore_users_and_groups_init("");
		
		if (!ok){
			return ok;
		}

		ok = App.restore_users_and_groups();
		
		if (ok){
			log_msg(Message.RESTORE_OK);
		}
		else{
			log_msg(Message.RESTORE_ERROR);
		}

		return ok;
	}

	// configs ------------------------

	public bool backup_config(){
		bool ok = true;
		
		var list = App.list_app_config_directories_from_home(true);
		var status = App.backup_app_settings_all(list);
		ok = ok && status;

		if (ok){
			log_msg(Message.BACKUP_OK);
		}
		else{
			log_msg(Message.BACKUP_ERROR);
		}

		return ok;
	}

	public bool restore_config(){
		bool ok = true;
		
		var list = App.list_app_config_directories_from_backup(true);
		var status = App.restore_app_settings_all(list);
		ok = ok && status;

		if (ok){
			log_msg(Message.RESTORE_OK);
		}
		else{
			log_msg(Message.RESTORE_ERROR);
		}
		
		return ok;
	}

	// themes ----------------------

	public bool backup_themes(){
		bool ok = true;

		foreach(var theme in Theme.list_themes_installed()) {
			if (theme.is_selected) {
				theme.zip(App.backup_dir,false);
				while (theme.is_running) {
					sleep(500);
				}
			}
		}
				
		if (ok){
			log_msg(Message.BACKUP_OK);
		}
		else{
			log_msg(Message.BACKUP_ERROR);
		}

		return ok;
	}

	public bool restore_themes(){
		bool ok = true;
		
		var list = Theme.list_themes_archived(App.backup_dir);

		string username = App.all_users ? "" : App.current_user.name;
		
		foreach(var theme in list){
			theme.check_installed(username);
			theme.is_selected = !theme.is_installed;
		}

		foreach(var theme in list) {
			
			if (theme.is_selected && !theme.is_installed) {

				theme.unzip(username, false);
				
				while (theme.is_running) {
					sleep(500);
				}

				theme.update_permissions();
				theme.update_ownership(App.current_user.name);
			}
		}

		Theme.fix_nested_folders();
		
		if (ok){
			log_msg(Message.RESTORE_OK);
		}
		else{
			log_msg(Message.RESTORE_ERROR);
		}

		return ok;
	}
	
	// mounts ---------------------
	
	public bool backup_mounts(){
		bool ok = App.backup_mounts();
		
		if (ok){
			log_msg(Message.BACKUP_OK);
		}
		else{
			log_msg(Message.BACKUP_ERROR);
		}

		return ok;
	}
	
	public bool restore_mounts(){
		var fstab_list = App.create_fstab_list_for_restore();
		var crypttab_list = App.create_crypttab_list_for_restore();

		bool ok = App.restore_mounts(fstab_list, crypttab_list, "");

		if (ok){
			log_msg(Message.RESTORE_OK);
		}
		else{
			log_msg(Message.RESTORE_ERROR);
		}
		
		return ok;
	}

	// home ---------------------
	
	public bool backup_home(){

		// get password -------------------
		
		App.prompt_for_password(true);
		
		if (App.password.length == 0){
			log_error(Message.PASSWORD_MISSING);
			return false;
		}

		// backup ------------------
		
		int status = Posix.system("%s\n".printf(save_bash_script_temp(App.backup_home_get_script())));
			
		bool ok = (status == 0);
		
		if (ok){
			log_msg(Message.BACKUP_OK);
		}
		else{
			log_msg(Message.BACKUP_ERROR);
		}

		return ok;
	}
	
	public bool restore_home(){
		
		// get password -------------------
		
		App.prompt_for_password(false);
		
		if (App.password.length == 0){
			log_error(Message.PASSWORD_MISSING);
			return false;
		}

		// restore ------------
		
		int status = Posix.system("%s\n".printf(save_bash_script_temp(App.restore_home_get_script())));
			
		bool ok = (status == 0);

		if (ok){
			log_msg(Message.RESTORE_OK);
		}
		else{
			log_msg(Message.RESTORE_ERROR);
		}
		
		return ok;
	}

	// crontabs -------------------

	public bool backup_crontab(){
		bool ok = App.backup_crontab();
		
		if (ok){
			log_msg(Message.BACKUP_OK);
		}
		else{
			log_msg(Message.BACKUP_ERROR);
		}

		return ok;
	}

	public bool restore_crontab(){
		bool ok = App.restore_crontab();
		
		if (ok){
			log_msg(Message.RESTORE_OK);
		}
		else{
			log_msg(Message.RESTORE_ERROR);
		}

		return ok;
	}

	
	// all items ----------------------------------

	public bool backup_all(){
		bool ok = false;

		App.task_list = BackupTask.create_list();
		App.backup_mode = true;

		foreach(var task in App.task_list){
			if (!task.is_selected){
				continue;
			}

			log_msg("");
			log_draw_line();
			string mode = (App.backup_mode) ? _("Backup") : _("Restore");
			log_msg("%s - %s".printf(mode,task.display_name));
			log_draw_line();
			log_msg("");
			
			string cmd = (App.backup_mode) ? task.backup_cmd : task.restore_cmd;

			log_debug(cmd);
			
			Posix.system(cmd);
		}
		
		if (ok){
			log_msg(Message.BACKUP_OK);
		}
		else{
			log_msg(Message.BACKUP_ERROR);
		}

		return ok;
	}

	public bool restore_all(){
		bool ok = false;

		App.task_list = BackupTask.create_list();
		App.backup_mode = false;

		foreach(var task in App.task_list){
			if (!task.is_selected){
				continue;
			}

			log_msg("");
			log_draw_line();
			string mode = (App.backup_mode) ? _("Backup") : _("Restore");
			log_msg("%s - %s".printf(mode,task.display_name));
			log_draw_line();
			log_msg("");
			
			string cmd = (App.backup_mode) ? task.backup_cmd : task.restore_cmd;

			log_debug(cmd);
			
			Posix.system(cmd);
		}
		
		if (ok){
			log_msg(Message.BACKUP_OK);
		}
		else{
			log_msg(Message.BACKUP_ERROR);
		}

		return ok;
	}
	*/
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
	CRON
}
