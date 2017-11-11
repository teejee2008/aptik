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

	// home
	public string userlist = "";
	public string password = "aptik";
	public bool full_backup = false;
	public bool exclude_hidden = false;
	public HomeDataBackupMode home_mode = HomeDataBackupMode.TAR;

	public uint64 config_size_limit = 0;
	
	public static int main (string[] args) {
		
		set_locale();

		LOG_TIMESTAMP = false;

		init_tmp(AppShortName);

		if (!user_is_admin()) {
			log_msg(_("Aptik needs admin access to backup and restore packages."));
			log_msg(_("Please run the application as admin (using 'sudo' or 'pkexec')"));
			exit(0);
		}

		check_dependencies();

		var console =  new AptikConsole();
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
			"rsync","cp","rm","touch","ln","grep","find","awk","pv","mount","umount","crontab","sync", "lsblk"
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
			string msg ="%s: %s".printf(Message.MISSING_COMMAND, missing);
			log_error(msg);
			log_error(_("Install required packages for missing commands"));
			exit(1);
		}
	}
	
	public AptikConsole(){

		distro = new LinuxDistro();

		basepath = Environment.get_current_dir();
	}

	public void print_backup_path(){
		log_msg("Backup path: %s".printf(basepath));
		log_msg(string.nfill(70,'-'));
	}

	public string help_message() {

		string fmt = "  %-30s %s\n";

		string fmt2 = "▰▰▰ %s ▰▰▰\n\n"; //▰▰▰ ◈
		
		string msg = "\n" + AppName + " v" + AppVersion + " by %s (%s)".printf(AppAuthor, AppAuthorEmail) + "\n\n";

		msg += _("Usage") + ": aptik <command> [options]\n\n";

		msg += fmt2.printf(Message.TASK_REPOS);
		
		msg += "%s:\n".printf(_("Commands"));
		msg += fmt.printf("--list-repos", _("List software repositories"));
		msg += fmt.printf("--backup-repos", _("Save list of software repositories"));
		msg += fmt.printf("--restore-repos", _("Add missing software repositories from backup"));
		msg += fmt.printf("--import-missing-keys", _("Find and import missing keys for apt repos"));
		msg += "\n";

		msg += "%s: %s, %s,\n%s\n\n".printf(_("Supports"), "apt (Debian & Derivatives)", "pacman (Arch & Derivatives)", "dnf/yum (Fedora & Derivatives)");
		
		msg += fmt2.printf(Message.TASK_CACHE);

		msg += "%s:\n".printf(_("Commands"));
		msg += fmt.printf("--backup-cache", _("Copy downloaded packages from system cache"));
		msg += fmt.printf("--restore-cache", _("Copy packages to system cache from backup"));
		msg += fmt.printf("--clear-cache", _("Remove downloaded packages from system cache"));
		msg += "\n";

		msg += "%s: %s, %s\n\n".printf(_("Supports"), "apt (Debian & Derivatives)", "pacman (Arch & Derivatives)");

		msg += fmt2.printf(Message.TASK_PACKAGES);

		msg += "%s:\n".printf(_("Commands"));
		msg += fmt.printf("--list-installed", _("List installed packages"));
		msg += fmt.printf("--list-available", _("List available packages"));
		msg += fmt.printf("--list-foreign ", _("List non-native packages"));
		msg += fmt.printf("--list-extra", _("List extra packages installed by user"));
		msg += fmt.printf("--list-{default|dist|base}", _("List default packages for linux distribution"));
		msg += fmt.printf("--backup-packages", _("Save list of installed packages"));
		msg += fmt.printf("--restore-packages", _("Install missing packages from backup"));
		msg += "\n";

		msg += "%s: %s, %s,\n%s\n\n".printf(_("Supports"), "apt (Debian & Derivatives)", "pacman (Arch & Derivatives)", "dnf/yum (Fedora & Derivatives)");

		msg += fmt2.printf(Message.TASK_USERS);

		msg += "%s:\n".printf(_("Commands"));
		msg += fmt.printf("--list-users", _("List users"));
		msg += fmt.printf("--list-users-all", _("List all users (including system user accounts)"));
		msg += fmt.printf("--backup-users", _("Backup users"));
		msg += fmt.printf("--restore-users", _("Restore users from backup"));
		msg += "\n";
		
		msg += fmt2.printf(Message.TASK_GROUPS);

		msg += "%s:\n".printf(_("Commands"));
		msg += fmt.printf("--list-groups", _("List groups"));
		msg += fmt.printf("--list-groups-all", _("List all groups (including system groups)"));
		msg += fmt.printf("--backup-groups", _("Backup groups"));
		msg += fmt.printf("--restore-groups", _("Restore groups from backup"));
		msg += "\n";

		msg += fmt2.printf(Message.TASK_HOME);

		msg += "%s:\n".printf(_("Commands"));
		msg += fmt.printf("--backup-home", _("Backup data in users' home directories"));
		msg += fmt.printf("--restore-home", _("Restore data in users' home directories from backup"));
		msg += fmt.printf("--fix-ownership", _("Updates ownership for users' home directory contents"));

		msg += "\n%s:\n".printf(_("Options"));
		msg += fmt.printf("--users <usr1,usr2,..>", _("Users to backup and restore"));
		msg += fmt.printf("", _("default: all users"));
		msg += "\n";
		msg += fmt.printf("--duplicity", _("Use duplicity for backup instead of TAR"));
		msg += fmt.printf("", _("default: TAR"));
		msg += "\n";
		msg += fmt.printf("--password <string>", _("Password for encryption/decryption with duplicity"));
		msg += fmt.printf("", _("default: 'aptik'"));
		msg += "\n";
		msg += fmt.printf("--full", _("Do full backup with duplicity"));
		msg += fmt.printf("", _("default: incremental if backup exists, else full"));
		msg += "\n";
		msg += fmt.printf("--exclude-hidden", _("Exclude hidden files and directories (app configs)"));
		msg += fmt.printf("", _("default: include"));
		msg += "\n";
		
		msg += fmt2.printf(Message.TASK_MOUNTS);

		msg += "%s:\n".printf(_("Commands"));
		msg += fmt.printf("--list-mounts", _("List /etc/fstab and /etc/crypttab entries"));
		msg += fmt.printf("--backup-mounts", _("Backup /etc/fstab and /etc/crypttab entries"));
		msg += fmt.printf("--restore-mounts", _("Restore /etc/fstab and /etc/crypttab entries from backup"));
		msg += "\n";

		msg += fmt2.printf(Message.TASK_DCONF);

		msg += "%s:\n".printf(_("Commands"));
		msg += fmt.printf("--list-dconf", _("List dconf settings changed by user"));
		msg += fmt.printf("--backup-dconf", _("Backup dconf settings changed by user"));
		msg += fmt.printf("--restore-dconf", _("Restore dconf settings from backup"));

		msg += "\n%s:\n".printf(_("Options"));
		msg += fmt.printf("--users <usr1,usr2,..>", _("Users to backup and restore"));
		msg += fmt.printf("", _("default: all users"));
		msg += "\n";
		
		msg += fmt2.printf(Message.TASK_CRON);

		msg += "%s:\n".printf(_("Commands"));
		msg += fmt.printf("--list-cron", _("List cron tasks"));
		msg += fmt.printf("--backup-cron", _("Backup cron tasks"));
		msg += fmt.printf("--restore-cron", _("Restore cron tasks"));

		msg += "\n%s:\n".printf(_("Options"));
		msg += fmt.printf("--users <usr1,usr2,..>", _("Users to backup and restore"));
		msg += fmt.printf("", _("default: all users"));
		msg += "\n";
		
		msg += fmt2.printf(_("All Items"));

		msg += "%s:\n".printf(_("Commands"));
		msg += fmt.printf("--backup-all", _("Backup all items"));
		msg += fmt.printf("--restore-all", _("Restore all items from backup"));
		msg += fmt.printf("--remove-all", _("Remove all items from backup"));
		msg += "\n";
		
		msg += fmt2.printf(("Common"));
		
		msg += "%s:\n".printf(_("Options"));
		msg += fmt.printf("--basepath <dir>", _("Backup directory (default: current directory)"));
		msg += fmt.printf("--scripted", _("Run in non-interactive mode"));
		msg += fmt.printf("--dry-run", _("(restore only) Simulate restore actions without making changes to system"));
		msg += fmt.printf("--help", _("Show all options"));
		msg += "\n";
		
		return msg;
	}

	public bool parse_arguments(string[] args) {

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
				basepath = args[k] + (args[k].has_suffix("/") ? "" : "/");
				break;

			case "--scripted":
				no_prompt = true;
				break;

			case "--password":
				k++;
				password = args[k];
				break;
				
			case "--users":
				k++;
				userlist = args[k];
				break;

			case "--full":
				full_backup = true;
				break;

			case "--exclude-hidden":
				exclude_hidden = true;
				break;
				
			case "--duplicity":
				home_mode = HomeDataBackupMode.DUPLICITY;
				break;
				
			case "--debug":
				LOG_DEBUG = true;
				break;
				
			case "--dry-run":
				dry_run = true;
				break;

			case "--list-repos":
			case "--backup-repos":
			case "--restore-repos":
			case "--import-missing-keys":
			
			case "--list-dist":
			case "--list-base":
			case "--list-default":
			case "--list-foreign":
			case "--list-installed":
			case "--list-available":
			case "--list-extra":
			case "--backup-packages":
			case "--restore-packages":

			case "--backup-cache":
			case "--backup-pkg-cache":
			case "--restore-cache":
			case "--restore-pkg-cache":
			case "--clear-cache":
			case "--clear-pkg-cache":

			case "--list-fonts":
			case "--backup-fonts":
			case "--restore-fonts":

			case "--list-themes":
			case "--backup-themes":
			case "--restore-themes":

			case "--list-icons":
			case "--backup-icons":
			case "--restore-icons":

			case "--list-users":
			case "--list-users-all":
			case "--backup-users":
			case "--restore-users":

			case "--list-groups":
			case "--list-groups-all":
			case "--backup-groups":
			case "--restore-groups":

			case "--backup-home":
			case "--restore-home":
			case "--fix-ownership":

			case "--list-mounts":
			case "--backup-mounts":
			case "--restore-mounts":

			case "--list-dconf":
			case "--backup-dconf":
			case "--restore-dconf":

			case "--list-cron":
			case "--backup-cron":
			case "--restore-cron":

			case "--backup-all":
			case "--restore-all":
			case "--remove-all":

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

		// process command ----------------------------------
		
		switch (command) {

		// repos --------------------------------------------
		
		case "--list-repos":
			return list_repos();

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
						
		// themes ---------------------------------------------

		case "--list-themes":
			//distro.print_system_info();
			return list_themes();

		case "--backup-themes":
			distro.print_system_info();
			return backup_themes();
			
		case "--restore-themes":
			distro.print_system_info();
			return restore_themes();

		// icons ---------------------------------------------
		
		case "--list-icons":
			//distro.print_system_info();
			return list_icons();

		case "--backup-icons":
			distro.print_system_info();
			return backup_icons();
			
		case "--restore-icons":
			distro.print_system_info();
			return restore_icons();

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

		// home -------------------------------------

		case "--backup-home":
			return backup_home();

		case "--restore-home":
			return restore_home();

		case "--fix-ownership":
			return fix_home_ownership();

		// mounts -------------------------------------------

		case "--list-mounts":
			return list_mount_entries();

		case "--backup-mounts":
			return backup_mount_entries();

		case "--restore-mounts":
			return restore_mount_entries();

		// dconf settings -------------------------------------------

		case "--list-dconf":
			return list_dconf_settings();

		case "--backup-dconf":
			return backup_dconf_settings();

		case "--restore-dconf":
			return restore_dconf_settings();

		// cron tasks -------------------------------------------

		case "--list-cron":
			return list_cron_tasks();

		case "--backup-cron":
			return backup_cron_tasks();

		case "--restore-cron":
			return restore_cron_tasks();

		// all ---------------------------------------------

		case "--backup-all":
			distro.print_system_info();
			return backup_all();

		case "--restore-all":
			distro.print_system_info();
			return restore_all();

		case "--remove-all":
			distro.print_system_info();
			return remove_all();
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

		ok = backup_users();
		if (!ok) { status = false; }

		ok = backup_groups();
		if (!ok) { status = false; }

		ok = backup_home();
		if (!ok) { status = false; }

		ok = backup_mount_entries();
		if (!ok) { status = false; }

		ok = backup_icons();
		if (!ok) { status = false; }

		ok = backup_themes();
		if (!ok) { status = false; }

		ok = backup_fonts();
		if (!ok) { status = false; }

		ok = backup_dconf_settings();
		if (!ok) { status = false; }

		ok = backup_cron_tasks();
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

		ok = restore_users();
		if (!ok) { status = false; }

		ok = restore_groups();
		if (!ok) { status = false; }

		ok = restore_home();
		if (!ok) { status = false; }

		ok = restore_mount_entries();
		if (!ok) { status = false; }

		ok = restore_icons();
		if (!ok) { status = false; }

		ok = restore_themes();
		if (!ok) { status = false; }

		ok = restore_fonts();
		if (!ok) { status = false; }

		ok = restore_dconf_settings();
		if (!ok) { status = false; }

		ok = restore_cron_tasks();
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

		path = path_combine(basepath, "debs");
		
		if (dir_exists(path)){
			
			var list = dir_list_names(path, false);
			int count = 0;
			foreach(var fpath in list){
				if (fpath.has_suffix(".deb")) { count++; }
			}
			
			if (count > 0){
				// skip if not empty
				log_msg("%s: %s (%d debs found)".printf(_("Skipped"), path, count));
			}
			else{
				// remove if empty
				remove_backup("debs");
			}
		}

		return status;
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
	
	// packages ------------------------------
	
	public bool list_packages_installed(){
		
		var mgr = new PackageManager(distro, dry_run);
		
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
		
		var mgr = new PackageManager(distro, dry_run);
		
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
		
		var mgr = new PackageManager(distro, dry_run);
		
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
		
		var mgr = new PackageManager(distro, dry_run);
		
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
		
		var mgr = new PackageManager(distro, dry_run);
		
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

	public bool list_repos(){

		var mgr = new RepoManager(distro, dry_run);
		return mgr.list_repos();
	}
	
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

		var mgr = new ThemeManager(distro, dry_run, "themes");
		mgr.check_installed_themes();
		mgr.list_themes();
		return true;
	}
	
	public bool backup_themes(){

		dir_create(basepath);

		copy_binary();

		var mgr = new ThemeManager(distro, dry_run, "themes");
		mgr.check_installed_themes();
		return mgr.save_themes(basepath);
	}

	public bool restore_themes(){
		
		check_basepath();
		if (!check_backup_dir_exists(BackupType.THEMES)) { return false; }
		
		var mgr = new ThemeManager(distro, dry_run, "themes");
		mgr.check_archived_themes(basepath);
		return mgr.restore_themes(basepath);
	}

	// icons -----------------------------

	public bool list_icons(){

		var mgr = new ThemeManager(distro, dry_run, "icons");
		mgr.check_installed_themes();
		return true;
	}
	
	public bool backup_icons(){

		dir_create(basepath);

		copy_binary();

		var mgr = new ThemeManager(distro, dry_run, "icons");
		mgr.check_installed_themes();
		return mgr.save_themes(basepath);
	}

	public bool restore_icons(){
		
		check_basepath();
		if (!check_backup_dir_exists(BackupType.ICONS)) { return false; }
		
		var mgr = new ThemeManager(distro, dry_run, "icons");
		mgr.check_archived_themes(basepath);
		return mgr.restore_themes(basepath);
	}

	// fonts -----------------------------

	public bool list_fonts(){

		var mgr = new FontManager(distro, dry_run);
		mgr.list_fonts();
		return true;
	}
	
	public bool backup_fonts(){

		dir_create(basepath);

		copy_binary();

		var mgr = new FontManager(distro, dry_run);
		return mgr.backup_fonts(basepath);
	}

	public bool restore_fonts(){
		
		check_basepath();
		if (!check_backup_dir_exists(BackupType.ICONS)) { return false; }
		
		var mgr = new FontManager(distro, dry_run);
		return mgr.restore_fonts(basepath);
	}

	// users -----------------------------

	public bool list_users(bool all = false){

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

		var mgr = new GroupManager(false);
		mgr.query_groups(true);
		mgr.list_groups(all);
		return true;
	}
	
	public bool backup_groups(){

		dir_create(basepath);

		copy_binary();

		bool status = true;

		var mgr = new GroupManager(dry_run);
		mgr.query_groups(true);
		bool ok = mgr.backup_groups(basepath);
		if (!ok){ status = false; }
		
		return status; 
	}

	public bool restore_groups(){
		
		check_basepath();
		if (!check_backup_dir_exists(BackupType.GROUPS)) { return false; }

		bool status = true;
		
		var mgr = new GroupManager(dry_run);
		bool ok = mgr.restore_groups(basepath);
		if (!ok){ status = false; }
		
		return status;
	}

	// mounts -----------------------------
	
	public bool list_mount_entries(){

		var mgr = new MountEntryManager(false);
		mgr.query_mount_entries();
		mgr.list_mount_entries();
		return true;
	}
	
	public bool backup_mount_entries(){

		dir_create(basepath);

		copy_binary();

		bool status = true;

		var mgr = new MountEntryManager(dry_run);
		mgr.query_mount_entries();
		bool ok = mgr.backup_mount_entries(basepath);
		if (!ok){ status = false; }
		
		return status; 
	}

	public bool restore_mount_entries(){
		
		check_basepath();
		if (!check_backup_dir_exists(BackupType.MOUNTS)) { return false; }

		bool status = true;
		
		var mgr = new MountEntryManager(dry_run);
		bool ok = mgr.restore_mount_entries(basepath);
		if (!ok){ status = false; }
		
		return status;
	}

	// home -----------------------------

	public bool backup_home(){

		bool status = true;

		var mgr = new UserHomeDataManager(dry_run);
		bool ok = mgr.backup_home(basepath, userlist, home_mode, password, full_backup, exclude_hidden);
		if (!ok){ status = false; }
		
		return status; 
	}

	public bool restore_home(){
		
		check_basepath();
		if (!check_backup_dir_exists(BackupType.HOME)) { return false; }

		bool status = true;
		
		var mgr = new UserHomeDataManager(dry_run);
		bool ok = mgr.restore_home(basepath, userlist, password);
		if (!ok){ status = false; }
		
		return status;
	}

	public bool fix_home_ownership(){
		
		//check_basepath();
		//if (!check_backup_dir_exists(BackupType.HOME)) { return false; }

		bool status = true;
		
		var mgr = new UserHomeDataManager(dry_run);
		bool ok = mgr.fix_home_ownership(userlist);
		if (!ok){ status = false; }
		
		return status;
	}

	// mounts -----------------------------
	
	public bool list_dconf_settings(){

		var mgr = new DconfManager(false);
		mgr.list_dconf_settings(userlist);
		return true;
	}
	
	public bool backup_dconf_settings(){

		dir_create(basepath);

		copy_binary();

		bool status = true;

		var mgr = new DconfManager(dry_run);
		bool ok = mgr.backup_dconf_settings(basepath, userlist);
		if (!ok){ status = false; }
		
		return status; 
	}

	public bool restore_dconf_settings(){
		
		check_basepath();
		if (!check_backup_dir_exists(BackupType.MOUNTS)) { return false; }

		bool status = true;
		
		var mgr = new DconfManager(dry_run);
		bool ok = mgr.restore_dconf_settings(basepath, userlist);
		if (!ok){ status = false; }
		
		return status;
	}

	// cron tasks -----------------------------
	
	public bool list_cron_tasks(){

		var mgr = new CronTaskManager(false);
		mgr.list_cron_tasks(userlist);
		return true;
	}
	
	public bool backup_cron_tasks(){

		dir_create(basepath);

		copy_binary();

		bool status = true;

		var mgr = new CronTaskManager(dry_run);
		bool ok = mgr.backup_cron_tasks(basepath, userlist);
		if (!ok){ status = false; }
		
		return status; 
	}

	public bool restore_cron_tasks(){
		
		check_basepath();
		if (!check_backup_dir_exists(BackupType.CRON)) { return false; }

		bool status = true;
		
		var mgr = new CronTaskManager(dry_run);
		bool ok = mgr.restore_cron_tasks(basepath, userlist);
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
	DCONF,
	CRON
}
