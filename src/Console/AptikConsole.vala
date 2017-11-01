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

		string fmt = "  --%-30s %s\n";
		
		string msg = "\n" + AppName + " v" + AppVersion + " by %s (%s)".printf(AppAuthor, AppAuthorEmail) + "\n\n";

		msg += _("Syntax") + ": aptik [options]\n\n";

		msg += _("Options") + ":\n\n";

		msg += _("Common") + ":\n\n";
		
		msg += fmt.printf("basepath <dir>", _("Backup directory (defaults to current directory)"));
		msg += fmt.printf("scripted", _("Run in non-interactive mode"));
		msg += fmt.printf("dry-run", _("Show actions for restore without making changes to system"));
		//msg += fmt.printf("user <username>" + _("Select username for listing config files"));
		//msg += fmt.printf("password <password>" + _("Specify password for encrypting and decrypting backups"));
		//msg += fmt.printf("[show-]desc" + _("Show package description if available"));
		msg += fmt.printf("help", _("Show all options"));
		msg += "\n";

		msg += "%s:\n\n".printf(Message.TASK_PPA);
		
		//msg += fmt.printf("list-repo            ",  _("List PPAs"));
		msg += fmt.printf("backup-repos", _("Save list of software repositories"));
		msg += fmt.printf("restore-repos", _("Add missing software repositories"));
		msg += fmt.printf("import-missing-keys", _("Import missing public keys for apt"));
		msg += "\n";
		
		msg += "%s:\n\n".printf(Message.TASK_CACHE);
		
		msg += fmt.printf("backup-cache", _("Copy downloaded packages from system cache"));
		msg += fmt.printf("restore-cache", _("Copy packages to system cache"));
		msg += fmt.printf("clear-cache", _("Remove downloaded packages from system cache"));
		msg += "\n";

		msg += "%s:\n\n".printf(Message.TASK_PACKAGE);
		
		msg += fmt.printf("list-installed", _("List installed packages"));
		msg += fmt.printf("list-available", _("List available packages"));
		msg += fmt.printf("list-foreign ", _("List non-native packages"));
		msg += fmt.printf("list-extra", _("List extra packages installed by user"));
		msg += fmt.printf("list-{default|dist|base}", _("List default packages for linux distribution"));
		msg += fmt.printf("backup-packages", _("Save list of installed packages"));
		msg += fmt.printf("restore-packages", _("Install missing packages"));
		msg += "\n";

		msg += "%s:\n\n".printf(Message.TASK_USER);
		
		msg += fmt.printf("list-users", _("List users"));
		msg += fmt.printf("list-users-all", _("List all users (including system user accounts)"));
		msg += fmt.printf("backup-users", _("Backup users and groups"));
		msg += fmt.printf("restore-users", _("Restore users and groups"));
		msg += "\n";
		
		msg += "%s:\n\n".printf(Message.TASK_GROUP);
		
		msg += fmt.printf("list-groups", _("List groups"));
		msg += fmt.printf("list-groups-all", _("List all groups (including system groups)"));
		msg += fmt.printf("backup-groups", _("Backup groups"));
		msg += fmt.printf("restore-groups", _("Restore groups"));
		msg += "\n";

		msg += _("All Items") + ":\n\n";
		
		msg += fmt.printf("backup-all", _("Backup all items"));
		msg += fmt.printf("restore-all", _("Restore all items"));

		/*
		msg += "%s:\n".printf(Message.TASK_CONFIG);
		msg += "\n";
		msg += fmt.printf("list-configs        " + _("List config dirs in /home/<user>") + "\n";
		msg += fmt.printf("backup-configs      " + _("Backup config files from /home/<user>") + "\n";
		msg += fmt.printf("restore-configs     " + _("Restore config files to /home/<user>") + "\n";
		msg += fmt.printf("size-limit <bytes>  " + _("Skip config dirs larger than specified size") + "\n";
		msg += "\n";
		*/
		
		/*
		msg += "%s:\n".printf(Message.TASK_THEME);
		msg += "\n";
		msg += fmt.printf("list-themes         " + _("List themes in /usr/share/themes") + "\n";
		msg += fmt.printf("backup-themes       " + _("Backup themes from /usr/share/themes") + "\n";
		msg += fmt.printf("restore-themes      " + _("Restore themes to /usr/share/themes") + "\n";
		msg += "\n";
		*/
		
		/*
		msg += "%s:\n".printf(Message.TASK_MOUNT);
		msg += "\n";
		msg += fmt.printf("backup-mounts       " + _("Backup /etc/fstab and /etc/crypttab entries") + "\n";
		msg += fmt.printf("restore-mounts      " + _("Restore /etc/fstab and /etc/crypttab entries") + "\n";
		msg += "\n";
		*/
		
		/*
		msg += "%s:\n".printf(Message.TASK_HOME);
		msg += "\n";
		msg += fmt.printf("backup-home         " + _("Backup user-created data in user's home directory") + "\n";
		msg += fmt.printf("restore-home        " + _("Restore user-created data in user's home directory") + "\n";
		msg += "\n";
		*/
		
		/*
		msg += "%s:\n".printf(Message.TASK_CRON);
		msg += "\n";
		msg += fmt.printf("backup-crontab         " + _("Backup user's scheduled tasks (crontab)") + "\n";
		msg += fmt.printf("restore-crontab        " + _("Restore user's scheduled tasks (crontab)") + "\n";
		msg += "\n";
		*/
		

		//msg += fmt.printf("clean               " + _("Remove all backups from backup location") + "\n";
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

			case "--list-dist":
			case "--list-base":
			case "--list-default":
				return list_packages_dist();

			case "--list-foreign":
				return list_packages_foreign();

			case "--list-installed":
				return list_packages_installed();

			case "--list-available":
				return list_packages_available();

			case "--list-extra":
				return list_packages_extra();

			case "--backup-packages":
				distro.print_system_info();
				return backup_packages();
				
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

			// fonts -------------------------------------

			case "--list-fonts":
				return list_fonts();
				
			case "--backup-fonts":
				distro.print_system_info();
				return backup_fonts();
				
			case "--restore-fonts":
				distro.print_system_info();
				return restore_fonts();
							
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

			case "--list-users":
				return list_users();

			case "--list-users-all":
				return list_users(true);

			case "--backup-users":
				return backup_users();

			case "--restore-users":
				return restore_users();

			// groups -------------------------------------------

			case "--list-groups":
				return list_groups();

			case "--list-groups-all":
				return list_groups(true);

			case "--backup-groups":
				return backup_groups();

			case "--restore-groups":
				return restore_groups();

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
			log_error("%s: %s".printf(Message.DIR_MISSING, backup_path));
			return false;
		}
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

	// packages ------------------------------
	
	public bool list_packages_installed(){
		
		var mgr = new PackageManager(distro, false, true);
		
		string txt = "";
		int count = 0;
		
		foreach(var pkg in mgr.packages_sorted){
			
			if (pkg.is_installed){

				txt += "%-50s".printf(pkg.name);
				
				if (mgr.description_available){
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

		return true;
	}

	public bool list_packages_foreign(){
		
		var mgr = new PackageManager(distro, false, true);
		
		string txt = "";
		int count = 0;
		
		foreach(var pkg in mgr.packages_sorted){
			
			if (pkg.is_installed && pkg.is_foreign){

				txt += "%-50s".printf(pkg.name);
				
				if (mgr.description_available){
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

		return true;
	}

	public bool list_packages_dist(){
		
		var mgr = new PackageManager(distro, false, true);
		
		string txt = "";
		int count = 0;
		
		foreach(var pkg in mgr.packages_sorted){
			
			if (pkg.is_default){

				txt += "%-50s".printf(pkg.name);
				
				if (mgr.description_available){
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

		return true;
	}

	public bool list_packages_extra(){
		
		var mgr = new PackageManager(distro, false, true);
		
		string txt = "";
		int count = 0;
		
		foreach(var pkg in mgr.packages_sorted){
			
			if (pkg.is_installed && !pkg.is_automatic && !pkg.is_default){

				txt += "%-50s".printf(pkg.name);
				
				if (mgr.description_available){
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

		return true;
	}

	public bool list_packages_available(){
		
		var mgr = new PackageManager(distro, false, true);
		
		string txt = "";
		int count = 0;
		
		foreach(var pkg in mgr.packages_sorted){
			
			if (pkg.is_available){

				txt += "%-50s".printf(pkg.name);
				
				if (mgr.description_available){
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

		return true;
	}

	public bool backup_packages(){
		
		dir_create(basepath);

		copy_binary();
		
		var mgr = new PackageManager(distro, dry_run, false);
		return mgr.save_package_list(basepath);
	}

	public bool restore_packages(){

		check_basepath();
		if (!check_backup_dir_exists(BackupType.PACKAGES)) { return false; }
		
		var mgr = new PackageManager(distro, dry_run, false);
		return mgr.restore_packages(basepath, no_prompt);
	}

	// cache  ---------------------
	
	public bool backup_cache(){

		dir_create(basepath);

		copy_binary();
		
		var mgr = new PackageCacheManager(distro, dry_run);
		return mgr.backup_cache(basepath);
	}

	public bool restore_cache(){

		check_basepath();
		if (!check_backup_dir_exists(BackupType.CACHE)) { return false; }
		
		var mgr = new PackageCacheManager(distro, dry_run);
		return mgr.restore_cache(basepath);
	}

	public bool clear_cache(){
		var mgr = new PackageCacheManager(distro, dry_run);
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

	// fonts -----------------------------

	public bool list_fonts(){

		dir_create(basepath);

		copy_binary();

		var mgr = new FontManager(distro, false, true);
		mgr.list_fonts();
		return true;
	}
	
	public bool backup_fonts(){

		dir_create(basepath);

		copy_binary();

		var mgr = new FontManager(distro, dry_run, false);
		return mgr.backup_fonts(basepath);
	}

	public bool restore_fonts(){
		
		check_basepath();
		if (!check_backup_dir_exists(BackupType.ICONS)) { return false; }
		
		var mgr = new FontManager(distro, dry_run, false);
		return mgr.restore_fonts(basepath);
	}

	// users -----------------------------

	public bool list_users(bool all = false){

		dir_create(basepath);

		copy_binary();

		var mgr = new UserManager(false);
		mgr.query_users(true);
		mgr.list_users(all);
		return true;
	}

	public bool backup_users(){

		dir_create(basepath);

		copy_binary();

		bool status = true;

		var us_mgr = new UserManager(dry_run);
		us_mgr.query_users(true);
		bool ok = us_mgr.backup_users(basepath);
		if (!ok){ status = false; }

		return status; 
	}

	public bool restore_users(){
		
		check_basepath();
		if (!check_backup_dir_exists(BackupType.USERS)) { return false; }

		bool status = true, ok;
		
		var usr_mgr = new UserManager(dry_run);
		ok = usr_mgr.restore_users(basepath);
		if (!ok){ status = false; }
		
		return status;
	}

	// groups -----------------------------
	
	public bool list_groups(bool all = false){

		dir_create(basepath);

		copy_binary();

		var mgr = new GroupManager(false);
		mgr.query_groups(true);
		mgr.list_groups(all);
		return true;
	}
	
	public bool backup_groups(){

		dir_create(basepath);

		copy_binary();

		bool status = true;

		var grp_mgr = new GroupManager(dry_run);
		grp_mgr.query_groups(true);
		bool ok = grp_mgr.backup_groups(basepath);
		if (!ok){ status = false; }
		
		return status; 
	}

	public bool restore_groups(){
		
		check_basepath();
		if (!check_backup_dir_exists(BackupType.GROUPS)) { return false; }

		bool status = true;
		
		var grp_mgr = new GroupManager(dry_run);
		bool ok = grp_mgr.restore_groups(basepath);
		if (!ok){ status = false; }
		
		return status;
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

	
/*
	// packages --------------------------


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
